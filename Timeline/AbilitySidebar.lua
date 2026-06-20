local mod = dmhub.GetModLoading()

local g_displayedAbility = nil

-- Shared document for broadcasting the active ability timeline to other players.
local g_abilityShareDocId = "abilityTimelineShare"

-- Current sharing state: nil when not sharing, otherwise a table of shared data.
local g_sharingData = nil

-- The token we are currently sharing for.
local g_sharingToken = nil

-- Check if the given token is on the current initiative turn.
local function IsTokenOnCurrentTurn(token)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return false
    end

    local currentId = q.currentTurn
    if type(currentId) ~= "string" then
        return false
    end

    if not GameHud.instance or not GameHud.instance:has_key("initiativeInterface") then
        return false
    end

    local tokens = GameHud.instance:GetTokensForInitiativeId(
        GameHud.instance.initiativeInterface, currentId) or {}
    for _, tok in ipairs(tokens) do
        if tok.charid == token.charid then
            return true
        end
    end

    return false
end

-- Check if we should share the ability timeline for this token.
local function ShouldShareAbility(token)
    if not token.canControl then
        return false
    end
    if dmhub.GetSettingValue("privaterolls") == "dm" then
        return false
    end
    return IsTokenOnCurrentTurn(token)
end

-- Write the current sharing data to the shared document.
local function WriteAbilityShare()
    if g_sharingData == nil then
        return
    end

    local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
    doc:BeginChange()

    -- Clear existing data.
    for k in pairs(doc.data) do
        doc.data[k] = nil
    end

    -- Write current sharing data.
    for k, v in pairs(g_sharingData) do
        doc.data[k] = v
    end

    doc.data.heartbeat = ServerTimestamp()
    doc:CompleteChange("Update ability share", {undoable = false})
end

-- Clear the shared document.
local function ClearAbilityShare()
    if g_sharingData == nil then
        return
    end

    g_sharingData = nil
    g_sharingToken = nil

    local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
    doc:BeginChange()
    for k in pairs(doc.data) do
        doc.data[k] = nil
    end
    doc:CompleteChange("Clear ability share", {undoable = false})

    -- Drop the engine's "current casting" state so spine eye-IK on every token
    -- decays back to no look-at.
    if spine.clearCurrentCast ~= nil then
        spine.clearCurrentCast()
    end
end

-- Heartbeat: update the timestamp every 3 seconds while sharing.
local function HeartbeatAbilityShare()
    if mod.unloaded then
        return
    end
    if g_sharingData == nil then
        return
    end

    local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
    doc:BeginChange()
    doc.data.heartbeat = ServerTimestamp()
    doc:CompleteChange("Heartbeat ability share", {undoable = false})

    dmhub.Schedule(3, HeartbeatAbilityShare)
end

-- Begin sharing ability data for the given token.
local function BeginAbilitySharing(token, ability)
    g_sharingToken = token
    g_sharingData = {
        casterTokenId = token.charid,
        ability = ability,
        userid = dmhub.loginUserid,
    }

    WriteAbilityShare()

    -- Tell the engine which token is casting; spine tokens with eye IK will turn to
    -- look at this token (and the caster itself will look at its first target once
    -- targets are set via UpdateAbilitySharing -> spine.setCurrentCastingTargets).
    if spine.setCurrentCastingToken ~= nil then
        spine.setCurrentCastingToken(token)
    end

    -- Start heartbeat loop.
    dmhub.Schedule(3, HeartbeatAbilityShare)
end

-- Boon/bane label strings matching the interactive dialog.
local g_readOnlyBoonsLabels = { "BANEx2", "BANE", "NONE", "EDGE", "EDGEx2" }

-- Build a read-only modifier pill that mirrors the interactive ModifierPanel
-- style from EmbeddedRollDialog. Shows buff/debuff coloring and selected state.
-- Colors are driven by classes + selectors on the parent Modifiers panel.
local function CreateReadOnlyModifierPill(modInfo)
    local isBuff = modInfo.buffOrDebuff == "buff"
    local isDebuff = modInfo.buffOrDebuff == "debuff"

    return gui.Panel{
        classes = {"modPill", "bgAlt"},
        borderWidth = 2,
        cornerRadius = 4,
        width = "auto",
        height = 18,
        pad = 4,
        flow = "horizontal",
        bgimage = true,
        hmargin = 2,

        -- Border tracks state: muted at rest, info (gold) when enabled,
        -- success/danger for an enabled buff/debuff.
        updateModifierPill = function(element, info)
            local buff = info.buffOrDebuff == "buff"
            local debuff = info.buffOrDebuff == "debuff"
            element:SetClass("border", not info.enabled)
            element:SetClass("borderInfo", info.enabled and not buff and not debuff)
            element:SetClass("borderSuccess", info.enabled and buff)
            element:SetClass("borderDanger", info.enabled and debuff)
        end,

        gui.Panel{
            classes = {"modIndicator"},
            bgimage = "drawsteel/Icons_Nav_CollapseArrow.png",
            width = 18,
            height = 18,
            collapsed = (not isBuff and not isDebuff) and 1 or 0,
            uiscale = isBuff and {y=-1, x=1} or nil,
            y = isDebuff and 2 or 0,

            -- Arrow tint: disabled grey until an enabled buff/debuff colors it.
            updateModifierPill = function(element, info)
                local buff = info.buffOrDebuff == "buff"
                local debuff = info.buffOrDebuff == "debuff"
                element:SetClass("bgSuccess", info.enabled and buff)
                element:SetClass("bgDanger", info.enabled and debuff)
                element:SetClass("bgDisabled", not (info.enabled and (buff or debuff)))
            end,
        },

        gui.Label{
            classes = {"modLabel", "sizeM"},
            text = modInfo.name,
            width = "auto",
            height = "auto",
            lmargin = 0,
            rmargin = 4,
            valign = "center",

            -- Label brightens from muted to default when enabled.
            updateModifierPill = function(element, info)
                element:SetClass("fg", info.enabled)
                element:SetClass("fgMuted", not info.enabled)
            end,
        },
    }
end

-- Format tier description text for read-only display.
-- Bolds leading damage numbers and applies rich text formatting.
local function FormatReadOnlyTierText(text)
    if text == nil or text == "" then
        return ""
    end
    local damageGroups = regex.MatchGroups(text, "^(?<damage>[0-9]+).*?damage")
    if damageGroups ~= nil then
        text = string.format("<b>%s</b>%s",
            damageGroups.damage,
            string.sub(text, string.len(damageGroups.damage) + 1))
    end
    text = MarkdownDocument.FormatRichText(text, {player = not dmhub.isDM})
    return text
end

-- Build a comprehensive read-only roll dialog panel that mirrors the layout
-- of the interactive EmbeddedRollDialog. Displays multi-target tokens,
-- boons/banes bar, surges, styled modifier panels, roll formula, and triggers.
local function CreateReadOnlyRollInfo(shareData)
    local ds = shareData.dialogState
    if ds == nil then
        -- Fall back to simple display if only legacy data is present.
        local children = {}
        if shareData.targetTokenIds ~= nil and #shareData.targetTokenIds > 0 then
            for _, tokenId in ipairs(shareData.targetTokenIds) do
                local targetToken = dmhub.GetTokenById(tokenId)
                if targetToken ~= nil and targetToken.valid then
                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        vmargin = 1,
                        gui.CreateTokenImage(targetToken, {
                            width = 24, height = 24,
                        }),
                        gui.Label{
                            classes = {"sizeS"},
                            text = targetToken.description or "Unknown",
                            width = "auto", height = "auto",
                            valign = "center", lmargin = 4,
                        },
                    }
                end
            end
        end
        if #children == 0 then return nil end
        return gui.Panel{
            width = "100%", height = "auto", flow = "vertical",
            pad = 6, tmargin = 4, children = children,
        }
    end

    -- Full dialog state is available -- build a comprehensive display.
    local sections = {}

    -- Boons/Banes bar (only for power rolls).
    if ds.isPowerRoll and GameSystem.UseBoons then
        local boonValue = ds.boonValue or 0
        local boonEntries = {}
        for i = 1, #g_readOnlyBoonsLabels do
            local entryBoon = i - 3 -- -2, -1, 0, 1, 2
            local isSelected = (boonValue == entryBoon)

            local isBane = (i <= 2)
            local isBoon = (i >= 4)

            -- Build icon panel (arrows) for non-NONE entries.
            local iconPanel = nil
            if i ~= 3 then
                local arrows = {}
                local arrowCount = (i == 1 or i == 5) and 2 or 1
                for j = 1, arrowCount do
                    local y = 0
                    if arrowCount == 2 then
                        y = (j == 1) and 2 or -2
                    end
                    arrows[#arrows+1] = gui.Panel{
                        bgimage = "drawsteel/Icons_Nav_CollapseArrow.png",
                        width = 16, height = 16,
                        bgcolor = "white",
                        scale = isBoon and {y=-1, x=1} or nil,
                        y = y,
                    }
                end
                iconPanel = gui.Panel{
                    flow = "none",
                    width = 16, height = 16,
                    valign = "center",
                    children = arrows,
                }
            end

            -- Entry bgcolor and border based on selection state.
            boonEntries[#boonEntries+1] = gui.Panel{
                -- Selection signalled by border color: success (boon), danger
                -- (bane), info (none); neutral border at rest.
                updateRollDialog = function(element, ds)
                    local sel = (ds.boonValue or 0) == entryBoon
                    element:SetClass("borderSuccess", sel and isBoon)
                    element:SetClass("borderDanger", sel and isBane)
                    element:SetClass("borderInfo", sel and not isBoon and not isBane)
                    element:SetClass("border", not sel)
                end,
                classes = {"boonPanel", "bgAlt",
                    cond(isSelected and isBoon, "borderSuccess"),
                    cond(isSelected and isBane, "borderDanger"),
                    cond(isSelected and not isBoon and not isBane, "borderInfo"),
                    cond(not isSelected, "border"),
                },
                width = "auto", height = "auto",
                flow = "horizontal",
                bgimage = true,
                borderWidth = 1,
                cornerRadius = 6,
                hpad = 6,
                vmargin = 2,
                isBane and iconPanel or nil,
                gui.Label{
                    classes = {"sizeS"},
                    text = g_readOnlyBoonsLabels[i],
                    valign = "center",
                    width = "auto", height = "auto",
                    bgimage = "panels/square.png",
                    textAlignment = "center",
                    bold = isSelected,
                },
                isBoon and iconPanel or nil,
            }
        end

        sections[#sections+1] = gui.Panel{
            halign = "center",
            width = "auto", height = "auto",
            flow = "horizontal",
            vmargin = 2,
            children = boonEntries,
        }
    end

    -- Modifiers panel.
    local modifierPills = {}
    sections[#sections+1] = gui.Panel{
        width = "100%", height = "auto",
        flow = "horizontal",
        wrap = true,

        create = function(element)
            element:FireEvent("updateRollDialog", ds)
        end,

        updateRollDialog = function(element, ds)
            local children = {}
            local newModifierPills = {}
            for _,m in ipairs(ds.modifiers or {}) do
                if not m.forced then
                    newModifierPills[m.guid] = modifierPills[m.guid] or CreateReadOnlyModifierPill(m)
                    children[#children+1] = newModifierPills[m.guid]
                    newModifierPills[m.guid]:FireEventTree("updateModifierPill", m)
                end
            end

            modifierPills = newModifierPills
            element.children = children
        end,
    }

    -- Multi-target container (token portraits with surge icons).
    if ds.targets ~= nil and #ds.targets > 1 then
        local tokenPanels = {}
        for i, target in ipairs(ds.targets) do
            local targetToken = dmhub.GetTokenById(target.tokenId)
            if targetToken ~= nil and targetToken.valid then
                -- Surge icons for this target.
                local surgeIcons = {}
                for s = 3, 1, -1 do
                    local isActive = (target.surges or 0) >= s
                    surgeIcons[#surgeIcons+1] = gui.Panel{
                        bgimage = "game-icons/surge.png",
                        width = 16, height = 16,
                        bgcolor = isActive and "white" or "#ffffff66",
                        collapsed = (target.surges or 0) < s and (s > 1) and 1 or 0,
                    }
                end

                tokenPanels[#tokenPanels+1] = gui.Panel{
                    width = 80, height = 80,
                    flow = "vertical",
                    halign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = (i == 1) and "#ffffff18" or "#00000000",

                    gui.Panel{
                        flow = "horizontal",
                        width = "100%", height = 48,
                        gui.CreateTokenImage(targetToken, {
                            halign = "center", valign = "top",
                            width = 48, height = 48,
                            bgcolor = "white",
                        }),
                        gui.Panel{
                            floating = true,
                            halign = "right",
                            flow = "vertical",
                            height = "100%", width = 16,
                            children = surgeIcons,
                        },
                    },

                    gui.Label{
                        classes = {"sizeXs"},
                        bold = true,
                        width = "95%", height = "auto",
                        maxHeight = 30,
                        halign = "center",
                        textOverflow = "truncate",
                        text = target.name,
                        textAlignment = "center",
                    },
                }
            end
        end

        if #tokenPanels > 0 then
            sections[#sections+1] = gui.Panel{
                width = "auto", height = "auto",
                maxWidth = 350,
                halign = "center", valign = "top",
                flow = "horizontal",
                wrap = true,
                children = tokenPanels,
            }
        end
    end

    -- Surges bar (for single target or when shown globally).
    if ds.isPowerRoll and ds.targets ~= nil and #ds.targets == 1 then
        local target = ds.targets[1]
        if (target.surges or 0) > 0 then
            local surgeChildren = {}
            surgeChildren[#surgeChildren+1] = gui.Label{
                classes = {"sizeS"},
                bold = true, valign = "center",
                text = "Surges:",
                width = "auto", height = "auto",
            }
            for s = 1, (target.surges or 0) do
                surgeChildren[#surgeChildren+1] = gui.Panel{
                    bgimage = "game-icons/surge.png",
                    width = 24, height = 24,
                    bgcolor = "white",
                }
            end
            sections[#sections+1] = gui.Panel{
                classes = {"bgAlt"},
                halign = "left", valign = "center",
                width = "auto", height = "auto",
                hpad = 4, vpad = 2, tmargin = 2,
                flow = "horizontal",
                children = surgeChildren,
            }
        end
    end

    -- Roll formula text.
    if ds.rollText ~= nil and ds.rollText ~= "" then
        sections[#sections+1] = gui.Panel{
            width = "auto", height = "auto",
            halign = "center", valign = "top",
            flow = "horizontal",
            gui.Label{
                classes = {"sizeS"},
                text = ds.rollText,
                bold = true,
                width = "auto", height = 18,
                lmargin = 6,
                halign = "left", valign = "center",
            },
        }
    end

    -- Power roll tier table with dice animation support.
    -- Uses gui.Table / gui.TableRow to match the interactive power table
    -- in MCDMAbilityRollBehavior.lua so that style selectors ("row" and
    -- "label" with "highlight") work correctly for tier highlighting.
    if ds.tierTexts ~= nil and #ds.tierTexts > 0 then
        local highlightTier = ds.highlightedTier
        local isRolling = (ds.rollState == "rolling" and ds.rollId ~= nil)

        local tierRows = {}
        for i = 1, #ds.tierTexts do
            local tierText = FormatReadOnlyTierText(ds.tierTexts[i])

            tierRows[#tierRows+1] = gui.TableRow{
                width = "100%",
                height = "auto",
                bgimage = true,

                gui.Label{
                    hpad = 0,
                    textAlignment = "left",
                    fontFace = "DrawSteelGlyphs",
                    text = cond(i == 1, '!', cond(i == 2, '@', '#')),
                    width = "16%",
                    fontSize = 34,
                    height = 20,
                    valign = "center",
                },

                gui.Panel{
                    width = "84%",
                    height = "auto",
                    valign = "center",
                    halign = "left",
                    vpad = 2,
                    hpad = 0,
                    gui.Label{
                        text = tierText,
                        fontSize = 15,
                        width = "100%",
                        height = "auto",
                        vpad = 0,
                        updateRollDialog = function(element, ds)
                            local t = ds.tierTexts ~= nil and ds.tierTexts[i] or nil
                            if t ~= nil then
                                element.text = FormatReadOnlyTierText(t)
                            end
                        end,
                    },
                },
            }
        end

        -- Dice animation state -- stored on the table's data table so
        -- it survives across think ticks.
        --
        -- Highlight a tier row using the default {row, highlight} (@info) fill,
        -- flipping the row's labels to @fgInverse so they stay legible on it.
        local function SetTierHighlight(row, on)
            row:SetClassTree("highlight", on)
            row:SetClassTree("fgInverse", on)
        end

        local tierContainer = gui.Table{
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 4,
            children = tierRows,

            create = function(element)

                -- Apply the static highlight for finished rolls.
                if not isRolling then
                    if highlightTier ~= nil then
                        for idx, row in ipairs(element.children) do
                            SetTierHighlight(row, idx == highlightTier)
                        end
                    end
                    return
                end

                -- Subscribe to dice events for the rolling animation.
                local rollMsg = nil
                for _, msg in ipairs(chat.messages) do
                    if msg.key == ds.rollId then
                        rollMsg = msg
                        break
                    end
                end

                if rollMsg == nil then
                    -- Roll message not found yet; fall back to static.
                    if highlightTier ~= nil then
                        for idx, row in ipairs(element.children) do
                            SetTierHighlight(row, idx == highlightTier)
                        end
                    end
                    element:ScheduleEvent("create", 0.1)
                    return
                end

                -- Calculate the flat modifier (total minus die results).
                local m_mod = rollMsg.total or 0
                local m_numDice = 0
                for _, roll in ipairs(rollMsg.rolls or {}) do
                    m_mod = m_mod - roll.result
                    local events = chat.DiceEvents(roll.guid)
                    if events ~= nil then
                        events:Listen(element)
                        m_numDice = m_numDice + 1
                    end
                end

                element.data = {
                    m_mod = m_mod,
                    m_numDice = m_numDice,
                    m_diceFaces = {},
                    m_endTime = nil,
                    m_finished = false,
                    rollMsg = rollMsg,
                }

                element.thinkTime = 0.1

                -- If there are no dice at all, just show the final tier.
                if m_numDice == 0 and rollMsg.total ~= nil then
                    local tier = RollUtils.DiceResultToTier(rollMsg)
                    for idx, row in ipairs(element.children) do
                        SetTierHighlight(row, idx == tier)
                    end
                    element.data.m_finished = true
                end
            end,

            -- A re-roll broadcasts a new highlightedTier while rollState
            -- stays "finished", so RefreshRemoteAbilityDisplay does not
            -- rebuild this panel; re-apply the highlight here. Skipped
            -- while a live dice animation is driving the highlight.
            updateRollDialog = function(element, ds)
                local d = element.data
                if d ~= nil and not d.m_finished then
                    return
                end
                if ds.highlightedTier ~= nil then
                    for idx, row in ipairs(element.children) do
                        SetTierHighlight(row, idx == ds.highlightedTier)
                    end
                end
            end,

            diceface = function(element, diceguid, num, timeRemaining)
                local d = element.data
                if d == nil or d.m_finished then
                    return
                end

                local endTime = dmhub.Time() + timeRemaining
                d.m_diceFaces[diceguid] = num
                if d.m_endTime == nil or endTime > d.m_endTime then
                    d.m_endTime = endTime
                end

                -- Recalculate running total from settled dice.
                local total = d.m_mod
                local count = 0
                for _, value in pairs(d.m_diceFaces) do
                    count = count + 1
                    total = total + value
                end

                if count == d.m_numDice then
                    -- All dice have values -- compute the running tier.
                    local rm = d.rollMsg
                    local tier = 1
                    if (rm.autosuccess) then
                        tier = 3
                    elseif (rm.autofailure) then
                        tier = 1
                    else
                        if total >= 17 then
                            tier = 3
                        elseif total >= 12 then
                            tier = 2
                        end
                        local boons = rm.boons or 0
                        local banes = rm.banes or 0
                        if boons >= 2 and banes == 0 then
                            tier = tier + 1
                        elseif banes >= 2 and boons == 0 then
                            tier = tier - 1
                        end
                        tier = tier + (rm.tiers or 0)
                        if tier > 3 then tier = 3 end
                        if tier < 1 then tier = 1 end
                        if tier == 3 and rm.nottierthree then
                            tier = 2
                        end
                        if tier == 1 and rm.nottierone then
                            tier = 2
                        end
                    end

                    -- Remember the last computed tier so the think
                    -- handler can lock it in when the dice settle.
                    d.m_currentTier = tier

                    for idx, row in ipairs(element.children) do
                        SetTierHighlight(row, idx == tier)
                    end
                end
            end,

            think = function(element)
                local d = element.data
                if d == nil then
                    return
                end

                -- When all dice have settled, lock in the final tier
                -- using the authoritative result from the rollMsg,
                -- matching the pattern in MCDMAbilityRollBehavior.lua.
                if not d.m_finished and d.m_endTime ~= nil and dmhub.Time() > d.m_endTime and d.rollMsg.total ~= nil then
                    d.m_finished = true
                    local finalTier = RollUtils.DiceResultToTier(d.rollMsg)
                    for idx, row in ipairs(element.children) do
                        SetTierHighlight(row, idx == finalTier)
                    end
                end

                -- Once finished (either from dice settling above or
                -- from the m_numDice==0 path in create), fire an event
                -- so sibling labels (phase banner, roll state) can
                -- update themselves.
                if d.m_finished and not d.m_eventFired then
                    d.m_eventFired = true
                    element.thinkTime = 0
                    element.root:FireEventTree("rollDiceSettled")
                end
            end,
        }

        sections[#sections+1] = tierContainer
    end

    -- Triggers display.
    if ds.triggers ~= nil and #ds.triggers > 0 then
        local trigChildren = {}
        for index, trig in ipairs(ds.triggers) do
            local triggerIndex = index
            local trigToken = dmhub.GetTokenById(trig.charid)
            local tokenImg = nil
            if trigToken ~= nil and trigToken.valid then
                tokenImg = gui.CreateTokenImage(trigToken, {
                    width = 36, height = 36,
                    halign = "center", valign = "top",
                })
            end

            local triggered = trig.triggered

            trigChildren[#trigChildren+1] = gui.Panel{
                classes = {
                    cond(triggered, "bgInverse", "transparent"),
                    cond(triggered, "borderInverse", "border"),
                },
                width = 120,
                height = 70,
                bgimage = true,
                flow = "vertical",
                borderWidth = 1,
                halign = trig.hostile and "right" or "left",
                -- Triggered fills with the inverse surface; resting is transparent.
                updateRollDialog = function(element, ds)
                    local trig = ds.triggers[triggerIndex]
                    if trig ~= nil then
                        local on = trig.triggered
                        element:SetClass("bgInverse", on)
                        element:SetClass("transparent", not on)
                        element:SetClass("borderInverse", on)
                        element:SetClass("border", not on)
                    end
                end,

                tokenImg,
                gui.Label{
                    classes = {"sizeXs", cond(triggered, "fgInverse")},
                    text = trig.name,
                    bold = true,
                    width = "auto", height = "auto",
                    halign = "center",
                    -- Dark inverse text on the triggered fill; default otherwise.
                    updateRollDialog = function(element, ds)
                        local trig = ds.triggers[triggerIndex]
                        if trig ~= nil then
                            element:SetClass("fgInverse", trig.triggered)
                        end
                    end,
                },
            }
        end
        if #trigChildren > 0 then
            sections[#sections+1] = gui.Panel{
                width = "100%", height = "auto",
                maxHeight = 96,
                wrap = true,
                flow = "horizontal",
                valign = "top",
                children = trigChildren,
            }
        end
    end

    -- Roll state indicator. Listens for rollDiceSettled to transition
    -- from "Rolling..." to "Awaiting result..." when dice settle locally.
    if ds.rollState == "rolling" then
        sections[#sections+1] = gui.Label{
            classes = {"sizeM", "warning"},
            text = "Rolling...",
            bold = true,
            width = "auto", height = "auto",
            halign = "center",
            tmargin = 4,
            italics = true,
            -- On local dice settle, shift from active (warning) to pending.
            rollDiceSettled = function(element)
                element.text = "Awaiting result..."
                element:SetClass("warning", false)
                element:SetClass("fgPending", true)
            end,
        }
    elseif ds.rollState == "finished" then
        sections[#sections+1] = gui.Label{
            classes = {"sizeM", "fgPending"},
            text = "Awaiting result...",
            bold = true,
            width = "auto", height = "auto",
            halign = "center",
            tmargin = 4,
            italics = true,
        }
    end

    if #sections == 0 then
        return nil
    end

    -- Phase banner tab on the left edge, matching the style used by the
    -- interactive EmbeddedRollDialog ("Roll Dice", "Results", etc.).
    -- The "Target" tab is already built into the ability tooltip so we
    -- only add tabs for the roll and results phases.
    local phaseTab = nil
    local phaseLabelText = nil
    if ds.rollState == "finished" then
        phaseLabelText = "Results"
    elseif ds.rollState ~= nil then
        phaseLabelText = "Roll Dice"
    end

    if phaseLabelText ~= nil then
        local phaseLabelElement = gui.Label{
            classes = {"fgInverse"},
            width = "auto",
            height = "auto",
            fontSize = 22,
            bold = true,
            text = phaseLabelText,
            y = -18,
            rotate = 90,
            halign = "center",
            valign = "center",
            rollDiceSettled = function(element)
                element.text = "Results"
            end,
        }

        phaseTab = gui.Panel{
            classes = {"bgInfo"},
            styles = {
                {
                    selectors = {"results"},
                    y = 60,
                }
            },
            x = -32,
            floating = true,
            valign = "top",
            halign = "left",
            height = 166 * 0.8,
            width = 33 * 0.8,
            bgimage = ActivatedAbility.TabBGImage(),
            rollDiceSettled = function(element)
                element:SetClass("results", true)
            end,
            phaseLabelElement,
        }
    end

    -- Add the floating tab as a child -- it won't affect the vertical
    -- flow because it is positioned with floating = true.
    if phaseTab ~= nil then
        sections[#sections+1] = phaseTab
    end

    return gui.Panel{
        width = 340,
        height = "auto",
        halign = "center",
        flow = "vertical",
        pad = 6,
        tmargin = 4,
        children = sections,
    }
end

-- The userid of the share data currently rendered as a remote display,
-- or nil if nothing is shown.
local g_remoteDisplayUserId = nil

-- The ability panel currently embedded in the remote display, used for
-- incremental updates without rebuilding the full tooltip.
local g_remoteAbilityPanel = nil

-- The last section highlighted on the remote ability panel.
local g_remoteLastSection = nil

-- The last dialog rollState we embedded roll info for.  Used to avoid
-- rebuilding the roll info panel during "rolling" (which would destroy
-- the dice event subscriptions on the tier table).
local g_remoteLastRollState = nil

-- Render a remote ability timeline from shared document data, or clear
-- it when the document is empty / expired.  Called from refreshGame on
-- the ability display panel.
local function RefreshRemoteAbilityDisplay(displayPanel, shareData)
    -- Determine whether we should show a remote display.
    local shouldShow = false

    if shareData ~= nil
        and shareData.ability ~= nil
        and shareData.casterTokenId ~= nil
        and shareData.userid ~= nil
        and shareData.userid ~= dmhub.loginUserid
    then
        -- Check heartbeat expiry (10 seconds).
        local age = TimestampAgeInSeconds(shareData.heartbeat or 0)
        if age < 10 then
            shouldShow = true
        end
    end

    -- Also suppress if the local user already has an ability displayed.
    if g_displayedAbility ~= nil then
        shouldShow = false
    end

    if not shouldShow then
        if g_remoteDisplayUserId ~= nil then
            g_remoteDisplayUserId = nil
            g_remoteAbilityPanel = nil
            g_remoteLastSection = nil
            g_remoteLastRollState = nil
            displayPanel.children = {}
        end
        return
    end

    local ability = shareData.ability
    local casterToken = dmhub.GetTokenById(shareData.casterTokenId)

    -- If the remote display is already showing for this user, do an
    -- incremental update: replace the embedded roll info and update
    -- section highlighting without rebuilding the full ability tooltip.
    if g_remoteDisplayUserId == shareData.userid and g_remoteAbilityPanel ~= nil and g_remoteAbilityPanel.valid then
        -- Rebuild the roll info panel when data changes, EXCEPT during
        -- "rolling" where the tier table has live dice event
        -- subscriptions that would be destroyed by a rebuild.
        local currentRollState = shareData.dialogState
            and shareData.dialogState.rollState or nil
        if currentRollState ~= g_remoteLastRollState then
            g_remoteLastRollState = currentRollState
            local rollInfoPanel = CreateReadOnlyRollInfo(shareData)
            if rollInfoPanel ~= nil then
                g_remoteAbilityPanel:FireEventTree("embedRollDialog", rollInfoPanel)
            end
        elseif shareData.dialogState ~= nil then
            g_remoteAbilityPanel:FireEventTree("updateRollDialog", shareData.dialogState)
        end

        -- Update section highlighting if changed.
        if shareData.section ~= nil and shareData.section ~= g_remoteLastSection then
            g_remoteAbilityPanel:FireEventTree("showAbilitySection", {
                ability = ability,
                section = shareData.section,
            })
            g_remoteLastSection = shareData.section
        end
        return
    end

    -- Full rebuild: build the ability tooltip card.
    if ability.typeName ~= "ActivatedAbility" then
        return
    end

    local tooltipAbility = ability
    if casterToken ~= nil and casterToken.valid then
        tooltipAbility = ability:GetActiveVariation(casterToken) or ability
    end

    local abilityPanel = CreateAbilityTooltip(tooltipAbility, {
        width = 346,
        token = casterToken,
    })

    if abilityPanel == nil then
        if g_remoteDisplayUserId ~= nil then
            g_remoteDisplayUserId = nil
            g_remoteAbilityPanel = nil
            g_remoteLastSection = nil
            g_remoteLastRollState = nil
            displayPanel.children = {}
        end
        return
    end

    abilityPanel:MakeNonInteractiveRecursive()

    -- Build the read-only roll info and embed it.
    local rollInfoPanel = CreateReadOnlyRollInfo(shareData)
    if rollInfoPanel ~= nil then
        abilityPanel:FireEventTree("embedRollDialog", rollInfoPanel)
    end

    -- Apply section highlighting if the caster has progressed.
    if shareData.section ~= nil then
        abilityPanel:FireEventTree("showAbilitySection", {
            ability = ability,
            section = shareData.section,
        })
    end
    g_remoteLastSection = shareData.section
    g_remoteLastRollState = shareData.dialogState
        and shareData.dialogState.rollState or nil

    -- Build a header showing who is casting.
    local headerChildren = {}
    if casterToken ~= nil and casterToken.valid then
        headerChildren[#headerChildren+1] = gui.CreateTokenImage(casterToken, {
            width = 28,
            height = 28,
        })
    end
    local casterName = "A creature"
    if casterToken ~= nil and casterToken.valid then
        casterName = casterToken.description or "Unknown"
    end
    headerChildren[#headerChildren+1] = gui.Label{
        classes = {"sizeS", "fgMuted"},
        text = string.format("%s is using %s", casterName, ability.name or "an ability"),
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 6,
        italics = true,
    }

    local header = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        bmargin = 4,
        children = headerChildren,
    }

    displayPanel.children = { header, abilityPanel }
    g_remoteDisplayUserId = shareData.userid
    g_remoteAbilityPanel = abilityPanel
end

-- Declared as a valid default so reading GameHud.instance.abilityDisplay returns
-- false (rather than throwing "unknown field in type Hud") before
-- InitAbilityDisplayPanel has run / on clients where the panel never gets set up.
-- Every reader guards on truthiness, so false reads as "no panel yet". Mirrors the
-- GameHud.instance = false pattern in GameHud.lua.
GameHud.abilityDisplay = false

function GameHud:InitAbilityDisplayPanel(abilityDisplayPanel)
    local resultPanel

    -- Panel used to show a remote player's ability timeline.
    local remoteDisplayPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        interactable = false,
        valign = "center",

        monitorGame = mod:GetDocumentSnapshot(g_abilityShareDocId).path,

        refreshGame = function(element)
            local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
            RefreshRemoteAbilityDisplay(element, doc.data)
        end,

        -- Periodically check heartbeat expiry so the display is removed
        -- even if no new document change arrives.
        thinkTime = 5,
        think = function(element)
            if g_remoteDisplayUserId == nil then
                return
            end
            local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
            local heartbeat = doc.data.heartbeat
            if heartbeat == nil or TimestampAgeInSeconds(heartbeat) >= 10 then
                g_remoteDisplayUserId = nil
                g_remoteAbilityPanel = nil
                g_remoteLastSection = nil
                g_remoteLastRollState = nil
                element.children = {}
            end
        end,
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        interactable = false,

        showAbility = function(element, token, ability, symbols, displayOptions)
            g_displayedAbility = ability

            -- Hide the remote display while a local ability is shown.
            remoteDisplayPanel.children = {}
            g_remoteDisplayUserId = nil
            g_remoteAbilityPanel = nil
            g_remoteLastSection = nil
            g_remoteLastRollState = nil

            -- Sharing is not started here. It begins in
            -- HighlightAbilitySection, which is the definitive signal
            -- that the ability is being actively used (targeting has
            -- begun) rather than just previewed on hover.

            displayOptions = displayOptions or {}

            local panel

            local needParent = true

            if not displayOptions.renderAsAbility then
                if ability.typeName == "ActiveTrigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability:GetText())
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, valign = "center" }
                        panel:SetClass("hidden", false)
                        panel:SetClass("collapsed", false)
                    else
                        --cannot render an active trigger without a display.
                        return
                    end
                elseif ability.typeName == "TriggeredAbilityDisplay" then
                    panel = ability:Render { width = 340, valign = "center" }
                elseif ability.categorization == "Trigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability.name)
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, valign = "center", token = token, ability = ability, symbols = symbols }
                    end
                end
            end

            if panel == nil and ability.typeName ~= "ActiveTrigger" then
                needParent = false
                panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                    { token = token, symbols = symbols, width = 346, })
                if panel == nil then
                    return
                end
                --Shwayguy: Entire panel cannot be made non-interactive
                --Implementation chip hover requires it
                panel:MakeNonInteractiveRecursive()
            end

            if panel == nil then
                return
            end

            if needParent then
                panel = gui.Panel{
                    classes = {"bgAlt"},
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    blurBackground = true,
                    panel,
                }
            end

            if dmhub.isDM then
                local abilityNamePanel = panel:FindChildRecursive(function(p)
                    return p:HasClass("abilityName")
                end)
                if abilityNamePanel ~= nil then
                    local rollVisibilityEye = gui.VisibilityPanel{
                        visible = dmhub.GetSettingValue("privaterolls") ~= "dm",
                        floating = true,
                        halign = "right",
                        valign = "top",
                        x = 20,
                        width = 20,
                        height = 20,
                        interactable = true,

                        press = function(el)
                            local isVisible = el:HasClass("visible")
                            el:FireEventTree("visible", not isVisible)
                            dmhub.SetSettingValue("privaterolls", cond(isVisible, "dm", "visible"))
                            dmhub.SetSettingValue("privaterolls:save", true)
                            if isVisible then
                                -- Toggled to hidden: clear any active share.
                                ClearAbilityShare()
                            else
                                -- Toggled to visible: begin sharing if mid-ability.
                                if g_displayedAbility ~= nil and token ~= nil and token.valid then
                                    BeginAbilitySharing(token, g_displayedAbility)
                                end
                            end
                        end,

                        hover = function(el)
                            local text
                            if el:HasClass("visible") then
                                text = "Ability visible to everyone"
                            else
                                text = "Ability hidden from players"
                            end
                            gui.Tooltip(text)(el)
                        end,
                    }

                    abilityNamePanel.children = {rollVisibilityEye}
                end
            end

            element.children = {panel}

        end,

        hideAbility = function(element)
            element.children = {}

            -- The local ability was hidden; re-evaluate whether a remote
            -- display should appear.
            g_displayedAbility = nil
            local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
            RefreshRemoteAbilityDisplay(remoteDisplayPanel, doc.data)

            -- Defer clearing the share so that if the ability is being
            -- replaced (e.g. targeting finished, cast phase starting),
            -- the new DisplayAbility call has time to re-establish
            -- g_displayedAbility before we wipe the share.
            dmhub.Schedule(0.2, function()
                if mod.unloaded then return end
                if g_displayedAbility == nil then
                    ClearAbilityShare()
                end
            end)
        end,
    }

    self.abilityDisplay = resultPanel

    abilityDisplayPanel.children = {resultPanel, remoteDisplayPanel}
end

if GameHud.instance and rawget(GameHud.instance, "abilityDisplayPanel") ~= nil then
    GameHud.instance:InitAbilityDisplayPanel(GameHud.instance.abilityDisplayPanel)
end

function CharacterPanel.FindEmbeddedRollDialog()
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return nil
    end

    local panel = GameHud.instance.abilityDisplay
    local embedded = panel:FindChildRecursive(function(p)
        return p:HasClass("embeddedRollDialog")
    end)
    return embedded
end

--True if a roll dialog is currently shown in the standalone roll host (table
--rolls and other non-ability rolls routed through EmbedDialogStandalone). This
--host carries no cast-coroutine ownership, so it is safe to wait on without
--risking a self-deadlock from a cast's own embedded dialog.
function CharacterPanel.StandaloneRollShown()
    local hud = rawget(GameHud, "instance")
    if not hud then
        return false
    end

    local host = rawget(hud, "standaloneRollHost")
    if host == nil or not host.valid then
        return false
    end

    for _, child in ipairs(host.children) do
        if child.valid and child.data ~= nil
           and child.data.IsShown ~= nil and child.data.IsShown() then
            return true
        end
    end

    return false
end

--True if the embedded ability dialog is occupied -- either visibly shown, or
--mid-acquisition: created and stamped with a live cast (castCoroutine) that has
--not relinquished its roll, but whose ShowDialog has not fired yet.
--
--AcquireAbilityRollDialog shows a roll in several steps with yields in between
--(DisplayAbility -> EmbedDialogInAbility -> yield -> the behavior calls
--ShowDialog), so there is a window where the dialog exists and is owned but
--IsShown() is still false. Counting only IsShown() there let a concurrent
--table-roll request (e.g. the Conduit prayer, fired from the action-request
--listener) slip into that gap and pop alongside the damage roll -- the
--player-side overlap. This mirrors the "queue behind it" classification in
--AcquireAbilityRollDialog so the gap is treated as occupied.
function CharacterPanel.EmbeddedRollInFlight()
    local embedded = CharacterPanel.FindEmbeddedRollDialog()
    if embedded == nil or not embedded.valid or embedded.data == nil then
        return false
    end

    if embedded.data.IsShown ~= nil and embedded.data.IsShown() then
        return true
    end

    --Not yet shown: occupied only while a live cast still owns an unfinished
    --roll. A relinquished roll, a dead owner, or an untracked lingering panel
    --is not in flight and must not block (avoids deadlock on leftovers).
    local ownerco = embedded.data.castCoroutine
    if ownerco ~= nil and (not embedded.data.rollRelinquished)
       and coroutine.IsCoroutineWithIdStillRunning(ownerco) then
        return true
    end

    return false
end

--Single source of truth for "is any dice-roll dialog currently in flight?"
--There are three independent roll surfaces, and each legacy gate only watched
--one of them -- which let, e.g., a Conduit prayer table roll (standalone host)
--pop on top of an ongoing-effect damage roll (embedded ability dialog):
--  1. the legacy singleton gamehud.rollDialog
--  2. the embedded ability dialog mounted in abilityDisplay
--  3. any dialog mounted in the standalone roll host (table rolls)
function CharacterPanel.AnyRollDialogShown()
    local hud = rawget(GameHud, "instance")
    if not hud then
        return false
    end

    --1. legacy singleton.
    local singleton = rawget(hud, "rollDialog")
    if singleton ~= nil and singleton.valid and singleton.data ~= nil
       and singleton.data.IsShown ~= nil and singleton.data.IsShown() then
        return true
    end

    --2. embedded ability dialog (shown or mid-acquisition).
    if CharacterPanel.EmbeddedRollInFlight() then
        return true
    end

    --3. standalone roll host.
    return CharacterPanel.StandaloneRollShown()
end

function CharacterPanel.EmbedDialogInAbility()
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()

    local panel = GameHud.instance.abilityDisplay
    panel:FireEventTree("embedRollDialog", dialog)
    return dialog
end

--Mount the embedded roll dialog in the standalone host (for roll-table and
--other non-ability rolls). Returns the dialog so the caller can ShowDialog.
function CharacterPanel.EmbedDialogStandalone()
    if (not GameHud.instance) or (not GameHud.instance.standaloneRollHost) then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()
    GameHud.instance.standaloneRollHost:FireEvent("embedRollDialog", dialog)
    return dialog
end

--Built as an inner panel because gui.Panel only registers event handlers
--passed at construction; assigning them on an existing panel is a no-op.
function GameHud:InitStandaloneRollHost(hostPanel)
    local innerPanel
    innerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",

        embedRollDialog = function(element, dialog)
            element.children = { dialog }
        end,

        --Poll to clear the mounted dialog after it hides itself. No
        --upward-traveling close event exists to listen for.
        thinkTime = 0.25,
        think = function(element)
            local child = element.children[1]
            if child ~= nil and ((not child.valid) or child:HasClass("hidden")) then
                element.children = {}
            end
        end,
    }

    hostPanel.children = { innerPanel }
    self.standaloneRollHost = innerPanel
end

if GameHud.instance and rawget(GameHud.instance, "standaloneRollHostPanel") ~= nil then
    GameHud.instance:InitStandaloneRollHost(GameHud.instance.standaloneRollHostPanel)
end

local g_abilityLocked = false

function CharacterPanel.UnlockDisplayAbility()
    g_abilityLocked = false
end

function CharacterPanel.DisplayAbility(token, ability, symbols, options)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return false
    end

    options = options or {}

    local panel = GameHud.instance.abilityDisplay

    local embeddedRoll = panel:FindChildRecursive(function(p)
        return p:HasClass("embeddedRollDialog")
    end)
    if embeddedRoll ~= nil then
        --could not displace existing ability.
        if g_abilityLocked then
            return false
        end

        -- Displace the existing ability visually, but do NOT clear
        -- sharing or g_displayedAbility. This path is hit when the
        -- same ability transitions from targeting to casting (e.g. the
        -- player clicked a target). Sharing should continue
        -- uninterrupted -- showAbility is about to fire next and will
        -- repopulate the panel.
        panel.children = {}
    end

    local displayOptions = {}
    if options.renderAsAbility then
        displayOptions.renderAsAbility = true
    end
    panel:FireEventTree("showAbility", token, ability, symbols, displayOptions)

    if options.lock then
        g_abilityLocked = true
    end

    return true
end

--Acquire an embedded roll dialog for an ability-roll behavior, serializing
--against any other ability roll in progress.
--
--Every ability cast runs all its behaviors in one coroutine, so the embedded
--roll dialog is stamped with that coroutine id (data.castCoroutine) and a
--data.rollRelinquished flag (set false here, set true by the dialog's
--RelinquishPanel when its roll finishes). Together they classify any dialog
--already on screen:
--   * castCoroutine == mine            -> reuse it (power roll then damage in
--                                         one cast share a dialog)
--   * owner alive and not relinquished -> queue (its roll is mid-flight; this
--                                         includes the not-yet-shown window
--                                         right after creation)
--   * relinquished / owner dead / untracked -> displace the lingering panel
--
--Classifying by rollRelinquished rather than IsShown is what makes the
--not-yet-shown init window safe (IsShown is false there too), while still
--letting a finished-but-lingering dialog be displaced -- so a cast that invokes
--a sub-ability roll does not deadlock against its own leftover panel.
--
--Must be called from within a cast coroutine (every ability behavior is).
--
--castOptions: the behavior's `options` table. If passed and a fresh card is
--shown, a cast-aware HideAbility handler is appended to its OnFinishCastHandlers
--(see below). Omit it to skip handler installation.
--
--Returns: dialog, displayed
--  dialog    -- the roll dialog to call ShowDialog on (the embedded dialog, or
--               GameHud.instance.rollDialog as a fallback when the sidebar is
--               unavailable). Caller should still nil/valid-check before use.
--  displayed -- true if a fresh ability card was shown; false when reusing a
--               dialog an earlier behavior of the same cast established.
function CharacterPanel.AcquireAbilityRollDialog(token, ability, symbols, displayOptions, castOptions)
    local coid = coroutine.GetCurrentId()

    --DIAG: trace roll-dialog acquisition while chasing the "dialog vanished,
    --dice stuck" bug. Pairs with the "RollDialog:: DESTROY" traceback. Safe to keep.
    print(string.format("AcquireRollDialog:: enter coid=%s ability=%s",
        tostring(coid), tostring(ability ~= nil and ability.name)))

    local waited = false
    while true do
        --Queue behind a roll mounted in the standalone host (table rolls etc.).
        --It carries no cast-coroutine ownership, so we simply wait for it to
        --clear. Only do this when we can yield; outside a coroutine we cannot
        --wait, so fall through (matches the embedded not-in-a-coroutine path).
        if coid ~= nil and (not mod.unloaded) and CharacterPanel.StandaloneRollShown() then
            if not waited then
                waited = true
                print("AcquireRollDialog:: QUEUE behind standalone roll dialog")
            end
            coroutine.yield(0.01)
            --re-evaluate from the top: the standalone roll may have cleared,
            --or an embedded dialog may now need classifying.
            goto continue
        end

        local existing = CharacterPanel.FindEmbeddedRollDialog()
        if existing == nil then
            break
        end

        local ownerco = nil
        local relinquished = false
        if existing.data ~= nil then
            ownerco = existing.data.castCoroutine
            relinquished = existing.data.rollRelinquished
        end

        if ownerco ~= nil and ownerco == coid then
            --This cast already has a dialog up; sequential behaviors share it.
            --Re-mark it active so a concurrent cast does not displace it in the
            --gap before we call ShowDialog on it again.
            if existing.data ~= nil then
                existing.data.rollRelinquished = false
            end
            print("AcquireRollDialog:: REUSE (own cast's dialog)")
            return existing, false
        end

        --Another cast's dialog. Displace only when its roll is finished
        --(relinquished -- panel just lingering until that cast ends), its
        --owning coroutine has died, or it is untracked. While its roll is in
        --progress -- including the not-yet-shown init window -- queue behind it.
        if ownerco == nil then
            print("AcquireRollDialog:: displace (untracked dialog)")
            break
        end
        if relinquished then
            print(string.format("AcquireRollDialog:: displace relinquished dialog castCoroutine=%s", tostring(ownerco)))
            break
        end
        if not coroutine.IsCoroutineWithIdStillRunning(ownerco) then
            print(string.format("AcquireRollDialog:: displace (owner dead) castCoroutine=%s", tostring(ownerco)))
            break
        end
        if coid == nil then
            --Cannot yield outside a coroutine; do not hang.
            print("AcquireRollDialog:: displace (caller not in a coroutine)")
            break
        end

        if not waited then
            waited = true
            print(string.format("AcquireRollDialog:: QUEUE behind dialog castCoroutine=%s", tostring(ownerco)))
        end
        coroutine.yield(0.01)

        ::continue::
    end

    --Clear any stale lock so DisplayAbility's displace guard does not refuse us.
    CharacterPanel.UnlockDisplayAbility()

    local displayed = CharacterPanel.DisplayAbility(token, ability, symbols, displayOptions)

    local dialog = CharacterPanel.EmbedDialogInAbility()
    if dialog ~= nil then
        if dialog.data ~= nil then
            dialog.data.castCoroutine = coid
            dialog.data.rollRelinquished = false
        end

        --give a few cycles for the dialog to init.
        for i = 1, 4 do
            coroutine.yield(0.01)
        end
    else
        dialog = GameHud.instance.rollDialog
    end

    --Install the ability-card hide handler ourselves, cast-aware: a shared
    --ability object can back several concurrent casts, so HideAbility(ability)
    --keyed on object identity alone can tear down a different cast's live
    --dialog. Only hide if the dialog on screen is still this cast's (or gone).
    if displayed and castOptions ~= nil then
        castOptions.OnFinishCastHandlers = castOptions.OnFinishCastHandlers or {}
        castOptions.OnFinishCastHandlers[#castOptions.OnFinishCastHandlers+1] = function()
            local cur = CharacterPanel.FindEmbeddedRollDialog()
            if cur ~= nil and cur.data ~= nil and cur.data.castCoroutine ~= nil
               and cur.data.castCoroutine ~= coid then
                --A different cast's dialog is on screen now; leave it alone.
                return
            end
            CharacterPanel.HideAbility(ability)
        end
    end

    print(string.format("AcquireRollDialog:: CREATE coid=%s displayed=%s dialogValid=%s",
        tostring(coid), tostring(displayed), tostring(dialog ~= nil and dialog.valid)))
    return dialog, displayed
end

function CharacterPanel.HighlightAbilitySection(options)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return
    end

    local panel = GameHud.instance.abilityDisplay
    panel:FireEventTree("showAbilitySection", options)

    -- Begin sharing if we haven't already. HighlightAbilitySection is
    -- the definitive signal that the ability is being actively used
    -- (targeting has begun), regardless of how the ability was activated
    -- (direct click vs action bar menu).
    if g_sharingData == nil
        and options.caster ~= nil
        and g_displayedAbility ~= nil
        and ShouldShareAbility(options.caster)
    then
        BeginAbilitySharing(options.caster, g_displayedAbility)
    end

    -- Update the shared document with the new section.
    if g_sharingData ~= nil then
        g_sharingData.section = options.section
        WriteAbilityShare()
    end
end

-- Update the shared ability data with targeting and modifier information.
-- Called from ability cast code after the roll dialog is configured.
-- data fields: targetTokenIds (string[]), modifiers ({name, guid, enabled}[])
function CharacterPanel.UpdateAbilitySharing(data)
    if g_sharingData == nil then
        return
    end

    for k, v in pairs(data) do
        g_sharingData[k] = v
    end

    -- Mirror the target list into the engine's "current casting" state so spine eye-IK
    -- on the caster picks up the first target as its look-at point.
    if data.targetTokenIds ~= nil and spine.setCurrentCastingTargets ~= nil then
        spine.setCurrentCastingTargets(data.targetTokenIds)
    end

    WriteAbilityShare()
end

function CharacterPanel.HideAbility(ability)
    local hud = rawget(GameHud, "instance")
    if (not hud) or (not rawget(hud, "abilityDisplay")) then
        return
    end

    local panel = hud.abilityDisplay

    local ctrl = dmhub.modKeys['ctrl'] or false
    if ctrl then
        dmhub.Coroutine(function()
            while dmhub.modKeys['ctrl'] do
                coroutine.yield(0.1)
            end
            if panel ~= nil and panel.valid and ability == g_displayedAbility then
                panel:FireEvent("hideAbility")
            end
        end)
        return true
    end

    if panel ~= nil and panel.valid and ability == g_displayedAbility then
        panel:FireEvent("hideAbility")
        return true
    end

    return false
end

--On reset-turn / backup-restore, tear down any open embedded roll dialog.
--dialog.data.Cancel() runs the dialog's own CancelRollDialog -> cancelRoll
--callback -> RelinquishPanel, which is the same path used when the user
--clicks the cancel button. Cast coroutines blocked in AcquireAbilityRollDialog's
--queue loop wake up via the relinquish flag.
dmhub.RegisterEventHandler("restoreFromBackup", function()
    local dialog = CharacterPanel.FindEmbeddedRollDialog()
    --Guard on IsShown: dialog.data.Cancel does not self-check the hidden state,
    --and the captured cancelRoll closure is not cleared after a normal close,
    --so calling Cancel on a stale-hidden dialog could re-fire it.
    if dialog ~= nil and dialog.valid and dialog.data ~= nil
       and dialog.data.Cancel ~= nil and dialog.data.IsShown ~= nil
       and dialog.data.IsShown() then
        dialog.data.Cancel()
    end

    --Tear down any dialog mounted in the standalone roll host.
    if GameHud.instance ~= nil and GameHud.instance.standaloneRollHost ~= nil
       and GameHud.instance.standaloneRollHost.valid then
        local host = GameHud.instance.standaloneRollHost
        for _, child in ipairs(host.children) do
            if child.valid and child.data ~= nil
               and child.data.Cancel ~= nil and child.data.IsShown ~= nil
               and child.data.IsShown() then
                child.data.Cancel()
            end
        end
        host.children = {}
    end
end)
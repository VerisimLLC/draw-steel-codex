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
    if currentId == nil then
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

    -- Start heartbeat loop.
    dmhub.Schedule(3, HeartbeatAbilityShare)
end

-- Boon/bane label strings matching the interactive dialog.
local g_readOnlyBoonsLabels = { "BANEx2", "BANE", "NONE", "EDGE", "EDGEx2" }

-- Build a read-only modifier pill that mirrors the interactive ModifierPanel
-- style from EmbeddedRollDialog. Shows buff/debuff coloring and selected state.
local function CreateReadOnlyModifierPill(modInfo)
    local borderColor = "#777777"
    if modInfo.enabled then
        if modInfo.buffOrDebuff == "buff" then
            borderColor = Styles.ModifierBuffColor
        elseif modInfo.buffOrDebuff == "debuff" then
            borderColor = Styles.ModifierDebuffColor
        else
            borderColor = Styles.Gold04
        end
    end

    local indicatorBgcolor = "#777777"
    local indicatorCollapsed = true
    if modInfo.buffOrDebuff == "buff" then
        indicatorCollapsed = false
        indicatorBgcolor = modInfo.enabled and Styles.ModifierBuffColor or "#777777"
    elseif modInfo.buffOrDebuff == "debuff" then
        indicatorCollapsed = false
        indicatorBgcolor = modInfo.enabled and Styles.ModifierDebuffColor or "#777777"
    end

    local labelColor = modInfo.enabled and "white" or "#777777"

    return gui.Panel{
        borderColor = borderColor,
        borderWidth = 2,
        cornerRadius = 4,
        width = "auto",
        height = 18,
        pad = 4,
        flow = "horizontal",
        bgimage = true,
        bgcolor = Styles.RichBlack03,
        hmargin = 2,

        gui.Panel{
            bgimage = "drawsteel/Icons_Nav_CollapseArrow.png",
            width = 18,
            height = 18,
            bgcolor = indicatorBgcolor,
            collapsed = indicatorCollapsed and 1 or 0,
            uiscale = modInfo.buffOrDebuff == "buff" and {y=-1, x=1} or nil,
            y = modInfo.buffOrDebuff == "debuff" and 2 or 0,
        },

        gui.Label{
            text = modInfo.name,
            fontSize = 16,
            width = "auto",
            height = "auto",
            lmargin = 0,
            rmargin = 4,
            valign = "center",
            color = labelColor,
            opacity = modInfo.enabled and 0.95 or 0.6,
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
                            text = targetToken.description or "Unknown",
                            fontSize = 14, color = "white",
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
                        scale = isBane and {y=-1, x=1} or nil,
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
            local entryBgcolor = Styles.RichBlack03
            local entryBorderColor = Styles.Gold02
            local entryBorderWidth = 1
            if isSelected then
                entryBorderWidth = 2
                if isBoon then
                    entryBgcolor = "srgb:#000044"
                    entryBorderColor = Styles.ModifierBuffColor
                elseif isBane then
                    entryBgcolor = "srgb:#16080B"
                    entryBorderColor = Styles.ModifierDebuffColor
                else
                    entryBgcolor = "srgb:#16080B"
                end
            end

            boonEntries[#boonEntries+1] = gui.Panel{
                width = "auto", height = "auto",
                flow = "horizontal",
                bgimage = true,
                bgcolor = entryBgcolor,
                borderWidth = entryBorderWidth,
                borderColor = entryBorderColor,
                cornerRadius = 6,
                hpad = 6,
                vmargin = 2,
                iconPanel,
                gui.Label{
                    text = g_readOnlyBoonsLabels[i],
                    color = Styles.textColor,
                    valign = "center",
                    width = "auto", height = "auto",
                    bgimage = "panels/square.png",
                    fontSize = 14,
                    textAlignment = "center",
                    bold = isSelected,
                },
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
    if ds.modifiers ~= nil and #ds.modifiers > 0 then
        local modChildren = {}
        for _, m in ipairs(ds.modifiers) do
            -- Skip forced-hidden modifiers.
            if not m.forced then
                modChildren[#modChildren+1] = CreateReadOnlyModifierPill(m)
            end
        end
        if #modChildren > 0 then
            sections[#sections+1] = gui.Panel{
                width = "100%", height = "auto",
                flow = "horizontal",
                wrap = true,
                children = modChildren,
            }
        end
    end

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
                        fontSize = 12, bold = true,
                        color = Styles.textColor,
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
                bold = true, valign = "center",
                color = "white", text = "Surges:",
                width = "auto", height = "auto",
                fontSize = 14,
            }
            for s = 1, (target.surges or 0) do
                surgeChildren[#surgeChildren+1] = gui.Panel{
                    bgimage = "game-icons/surge.png",
                    width = 24, height = 24,
                    bgcolor = "white",
                }
            end
            sections[#sections+1] = gui.Panel{
                halign = "left", valign = "center",
                width = "auto", height = "auto",
                bgcolor = "black", bgimage = true,
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
                text = ds.rollText,
                fontSize = 14, bold = true,
                width = "auto", height = 18,
                lmargin = 6,
                halign = "left", valign = "center",
                color = "white",
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
                    text = string.format("%d", i),
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
                    },
                },
            }
        end

        -- Dice animation state -- stored on the table's data table so
        -- it survives across think ticks.
        local tierContainer = gui.Table{
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 4,
            styles = {
                {
                    selectors = {"row", "highlight"},
                    bgcolor = Styles.textColor,
                },
                {
                    selectors = {"label", "highlight"},
                    color = "black",
                },
            },
            children = tierRows,

            create = function(element)

                -- Apply the static highlight for finished rolls.
                if not isRolling then
                    if highlightTier ~= nil then
                        for idx, row in ipairs(element.children) do
                            row:SetClassTree("highlight", idx == highlightTier)
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
                            row:SetClassTree("highlight", idx == highlightTier)
                        end
                    end
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
                if m_numDice == 0 then
                    local tier = RollUtils.DiceResultToTier(rollMsg)
                    for idx, row in ipairs(element.children) do
                        row:SetClassTree("highlight", idx == tier)
                    end
                    element.data.m_finished = true
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
                        row:SetClassTree("highlight", idx == tier)
                    end
                end
            end,

            think = function(element)
                local d = element.data
                if d == nil then --or d.m_finished then
                    return
                end

                -- When all dice have settled, lock in the final tier
                -- using the authoritative result from the rollMsg,
                -- matching the pattern in MCDMAbilityRollBehavior.lua.
                if d.m_endTime ~= nil and dmhub.Time() > d.m_endTime then
                    d.m_finished = true
                    element.thinkTime = 0

                    local finalTier = RollUtils.DiceResultToTier(d.rollMsg)
                    for idx, row in ipairs(element.children) do
                        row:SetClassTree("highlight", idx == finalTier)
                    end
                end
            end,
        }

        sections[#sections+1] = tierContainer
    end

    -- Triggers display.
    if ds.triggers ~= nil and #ds.triggers > 0 then
        local trigChildren = {}
        for _, trig in ipairs(ds.triggers) do
            local trigToken = dmhub.GetTokenById(trig.charid)
            local tokenImg = nil
            if trigToken ~= nil and trigToken.valid then
                tokenImg = gui.CreateTokenImage(trigToken, {
                    width = 36, height = 36,
                    halign = "center", valign = "top",
                })
            end

            local trigBgcolor = trig.triggered and Styles.textColor or "#00000000"
            local labelColor = trig.triggered and Styles.backgroundColor or Styles.textColor

            trigChildren[#trigChildren+1] = gui.Panel{
                width = 120, height = 70,
                bgimage = true,
                bgcolor = trigBgcolor,
                flow = "vertical",
                borderWidth = 1,
                borderColor = trig.triggered and "white" or "grey",
                halign = trig.hostile and "right" or "left",

                tokenImg,
                gui.Label{
                    text = trig.name,
                    fontSize = 12, bold = true,
                    width = "auto", height = "auto",
                    halign = "center",
                    color = labelColor,
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

    -- Roll state indicator.
    if ds.rollState == "rolling" then
        sections[#sections+1] = gui.Label{
            text = "Rolling...",
            fontSize = 16, bold = true,
            color = "#ffdd88",
            width = "auto", height = "auto",
            halign = "center",
            tmargin = 4,
            italics = true,
        }
    elseif ds.rollState == "finished" then
        sections[#sections+1] = gui.Label{
            text = "Awaiting result...",
            fontSize = 16, bold = true,
            color = "#88ddff",
            width = "auto", height = "auto",
            halign = "center",
            tmargin = 4,
            italics = true,
        }
    end

    if #sections == 0 then
        return nil
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
    if g_remoteDisplayUserId == shareData.userid
        and g_remoteAbilityPanel ~= nil
        and g_remoteAbilityPanel.valid
    then
        -- Only rebuild the roll info panel when the rollState changes.
        -- During "rolling" the tier table has live dice event subscriptions;
        -- rebuilding it would destroy those and break the animation.
        local currentRollState = shareData.dialogState
            and shareData.dialogState.rollState or nil
        if currentRollState ~= g_remoteLastRollState then
            g_remoteLastRollState = currentRollState
            local rollInfoPanel = CreateReadOnlyRollInfo(shareData)
            if rollInfoPanel ~= nil then
                g_remoteAbilityPanel:FireEventTree("embedRollDialog", rollInfoPanel)
            end
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
    local tooltipAbility = ability
    if casterToken ~= nil and casterToken.valid and ability.GetActiveVariation ~= nil then
        tooltipAbility = ability:GetActiveVariation(casterToken) or ability
    end

    local abilityPanel = CreateAbilityTooltip(tooltipAbility, {
        width = 346,
        bgcolor = "#222222e9",
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
        text = string.format("%s is using %s", casterName, ability.name or "an ability"),
        fontSize = 14,
        color = "#dddddd",
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

        showAbility = function(element, token, ability, symbols)
            g_displayedAbility = ability

            -- Hide the remote display while a local ability is shown.
            remoteDisplayPanel.children = {}
            g_remoteDisplayUserId = nil
            g_remoteAbilityPanel = nil
            g_remoteLastSection = nil
            g_remoteLastRollState = nil

            -- Start sharing if this token is on the current turn.
            if ShouldShareAbility(token) then
                BeginAbilitySharing(token, ability)
            end

            local panel

            local needParent = true

                print("ABILITY:: RENDER TRIGGER START", ability.typeName)
            if ability.typeName == "ActiveTrigger" then
                local triggerInfo = token.properties:GetTriggeredActionInfo(ability:GetText())
                print("ABILITY:: RENDER TRIGGER", ability:GetText(), json(triggerInfo))
                if triggerInfo ~= nil then
                    panel = triggerInfo:Render { width = 340, valign = "center" }
                    panel:SetClass("hidden", false)
                    panel:SetClass("collapsed", false)
                end
            elseif ability.typeName == "TriggeredAbilityDisplay" then
                panel = ability:Render { width = 340, valign = "center" }
            else

                if ability.categorization == "Trigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability.name)
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, valign = "center", token = token, ability = ability, symbols = symbols }
                    end
                end

                if panel == nil then
                    needParent = false
                    panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                        { token = token, symbols = symbols, width = 346, bgcolor = "#222222e9", })
                    panel:MakeNonInteractiveRecursive()
                end
            end

            if needParent then
                panel = gui.Panel{
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    bgcolor = "#222222e9",
                    bgimage = true,
                    blurBackground = true,
                    panel,
                }
            end

            element.children = {panel}

        end,

        hideAbility = function(element)
            ClearAbilityShare()
            element.children = {}

            -- The local ability was hidden; re-evaluate whether a remote
            -- display should appear.
            g_displayedAbility = nil
            local doc = mod:GetDocumentSnapshot(g_abilityShareDocId)
            RefreshRemoteAbilityDisplay(remoteDisplayPanel, doc.data)
        end,
    }

    self.abilityDisplay = resultPanel

    abilityDisplayPanel.children = {resultPanel, remoteDisplayPanel}
end

if GameHud.instance and rawget(GameHud.instance, "abilityDisplayPanel") ~= nil then
    GameHud.instance:InitAbilityDisplayPanel(GameHud.instance.abilityDisplayPanel)
end

function CharacterPanel.EmbedDialogInAbility()
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()

    local panel = GameHud.instance.abilityDisplay
    print("HIDE:: DO EMBED")
    panel:FireEventTree("embedRollDialog", dialog)
    return dialog
end

function CharacterPanel.DisplayAbility(token, ability, symbols)
    print("MENU:: DISPLAY ABILITY", ability)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        print("MENU:: DISPLAY ABILITY FAILED")
        return false
    end

    local panel = GameHud.instance.abilityDisplay

    local embeddedRoll = panel:FindChildRecursive(function(p)
        return p:HasClass("embeddedRollDialog")
    end)
    if embeddedRoll ~= nil then
        print("MENU:: ALREADY HAVE AN ABILITY")
        --could not displace existing ability.
        --return false

        --displace existing ability.
        CharacterPanel.HideAbility(g_displayedAbility)
    end

        print("MENU:: DISPLAY ABILITY SHOWING")

    panel:FireEventTree("showAbility", token, ability, symbols)

    return true
end

function CharacterPanel.HighlightAbilitySection(options)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return
    end

    local panel = GameHud.instance.abilityDisplay
    panel:FireEventTree("showAbilitySection", options)

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

    WriteAbilityShare()
end

function CharacterPanel.HideAbility(ability)
    print("ABILITY:: HIDE", ability)
    if (not GameHud.instance) or (not rawget(GameHud.instance, "abilityDisplay")) then
        return
    end

    -- Clear sharing immediately when the ability hides, even if the
    -- visual hide is deferred (e.g. ctrl held).
    ClearAbilityShare()

    local panel = GameHud.instance.abilityDisplay

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
local mod = dmhub.GetModLoading()

local g_displayedAbility = nil

-- A card that was built invisible because it exists only to host a roll dialog that
-- may never appear (see AcquireAbilityRollDialog / RevealAbilityCard below). Holds the
-- card's wrapper panel until the dialog un-hides, at which point it is faded in and
-- this is cleared. nil whenever no card is waiting on a roll.
local g_deferredCard = nil

-- Abilities that were routed INTO the currently displayed card instead of getting a
-- card of their own -- i.e. Hidden sub-abilities that DisplayAbility deliberately
-- swallowed (see DisplayAbility below). Teardown calls HideAbility with whatever the
-- action bar last cast, which for an invoked sub-ability is one of these and never
-- g_displayedAbility, so an identity-only match left the parent card on screen
-- forever (report NA3SCFH5: "Aspect of the Wild" card stuck after shapeshifting).
-- Reset whenever the card is (re)populated or torn down.
local g_displayedAbilityAliases = {}

local function ClearDisplayedAbilityAliases()
    g_displayedAbilityAliases = {}
end

--True if `ability` owns the card currently on screen, either directly or because it
--was folded into that card as a Hidden sub-ability.
local function AbilityOwnsDisplayedCard(ability)
    if ability == nil or g_displayedAbility == nil then
        return false
    end

    if ability == g_displayedAbility then
        return true
    end

    for _,alias in ipairs(g_displayedAbilityAliases) do
        if alias == ability then
            return true
        end
    end

    return false
end

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
    -- The token can be stale/despawned by the time an invoke resolves (indexing
    -- .canControl on an invalid token raises "Error indexing userdata"). Guard so
    -- a sharing check can never throw and abort the caller (e.g. invokeAbility).
    if token == nil or not token.valid then
        return false
    end
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

--True when the local player's rolls (and therefore the ability card they are
--casting from) are shared with the whole table. Anything else -- "dm" or
--"dicetower" -- means some part of what is happening is private, which is what
--the roll-visibility banner on the ability card announces.
local function RollsVisibleToEveryone()
    return dmhub.GetSettingValue("privaterolls") == "visible"
end

--Apply a roll-visibility change made from the ability card itself (the director's
--eyelid, or the banner below). Writes the preference and starts/stops sharing so
--the change takes effect on the card that is already on screen.
local function SetAbilityRollVisibility(value, token)
    dmhub.SetSettingValue("privaterolls", value)
    dmhub.SetSettingValue("privaterolls:save", true)

    if value == "visible" then
        if g_displayedAbility ~= nil and token ~= nil and token.valid then
            BeginAbilitySharing(token, g_displayedAbility)
        end
    else
        ClearAbilityShare()
    end
end

-- Boon/bane label strings matching the interactive dialog.
local g_readOnlyBoonsLabels = { "BANEx2", "BANE", "NONE", "EDGE", "EDGEx2" }

-- Build a read-only modifier pill that mirrors the interactive ModifierPanel
-- style from EmbeddedRollDialog. Shows buff/debuff coloring and selected state.
-- Colors are driven by classes + selectors on the parent Modifiers panel.
local function CreateReadOnlyModifierPill(modInfo)
    local isBuff = modInfo.buffOrDebuff == "buff"
    local isDebuff = modInfo.buffOrDebuff == "debuff"

    --The latest broadcast info for this pill, so spoiler reveals can reformat
    --the label without waiting for the next broadcast.
    local m_info = modInfo

    --Spoilered modifier names ({#...} markup, see PowerRollSpoilers in
    --EmbeddedRollDialog) render as a redaction bar for players until the
    --director reveals them.
    local function FormatPillName(info)
        local text = info.name
        if PowerRollSpoilers.HasSpoiler(text) then
            local raw = info.spoilerName or text
            local revealed = PowerRollSpoilers.IsRevealed(PowerRollSpoilers.Key(raw),
                PowerRollSpoilers.DefaultRevealed(raw))
            text = PowerRollSpoilers.Format(text, revealed)
        end
        return text
    end

    --The director gets the eyelid toggle on the mirror pill too, since a
    --player's roll shows for the director only as this read-only view.
    local spoilerEye = nil
    if dmhub.isDM and PowerRollSpoilers.HasSpoiler(modInfo.spoilerName or modInfo.name or "") then
        local raw = modInfo.spoilerName or modInfo.name
        spoilerEye = PowerRollSpoilers.CreateEyeButton{
            key = PowerRollSpoilers.Key(raw),
            name = raw,
            description = modInfo.spoilerDescription or "",
            defaultRevealed = PowerRollSpoilers.DefaultRevealed(raw),
        }
    end

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
            text = FormatPillName(modInfo),
            width = "auto",
            height = "auto",
            lmargin = 0,
            rmargin = 4,
            valign = "center",

            --Re-render the redaction when the director reveals or hides the
            --spoiler mid-roll.
            monitorGame = PowerRollSpoilers.DocumentPath(),
            refreshGame = function(element)
                element.text = FormatPillName(m_info)
            end,

            -- Label brightens from muted to default when enabled.
            updateModifierPill = function(element, info)
                m_info = info
                element.text = FormatPillName(info)
                element:SetClass("fg", info.enabled)
                element:SetClass("fgMuted", not info.enabled)
            end,
        },

        spoilerEye,
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

--The grey banner pinned to the top of the ability card whenever the local
--player's rolls are NOT visible to everyone.
--
--Both the director and players get it. The director can hide rolls deliberately
--with the eyelid on the card, but a PLAYER has no eyelid at all and can end up
--stuck on "Visible to you and Director" forever just by leaving "save roll
--visibility preferences" ticked once in a roll dialog -- DSRollDialog writes the
--dropdown choice straight back into the `privaterolls` preference. ShouldShareAbility
--then refuses to broadcast anything they cast, so their ability cards silently stop
--appearing for the whole table with nothing on screen explaining why (report
--EHW82XXT: "I cannot see my player's ability cards while they are making rolls, I am
--the director"). The banner makes that state visible to whoever caused it, and is
--itself the one-click way out.
local function CreateRollVisibilityBanner(token, cardWidth)
    local function BannerText()
        if dmhub.GetSettingValue("privaterolls") == "dicetower" then
            return "Dice Tower Roll"
        end
        if dmhub.isDM then
            return "Hidden from Players"
        end
        return "Hidden from Other Players"
    end

    local function BannerTooltip()
        if dmhub.GetSettingValue("privaterolls") == "dicetower" then
            return "This roll goes to the dice tower -- only the Director sees the result.\n\nClick to make your rolls visible to everyone."
        end
        if dmhub.isDM then
            return "This ability is not being shared with your players.\n\nClick to make it visible to everyone."
        end
        return "This ability is only being shared with the Director -- the other players cannot see it.\n\nClick to make it visible to everyone."
    end

    local label

    local function Refresh(element)
        local hidden = not RollsVisibleToEveryone()
        element:SetClass("collapsed", not hidden)
        if hidden and label ~= nil and label.valid then
            label.text = string.format("<b>%s</b>", BannerText())
        end
    end

    label = gui.Label{
        classes = {"fgMuted", "sizeS"},
        text = string.format("<b>%s</b>", BannerText()),
        markdown = true,
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 6,
    }

    return gui.Panel{
        classes = {"bgAlt", cond(RollsVisibleToEveryone(), "collapsed")},
        bgimage = "panels/square.png",
        width = cardWidth,
        height = 22,
        halign = "left",
        valign = "top",
        flow = "horizontal",
        cornerRadius = 4,
        bmargin = 2,
        interactable = true,

        --Settings are polled, so this fires a frame after the eyelid (or the dice
        --panel, or the settings dialog) changes the preference.
        multimonitor = {"privaterolls"},
        monitor = function(element)
            Refresh(element)
        end,

        press = function(element)
            SetAbilityRollVisibility("visible", token)
            Refresh(element)
        end,

        hover = function(element)
            gui.Tooltip(BannerTooltip())(element)
        end,

        --The same eyelid that appears on the ability name, repeated here so the
        --banner reads as the state of that control.
        gui.Panel{
            classes = {"bgFgMuted"},
            bgimage = "ui-icons/eye-closed.png",
            width = 16,
            height = 16,
            valign = "center",
            lmargin = 8,
        },

        label,
    }
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
            --A fresh card owns itself; any sub-abilities folded into the previous
            --card are no longer relevant.
            ClearDisplayedAbilityAliases()

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
                --The card grows with the ability's text, and this sidebar is
                --height 100% / valign center, so a long enough ability runs off
                --both the top and the bottom of the screen. Tell the card how
                --much room there actually is and let its body scroll. Prefer the
                --laid-out height of the sidebar; fall back to the screen if this
                --is the first render and nothing has been measured yet.
                local availableHeight = element.renderedHeight
                if availableHeight == nil or availableHeight <= 0 then
                    availableHeight = dmhub.screenDimensionsBelowTitlebar.y
                end

                panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                    { token = token, symbols = symbols, width = 346,
                      maxHeight = math.max(200, availableHeight - 60), })
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
                    --Top, not center: the card is no longer the direct child of the
                    --sidebar, it shares a vertical wrapper with the visibility banner
                    --and that wrapper does the centering. Two siblings with different
                    --valigns in one vertical flow stack from opposite ends and overlap.
                    valign = "top",
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
                            SetAbilityRollVisibility(cond(isVisible, "dm", "visible"), token)
                        end,

                        --Keep the eyelid in step with the banner below it (and with
                        --any other surface that writes the preference, e.g. the dice
                        --panel's context menu or the settings dialog).
                        multimonitor = {"privaterolls"},
                        monitor = function(el)
                            local shouldBeVisible = dmhub.GetSettingValue("privaterolls") ~= "dm"
                            if el:HasClass("visible") ~= shouldBeVisible then
                                el:FireEventTree("visible", shouldBeVisible)
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

            --Wrap the card so the roll-visibility banner can sit above it. The card
            --width is fixed by the branch that built it (346 for the ability tooltip,
            --340 for the trigger renderers), so the banner is given the same width
            --rather than a "100%" that would have to resolve against an auto parent.
            local cardWidth = cond(needParent, 340, 346)

            --See the valign note above: the banner and the card must agree, and the
            --wrapper carries the centering the card used to do itself.
            panel.selfStyle.valign = "top"

            local wrapperArgs = {
                width = "auto",
                height = "auto",
                valign = "center",
                flow = "vertical",

                CreateRollVisibilityBanner(token, cardWidth),
                panel,
            }

            --A card raised purely to host a roll dialog is built invisible and only
            --revealed once that dialog actually un-hides (RevealAbilityCard). Rolls
            --that resolve without ever showing UI -- deterministic damage taking the
            --skipDeterministic fast path, a ShowDialog that bails -- therefore never
            --flash an empty card on screen for a few frames.
            --
            --`hidden`, NOT `opacity`: opacity is applied per widget to its own
            --bgimage/border/label colour (SheetPanel.RefreshStyle, SheetLabel) and is
            --never inherited, so opacity=0 on this bgimage-less wrapper hid nothing
            --at all. `hidden` hides the whole subtree and makes it non-interactive
            --while still taking up space in the flow, so the roll dialog mounted
            --inside still lays out and initializes during the wait -- the same state
            --the dialog itself lives in before its own ShowDialog.
            if displayOptions.deferReveal then
                wrapperArgs.hidden = 1
            end

            local cardWrapper = gui.Panel(wrapperArgs)
            if displayOptions.deferReveal then
                g_deferredCard = cardWrapper
            else
                g_deferredCard = nil
            end
            print(string.format("AbilityCard:: BUILD ability=%s deferred=%s",
                tostring(ability ~= nil and ability.name), tostring(displayOptions.deferReveal == true)))

            element.children = { cardWrapper }

        end,

        hideAbility = function(element)
            element.children = {}

            -- The local ability was hidden; re-evaluate whether a remote
            -- display should appear.
            g_deferredCard = nil
            g_displayedAbility = nil
            ClearDisplayedAbilityAliases()
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

--Hot-reload re-init. The `.valid` term is load-bearing, not defensive noise: the
--hud subtree can be gone while GameHud.instance (and its cached panel handles)
--live on, and a destroyed panel is still a truthy userdata. Re-initializing
--against a dead abilityDisplayPanel builds resultPanel/remoteDisplayPanel, then
--drops them -- `children =` is dead-panel guarded on the C# side and silently
--no-ops -- so the pair is left unparented for SheetManager's leak sweep to
--destroy, while `self.abilityDisplay = resultPanel` installs a permanently
--DESTROYED handle. Every later FindEmbeddedRollDialog / DisplayAbility then
--dereferences a null SheetPanel (NullReferenceException out of
--LuaSheetPanel.FindChildRecursive), and every EmbedDialogInAbility builds a roll
--dialog that nothing can mount. Skipping the re-init leaves the previous handle
--in place; the next CreateAbilityDisplayPanel (hud rebuild) sets up a live one.
local abilityDisplayPanelForReload = GameHud.instance and rawget(GameHud.instance, "abilityDisplayPanel")
if abilityDisplayPanelForReload and abilityDisplayPanelForReload.valid then
    GameHud.instance:InitAbilityDisplayPanel(abilityDisplayPanelForReload)
end

--The ability display / standalone roll hosts are cached panel references on the
--GameHud instance (see InitAbilityDisplayPanel / InitStandaloneRollHost). Nothing
--clears them when the panel behind them is destroyed -- the hud subtree can be torn
--down while GameHud.instance lives on -- and a destroyed panel handle is still a
--userdata, so it is TRUTHY in Lua. A plain `if not GameHud.instance.abilityDisplay`
--check therefore passes for a dead panel, and the code proceeds to use it. That is
--not harmless: the C# LuaSheetPanel accessors dereference a null SheetPanel, so
--FindChildRecursive / SetClassTree / canFocus throw NullReferenceException out
--through the Lua VM, while the handful of accessors that ARE dead-panel guarded
--(FireEvent, FireEventTree, `children =`) silently no-op -- which is how a freshly
--built roll dialog ends up parented to nothing and gets destroyed by SheetManager's
--end-of-frame leak sweep ("was created but not attached to a parent").
--
--`.valid` is the only reliable liveness test. Note the `not panel` term must come
--first: GameHud.abilityDisplay defaults to `false`, and indexing a boolean errors.
local function LiveHostPanel(name)
    local hud = rawget(GameHud, "instance")
    if not hud then
        return nil
    end

    --rawget: standaloneRollHost has no declared default, and reading an
    --undeclared field off a game-typed instance raises. Matches the existing
    --rawget guards in HideAbility / StandaloneRollShown.
    local panel = rawget(hud, name)
    if (not panel) or (not panel.valid) then
        return nil
    end

    return panel
end

function CharacterPanel.FindEmbeddedRollDialog()
    local panel = LiveHostPanel("abilityDisplay")
    if panel == nil then
        return nil
    end

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

    --An action-request prompt that has not finished yet. It has no cast to own
    --it, and it is hidden both before it appears and while its dice are in the
    --air, so without this flag those stretches read as "free" and a second
    --prompt lands on top of it. Cleared when the roll resolves.
    if embedded.data.promptPending then
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

--Both embed entry points hand the freshly built dialog to a fire-and-forget
--event and trust that something in the tree mounted it. Nothing verifies that,
--and an unmounted panel is not merely useless -- SheetManager's end-of-frame
--leak sweep destroys any panel still sitting on its birth root, logging
--"Panel ... was created but not attached to a parent". Returning that doomed
--handle is what strands the callers: ShowDialog silently bails on the now
--invalid panel (roll never happens), or -- when ShowDialog runs synchronously
--in the same frame, as the table-roll path does -- the roll starts and then its
--complete callback fires against destroyed widgets (SetClassTree / gui.SetFocus
---> NullReferenceException out of LuaSheetPanel).
--
--So: assert the handoff. If nothing took ownership, tear the orphan down here
--and report failure, which every caller already handles by falling back to the
--legacy roll dialog. A mounted dialog always has a parent by the time the
--synchronous FireEventTree returns -- every embedRollDialog handler mounts via
--`element.children = { dialog }`, which reparents immediately.
local function ClaimEmbeddedDialog(dialog, where)
    if dialog == nil then
        return nil
    end

    if dialog.valid and dialog.parent ~= nil then
        return dialog
    end

    print(string.format("RollDialog:: EMBED FAILED (%s) -- nothing mounted the dialog; destroying orphan", where))
    dialog:DestroySelf()
    return nil
end

--aiDriven: true when the roller is under Monster AI control. The AI drives and
--completes its own rolls, so the card must not offer a cancel affordance for
--one (the close X). Fired as a second event AFTER embedRollDialog, which is
--what reveals the button -- order matters. ESC still cancels.
function CharacterPanel.EmbedDialogInAbility(aiDriven)
    local panel = LiveHostPanel("abilityDisplay")
    if panel == nil then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()

    panel:FireEventTree("embedRollDialog", dialog)
    panel:FireEventTree("rollDialogAIDriven", aiDriven or false)
    return ClaimEmbeddedDialog(dialog, "ability")
end

--Mount the embedded roll dialog in the standalone host (for roll-table and
--other non-ability rolls). Returns the dialog so the caller can ShowDialog.
function CharacterPanel.EmbedDialogStandalone()
    local host = LiveHostPanel("standaloneRollHost")
    if host == nil then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()
    host:FireEvent("embedRollDialog", dialog)
    return ClaimEmbeddedDialog(dialog, "standalone")
end

--The ability whose card is on screen right now, or nil. Returns the object
--rather than a bool so callers can tell WHICH ability it is.
function CharacterPanel.DisplayedAbility()
    return g_displayedAbility
end

--Two abilities that mean "the same ability" for card purposes. A card can be
--showing the live object while a roll prompt arrives carrying a copy that came
--over the network, so plain == is not enough.
local function SameAbilityForCard(a, b)
    if a == nil or b == nil then
        return false
    end
    if a == b then
        return true
    end

    --pcall: the displayed "ability" can be a trigger or, in odd cases, a plain
    --table with no try_get at all.
    local function field(obj, key)
        local value = nil
        pcall(function() value = obj:try_get(key) end)
        return value
    end

    local guidA, guidB = field(a, "guid"), field(b, "guid")
    if guidA ~= nil and guidB ~= nil then
        return guidA == guidB
    end

    local nameA = field(a, "name")
    return nameA ~= nil and nameA == field(b, "name")
end

--typeName is a type-level property, so try_get does not see it and a plain
--table has none at all. pcall keeps both cases from raising.
local function TypeNameOf(obj)
    if obj == nil then
        return nil
    end
    local name = nil
    pcall(function() name = obj.typeName end)
    return name
end

--A leftover roll dialog we are allowed to throw away: it is not on screen, and
--no live ability cast still owns it. Mirrors the classification in
--AcquireAbilityRollDialog.
local function EmbeddedDialogIsDiscardable(dialog)
    if dialog == nil or not dialog.valid then
        return true
    end

    if dialog.data ~= nil and dialog.data.IsShown ~= nil and dialog.data.IsShown() then
        return false
    end

    --An action-request prompt that has not finished yet. It looks exactly like a
    --leftover once its dice are thrown -- hidden, and owned by no cast -- so
    --without this it would be destroyed out from under the roll in progress.
    if dialog.data ~= nil and dialog.data.promptPending then
        return false
    end

    local ownerco = dialog.data ~= nil and dialog.data.castCoroutine or nil
    if ownerco == nil then
        return true
    end
    if dialog.data.rollRelinquished then
        return true
    end
    return not coroutine.IsCoroutineWithIdStillRunning(ownerco)
end

--Mount a roll dialog for a roll PROMPT -- a roll pushed at us by an action
--request rather than by our own ability cast. Unlike AcquireAbilityRollDialog
--this never yields, so it is safe to call from a panel event handler.
--
--args.ability / args.token: the ability that caused the prompt and the token
--casting it. When nothing else is on the sidebar we put that ability's card up
--so the player can see what they are rolling against.
--
--The roll always goes under the ability card. If it cannot -- no sidebar, or
--someone else's card is up -- this returns nil and the caller should fall back
--to the legacy roll dialog. It deliberately does NOT use the standalone roll
--host: that host destroys its dialog as soon as it hides, and a roll dialog
--hides while its dice are still in the air, so the roll would be torn down
--mid-flight. Only table rolls, which stay up until they are done, are safe there.
--
--Returns { dialog, ownedAbility, locked, showDelay }. ownedAbility is set only
--when WE put the card up, and is what the caller must pass to HideAbility when
--the roll finishes. Nothing else cleans it up.
function CharacterPanel.EmbedPromptRollDialog(args)
    args = args or {}

    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return nil
    end

    --Something is mid-roll on the sidebar; don't stomp it.
    if CharacterPanel.EmbeddedRollInFlight() then
        return nil
    end

    --Destroy a finished-but-still-mounted dialog before we mount ours. The
    --ability card's slot just overwrites its child without destroying it, and a
    --dialog that is never destroyed keeps its dice cage registered, which leaves
    --the rolled 3D dice on screen.
    local stale = CharacterPanel.FindEmbeddedRollDialog()
    if stale ~= nil then
        if not EmbeddedDialogIsDiscardable(stale) then
            return nil
        end
        if stale.valid then
            stale:DestroySelf()
        end
    end

    local ability = args.ability
    local token = args.token
    local displayed = CharacterPanel.DisplayedAbility()

    local ownedAbility = nil
    local locked = false

    if displayed == nil then
        --Nothing on the sidebar: put the ability card up ourselves, and lock it
        --so a stray hover cannot yank it out from under the roll.
        if ability == nil or TypeNameOf(ability) ~= "ActivatedAbility" or token == nil or not token.valid then
            return nil
        end

        CharacterPanel.UnlockDisplayAbility()
        if not CharacterPanel.DisplayAbility(token, ability, nil, {lock = true}) then
            CharacterPanel.UnlockDisplayAbility()
            return nil
        end
        ownedAbility = ability
        locked = true
    elseif not SameAbilityForCard(displayed, ability) then
        --Someone else's card is up (a hovered ability, another cast). Leave it
        --alone; the caller falls back to the legacy dialog.
        return nil
    end
    --else: the card already shows this ability -- ride along, own nothing.

    local dialog = CharacterPanel.EmbedDialogInAbility()
    --EmbedDialogInAbility hands the dialog to the card via an event and returns
    --it whether or not anything took it, so check it really landed.
    if dialog ~= nil and CharacterPanel.FindEmbeddedRollDialog() ~= dialog then
        if dialog.valid then
            dialog:DestroySelf()
        end
        dialog = nil
    end

    if dialog == nil then
        if ownedAbility ~= nil then
            CharacterPanel.HideAbility(ownedAbility)
        end
        if locked then
            CharacterPanel.UnlockDisplayAbility()
        end
        return nil
    end

    if dialog.data ~= nil then
        --No ability cast owns this dialog; leave castCoroutine nil so the
        --ownership checks elsewhere read it as untracked rather than as a dead
        --cast. promptPending stands in for that ownership, and stays set until
        --the roll resolves -- the caller clears it.
        dialog.data.rollRelinquished = false
        dialog.data.promptPending = true
    end

    return {
        dialog = dialog,
        ownedAbility = ownedAbility,
        locked = locked,
        --The dialog is only a specification until the UI builds it a frame or
        --two later. Its dice cage registers itself as the panel the 3D dice live
        --in from its own create handler, so showing the roll in this same frame
        --gets you a dialog with no dice in it and a Roll button that does
        --nothing. Callers must wait this long before showing the roll.
        --AcquireAbilityRollDialog does the same thing by yielding 4 cycles; we
        --cannot yield here, so we hand the delay to ShowDialog instead. Kept
        --generous so it still covers several frames on a slow machine.
        showDelay = 0.2,
    }
end

--Built as an inner panel because gui.Panel only registers event handlers
--passed at construction; assigning them on an existing panel is a no-op.
function GameHud:InitStandaloneRollHost(hostPanel)
    local innerPanel
    --Set once the mounted dialog has been seen shown; the shown -> hidden
    --transition is the close signal (Proceed/Cancel only hide the dialog).
    local childWasShown = false
    innerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",

        embedRollDialog = function(element, dialog)
            childWasShown = false
            element.children = { dialog }
        end,

        --Poll to tear down the mounted dialog after it hides itself. No
        --upward-traveling close event exists to listen for. Destroying (not
        --just leaving it hidden) matters: the dialog's dice cage stays
        --registered as a dice-preview panel until the panel is destroyed, and
        --DiceController only destroys settled embedded-roll dice once their
        --cage is unregistered -- a lingering hidden dialog left the rolled 3D
        --dice on screen forever (e.g. the Conduit start-of-turn Piety table
        --roll). Only ever-shown dialogs are torn down, so a freshly mounted
        --dialog whose ShowDialog is deferred is left alone.
        thinkTime = 0.25,
        think = function(element)
            local child = element.children[1]
            if child == nil then
                return
            end
            if not child.valid then
                element.children = {}
                return
            end
            local shown = child.data ~= nil and child.data.IsShown ~= nil and child.data.IsShown()
            if shown then
                childWasShown = true
            elseif childWasShown then
                childWasShown = false
                child:DestroySelf()
                element.children = {}
            end
        end,
    }

    hostPanel.children = { innerPanel }
    self.standaloneRollHost = innerPanel
end

--See the abilityDisplayPanel re-init above: re-initializing against a destroyed
--host panel silently orphans innerPanel and installs a dead standaloneRollHost,
--after which every EmbedDialogStandalone leaks an unmountable roll dialog.
local standaloneRollHostPanelForReload = GameHud.instance and rawget(GameHud.instance, "standaloneRollHostPanel")
if standaloneRollHostPanelForReload and standaloneRollHostPanelForReload.valid then
    GameHud.instance:InitStandaloneRollHost(standaloneRollHostPanelForReload)
end

local g_abilityLocked = false

function CharacterPanel.UnlockDisplayAbility()
    g_abilityLocked = false
end

function CharacterPanel.DisplayAbility(token, ability, symbols, options)
    local panel = LiveHostPanel("abilityDisplay")
    if panel == nil then
        return false
    end

    options = options or {}

    -- Hidden-category abilities are almost always invoked sub-abilities / sub-layers
    -- of a parent ability. When a parent ability card is already on screen, retain it
    -- instead of replacing it with the hidden sub-ability's tooltip. Returning true
    -- (without firing showAbility, so g_displayedAbility stays the parent) lets callers
    -- such as AcquireAbilityRollDialog proceed to embed the roll into the parent card.
    if ability ~= nil and ability:try_get("categorization") == "Hidden"
        and g_displayedAbility ~= nil then
        --Remember that this sub-ability is riding on the parent's card, so the
        --teardown call HideAbility(g_currentAbility) can still find and close it.
        if not AbilityOwnsDisplayedCard(ability) then
            g_displayedAbilityAliases[#g_displayedAbilityAliases+1] = ability
        end
        return true
    end

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
    if options.deferReveal then
        displayOptions.deferReveal = true
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

    --Do not raise a *visible* card for a roll that may never show one: build it
    --invisible and let the dialog reveal it when it un-hides (RevealAbilityCard).
    --Rolls that resolve silently -- deterministic damage taking ShowDialog's
    --skipDeterministic fast path, or a ShowDialog that bails -- then tear their
    --card down again without it ever having been seen, instead of flashing an
    --empty card for a few frames (the "Collision" flash on wall collisions).
    --
    --Skipped when this ability's card is ALREADY on screen -- targeting raised it
    --and DisplayAbility rebuilds it unconditionally, so deferring there would blink
    --a card the player is already looking at out of existence.
    local hostPanel = LiveHostPanel("abilityDisplay")
    local cardAlreadyUp = hostPanel ~= nil and #hostPanel.children > 0
        and AbilityOwnsDisplayedCard(ability)

    local acquireDisplayOptions = {}
    for k, v in pairs(displayOptions or {}) do
        acquireDisplayOptions[k] = v
    end
    acquireDisplayOptions.deferReveal = not cardAlreadyUp

    local displayed = CharacterPanel.DisplayAbility(token, ability, symbols, acquireDisplayOptions)

    --_tmp_aicontrol is a counter, raised while the Monster AI holds the token
    --(MonsterAI:BeginTokenControl). The dialog itself reads the same flag off
    --options.creature to hide its own buttons; the card's close X is outside the
    --dialog's subtree, so it has to be told.
    local aiDriven = token ~= nil and token.valid and token.properties ~= nil
        and token.properties._tmp_aicontrol > 0

    local dialog = CharacterPanel.EmbedDialogInAbility(aiDriven)
    if dialog ~= nil then
        if dialog.data ~= nil then
            dialog.data.castCoroutine = coid
            dialog.data.rollRelinquished = false
        end

        --give a few cycles for the dialog to init.
        for i = 1, 4 do
            coroutine.yield(0.01)
        end
    elseif GameHud.instance then
        --rawget: the lobby hud (CreateLobbyHud) never sets rollDialog, and a plain
        --index of an unset field on a game-typed instance raises. Matches the
        --rawget guard in AnyRollDialogShown above. nil falls through to the
        --caller's own nil/valid check.
        dialog = rawget(GameHud.instance, "rollDialog")
    else
        --No live HUD (e.g. a cast driven headlessly / off a real turn). Fall back
        --to the global hud's roll dialog so the roll can still resolve instead of
        --crashing on an index of the `GameHud.instance = false` default.
        dialog = gamehud ~= nil and gamehud.rollDialog or nil
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

--Fade in a card that AcquireAbilityRollDialog built invisible. Called by the
--embedded roll dialog at the moment it stops being hidden -- the first point at
--which we know the player is definitely going to see a roll. A no-op when no
--card is waiting, so it is safe to call on every ShowDialog.
--
--dialogPanel: the dialog that is becoming visible. The card is only revealed when
--that dialog is the one mounted in the ability card, so a table roll in the
--standalone host cannot pull up somebody else's pending card.
function CharacterPanel.RevealAbilityCard(dialogPanel)
    if g_deferredCard == nil then
        return
    end

    if not g_deferredCard.valid then
        g_deferredCard = nil
        return
    end

    if dialogPanel ~= nil and CharacterPanel.FindEmbeddedRollDialog() ~= dialogPanel then
        print("AbilityCard:: REVEAL skipped -- dialog is not the one in the ability card")
        return
    end

    print("AbilityCard:: REVEAL")
    g_deferredCard.selfStyle.hidden = 0
    g_deferredCard = nil
end

function CharacterPanel.HighlightAbilitySection(options)
    local panel = LiveHostPanel("abilityDisplay")
    if panel == nil then
        return
    end

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
            if panel ~= nil and panel.valid and AbilityOwnsDisplayedCard(ability) then
                panel:FireEvent("hideAbility")
            end
        end)
        return true
    end

    if panel ~= nil and panel.valid and AbilityOwnsDisplayedCard(ability) then
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
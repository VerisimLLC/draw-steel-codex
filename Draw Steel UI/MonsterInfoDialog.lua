local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- MonsterInfoDialog
--
-- The fullscreen "Monster Info" view opened from a monster token's radial
-- menu when the "monsterinfo" game setting is on: the monster's portrait,
-- very large, beside a stat block. Entries the players have not learned show
-- as "???" (see Draw Steel Core Rules/MonsterKnowledge.lua for what is known
-- and how it is learned). The Director sees everything, with an eye icon
-- beside each entry to reveal or hide it for the players, plus Reveal All /
-- Hide All / Reset buttons.
--
-- This is an independent rendering of the monster; it deliberately does not
-- use or modify monster:Render (the Director's bestiary stat block). Ability
-- cards are the shared ActivatedAbility:Render.
--
-- The stat block rebuilds whenever the knowledge document changes, so a
-- Director's toggle updates every open dialog live.
----------------------------------------------------------------------

MonsterInfoDialog = {}

local UNKNOWN = "???"

--- True when the radial menu should offer Monster Info for this token.
function MonsterInfoDialog.AvailableForToken(token)
    return MonsterKnowledge.Enabled() and MonsterKnowledge.KeyForToken(token) ~= nil
end

--The stat block's name for the monster: the bestiary entry's name, else the
--monster type. Respects the Director making the token's name private.
local function DisplayName(ctx)
    if not ctx.token.canLocalPlayerSeeName then
        return UNKNOWN
    end

    local name = nil
    local asset = assets.monsters[ctx.key]
    if asset ~= nil then
        name = asset.name
    end
    if name == nil or name == "" then
        name = ctx.props:try_get("monster_type")
    end
    if name == nil or name == "" then
        name = ctx.token.name
    end
    return name or UNKNOWN
end

--Speed is always known: "5" or "5 (Fly, Climb)".
local function SpeedText(props)
    local moveTypes = {}
    for id,speed in pairs(props:try_get("movementSpeeds", {})) do
        if speed > 0 then
            local info = creature.movementTypeById[id]
            moveTypes[#moveTypes+1] = (info ~= nil and info.name) or id
        end
    end
    table.sort(moveTypes)

    local text = tostring(props:WalkingSpeed())
    if #moveTypes > 0 then
        text = text .. " (" .. string.join(moveTypes, ", ") .. ")"
    end
    return text
end

--One "Fire 5" / "Corruption 3" style entry of the Immunity or Weakness list.
local function ResistanceEntryText(entry)
    local damageType = ""
    if entry:try_get("damageType", "all") ~= "all" then
        damageType = entry.damageType
        damageType = damageType:gsub("^%l", string.upper) .. " "
    end

    local keywords = {}
    for k,_ in pairs(entry:try_get("keywords", {})) do
        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
    end
    table.sort(keywords)
    if #keywords > 0 then
        damageType = string.join(keywords, " ") .. " " .. damageType
    end

    return string.format("%s%d", damageType, math.abs(entry.dr))
end

--"Immunity Fire 5, ??? / Weakness Holy 3". Empty when the monster has none.
--Hidden entries collapse to a single ??? per list so the count is not leaked.
local function ResistanceText(ctx)
    local resistances = ctx.props:try_get("resistances", {})
    if #resistances == 0 then
        return ""
    end

    local function collect(isImmunity)
        local entries = {}
        local hidden = false
        for _,entry in ipairs(resistances) do
            local dr = entry:try_get("dr", 0)
            if (isImmunity and dr > 0) or ((not isImmunity) and dr < 0) then
                if MonsterKnowledge.IsResistanceRevealed(ctx.key, entry:try_get("damageType", "all")) then
                    entries[#entries+1] = ResistanceEntryText(entry)
                else
                    hidden = true
                end
            end
        end
        if hidden then
            entries[#entries+1] = UNKNOWN
        end
        return entries
    end

    local parts = {}
    local immunities = collect(true)
    if #immunities > 0 then
        parts[#parts+1] = string.format("<b>Immunity</b> %s", string.join(immunities, ", "))
    end
    local weaknesses = collect(false)
    if #weaknesses > 0 then
        parts[#parts+1] = string.format("<b>Weakness</b> %s", string.join(weaknesses, ", "))
    end
    return string.join(parts, " / ")
end

local function StaminaText(ctx)
    local knowledge = MonsterKnowledge.StaminaKnowledge(ctx.key)

    if MonsterKnowledge.LocalUserSeesAll() then
        local text = string.format("<b>Stamina</b> %d", ctx.props:MaxHitpoints())
        if knowledge.visible and knowledge.tier < 3 and knowledge.estimate ~= nil then
            text = text .. string.format(" (players see ~%d)", knowledge.estimate)
        end
        return text
    end

    if not knowledge.visible then
        return "<b>Stamina</b> " .. UNKNOWN
    end
    if knowledge.tier >= 3 or knowledge.estimate == nil then
        return string.format("<b>Stamina</b> %d", ctx.props:MaxHitpoints())
    end
    return string.format("<b>Stamina</b> ~%d", knowledge.estimate)
end

----------------------------------------------------------------------
-- Building blocks
----------------------------------------------------------------------

--The Director's eye beside an entry: shows whether PLAYERS can see it and
--toggles it. Stays in sync with the document (another client may toggle it).
local function CreateEye(ctx, entryKey, options)
    options = options or {}
    local playersCanSee = options.playersCanSee or function()
        return MonsterKnowledge.PlayersCanSee(ctx.key, entryKey)
    end
    local setVisible = options.setVisible or function(value)
        MonsterKnowledge.SetRevealed(ctx.key, entryKey, value)
    end

    return gui.VisibilityPanel{
        visible = playersCanSee(),
        width = 16,
        height = 16,
        valign = "center",
        rmargin = 6,
        swallowPress = true,
        hoverCursor = "hand",
        click = function(element)
            local visible = playersCanSee()
            setVisible(not visible)
            element:FireEvent("visible", not visible)
        end,
        linger = function(element)
            gui.Tooltip(cond(playersCanSee(),
                "Players can see this. Click to hide it from them.",
                "Hidden from players. Click to reveal it to them."))(element)
        end,
        monitorGame = MonsterKnowledge.DocumentPath(),
        refreshGame = function(element)
            element:FireEvent("visible", playersCanSee())
        end,
    }
end

--A label plus, for the Director, its eye. entryKey nil = always visible, no eye.
local function Entry(ctx, entryKey, labelArgs, eyeOptions)
    local children = {}
    if ctx.director and entryKey ~= nil then
        children[#children+1] = CreateEye(ctx, entryKey, eyeOptions)
    end

    labelArgs.width = labelArgs.width or "auto"
    labelArgs.height = labelArgs.height or "auto"
    labelArgs.valign = "center"
    children[#children+1] = gui.Label(labelArgs)

    return gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = labelArgs.halign or "left",
        valign = "center",
        children = children,
    }
end

--Text shown to the local user for an entry: the real text when revealed,
--else the label with ???.
local function EntryText(ctx, entryKey, label, value)
    if MonsterKnowledge.IsRevealed(ctx.key, entryKey) then
        return string.format("<b>%s</b> %s", label, tostring(value))
    end
    return string.format("<b>%s</b> %s", label, UNKNOWN)
end

local function Row(children)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 2,
        children = children,
    }
end

local function Divider()
    return gui.Divider{
        width = "100%",
        vmargin = 6,
    }
end

--Name + role line, keywords + EV line.
local function BuildHeader(ctx)
    local props = ctx.props

    local roleText = UNKNOWN
    if MonsterKnowledge.IsRevealed(ctx.key, "role") then
        pcall(function() roleText = props:RoleDescription() end)
    end

    local keywordsText = UNKNOWN
    if MonsterKnowledge.IsRevealed(ctx.key, "keywords") then
        local keywordsSorted = {}
        for k,_ in pairs(props:try_get("keywords", {})) do
            keywordsSorted[#keywordsSorted+1] = ActivatedAbility.CanonicalKeyword(k)
        end
        table.sort(keywordsSorted)
        keywordsText = string.join(keywordsSorted, ", ")
    end

    local evText = UNKNOWN
    if MonsterKnowledge.IsRevealed(ctx.key, "ev") then
        local ev = 0
        pcall(function() ev = props:EV() end)
        evText = string.format("EV %d", ev)
        if props:try_get("minion", false) then
            evText = evText .. " for " .. GameSystem.minionsPerSquadText .. " minions"
        end
    end

    return {
        Row{
            Entry(ctx, nil, {
                classes = {"sizeXxl", "bold"},
                smallcaps = true,
                text = DisplayName(ctx),
            }),
            Entry(ctx, "role", {
                classes = {"sizeL"},
                smallcaps = true,
                halign = "right",
                text = roleText,
            }),
        },
        Row{
            Entry(ctx, "keywords", {
                classes = {"sizeM"},
                text = keywordsText,
            }),
            Entry(ctx, "ev", {
                classes = {"sizeM"},
                halign = "right",
                text = evText,
            }),
        },
    }
end

--Stamina / immunities, speed / size, captain / free strike.
local function BuildVitals(ctx)
    local props = ctx.props
    local rows = {}

    --the immunities eye only exists when the monster has any resistances.
    local immunitiesKey = nil
    if #props:try_get("resistances", {}) > 0 then
        immunitiesKey = "immunities"
    end

    rows[#rows+1] = Row{
        Entry(ctx, "stamina", {
            classes = {"sizeM"},
            text = StaminaText(ctx),
        }, {
            playersCanSee = function()
                return MonsterKnowledge.StaminaKnowledge(ctx.key).visible
            end,
            setVisible = function(value)
                MonsterKnowledge.SetStaminaVisibleToPlayers(ctx.key, value)
            end,
        }),
        Entry(ctx, immunitiesKey, {
            classes = {"sizeM"},
            halign = "right",
            text = ResistanceText(ctx),
        }),
    }

    local sizeText = UNKNOWN
    if MonsterKnowledge.IsRevealed(ctx.key, "size") then
        local size = "?"
        local stability = 0
        pcall(function() size = props:SizeDescription() end)
        pcall(function() stability = props:BaseForcedMoveResistance() end)
        sizeText = string.format("%s / <b>Stability</b> %d", size, stability)
    end

    rows[#rows+1] = Row{
        Entry(ctx, nil, {
            classes = {"sizeM"},
            text = string.format("<b>Speed</b> %s", SpeedText(props)),
        }),
        Entry(ctx, "size", {
            classes = {"sizeM"},
            halign = "right",
            text = string.format("<b>Size</b> %s", sizeText),
        }),
    }

    local withCaptain = props:try_get("withCaptain")
    local captainEntry
    if withCaptain ~= nil and withCaptain ~= "" then
        captainEntry = Entry(ctx, "captain", {
            classes = {"sizeM"},
            text = EntryText(ctx, "captain", "With Captain", withCaptain),
        })
    else
        --placeholder so Free Strike still right-aligns in a two-column row.
        captainEntry = gui.Panel{ width = 1, height = 1 }
    end

    local freeStrike = 0
    pcall(function() freeStrike = props:OpportunityAttack() end)
    rows[#rows+1] = Row{
        captainEntry,
        Entry(ctx, "freestrike", {
            classes = {"sizeM"},
            halign = "right",
            text = EntryText(ctx, "freestrike", "Free Strike", freeStrike),
        }),
    }

    return rows
end

--The five characteristics in one row.
local function BuildCharacteristics(ctx)
    local props = ctx.props
    local columns = {}
    local count = #creature.attributeIds
    for i,attrid in ipairs(creature.attributeIds) do
        local info = creature.attributesInfo[attrid]
        local entryKey = MonsterKnowledge.EntryKey("attr", attrid)

        local value = UNKNOWN
        if MonsterKnowledge.IsRevealed(ctx.key, entryKey) then
            value = ModStr(props:GetAttribute(attrid):Value())
        end

        local halign = "center"
        if i == 1 then
            halign = "left"
        elseif i == count then
            halign = "right"
        end

        columns[#columns+1] = gui.Panel{
            width = string.format("%d%%", math.floor(100 / count)),
            height = "auto",
            flow = "horizontal",
            children = {
                Entry(ctx, entryKey, {
                    classes = {"sizeM", "bold"},
                    halign = halign,
                    text = string.format("%s %s", info.description, value),
                }),
            },
        }
    end

    return Row(columns)
end

--Traits: revealed ones in full; players get one muted line if any remain.
local function BuildTraits(ctx)
    local rows = {}
    local hidden = 0
    local labelWidth = "100%"
    if ctx.director then
        labelWidth = "100%-22"
    end

    for _,entry in ipairs(MonsterKnowledge.TraitEntries(ctx.props)) do
        if MonsterKnowledge.IsRevealed(ctx.key, entry.key) then
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                children = {
                    Entry(ctx, entry.key, {
                        classes = {"sizeM"},
                        width = labelWidth,
                        textWrap = true,
                        text = string.format("<b>%s:</b> <i>%s</i>", entry.name, StringInterpolateGoblinScript(entry.description, ctx.props)),
                    }),
                },
            }
        else
            hidden = hidden + 1
        end
    end

    if hidden > 0 then
        rows[#rows+1] = gui.Label{
            classes = {"sizeM", "fgMuted"},
            width = "100%",
            height = "auto",
            vmargin = 4,
            text = "<i>This creature has traits you have not yet learned about.</i>",
        }
    end

    return rows
end

--Abilities: revealed ones as full ability cards; players get one muted line
--if any remain.
local function BuildAbilities(ctx)
    local rows = {}
    local hidden = 0
    local cardWidth = "100%"
    if ctx.director then
        cardWidth = "100%-22"
    end

    for _,entry in ipairs(MonsterKnowledge.AbilityEntries(ctx.props)) do
        if MonsterKnowledge.IsRevealed(ctx.key, entry.key) then
            local card = entry.ability:Render({
                width = cardWidth,
            }, {
                token = ctx.token,
            })

            local children = {}
            if ctx.director then
                children[#children+1] = CreateEye(ctx, entry.key)
            end
            children[#children+1] = card

            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                children = children,
            }
        else
            hidden = hidden + 1
        end
    end

    if hidden > 0 then
        rows[#rows+1] = gui.Label{
            classes = {"sizeM", "fgMuted"},
            width = "100%",
            height = "auto",
            vmargin = 4,
            text = "<i>This creature has abilities you have not yet learned about.</i>",
        }
    end

    return rows
end

--Every entry key the Director's Reveal All / Hide All should cover.
local function AllEntryKeys(ctx)
    local keys = { "role", "keywords", "ev", "size", "freestrike", "captain", "immunities" }
    for _,attrid in ipairs(creature.attributeIds) do
        keys[#keys+1] = MonsterKnowledge.EntryKey("attr", attrid)
    end
    for _,entry in ipairs(MonsterKnowledge.TraitEntries(ctx.props)) do
        keys[#keys+1] = entry.key
    end
    for _,entry in ipairs(MonsterKnowledge.AbilityEntries(ctx.props)) do
        keys[#keys+1] = entry.key
    end
    return keys
end

local function BuildFooter(ctx)
    local buttons = {}

    if ctx.director then
        buttons[#buttons+1] = gui.Button{
            classes = {"sizeM"},
            text = "Reveal All",
            hover = gui.Tooltip("Show the players this whole stat block."),
            click = function(element)
                MonsterKnowledge.SetRevealedMany(ctx.key, AllEntryKeys(ctx), true)
            end,
        }
        buttons[#buttons+1] = gui.Button{
            classes = {"sizeM"},
            text = "Hide All",
            hover = gui.Tooltip("Hide every entry from the players again."),
            click = function(element)
                MonsterKnowledge.SetRevealedMany(ctx.key, AllEntryKeys(ctx), false)
            end,
        }
        buttons[#buttons+1] = gui.Button{
            classes = {"sizeM"},
            text = "Reset",
            hover = gui.Tooltip("Forget everything learned about this monster type, including kills. Automatic learning starts over."),
            click = function(element)
                MonsterKnowledge.Reset(ctx.key)
            end,
        }
    end

    buttons[#buttons+1] = gui.Button{
        classes = {"sizeM"},
        text = "Close",
        click = function(element)
            GameHud.instance:CloseModal()
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        tmargin = 12,
        children = buttons,
    }
end

--The whole stat block body. Rebuilt on every knowledge change.
local function BuildStatBlockContent(ctx)
    local children = {}
    local function append(list)
        for _,child in ipairs(list) do
            children[#children+1] = child
        end
    end

    append(BuildHeader(ctx))
    children[#children+1] = Divider()
    append(BuildVitals(ctx))
    children[#children+1] = BuildCharacteristics(ctx)
    children[#children+1] = Divider()
    append(BuildTraits(ctx))
    append(BuildAbilities(ctx))
    children[#children+1] = BuildFooter(ctx)

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

----------------------------------------------------------------------
-- The dialog
----------------------------------------------------------------------

--The portrait, as large as the space allows. Spine tokens use their live
--inspect portrait at a fixed 3:4; images keep their own aspect.
local function CreatePortraitPanel(token, maxWidth, maxHeight)
    if token.hasSpineAnimation then
        return gui.Panel{
            bgimage = token.inspectPortrait,
            bgcolor = "white",
            width = math.floor(maxHeight * 0.75),
            height = maxHeight,
            autosizeimage = false,
            interactable = false,
            halign = "center",
            valign = "center",
        }
    end

    return gui.Panel{
        bgimage = token.offTokenPortrait,
        bgcolor = "white",
        width = "auto",
        height = "auto",
        maxWidth = maxWidth,
        maxHeight = maxHeight,
        autosizeimage = true,
        interactable = false,
        halign = "center",
        valign = "center",
    }
end

--- Open the Monster Info view for a monster token. Does nothing for tokens
--- players cannot learn about (heroes, hero summons).
--- @param token CharacterToken
function MonsterInfoDialog.Show(token)
    local key = MonsterKnowledge.KeyForToken(token)
    if key == nil or token.properties == nil then
        return
    end

    local ctx = {
        token = token,
        props = token.properties,
        key = key,
        --eye toggles and Director buttons: a Director looking as the Director.
        director = GameHud.DirectorUIVisible() and MonsterKnowledge.LocalUserSeesAll(),
    }

    local screen = dmhub.screenDimensions
    local maxHeight = math.floor(screen.y * 0.86)
    local portraitMaxWidth = math.floor(screen.x * 0.45)
    local blockWidth = math.min(720, math.floor(screen.x * 0.45))

    local statBlock = gui.Panel{
        classes = {"bordered", "bg"},
        width = blockWidth,
        height = "auto",
        maxHeight = maxHeight,
        vscroll = true,
        flow = "vertical",
        hpad = 24,
        vpad = 20,
        borderBox = true,
        halign = "center",
        valign = "center",
        children = {
            BuildStatBlockContent(ctx),
        },

        --any client revealing or hiding an entry rebuilds the block.
        monitorGame = MonsterKnowledge.DocumentPath(),
        refreshGame = function(element)
            if not ctx.token.valid or ctx.token.properties == nil then
                return
            end
            ctx.props = ctx.token.properties
            element.children = {
                BuildStatBlockContent(ctx),
            }
        end,
    }

    local content = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        interactable = true,
        --presses on the content must not reach the backdrop and close the dialog.
        swallowPress = true,
        children = {
            gui.Panel{
                width = "auto",
                height = "auto",
                rmargin = 40,
                valign = "center",
                children = {
                    CreatePortraitPanel(token, portraitMaxWidth, maxHeight),
                },
            },
            statBlock,
        },
    }

    local backdrop = gui.Panel{
        --a standalone modal owns its theme cascade.
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "black",
        opacity = 0.94,
        interactable = true,

        press = function(element)
            GameHud.instance:CloseModal()
        end,

        --Escape closes too (escapeActivates would fire click, which a press
        --swallowed by the content never completes; capture it directly).
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            GameHud.instance:CloseModal()
        end,

        children = {
            content,
        },
    }

    GameHud.instance:ShowModal(backdrop)
end

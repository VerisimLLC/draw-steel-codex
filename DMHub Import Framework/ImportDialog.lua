local mod = dmhub.GetModLoading()

local CreateImportAssetsDialog

LaunchablePanel.Register{
	name = "Import...",
	halign = "center",
	valign = "center",
    group = "share",
	hidden = function()
		return not dmhub.isDM
	end,
	content = function(args)
        return CreateImportAssetsDialog(args)
	end,
}

local g_currentImporterSetting = setting{
    id = "importer:current",
    description = "Last used importer type",
    default = nil,
    storage = "preference",
}

--The import dialog is a fixed size. Most importers put a small input panel at the top and
--fill the space beneath it with the parsed-content panel, the bandwidth notice and the
--Import button, all of which are anchored/centred in the dialog by CreateImportAssetsDialog.
--The My Content browser carries its own footer (dependency notice + cost + Import) inside
--its panel, so none of that lower furniture applies to it and it gets everything under the
--title + importer-dropdown header: ~120px of header plus the input panel's own 16px bottom
--margin. Kept here as constants so the browser's height tracks the dialog's.
local g_importDialogHeight = 940
local g_importDialogHeaderHeight = 140

--display names for compendium tables shown by the My Content importer.
local g_tableDisplayNames = {
    tbl_Gear = "Equipment",
    campaignNotes = "Campaign Notes",
    documents = "Documents",
    classes = "Classes",
    feats = "Feats",
    backgrounds = "Backgrounds",
    charConditions = "Character Conditions",
    characterOngoingEffects = "Ongoing Effects",
    characterResources = "Character Resources",
    characterTypes = "Character Types",
    creatureTemplates = "Creature Templates",
    currency = "Currency",
    customAttributes = "Character Attributes",
    damageTypes = "Damage Types",
    equipmentCategories = "Equipment Categories",
    featurePrefabs = "Character Feature Prefabs",
    globalRuleMods = "Global Rules",
    languages = "Languages",
    lootTables = "Loot Tables",
    nameGenerators = "Name Generators",
    parties = "Parties",
    races = "Ancestries",
    kits = "Kits",
    subclasses = "Subclasses",
    subraces = "Subraces",
}

local g_tableDisplayNamesSingular = {
    tbl_Gear = "Equipment",
    campaignNotes = "Campaign Note",
    documents = "Document",
    classes = "Class",
    feats = "Feat",
    backgrounds = "Background",
    charConditions = "Character Condition",
    characterOngoingEffects = "Ongoing Effect",
    characterResources = "Character Resource",
    characterTypes = "Character Type",
    creatureTemplates = "Creature Template",
    currency = "Currency",
    customAttributes = "Character Attribute",
    damageTypes = "Damage Type",
    equipmentCategories = "Equipment Category",
    featurePrefabs = "Character Feature Prefab",
    globalRuleMods = "Global Rule",
    languages = "Language",
    lootTables = "Loot Table",
    nameGenerators = "Name Generator",
    parties = "Party",
    races = "Ancestry",
    kits = "Kit",
    subclasses = "Subclass",
    subraces = "Subrace",
}

--The "My Content" importer: shows the user's other games as tiles with content
--summaries (from cached metadata, no connection needed), then drills into one
--game at a time: characters as selectable tiles, compendium content as a tree.
--Dependency tracking and install are handled by the engine
--(LuaRemoteGameContent / lobby:FetchGameContent).
local CreateMyContentImportPanel
CreateMyContentImportPanel = function()

    local resultPanel

    --per-source-game state, keyed by gameid.
    local m_state = {}

    local m_scanStarted = false
    local m_importing = false
    local m_selectionDirty = false

    --the game currently open in the detail view, or nil for the overview.
    local m_currentGameid = nil

    local m_overviewPanel
    local m_overviewGrid
    local m_detailHeaderBar
    local m_detailContainer
    local m_footerPanel
    local m_depsLabel
    local m_costLabel
    local m_statusLabel
    local m_importButton

    local function GameState(gameid)
        if m_state[gameid] == nil then
            m_state[gameid] = {
                content = nil,
                status = "pending",
                error = nil,
                selected = {},
                fetchedChars = {},
                fetchingChars = {},
                pendingChars = 0,
                partyNames = {},
                installGuids = nil,
            }
        end
        return m_state[gameid]
    end

    local function MarkSelectionDirty()
        m_selectionDirty = true
    end

    local function EnsureCharacterFetched(gameid, charid)
        local state = GameState(gameid)
        if state.fetchedChars[charid] ~= nil or state.fetchingChars[charid] or state.content == nil or (not state.content.ready) then
            return
        end

        state.fetchingChars[charid] = true
        state.pendingChars = state.pendingChars + 1
        state.content:FetchCharacter(charid, function(info)
            if mod.unloaded then
                return
            end

            state.pendingChars = state.pendingChars - 1
            state.fetchingChars[charid] = nil
            if info ~= nil then
                state.fetchedChars[charid] = info
            else
                --the character couldn't be fetched (may have been deleted); deselect it.
                state.fetchedChars[charid] = false
                state.selected[charid] = nil
                if resultPanel ~= nil and resultPanel.valid then
                    resultPanel:FireEventTree("characterUnavailable", gameid, charid)
                end
            end

            MarkSelectionDirty()
        end)
    end

    --start the (async) content fetch for a game if it hasn't been fetched yet.
    --Completion is broadcast through resultPanel so a rebuilt detail view still
    --hears about it.
    local function EnsureFetched(gameid)
        local state = GameState(gameid)
        if state.status ~= "pending" then
            return
        end

        state.status = "loading"
        lobby:FetchGameContent(gameid, {
            ready = function(content)
                if mod.unloaded then
                    return
                end

                state.content = content
                state.status = "ready"

                for _,item in ipairs(content:GetTableItems("parties")) do
                    state.partyNames[item.id] = item.name
                end

                --character portraits/names from the source game's own data, used to
                --fill in anything the cached index doesn't know (older games).
                state.charSummaries = content:GetCharacterSummaries()

                --fetch any characters that were selected before the content arrived.
                for charid,_ in pairs(state.selected) do
                    EnsureCharacterFetched(gameid, charid)
                end

                if resultPanel ~= nil and resultPanel.valid then
                    resultPanel:FireEventTree("gameContentReady", gameid)
                end

                MarkSelectionDirty()
            end,
            error = function(err)
                if mod.unloaded then
                    return
                end

                state.status = "error"
                state.error = err
                if resultPanel ~= nil and resultPanel.valid then
                    resultPanel:FireEventTree("gameContentError", gameid, err)
                end

                MarkSelectionDirty()
            end,
        })
    end

    --recompute the dependency closure, cost, and footer state for the game
    --currently open in the detail view.
    local function RecomputeSelection()
        if resultPanel == nil or (not resultPanel.valid) then
            return
        end

        local state = nil
        if m_currentGameid ~= nil then
            state = m_state[m_currentGameid]
        end

        local numSelected = 0
        local numDeps = 0
        local numMedia = 0
        local depNames = {}
        local totalCostKB = 0
        local waiting = false

        if state ~= nil then
            state.installGuids = nil

            for _,_ in pairs(state.selected) do
                numSelected = numSelected + 1
            end

            if numSelected > 0 then
                if state.content == nil or (not state.content.ready) or state.pendingChars > 0 then
                    waiting = true
                else
                    local closure = state.content:ComputeClosure(state.selected)
                    local guids = {}
                    for k,_ in pairs(state.selected) do
                        guids[#guids+1] = k
                    end

                    for depid,_ in pairs(closure) do
                        if state.selected[depid] == nil then
                            guids[#guids+1] = depid
                            numDeps = numDeps + 1

                            local desc = state.content:DescribeAsset(depid)
                            if desc ~= nil then
                                if desc.kind == "image" or desc.kind == "audio" or desc.kind == "imageLibrary"
                                    or desc.kind == "audioFolder" or desc.kind == "monsterFolder" or desc.kind == "objectFolder"
                                    or desc.kind == "unsupported" then
                                    numMedia = numMedia + 1
                                elseif desc.kind == "tableitem" and desc.table ~= nil then
                                    depNames[#depNames+1] = string.format("%s (%s)", desc.name, g_tableDisplayNamesSingular[desc.table] or desc.table)
                                elseif desc.kind == "monster" then
                                    depNames[#depNames+1] = string.format("%s (Monster)", desc.name)
                                elseif desc.kind == "character" then
                                    depNames[#depNames+1] = string.format("%s (Character)", desc.name)
                                else
                                    depNames[#depNames+1] = desc.name
                                end
                            end
                        end
                    end

                    state.installGuids = guids
                    totalCostKB = state.content:GetInstallCostKB(guids)
                end
            end
        end

        if numSelected == 0 then
            m_depsLabel.text = ""
            m_costLabel.text = ""
        elseif waiting then
            m_depsLabel.text = "Resolving dependencies..."
            m_costLabel.text = ""
        else
            if numDeps == 0 then
                m_depsLabel.text = ""
            else
                local maxShown = 8
                local shown = {}
                for i=1,math.min(#depNames, maxShown) do
                    shown[#shown+1] = depNames[i]
                end

                local extra = ""
                if #depNames > maxShown then
                    extra = string.format(", +%d more", #depNames - maxShown)
                end

                local mediaText = ""
                if numMedia > 0 then
                    mediaText = string.format(" (+%d supporting assets)", numMedia)
                end

                if #shown > 0 then
                    m_depsLabel.text = string.format("Also brings dependencies: %s%s%s", table.concat(shown, ", "), extra, mediaText)
                else
                    m_depsLabel.text = string.format("Also brings %d supporting assets", numMedia)
                end
            end

            local quotaKB = round(dmhub.uploadQuotaRemaining/1024)
            local warning = ""
            if totalCostKB > quotaKB then
                warning = " <color=#ff0000>(not enough bandwidth)</color>"
            end
            m_costLabel.text = string.format("Upload cost: %dKB of %dKB available%s", totalCostKB, quotaKB, warning)
        end

        local canImport = numSelected > 0 and (not waiting) and (not m_importing)
        m_importButton:SetClass("hidden", not canImport)

        resultPanel:FireEventTree("refreshCounts")
    end

    --a collapsible section with a header, lazy-built body, and selected/total counts.
    local function CreateSection(options)
        local expanded = options.startExpanded == true
        local built = false
        local bodyPanel
        local arrow

        local buildBody = options.buildBody

        bodyPanel = gui.Panel{
            classes = {cond(expanded, nil, "collapsed")},
            width = "100%",
            height = "auto",
            flow = "vertical",
        }

        if expanded then
            built = true
            bodyPanel.children = buildBody()
        end

        local Toggle = function()
            expanded = not expanded
            arrow:SetClass("expanded", expanded)
            if expanded and (not built) then
                built = true
                bodyPanel.children = buildBody()
                resultPanel:FireEventTree("refreshCounts")
            end
            bodyPanel:SetClass("collapsed", not expanded)
        end

        arrow = gui.ExpandoArrow{
            width = 16,
            height = 16,
            valign = "center",
            swallowPress = true,
            press = function()
                Toggle()
            end,
        }

        if expanded then
            arrow:SetClass("expanded", true)
        end

        local countLabel = gui.Label{
            fontSize = 14,
            color = "#aaaaaa",
            width = "auto",
            height = "auto",
            hmargin = 6,
            valign = "center",
            text = "",
            refreshCounts = function(element)
                if not built then
                    return
                end
                local counts = { total = 0, selected = 0 }
                bodyPanel:FireEventTree("count", counts)
                element.text = string.format("(%d/%d)", counts.selected, counts.total)
            end,
        }

        local headerPanel = gui.Panel{
            classes = {"mcRow"},
            bgimage = "panels/square.png",
            flow = "horizontal",
            width = "100%",
            height = 26,
            press = function()
                Toggle()
            end,

            arrow,
            gui.Label{
                fontSize = 16,
                bold = true,
                width = "auto",
                height = "auto",
                valign = "center",
                text = options.title,
            },
            countLabel,
        }

        return gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            hmargin = options.hmargin or 0,
            headerPanel,
            bodyPanel,
        }
    end

    --A minimal checkbox built from the house checkBackground/checkMark classes.
    --gui.Check is not used here: its root 'checkbox' class is styled for a text
    --label (wide minimum width, own hover surface), which fights our row layout.
    --Toggling fires 'change'; assigning .value is silent (mirrors gui.Check).
    local function CreateCheck(args)
        local checked = args.value or false
        args.value = nil

        local checkMark = gui.Panel{
            classes = {"checkMark"},
            hmargin = 0,
            vmargin = 0,
            floating = true,
        }

        checkMark:SetClass("hidden", not checked)

        args.classes = args.classes or {}
        args.classes[#args.classes+1] = "checkBackground"

        args.GetValue = function(element)
            return checked
        end

        args.SetValue = function(element, val, firechange)
            if checked ~= val then
                checked = val
                checkMark:SetClass("hidden", not val)
                if firechange == true then
                    element:FireEvent("change")
                end
            end
        end

        args.press = function(element)
            checked = not checked
            checkMark:SetClass("hidden", not checked)
            element:FireEvent("change")
        end

        args[#args+1] = checkMark

        return gui.Panel(args)
    end

    --a selectable row with a title and optional subtitle, used in the compendium tree.
    local function CreateAssetRow(state, guid, options)
        local check
        check = CreateCheck{
            value = state.selected[guid] ~= nil,
            width = 22,
            height = 22,
            valign = "center",
            swallowPress = true,
            change = function(element)
                local row = element.parent
                if row ~= nil and row:HasClass("unavailable") then
                    element.value = false
                    return
                end

                if element.value then
                    state.selected[guid] = true
                    if options.isCharacter then
                        EnsureCharacterFetched(options.gameid, guid)
                    end
                else
                    state.selected[guid] = nil
                end

                MarkSelectionDirty()
            end,

            clearSelection = function(element)
                if element.value then
                    element.value = false
                end
            end,

            setSelected = function(element, val)
                if element.value ~= val then
                    --.value alone is silent; fire change so state updates.
                    element.value = val
                    element:FireEvent("change")
                end
            end,
        }

        local title = options.title
        if title == nil or title == "" then
            title = "(unnamed)"
        end

        local labels = {
            gui.Label{
                fontSize = 15,
                width = "auto",
                height = "auto",
                maxWidth = 500,
                text = title,
            },
        }

        if options.subtitle ~= nil and options.subtitle ~= "" then
            labels[#labels+1] = gui.Label{
                fontSize = 12,
                color = "#aaaaaa",
                width = "auto",
                height = "auto",
                maxWidth = 500,
                text = options.subtitle,
            }
        end

        return gui.Panel{
            classes = {"mcRow"},
            bgimage = "panels/square.png",
            flow = "horizontal",
            width = "100%",
            height = 26,
            hmargin = options.hmargin or 0,
            borderBox = true,
            hpad = 4,

            data = {
                guid = guid,
                gameid = options.gameid,
            },

            count = function(element, counts)
                counts.total = counts.total + 1
                if state.selected[guid] ~= nil then
                    counts.selected = counts.selected + 1
                end
            end,

            characterUnavailable = function(element, gameid, charid)
                if gameid == options.gameid and charid == guid then
                    element:SetClass("unavailable", true)
                    check:FireEvent("clearSelection")
                end
            end,

            press = function(element)
                if not element:HasClass("unavailable") then
                    --clicking anywhere on the row toggles, via the check's own press.
                    check:FireEvent("press")
                end
            end,

            check,
            gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                valign = "center",
                hmargin = 6,
                children = labels,
            },
        }
    end

    --small Select All / Clear links used at the top of compendium section bodies.
    local function CreateSelectionLinks(getBody)
        return gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = 20,
            halign = "left",
            hmargin = 24,

            gui.Label{
                fontSize = 13,
                color = "#8888ff",
                width = "auto",
                height = "auto",
                text = "Select All",
                press = function(element)
                    getBody():FireEventTree("setSelected", true)
                end,
            },
            gui.Label{
                fontSize = 13,
                color = "#aaaaaa",
                width = "auto",
                height = "auto",
                hmargin = 8,
                text = "|",
            },
            gui.Label{
                fontSize = 13,
                color = "#8888ff",
                width = "auto",
                height = "auto",
                text = "Clear",
                press = function(element)
                    getBody():FireEventTree("setSelected", false)
                end,
            },
        }
    end

    --a selectable character tile with portrait, name, and owner.
    local function CreateCharacterTile(state, entry, players, gameid)
        local portrait = entry.portrait
        if portrait == nil and entry.owner ~= nil and players[entry.owner] ~= nil and players[entry.owner].appearance ~= nil then
            portrait = players[entry.owner].appearance.portraitId
        end

        --the fetched game content knows the real portrait even when the cached
        --index (written by an older client) doesn't.
        if (portrait == nil or portrait == "") and state.charSummaries ~= nil and state.charSummaries[entry.id] ~= nil then
            portrait = state.charSummaries[entry.id].portrait
        end

        local subtitle = entry.summary
        if entry.owner ~= nil and entry.owner ~= "PARTY" and players[entry.owner] ~= nil and players[entry.owner].displayName ~= nil then
            subtitle = players[entry.owner].displayName
        end

        local portraitPanel = gui.Panel{
            width = 96,
            height = 96,
            halign = "center",
            vmargin = 8,
            cornerRadius = 6,
            bgcolor = "white",
            bgimage = portrait,
        }

        return gui.Panel{
            classes = {"mcCharTile", cond(state.selected[entry.id] ~= nil, "selected", nil)},
            bgimage = "panels/square.png",
            flow = "vertical",
            width = 150,
            height = 168,
            margin = 6,
            borderBox = true,
            cornerRadius = 6,

            data = {
                guid = entry.id,
                gameid = gameid,
            },

            count = function(element, counts)
                counts.total = counts.total + 1
                if state.selected[entry.id] ~= nil then
                    counts.selected = counts.selected + 1
                end
            end,

            characterUnavailable = function(element, forGameid, charid)
                if forGameid == gameid and charid == entry.id then
                    element:SetClass("unavailable", true)
                    element:SetClass("selected", false)
                end
            end,

            clearSelection = function(element)
                element:SetClass("selected", false)
            end,

            press = function(element)
                if element:HasClass("unavailable") then
                    return
                end

                if state.selected[entry.id] ~= nil then
                    state.selected[entry.id] = nil
                    element:SetClass("selected", false)
                else
                    state.selected[entry.id] = true
                    element:SetClass("selected", true)
                    EnsureCharacterFetched(gameid, entry.id)
                end

                MarkSelectionDirty()
            end,

            gameContentReady = function(element, forGameid)
                if forGameid ~= gameid then
                    return
                end

                if (portrait == nil or portrait == "") and state.charSummaries ~= nil and state.charSummaries[entry.id] ~= nil
                    and state.charSummaries[entry.id].portrait ~= nil then
                    portrait = state.charSummaries[entry.id].portrait
                    portraitPanel.bgimage = portrait
                end
            end,

            portraitPanel,

            gui.Label{
                fontSize = 15,
                bold = true,
                width = "100%-8",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = false,
                text = entry.name or "(unnamed)",
            },

            gui.Label{
                fontSize = 11,
                color = "#aaaaaa",
                width = "100%-8",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = false,
                text = subtitle or "",
            },
        }
    end

    --one line like "5 Characters" with singular/plural handling.
    local function CountLine(n, singular, plural)
        if n == 1 then
            return string.format("1 %s", singular)
        end
        return string.format("%d %s", n, plural)
    end

    --summary lines for a game tile, from cached metadata only.
    local function SummarizeGame(gameInfo, isDirector)
        local lines = {}

        local nchars = 0
        for _,entry in pairs(gameInfo.characterIndex) do
            if isDirector or entry.owner == dmhub.loginUserid or entry.owner == dmhub.userid then
                nchars = nchars + 1
            end
        end

        if nchars > 0 then
            lines[#lines+1] = CountLine(nchars, "Character", "Characters")
        end

        if isDirector then
            local s = gameInfo.contentSummary
            if s ~= nil then
                if s.monsters > 0 then
                    lines[#lines+1] = CountLine(s.monsters, "Monster", "Monsters")
                end
                if s.classes > 0 then
                    lines[#lines+1] = CountLine(s.classes, "Class", "Classes")
                end
                if s.races > 0 then
                    lines[#lines+1] = CountLine(s.races, "Ancestry", "Ancestries")
                end
                if s.kits > 0 then
                    lines[#lines+1] = CountLine(s.kits, "Kit", "Kits")
                end
                if s.other > 0 then
                    lines[#lines+1] = string.format("+%d compendium entries", s.other)
                end
            end
        end

        return lines
    end

    local ShowGame --forward declaration; defined after the detail builder.

    --a game tile on the overview screen.
    local function CreateGameTile(entry)
        local gameInfo = entry.game
        local isDirector = entry.isDirector
        local unavailable = (gameInfo.storage == 3) and (not gameInfo.hasLocalData)

        local summary
        if unavailable then
            summary = "Unavailable: this offline game's data is on another computer."
        else
            summary = table.concat(SummarizeGame(gameInfo, isDirector), ", ")
            if summary == "" then
                summary = "Open this game to record its content."
            end
        end

        return gui.Panel{
            classes = {"mcTile", cond(unavailable, "unavailable", nil)},
            bgimage = "panels/square.png",
            flow = "vertical",
            width = 240,
            height = 208,
            margin = 8,
            borderBox = true,
            cornerRadius = 6,

            press = function(element)
                if not unavailable then
                    ShowGame(entry)
                end
            end,

            gui.Panel{
                width = 224,
                height = 100,
                halign = "center",
                vmargin = 8,
                cornerRadius = 6,
                bgcolor = "white",
                bgimage = gameInfo.coverart,
            },

            gui.Panel{
                flow = "horizontal",
                width = "100%-16",
                height = "auto",
                halign = "center",

                gui.Label{
                    fontSize = 16,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    maxWidth = 160,
                    textWrap = false,
                    valign = "center",
                    text = gameInfo.description,
                },

                gui.Label{
                    fontSize = 12,
                    color = cond(isDirector, "#ffcc66", "#88ccff"),
                    width = "auto",
                    height = "auto",
                    hmargin = 6,
                    valign = "center",
                    text = cond(isDirector, "Director", "Player"),
                },
            },

            gui.Label{
                fontSize = 12,
                color = "#aaaaaa",
                width = "100%-16",
                height = "auto",
                halign = "center",
                vmargin = 4,
                textWrap = true,
                text = summary,
            },
        }
    end

    --the per-game detail screen: characters as tiles, compendium content as a tree.
    local function CreateGameDetail(entry)
        local gameInfo = entry.game
        local isDirector = entry.isDirector
        local gameid = gameInfo.gameid
        local state = GameState(gameid)

        local players = gameInfo.playerInfo

        --gather the characters we show for this game from its cached index.
        local charEntries = {}
        for charid,charEntry in pairs(gameInfo.characterIndex) do
            local include = isDirector
            if not include then
                include = (charEntry.owner == dmhub.loginUserid) or (charEntry.owner == dmhub.userid)
            end

            if include then
                charEntries[#charEntries+1] = charEntry
            end
        end

        table.sort(charEntries, function(a,b)
            return (a.name or "") < (b.name or "")
        end)

        local BuildCharacterTiles = function()
            local rows = {}

            if #charEntries == 0 then
                rows[#rows+1] = gui.Label{
                    fontSize = 14,
                    color = "#aaaaaa",
                    width = "auto",
                    height = "auto",
                    hmargin = 24,
                    text = "No characters found in this game.",
                }
                return rows
            end

            --group by party. Characters with no recorded party go in one group.
            local groups = {}
            local groupOrder = {}
            for _,charEntry in ipairs(charEntries) do
                local key = charEntry.party or "__none"
                if groups[key] == nil then
                    groups[key] = {}
                    groupOrder[#groupOrder+1] = key
                end
                local list = groups[key]
                list[#list+1] = charEntry
            end

            table.sort(groupOrder, function(a,b)
                if (a == "__none") ~= (b == "__none") then
                    return b == "__none"
                end
                return a < b
            end)

            local multipleGroups = #groupOrder > 1

            for _,key in ipairs(groupOrder) do
                if multipleGroups or key ~= "__none" then
                    rows[#rows+1] = gui.Label{
                        fontSize = 14,
                        bold = true,
                        color = "#cccccc",
                        width = "auto",
                        height = "auto",
                        hmargin = 24,
                        vmargin = 2,
                        data = {
                            partyid = key,
                        },
                        text = cond(key == "__none", "No Party", state.partyNames[key] or "Party"),
                        gameContentReady = function(element, forGameid)
                            if forGameid == gameid and element.data.partyid ~= "__none" and state.partyNames[element.data.partyid] ~= nil then
                                element.text = state.partyNames[element.data.partyid]
                            end
                        end,
                    }
                end

                local tiles = {}
                for _,charEntry in ipairs(groups[key]) do
                    tiles[#tiles+1] = CreateCharacterTile(state, charEntry, players, gameid)
                end

                rows[#rows+1] = gui.Panel{
                    flow = "horizontal",
                    wrap = true,
                    width = "100%-24",
                    halign = "right",
                    height = "auto",
                }
                rows[#rows].children = tiles
            end

            return rows
        end

        local charactersPanel = CreateSection{
            title = "Characters",
            startExpanded = true,
            hmargin = 16,
            buildBody = BuildCharacterTiles,
        }

        --compendium content: only shown for games the user directs, and only once fetched.
        local BuildCompendiumSections = function()
            local sections = {}

            if state.content == nil or (not state.content.ready) then
                return sections
            end

            local bestiary = state.content:GetBestiary()
            local visibleMonsters = {}
            for _,m in ipairs(bestiary.monsters) do
                if not m.hidden then
                    visibleMonsters[#visibleMonsters+1] = m
                end
            end

            if #visibleMonsters > 0 then
                local folderNames = {}
                for _,f in ipairs(bestiary.folders) do
                    folderNames[f.id] = f.name
                end

                table.sort(visibleMonsters, function(a,b)
                    local afolder = folderNames[a.folder] or ""
                    local bfolder = folderNames[b.folder] or ""
                    if afolder ~= bfolder then
                        return afolder < bfolder
                    end
                    return (a.name or "") < (b.name or "")
                end)

                sections[#sections+1] = CreateSection{
                    title = string.format("Bestiary (%d)", #visibleMonsters),
                    hmargin = 16,
                    buildBody = function()
                        local rows = {}
                        rows[#rows+1] = CreateSelectionLinks(function()
                            return rows[1].parent
                        end)

                        local lastFolder = nil
                        for _,m in ipairs(visibleMonsters) do
                            local folderName = folderNames[m.folder]
                            if folderName ~= lastFolder and folderName ~= nil then
                                lastFolder = folderName
                                rows[#rows+1] = gui.Label{
                                    fontSize = 13,
                                    bold = true,
                                    color = "#cccccc",
                                    width = "auto",
                                    height = "auto",
                                    hmargin = 24,
                                    vmargin = 2,
                                    text = folderName,
                                }
                            end

                            rows[#rows+1] = CreateAssetRow(state, m.id, {
                                gameid = gameid,
                                title = m.name,
                                hmargin = 24,
                            })
                        end

                        return rows
                    end,
                }
            end

            local tables = state.content:GetObjectTables()

            local CreateTableSection = function(tableName)
                local visibleItems = {}
                for _,item in ipairs(tables[tableName] or {}) do
                    if not item.hidden then
                        visibleItems[#visibleItems+1] = item
                    end
                end

                if #visibleItems == 0 then
                    return nil
                end

                table.sort(visibleItems, function(a,b)
                    return (a.name or "") < (b.name or "")
                end)

                return CreateSection{
                    title = string.format("%s (%d)", g_tableDisplayNames[tableName] or tableName, #visibleItems),
                    hmargin = 16,
                    buildBody = function()
                        local rows = {}
                        rows[#rows+1] = CreateSelectionLinks(function()
                            return rows[1].parent
                        end)

                        for _,item in ipairs(visibleItems) do
                            rows[#rows+1] = CreateAssetRow(state, item.id, {
                                gameid = gameid,
                                title = item.name,
                                hmargin = 24,
                            })
                        end

                        return rows
                    end,
                }
            end

            --featured categories first, then everything else alphabetically.
            local featured = {"classes", "races", "kits"}
            local featuredSet = {}
            for _,tableName in ipairs(featured) do
                featuredSet[tableName] = true
                sections[#sections+1] = CreateTableSection(tableName)
            end

            local tableNames = {}
            for tableName,_ in pairs(tables) do
                if not featuredSet[tableName] then
                    tableNames[#tableNames+1] = tableName
                end
            end

            table.sort(tableNames, function(a,b)
                return (g_tableDisplayNames[a] or a) < (g_tableDisplayNames[b] or b)
            end)

            for _,tableName in ipairs(tableNames) do
                sections[#sections+1] = CreateTableSection(tableName)
            end

            return sections
        end

        local compendiumPanel = nil
        if isDirector then
            compendiumPanel = gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                gameContentReady = function(element, forGameid)
                    if forGameid == gameid then
                        element.children = BuildCompendiumSections()
                    end
                end,
            }

            if state.status == "ready" then
                compendiumPanel:FireEventTree("gameContentReady", gameid)
            end
        end

        local statusText
        if state.status == "error" then
            statusText = string.format("<color=#ff8888>Could not load this game's content: %s</color>", state.error or "unknown error")
        else
            statusText = "Loading game content..."
        end

        local statusLabel = gui.Label{
            classes = {cond(state.status == "ready", "collapsed", nil)},
            fontSize = 13,
            color = "#aaaaaa",
            width = "auto",
            height = "auto",
            hmargin = 16,
            vmargin = 4,
            text = statusText,
            gameContentReady = function(element, forGameid)
                if forGameid == gameid then
                    element:SetClass("collapsed", true)
                end
            end,
            gameContentError = function(element, forGameid, err)
                if forGameid == gameid then
                    element:SetClass("collapsed", false)
                    element.text = string.format("<color=#ff8888>Could not load this game's content: %s</color>", err or "unknown error")
                end
            end,
        }

        local bodyChildren = {
            statusLabel,
            charactersPanel,
        }

        if compendiumPanel ~= nil then
            bodyChildren[#bodyChildren+1] = compendiumPanel
        end

        return gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            children = bodyChildren,
        }
    end

    --the fixed navigation bar shown above the (scrolling) detail view: a back
    --button plus the game's cover, title, and role. Lives outside the scroll
    --region so the way back is always visible.
    local function CreateDetailHeader(entry)
        local gameInfo = entry.game
        local isDirector = entry.isDirector

        return gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "100%",
            borderBox = true,
            hpad = 4,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff11",

            gui.Button{
                classes = {"sizeS"},
                valign = "center",
                hmargin = 4,
                text = "< All Games",
                click = function(element)
                    resultPanel:FireEvent("showOverview")
                end,
            },

            gui.Panel{
                width = 72,
                height = 40,
                valign = "center",
                hmargin = 8,
                cornerRadius = 4,
                bgcolor = "white",
                bgimage = gameInfo.coverart,
            },

            gui.Label{
                fontSize = 18,
                bold = true,
                width = "auto",
                height = "auto",
                hmargin = 8,
                valign = "center",
                text = gameInfo.description,
            },

            gui.Label{
                fontSize = 13,
                color = cond(isDirector, "#ffcc66", "#88ccff"),
                width = "auto",
                height = "auto",
                hmargin = 8,
                valign = "center",
                text = cond(isDirector, "Director", "Player"),
            },
        }
    end

    ShowGame = function(entry)
        local gameid = entry.game.gameid
        m_currentGameid = gameid

        --a failed fetch gets another try each time the game is opened.
        local state = GameState(gameid)
        if state.status == "error" then
            state.status = "pending"
            state.error = nil
        end

        m_detailHeaderBar.children = { CreateDetailHeader(entry) }
        m_detailContainer.children = { CreateGameDetail(entry) }
        EnsureFetched(gameid)

        m_overviewPanel:SetClass("collapsed", true)
        m_detailHeaderBar:SetClass("collapsed", false)
        m_detailContainer:SetClass("collapsed", false)
        m_footerPanel:SetClass("collapsed", false)

        m_statusLabel.text = ""
        MarkSelectionDirty()
        resultPanel:FireEventTree("refreshCounts")
    end

    local function ShowOverview()
        m_currentGameid = nil
        m_detailHeaderBar:SetClass("collapsed", true)
        m_detailHeaderBar.children = {}
        m_detailContainer:SetClass("collapsed", true)
        m_detailContainer.children = {}
        m_overviewPanel:SetClass("collapsed", false)
        m_footerPanel:SetClass("collapsed", true)
        MarkSelectionDirty()
    end

    local function StartScan()
        if m_scanStarted then
            return
        end

        m_scanStarted = true

        local gameEntries = {}
        for _,g in ipairs(lobby.games) do
            if g.gameid ~= dmhub.gameid then
                gameEntries[#gameEntries+1] = {
                    game = g,
                    isDirector = g:IsDM(nil),
                }
            end
        end

        table.sort(gameEntries, function(a,b)
            if a.isDirector ~= b.isDirector then
                return a.isDirector
            end
            return (a.game.description or "") < (b.game.description or "")
        end)

        local tiles = {}
        for _,entry in ipairs(gameEntries) do
            tiles[#tiles+1] = CreateGameTile(entry)
        end

        if #tiles == 0 then
            tiles[#tiles+1] = gui.Label{
                fontSize = 16,
                color = "#aaaaaa",
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 32,
                text = "You are not in any other games.",
            }
        end

        m_overviewGrid.children = tiles
    end

    local function DoImport()
        if m_importing or m_currentGameid == nil then
            return
        end

        --make sure the closure reflects the very latest selection before we commit.
        if m_selectionDirty then
            m_selectionDirty = false
            RecomputeSelection()
        end

        local state = m_state[m_currentGameid]
        if state == nil or state.installGuids == nil or #state.installGuids == 0 or state.content == nil then
            return
        end

        local guids = state.installGuids
        local count = #guids

        m_importing = true
        m_importButton:SetClass("hidden", true)
        m_statusLabel.text = "Importing..."

        state.content:Install{
            guids = guids,
            progress = function(status, done, total)
                if resultPanel.valid then
                    m_statusLabel.text = string.format("%s (%d/%d)", status, done, total)
                end
            end,
            complete = function(success, err, skipped)
                if mod.unloaded then
                    return
                end

                m_importing = false

                if not success then
                    if resultPanel.valid then
                        m_statusLabel.text = string.format("<color=#ff8888>Import failed: %s</color>", err or "unknown error")
                    end
                    MarkSelectionDirty()
                    return
                end

                state.selected = {}
                state.installGuids = nil

                if resultPanel.valid then
                    m_statusLabel.text = string.format("Import complete! %d items copied into this game.", count)
                    resultPanel:FireEventTree("clearSelection")
                end

                MarkSelectionDirty()
            end,
        }
    end

    m_overviewGrid = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
    }

    m_overviewPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        vscroll = true,
        hideObjectsOutOfScroll = true,

        gui.Label{
            fontSize = 14,
            color = "#aaaaaa",
            width = "auto",
            height = "auto",
            hmargin = 8,
            vmargin = 6,
            text = "Choose a game to browse and import its content into this game.",
        },

        m_overviewGrid,
    }

    m_detailHeaderBar = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = 48,
        flow = "vertical",
    }

    m_detailContainer = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%-148",
        flow = "vertical",
        vscroll = true,
        hideObjectsOutOfScroll = true,
    }

    m_depsLabel = gui.Label{
        fontSize = 14,
        width = "100%",
        height = "auto",
        maxWidth = 1020,
        textWrap = true,
        halign = "left",
        text = "",
    }

    m_costLabel = gui.Label{
        fontSize = 13,
        color = "#aaaaaa",
        width = 360,
        height = "auto",
        textAlignment = "left",
        valign = "center",
        text = "",
    }

    m_statusLabel = gui.Label{
        fontSize = 15,
        width = 420,
        height = "auto",
        textAlignment = "center",
        valign = "center",
        text = "",
    }

    m_importButton = gui.Button{
        classes = {"sizeL", "hidden"},
        valign = "center",
        hmargin = 8,
        text = "Import",
        click = function(element)
            DoImport()
        end,
    }

    m_footerPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = 96,
        flow = "vertical",
        borderBox = true,
        vpad = 4,

        m_depsLabel,

        gui.Panel{
            width = "100%",
            height = 44,
            flow = "horizontal",

            m_costLabel,
            m_statusLabel,
            m_importButton,
        },
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = 1060,
        height = g_importDialogHeight - g_importDialogHeaderHeight,
        halign = "center",

        data = {
            type = "mycontent",
        },

        styles = {
            {
                selectors = {"mcRow"},
                bgcolor = "clear",
            },
            {
                selectors = {"mcRow", "hover"},
                bgcolor = "#ffffff22",
            },
            {
                selectors = {"mcTile"},
                bgcolor = "#ffffff08",
            },
            {
                selectors = {"mcTile", "hover"},
                bgcolor = "#ffffff22",
            },
            {
                selectors = {"mcCharTile"},
                bgcolor = "#ffffff08",
                borderWidth = 2,
                borderColor = "#00000000",
            },
            {
                selectors = {"mcCharTile", "hover"},
                bgcolor = "#ffffff22",
            },
            {
                selectors = {"mcCharTile", "selected"},
                bgcolor = "#ffcc6622",
                borderColor = "#ffcc66",
            },
            {
                selectors = {"unavailable"},
                color = "#888888",
                strikethrough = true,
            },
        },

        importer = function(element, importer)
            if importer.input == "mycontent" then
                StartScan()
            end
        end,

        showOverview = function(element)
            ShowOverview()
        end,

        thinkTime = 0.25,
        think = function(element)
            if m_selectionDirty then
                m_selectionDirty = false
                RecomputeSelection()
            end
        end,

        m_overviewPanel,
        m_detailHeaderBar,
        m_detailContainer,
        m_footerPanel,
    }

    return resultPanel
end

CreateImportAssetsDialog = function(args)
    local dialogPanel

    local m_currentImporter = nil
    local m_currentImporterId = nil

    import:ClearState()

    local textImport
    local textImportButton = gui.Button{
        classes = {"hidden"},
        halign = "center",
        valign = "bottom",
        text = "Import",
        click = function(element)
            element:SetClass("hidden", true)
            import:ImportFromText(textImport.text)
            dialogPanel:FireEventTree("refreshImport")
        end,
    }

    textImport = gui.Input{
        width = 500,
        height = 100,
        placeholderText = "Paste JSON data...",
        textAlignment = "topleft",
        text = "",
        edit = function(element)
            textImportButton:SetClass("hidden", false)
        end,
    }

    local textImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        data = {
            type = "text",
        },

        textImport,
        textImportButton,
    }

    local plaintextImportPanel
    plaintextImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        data = {
            type = "plaintext",
        },
 
        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ReadTextFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        print("Calling ImportPlainText with data: ", json(data))
                        import:ImportPlainText(data)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"txt", "json", "ds-hero"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        plaintextImportPanel:FireEvent("openFiles", paths)
                    end,
                }
            end,
        },

    }

    local docxImportPanel
    docxImportPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",

        data = {
            type = "docx",
        },
 
        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ParseDocxFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        print("Calling ImportPlainText with data: ", json(data))
                        import:ImportPlainText(data)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"docx", "txt"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        docxImportPanel:FireEvent("openFiles", paths)
                    end,
                }
            end,
        },
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Folder...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFolderDialog{
                    id = "Import",
                    extensions = {"docx"},
                    prompt = "Choose folder to import...",
                    open = function(folderPath, files)
                        docxImportPanel:FireEvent("openFiles", files)
                    end,
                }
            end,
        },       

    }

    local filesImportPanel
    filesImportPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",

        data = {
            type = "files",
        },

        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ParseJsonFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        import:ImportFromJson(data, path)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"json"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        filesImportPanel:FireEvent("openFiles", paths)

                    end,
                }
            end,
        },

        gui.Button{
            classes = {"sizeL"},
            text = "Choose Folder...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFolderDialog{
                    id = "Import",
                    extensions = {"json"},
                    prompt = "Choose folder to import...",
                    open = function(folderPath, files)
                        filesImportPanel:FireEvent("openFiles", files)
                    end,
                }
            end,
        },

    }

    local urlImportPanel
    urlImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        data = {
            type = "url",
        },

        gui.Panel{
            width = "auto",
            height = 28,
            flow = "horizontal",
            halign = "center",
            gui.Input{
                placeholderText = "Enter URL...",
                halign = "center",
                width = 600,
                height = 28,
                fontSize = 20,
                characterLimit = 1024,
                data = {
                    url = "",
                },
                importer = function(element, importer)
                    element.placeholderText = importer.urlText or "Enter URL..."
                end,

                change = function(element)
                    local url = element.data.url

                    if url ~= "" and url ~= nil then
                        element.text = ""
                        element.data.url = ""
                        element.parent:FireEventTree("url", element.data.url)

                        printf("NET:: Sent request for %s", url)
                        net.Get{
                            url = url,
                            success = function(data)
                        printf("NET:: SUCCESS %s / %s", url, json(data))
                                import:ImportFromJson(data, url)
                                dialogPanel:FireEventTree("refreshImport")
                            end,
                            error = function(err)
                        printf("NET:: FAILURE %s", err)
                                dialogPanel:FireEventTree("error", err)
                            end,
                        }
                    else
                        dialogPanel:FireEventTree("error", "URL is not valid")
                    end
                end,

                edit = function(element)
                    local url = element.text
                    if m_currentImporter.translateurl ~= nil then
                        url = m_currentImporter.translateurl(element.text)
                        if url == nil then
                            url = ""
                        end
                    end

                    element.data.url = url

                    element.parent:FireEventTree("url", url)
                end,
            },

            gui.Button{
                classes = {"sizeL", "hidden"},
                width = 160,
                text = "Submit",
                url = function(element, url)
                    element:SetClass("hidden", url == "")
                end,
                click = function(element)
                    element.parent:FireEventTree("change")
                end,
            },
        },
    }

    local myContentImportPanel = CreateMyContentImportPanel()

    local importers = import.importers
    local importerOptions = {}
    for key,importer in pairs(importers) do
        importerOptions[#importerOptions+1] = {
            id = key,
            text = importer.description,
            ord = importer.priority or 0,
        }
    end

    table.sort(importerOptions, function(a,b) return a.ord > b.ord end)

    local importPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        hmargin = 32,
        halign = "center",
        valign = "top",
        vmargin = 16,
        import = function(element)
        end,

        gui.Panel{
            importer = function(element, importer)
                local children = element.children
                for _,child in ipairs(children) do
                    child:SetClass("collapsed", child.data.type ~= importer.input)
                end
            end,
            flow = "none",
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            textImportPanel,
            plaintextImportPanel,
            filesImportPanel,
            docxImportPanel,
            urlImportPanel,
            myContentImportPanel,
        },
    }

    --read the last used importer, but also make sure it's valid.
    local importerid = importerOptions[1].id
    if g_currentImporterSetting:Get() ~= nil then
        local id = g_currentImporterSetting:Get()
        for _,option in ipairs(importerOptions) do
            if id == option.id then
                importerid = option.id
            end
        end
    end

    local importerDropdown = gui.Dropdown{
        width = 240,
        options = importerOptions,
        idChosen = importerid,
        create = function(element)
            element:FireEvent("change")
        end,
        change = function(element)
            g_currentImporterSetting:Set(element.idChosen)
            m_currentImporter = importers[element.idChosen]
            m_currentImporterId = element.idChosen
            import:SetActiveImporter(m_currentImporterId)
            importPanel:FireEventTree("importer", importers[element.idChosen])
        end,
    }

    local importerSelectionPanel = gui.Panel{
        flow = "horizontal",
        halign = "center",
        valign = "top",
        width = "auto",
        height = "auto",
        hmargin = 8,
        vmargin = 16,
        gui.Label{
            hmargin = 8,
            text = "Choose Importer:",
            height = 28,
            fontSize = 18,
            textAlignment = "center",
            width = "auto",
        },
        importerDropdown,
    }

    local contentPanel = gui.Panel{
        classes = "collapsed",
        halign = "center",
        valign = "center",
        flow = "vertical",
        hpad = 20,
        width = 500,
        height = 420,

        error = function(element)
            element:SetClass("collapsed", true)
        end,

        import = function(element)
            element:SetClass("collapsed", false)
        end,

        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vpad = 8,
            vscroll = true,
		    hideObjectsOutOfScroll = true,

            styles = {
                {
                    selectors = {"exclude"},
                    strikethrough = true,
                    color = "#777777",
                },

                {
                    selectors = {"deleteItemButton"},
                    hidden = 1,

                },
                {
                    selectors = {"deleteItemButton", "parent:hover", "~importing"},
                    hidden = 0,
                },


            },

            import = function(element)
                local children = {}
                local imports = import:GetImports()
                local count = 0
                for _,_ in pairs(imports) do
                    count = count+1
                end
                printf("IMPORT:: IMPORT COUNT = %d", count)
                for tableid,tableInfo in pairs(imports) do
                    for key,asset in pairs(tableInfo) do


                        local outcomeIcon = gui.Panel{
                            classes = {"hidden"},
                            floating = true,
                            bgimage = "ui-icons/greend20.png",
                            bgcolor = "white",
                            width = 16,
                            height = 16,
                            vmargin = 8,
                            hmargin = 8,
                            halign = "right",
                            valign = "top",

                            data = {
                                tooltip = nil,
                            },

                            hover = function(element)
                                if element.data.tooltip ~= nil then
                                    gui.Tooltip(element.data.tooltip)(element)
                                end
                            end,

                            importing = function(element)
                                if not element:HasClass("hidden") then
                                    return
                                end

                                local result = import.importedAssets[key]
                                printf("Imported assets: %s vs %s", key, json(import.importedAssets))
                                if result ~= nil then
                                    element:SetClass("hidden", false)
                                    if type(result) == "string" then
                                        element.selfStyle.bgimage = "ui-icons/redd20.png"
                                        element.data.tooltip = result
                                    else
                                        element.data.tooltip = "Imported Successfully"
                                    end
                                end
                            end,
                        }

                        local reimportIcon

                        if import:IsReimport(asset) then
                            reimportIcon = gui.Panel{
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 64,
                                width = 16,
                                height = 16,
                                bgcolor = "white",
                                bgimage = "panels/hud/clockwise-rotation.png",
                                hover = gui.Tooltip("This asset already exists and will be re-imported."),
                            }
                        end

                        print("XXX: REIMPORT ICON = ", reimportIcon ~= nil)


                        local alertIcon

                        if import:GetAssetLog(asset) ~= nil then
                            alertIcon = gui.Label{
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 40,
                                width = 16,
                                height = 16,
                                cornerRadius = 8,
                                bgimage = "panels/square.png",
                                bgcolor = "#999900",
                                fontSize = 18,
                                bold = true,
                                color = "black",
                                opacity = 1,
                                textAlignment = "center",
                                text = "!",

                                showRenderLog = function(element, istooltip)
                                    if element.popup ~= nil then
                                        return
                                    end

                                    local panel = gui.TooltipFrame(
                                        gui.Panel{
                                            width = "auto",
                                            height = "auto",
                                            maxHeight = 900,
                                            vscroll = true,
                                            styles = {
                                                Styles.Default
                                            },

                                            gui.Panel{
                                                hpad = 8,
                                                width = "auto",
                                                height = "auto",
                                                flow = "vertical",
                                                valign = "top",
                                                import:GetCurrentImporter().renderLog(import:GetAssetLog(asset)),
                                            },
                                        }, {
                                            halign = "left",
                                            valign = "center",
                                        }
                                    )

                                    if istooltip then
                                        element.tooltip = panel
                                    else
                                        element.popup = panel
                                    end


                                end,

                                press = function(element)
                                    if import:GetCurrentImporter().renderLog ~= nil then
                                        element:FireEvent("showRenderLog", false)
                                    end
                                end,

                                hover = function(element)
                                    if import:GetCurrentImporter().renderLog ~= nil then
                                        element:FireEvent("showRenderLog", true)

                                    else
                                        local text = ""
                                        for _,log in ipairs(import:GetAssetLog(asset)) do
                                            if text ~= "" then
                                                text = text .. "\n"
                                            end

                                            text = string.format("%s%s %s", text, Styles.bullet, log)
                                        end

                                        gui.Tooltip{text = text, fontSize = 14}(element)
                                    end
                                end,
                            }
                        end

                        local panel
                        panel = gui.Panel{
                            classes = {"importItemPanel"},
                            bgimage = "panels/square.png",
                            width = "90%",
                            height = 40,
                            halign = "left",
                            hmargin = 8,
                            flow = "vertical",

                            styles = {
                                {
                                    bgcolor = "clear",
                                },
                                {
                                    selectors = {"hover"},
                                    bgcolor = "#ffffff22",
                                },
                            },

                            data = {
                                ord = {tableid, asset.name},
                            },

                            alertIcon,
                            reimportIcon,
                            outcomeIcon,

                            gui.Panel{
                                flow = "horizontal",
                                width = 250,
                                height = 40,
                                hmargin = 8,
                                hover = function(element)
                                    local tooltip = CreateCompendiumItemTooltip(asset, {halign = "right", valign = "center", width = 800})
                                    element.tooltip = tooltip
                                end,
                                gui.Panel{
                                    width = 40,
                                    height = 40,
                                    bgcolor = "white",
                                    thinkTime = 0.2,
                                    think = function(element)
                                        local img = import:GetImage(asset)
                                        if img ~= nil then
                                            element.bgimage = img
                                        end
                                    end,
                                },

                                gui.Panel{
                                    flow = "vertical",
                                    width = "auto",
                                    height = 40,
                                    gui.Label{
                                        fontSize = 16,
                                        bold = true,
                                        width = "auto",
                                        height = 20,
                                        minWidth = 200,
                                        vmargin = 1,
                                        hmargin = 4,
                                        valign = "top",
                                        text = asset.name,
                                    },

                                    gui.Label{
                                        fontSize = 14,
                                        width = 200,
                                        height = 20,
                                        vmargin = 1,
                                        hmargin = 4,
                                        valign = "top",
                                        text = tableid,
                                    },
                                },
                            },

                            gui.Button{
                                classes = {"deleteButton", "sizeS"},
                                floating = true,
                                halign = "right",
                                valign = "top",
                                click = function(element)
                                    panel:SetClassTree("exclude", not panel:HasClass("exclude"))
                                    import:SetImportRemoved(key, panel:HasClass("exclude"))
                                end,
                            },
                        }

                        children[#children+1] = panel
                    end
                end


                table.sort(children, function(a,b)
                    for i=1,#a.data.ord do
                        if a.data.ord[i] ~= b.data.ord[i] then
                            return a.data.ord[i] < b.data.ord[i]
                        end
                    end
                end)



                element.children = children
            end,
        },

    }

    local logPanel = gui.Panel{
        vscroll = true,
        height = 240,
        width = 400,
        flow = "vertical",
        floating = true,
        halign = "right",
        valign = "bottom",
        margin = 8,

        styles = {
            {
                selectors = {"label"},
                width = "90%",
                height = "auto",
                fontSize = 16,
                halign = "left",
                hmargin = 4,
                textWrap = true,
            }
        },

        import = function(element)
            local children = {}
            local imports = import:GetImports()
            for _,entry in ipairs(import:GetLog()) do

                local label = gui.Label{
                    text = entry,
                }

                children[#children+1] = label
            end

            element.children = children
        end,
    }

    local statusMessage = gui.Label{
        classes = {"collapsed"},
        halign = "left",
        valign = "center",
        hmargin = 64,
        width = "auto",
        height = "auto",
        maxWidth = 400,
        fontSize = 18,

        error = function(element, error)
            element:SetClass("collapsed", false)

            local text = error or import.error
            if m_currentImporter.translateerror ~= nil then
                text = m_currentImporter.translateerror(text) or text
            end
            element.text = text
        end,
        import = function(element)
            element:SetClass("collapsed", true)
        end,
    }

    local completeButton = gui.Button{
        classes = {"sizeL", "hidden"},
        halign = "center",
        valign = "bottom",
        text = "Finish",
        click = function(element)
            dialogPanel.parent:DestroySelf()
        end,
    }

    local importingText = gui.Label{
        classes = {"hidden"},
        halign = "center",
        valign = "bottom",
        text = "Importing",
        fontSize = 22,
        width = "auto",
        height = "auto",
        vmargin = 16,

        think = function(element)
            if element.text == "Importing" then
                element.text = "Importing."
            elseif element.text == "Importing." then
                element.text = "Importing.."
            elseif element.text == "Importing.." then
                element.text = "Importing..."
            else
                element.text = "Importing"
            end

            if import.pendingUpload == false then
                dialogPanel:SetClassTree("importing", true)
                dialogPanel:FireEventTree("importing")
                local processing = import:CompleteImportStep()
                if not processing then
                    element.thinkTime = nil

                    if import.error ~= nil then
                        element.root:FireEventTree("refreshImport")
                        element.text = "Error Importing"
                    else
                        element.text = "Complete!"
                        element:ScheduleEvent("complete", 1)
                    end
                end
            end
        end,

        complete = function(element)
            element:SetClass("hidden", true)
            completeButton:SetClass("hidden", false)
        end,
    }


    local bandwidthLabel = gui.Label{
        floating = true,
        halign = "left",
        valign = "bottom",
        hmargin = 16,
        vmargin = 64,
        fontSize = 16,
        width = 420,
        height = "auto",
        maxWidth = 420,

        refreshImport = function(element)
            local kb = import.uploadCostKB

            if kb <= 0 then
                element.text = ""
                return
            end

            local notEnough = ""
            if not import.haveEnoughBandwidth then
                notEnough = "\n<color=#ff0000>Not enough bandwidth available</color>"
            end

            element.text = string.format("Bandwidth required to import assets: %dKB\nBandwidth available this month: %dKB%s", kb, round(dmhub.uploadQuotaRemaining/1024), notEnough)
        end,
    }

    local importButton = gui.Button{
        classes = {"sizeL", "hidden"},
        halign = "center",
        valign = "bottom",
        text = "Import",
        refreshImport = function(element)
            if import.error ~= nil then
                element:SetClass("hidden", true)
            else
                local haveImports = false
                local imports = import:GetImports()
                for tableid,tableInfo in pairs(imports) do
                    for key,asset in pairs(tableInfo) do
                        haveImports = true
                    end
                end

                element:SetClass("hidden", (not haveImports) or (not import.haveEnoughBandwidth))

            end
        end,
        click = function(element)
            element:SetClass("hidden", true)
            importingText:SetClass("hidden", false)
            importingText.thinkTime = 0.1
        end,
    }



    dialogPanel = gui.Panel{
        width = 1200,
        height = g_importDialogHeight,
        flow = "vertical",

        refreshImport = function(element)
            if import.error == nil then
                dialogPanel:FireEventTree("import")
            else
                dialogPanel:FireEventTree("error")
            end
        end,

        gui.Label{
            classes = {"title"},
            vmargin = 16,
            valign = "top",
            halign = "center",
            width = "auto",
            height = "auto",
            text = "Importer",
        },

        importerSelectionPanel,
        importPanel,
        contentPanel,

        statusMessage,
        importingText,
        completeButton,

        bandwidthLabel,
        importButton,

        logPanel,

    }

    return dialogPanel
end

--register the built-in My Other Games importer, which pulls content from the
--user's other games. It uses its own browser panel rather than a text/file
--input. Highest priority makes it the default importer in the dropdown (a
--user's last-used importer, once they pick one, still wins).
if import ~= nil and import.Register ~= nil then
    import.Register{
        id = "mycontent",
        description = "My Other Games",
        input = "mycontent",
        priority = 300,
    }
end
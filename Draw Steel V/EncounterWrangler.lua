local mod = dmhub.GetModLoading()

--=============================================================================
-- ENCOUNTER WRANGLER
-- ------------------
-- A Director-facing window for managing every monster in the current
-- encounter, opened from the notebook button on the monster side of the
-- initiative bar (MCDMInitiativeBar.lua).
--
-- A Malice card leads the grid: every malice ability available in the
-- encounter, aggregated and deduped across monsters -- abilities every
-- monster shares sit under "Common", band-specific ones under their band's
-- name ("Goblin", "Orc"). While a monster that can use one has the turn,
-- affordable abilities pulse and clicking casts them through the action
-- bar, just like the statblock abilities below.
--
-- Monsters are grouped by monster type, so five Goblin Warriors produce ONE
-- card: a compact single-line row per initiative unit (a monster, several
-- same-type monsters grouped onto one initiative, or a whole minion squad
-- shown as a token stack in its squad color), with stamina, condition
-- icons (+ add menu), grouped partners from other cards on the right (a
-- squad's captain crowned), turn state (grey = moved, highlight = current,
-- pulsing swords = eligible to be picked, click to take the turn), followed
-- by the type's statblock rendered once via monster:Render -- the same
-- renderer the character panel's bestiary popup uses. Cards lay out side by
-- side and wrap; ONE outer scrollbar handles overflow.
--
-- Hosted as a menu-hidden dockable panel registration so the icon-rail
-- window machinery provides all the chrome: title bar, drag, resize,
-- close, and the pop-out-into-an-OS-window button.
--=============================================================================

EncounterWrangler = {
    panelName = "Encounter Wrangler",
}

--The wrangler is experimental: it only surfaces when the per-user
--"dev:encounterwrangler" flag is on (toggle with "/toggle dev:encounterwrangler"
--in chat). Deliberately absent from SettingsScreen.lua so it never appears in
--the settings UI, and the dockable panel it hosts is already filtered out of
--the panel menus and the icon rail, so the flag gates the ONLY entry point:
--the notebook button on the monster side of the initiative bar
--(MCDMInitiativeBar.lua reads the same flag by id).
EncounterWrangler.enabledSetting = setting{
    id = "dev:encounterwrangler",
    default = false,
    storage = "preference",
}

--True if the wrangler is available to this user at all.
function EncounterWrangler.Enabled()
    return dmhub.GetSettingValue("dev:encounterwrangler") == true
end

local STATBLOCK_WIDTH = 500
--borderBox card: statblock width + the card's own padding.
local CARD_WIDTH = STATBLOCK_WIDTH + 16
--Cards are packed into fixed-width columns; a column is a card plus the
--hmargin it carries on each side.
local COLUMN_WIDTH = CARD_WIDTH + 12
--the vscroll host's scrollbar overlays the right edge of its 100%-wide
--child once the content overflows; keep the last column clear of it.
local SCROLLBAR_GUTTER = 16
local MAX_COLUMNS = 12

local g_wranglerStyles = {
    {
        selectors = {"wranglerCard"},
        bgcolor = "#00000066",
        borderWidth = 1,
        borderColor = "#ffffff33",
        cornerRadius = 4,
    },
    {
        selectors = {"wranglerCardTitle"},
        fontSize = 24,
        bold = true,
        color = "white",
    },
    --the xN multiplier riding next to a monster card's title.
    {
        selectors = {"wranglerCardCount"},
        fontSize = 15,
        bold = true,
        color = "#cccccc",
    },
    --the level/role line on the right of a monster card's header.
    {
        selectors = {"wranglerCardRole"},
        fontSize = 13,
        color = "#cccccc",
    },
    {
        selectors = {"wranglerRow"},
        bgcolor = "clear",
    },
    {
        selectors = {"wranglerRow", "hover"},
        bgcolor = "#ffffff11",
    },
    {
        selectors = {"wranglerRowName"},
        fontSize = 13,
        color = "white",
    },
    {
        selectors = {"wranglerRowStamina"},
        fontSize = 13,
        bold = true,
        color = "#9fdcae",
    },
    {
        selectors = {"wranglerRowStamina", "winded"},
        color = "#ffaa44",
    },
    {
        selectors = {"wranglerRowStamina", "dying"},
        color = "#ff5555",
    },
    {
        selectors = {"wranglerRowStamina", "dead"},
        color = "#ff5555",
    },
    {
        selectors = {"wranglerCondAdd"},
        fontSize = 14,
        bold = true,
        color = "#ffffff88",
        textAlignment = "center",
    },
    {
        selectors = {"wranglerCondAdd", "hover"},
        color = "white",
    },
    {
        selectors = {"wranglerCondIcon", "hover"},
        brightness = 1.5,
    },
    --an entry that has taken its turn: desaturated token, greyed-out name.
    {
        selectors = {"wranglerRowName", "hadTurn"},
        color = "#888888",
    },
    {
        selectors = {"tokenImagePortrait", "hadTurn"},
        saturation = 0,
    },
    {
        selectors = {"tokenImageFrame", "hadTurn"},
        saturation = 0,
    },
    {
        selectors = {"wranglerRow", "currentTurn"},
        bgcolor = "#DE1E4744",
        borderWidth = 1,
        borderColor = "#DE1E47",
    },
    {
        selectors = {"wranglerRow", "partnerHighlight"},
        bgcolor = "#ffffff33",
        borderWidth = 1,
        borderColor = "white",
    },
    {
        selectors = {"wranglerNote"},
        fontSize = 14,
        color = "#ccccccff",
        textAlignment = "center",
    },
    --section headers inside the Malice card: "Common", "Goblin", etc.
    {
        selectors = {"wranglerMaliceSection"},
        fontSize = 15,
        bold = true,
        smallcaps = true,
        color = "#d9b96c",
    },
}

--Collect the encounter's monsters, grouped by monster type. Uses the
--initiative queue's non-player entries when initiative is running;
--otherwise falls back to every monster on the current map so the Director
--can prep before rolling initiative. Tokens without a monster type (e.g.
--a director-run named NPC riding a monster entry) group individually.
local function CollectGroups()
    local byKey = {}
    local groups = {}

    local function AddToken(tok, requireMonster)
        if tok == nil or not tok.valid or tok.properties == nil then
            return
        end

        local isMonster = false
        pcall(function() isMonster = tok.properties:IsMonster() end)
        if requireMonster and not isMonster then
            return
        end

        local monsterType = nil
        pcall(function() monsterType = tok.properties:GetMonsterType() end)
        if monsterType == "" then
            monsterType = nil
        end

        local key = monsterType or ("token:" .. tok.charid)
        local group = byKey[key]
        if group == nil then
            group = {
                key = key,
                name = monsterType or tok.name or "Creature",
                tokens = {},
            }
            byKey[key] = group
            groups[#groups+1] = group
        end
        group.tokens[#group.tokens+1] = tok
    end

    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        for k,_ in pairs(queue.entries) do
            if not queue:IsEntryPlayer(k) then
                local tokens = InitiativeQueue.GetTokensForInitiativeId(k, dmhub.allTokens)
                for _,tok in ipairs(tokens) do
                    AddToken(tok, false)
                end
            end
        end
    else
        local tokens = dmhub.GetTokens{ playerControlled = false }
        for _,tok in ipairs(tokens) do
            AddToken(tok, true)
        end
    end

    table.sort(groups, function(a, b) return a.name < b.name end)
    for _,group in ipairs(groups) do
        table.sort(group.tokens, function(a, b)
            local an = a.name or ""
            local bn = b.name or ""
            if an ~= bn then
                return an < bn
            end
            return a.charid < b.charid
        end)
    end

    return groups
end

--A cheap membership fingerprint: the hud broadcasts 'refresh' on every game
--dirty, and we only rebuild the cards when the roster actually changed.
--Includes each token's initiative id so regrouping monsters (or forming
--squads) rebuilds the rows; turn/stamina churn stays row-local.
local function GroupsSignature(groups)
    local parts = {}
    for _,group in ipairs(groups) do
        parts[#parts+1] = group.key
        for _,tok in ipairs(group.tokens) do
            parts[#parts+1] = tok.charid
            local initid = nil
            pcall(function() initid = InitiativeQueue.GetInitiativeId(tok) end)
            parts[#parts+1] = initid or ""
        end
    end
    return table.concat(parts, "|")
end

--Split a group's tokens into display units, respecting initiative grouping:
--tokens sharing an initiative entry (a minion squad's shared entry, or a
--deliberate initiativeGrouping) share ONE row. A squad always gets its own
--row even inside a larger grouped entry, so it keeps its color and stack.
--Units carry charids, not tokens -- rows re-resolve.
local function PartitionUnits(tokens)
    local units = {}
    local byKey = {}
    for _,tok in ipairs(tokens) do
        local initid = nil
        pcall(function() initid = InitiativeQueue.GetInitiativeId(tok) end)
        initid = initid or tok.charid

        local squadName = nil
        pcall(function()
            if tok.properties.minion then
                squadName = tok.properties:MinionSquad()
            end
        end)

        local key = initid .. "|" .. (squadName or "")
        local unit = byKey[key]
        if unit == nil then
            unit = { initid = initid, squad = squadName, charids = {} }
            byKey[key] = unit
            units[#units+1] = unit
        end
        unit.charids[#unit.charids+1] = tok.charid
    end
    return units
end

--Union of conditions + status effects across a unit's tokens, deduped, as
--{icon, display, name, tooltip, remove(token)} entries. Same table lookups
--the character panel's chips use.
local function CollectConditionEntries(tokens)
    local seen = {}
    local entries = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    local ongoingTable = dmhub.GetTable("characterOngoingEffects") or {}

    for _,tok in ipairs(tokens) do
        local c = tok.properties
        if c ~= nil then
            for condid, cond in pairs(c:try_get("inflictedConditions", {})) do
                local info = conditionsTable[condid]
                if info ~= nil and not seen["cond:" .. condid] then
                    seen["cond:" .. condid] = true
                    local tooltip = nil
                    pcall(function() tooltip = TacPanel.ConditionTooltipText(condid, cond, c) end)
                    entries[#entries+1] = {
                        icon = info.iconid,
                        display = info.display or {},
                        name = info.name,
                        tooltip = tooltip or info.name,
                        remove = function(t)
                            t.properties:InflictCondition(condid, {purge = true})
                        end,
                    }
                end
            end

            local effects = nil
            pcall(function() effects = c:ActiveOngoingEffects() end)
            for _,entry in ipairs(effects or {}) do
                local info = ongoingTable[entry.ongoingEffectid]
                if info ~= nil and info.statusEffect and not seen["fx:" .. entry.ongoingEffectid] then
                    seen["fx:" .. entry.ongoingEffectid] = true
                    local icon = nil
                    local display = {}
                    local tooltip = nil
                    pcall(function()
                        icon = info:GetDisplayIcon()
                        display = info:GetDisplayDisplay() or {}
                        tooltip = TacPanel.StatusEffectTooltipText(entry, info, c)
                    end)
                    entries[#entries+1] = {
                        icon = icon,
                        display = display,
                        name = info.name,
                        tooltip = tooltip or info.name,
                        remove = function(t)
                            t.properties:RemoveOngoingEffect(entry.ongoingEffectid)
                        end,
                    }
                end
            end
        end
    end

    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)
    return entries
end

--One compact single-line row per unit -- an initiative entry's worth of
--monsters within one type card: a single monster, several same-type
--monsters grouped onto one initiative, or a whole minion squad. Shows a
--token stack, name (squad rows in their squad color), a compact stamina
--readout, condition icons with a + to add more, and any grouped partners
--from other type cards (a squad's captain wears the crown) on the right.
--Greyed once the entry has taken its turn, highlighted while it IS the
--turn, and pulsing claim-swords while it is eligible to be picked.
--Rows update from the hud's 'refresh' broadcast, which covers every
--member token (a single monitorGame path could not).
local function CreateInstanceRow(unit, groupName)
    local m_charids = unit.charids
    local m_squadName = unit.squad
    local m_initid = unit.initid

    local m_charidSet = {}
    for _,charid in ipairs(m_charids) do
        m_charidSet[charid] = true
    end

    local function ResolveTokens()
        local out = {}
        for _,charid in ipairs(m_charids) do
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid and tok.properties ~= nil then
                out[#out+1] = tok
            end
        end
        return out
    end

    --The unit's tokens as a small stack: all full size, fanned
    --left-to-right with the lead token leftmost. Sibling order is z-order,
    --so copies are added rightmost-first and the lead last, putting the
    --lead on top of the stack.
    local stackPanel = gui.Panel{
        flow = "none",
        width = 36,
        height = "100%",
        halign = "left",
        valign = "center",
    }
    do
        local children = {}
        local count = math.min(#m_charids, 4)
        local step = 8
        if count > 1 then
            step = math.min(8, (36-20)/(count-1))
        end
        for i = count, 2, -1 do
            local tok = dmhub.GetCharacterById(m_charids[i])
            if tok ~= nil and tok.valid then
                children[#children+1] = gui.CreateTokenImage(tok, {
                    width = 20,
                    height = 20,
                    floating = true,
                    halign = "left",
                    valign = "center",
                    x = (i-1)*step,
                })
            end
        end
        local lead = dmhub.GetCharacterById(m_charids[1])
        if lead ~= nil and lead.valid then
            children[#children+1] = gui.CreateTokenImage(lead, {
                width = 20,
                height = 20,
                floating = true,
                halign = "left",
                valign = "center",
                x = 0,
            })
        end
        stackPanel.children = children
    end

    local nameLabel = gui.Label{
        classes = {"wranglerRowName"},
        width = 116,
        height = "auto",
        valign = "center",
        lmargin = 4,
        textWrap = false,
        minFontSize = 8,
        text = "",
    }

    --Take this entry's turn: the same flow the initiative bar runs when a
    --card is dragged into the center slot.
    local function ClaimTurn()
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            return
        end
        if q.entries[m_initid] == nil then
            return
        end
        q:SelectTurn(m_initid)
        dmhub:UploadInitiativeQueue()

        local tokens = InitiativeQueue.GetTokensForInitiativeId(m_initid, dmhub.allTokens)
        local tokenIds = {}
        for _,tok in ipairs(tokens or {}) do
            if tok.properties ~= nil then
                tok.properties:BeginTurn()
                tokenIds[#tokenIds+1] = tok.charid
            end
        end
        if #tokenIds > 0 then
            pcall(function()
                chat.SendCustom(StartOfTurnChatMessage.new{
                    tokenids = tokenIds,
                })
            end)
        end
    end

    --The initiative swords, pulsing like they do over the map token while
    --this entry is eligible to be picked. Kept in layout at opacity 0 when
    --ineligible so the row's columns never shift.
    local swordsPanel
    swordsPanel = gui.Panel{
        classes = {"wranglerSwords"},
        width = 18,
        height = 18,
        halign = "left",
        valign = "center",
        rmargin = 2,
        bgimage = "panels/initiative/initiative-icon2.png",
        bgcolor = "white",
        interactable = false,
        hoverCursor = "pressbutton",
        swallowPress = true,
        selfStyle = {
            opacity = 0,
        },
        linger = function(element)
            gui.Tooltip("Take this monster's turn")(element)
        end,
        press = function(element)
            ClaimTurn()
        end,
        --the same sine pulse the map token's initiative swords use.
        think = function(element)
            local r = math.sin(dmhub.Time()*2*math.pi)
            if element:HasClass("hover") then
                r = 1
                element.selfStyle.opacity = 1
                element.selfStyle.brightness = 2
            else
                element.selfStyle.opacity = 0.8
                element.selfStyle.brightness = 1
            end
            element.selfStyle.scale = 1.1 + r*0.15
        end,
    }

    local staminaLabel = gui.Label{
        classes = {"wranglerRowStamina"},
        width = 84,
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
        minFontSize = 7,
        text = "",
    }

    local addButton = gui.Label{
        classes = {"wranglerCondAdd"},
        text = "+",
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        hoverCursor = "pressbutton",
        swallowPress = true,
        linger = function(element)
            gui.Tooltip("Add a condition or effect")(element)
        end,
        press = function(element)
            local tokens = ResolveTokens()
            if #tokens == 0 then
                return
            end
            pcall(function()
                TacPanel.AddConditionMenu{
                    tokens = tokens,
                    button = element,
                }
            end)
        end,
    }

    local conditionsPanel = gui.Panel{
        flow = "horizontal",
        width = "100%-264",
        height = "100%",
        halign = "left",
        valign = "center",
    }

    local function ConditionIcon(entry)
        return gui.Panel{
            classes = {"wranglerCondIcon"},
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 2,
            bgimage = entry.icon,
            bgcolor = entry.display.bgcolor or "white",
            hueshift = entry.display.hueshift or 0,
            hoverCursor = "pressbutton",
            swallowPress = true,
            linger = function(element)
                gui.Tooltip(string.format("%s\n<i>Click to remove.</i>", entry.tooltip))(element)
            end,
            press = function(element)
                --for a squad, remove from every member that has it.
                for _,tok in ipairs(ResolveTokens()) do
                    pcall(function()
                        tok:ModifyProperties{
                            description = "Remove Condition",
                            execute = function()
                                entry.remove(tok)
                            end,
                        }
                    end)
                end
            end,
        }
    end

    local selectPanel = gui.Panel{
        flow = "horizontal",
        width = 156,
        height = "100%",
        halign = "left",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        hoverCursor = "pressbutton",
        linger = function(element)
            gui.Tooltip("Select and center on this monster")(element)
        end,
        press = function(element)
            local tokens = ResolveTokens()
            local target = nil
            for _,tok in ipairs(tokens) do
                local dead = false
                pcall(function() dead = tok.properties:IsDead() end)
                if not dead then
                    target = tok
                    break
                end
            end
            target = target or tokens[1]
            if target == nil then
                return
            end
            dmhub.SelectToken(target.charid)
            dmhub.CenterOnToken(target.charid, {smooth = true})
        end,
        stackPanel,
        nameLabel,
    }

    --Partners: tokens sharing this row's initiative entry but shown in a
    --different type card -- a squad's captain (crowned), or deliberately
    --grouped monsters of another type. Hovering one highlights its own row;
    --pressing selects and centers it. Deduped by squad so a partnered squad
    --shows a single icon. Computed at build time: a regroup changes the
    --roster signature and rebuilds the cards.
    local partners = {}
    do
        local entryTokens = {}
        pcall(function()
            entryTokens = InitiativeQueue.GetTokensForInitiativeId(m_initid, dmhub.allTokens) or {}
        end)

        local captainid = nil
        if m_squadName ~= nil then
            local firstTok = dmhub.GetCharacterById(m_charids[1])
            if firstTok ~= nil and firstTok.valid and firstTok.properties ~= nil then
                pcall(function()
                    local squadInfo = firstTok.properties:try_get("_tmp_minionSquad")
                    if squadInfo ~= nil and squadInfo.captain ~= nil and squadInfo.captain.valid then
                        captainid = squadInfo.captain.charid
                    end
                end)
            end
        end

        local seenPartner = {}
        for _,tok in ipairs(entryTokens) do
            if not m_charidSet[tok.charid] and tok.properties ~= nil then
                local ptype = nil
                pcall(function() ptype = tok.properties:GetMonsterType() end)
                if ptype ~= groupName or tok.charid == captainid then
                    local psquad = nil
                    pcall(function()
                        if tok.properties.minion then
                            psquad = tok.properties:MinionSquad()
                        end
                    end)
                    local pkey = psquad or tok.charid
                    if not seenPartner[pkey] then
                        seenPartner[pkey] = true
                        partners[#partners+1] = {
                            charid = tok.charid,
                            name = psquad or tok.name or "Grouped monster",
                            captain = tok.charid == captainid,
                        }
                    end
                end
            end
        end

        --the captain always shows, even if it is not on the shared entry.
        if captainid ~= nil and not seenPartner[captainid] and not m_charidSet[captainid] then
            local found = false
            for _,p in ipairs(partners) do
                if p.charid == captainid then
                    found = true
                    break
                end
            end
            if not found then
                local ctok = dmhub.GetCharacterById(captainid)
                partners[#partners+1] = {
                    charid = captainid,
                    name = (ctok ~= nil and ctok.name) or "Captain",
                    captain = true,
                }
            end
        end
    end

    local partnersPanel = nil
    if #partners > 0 then
        local partnerChildren = {}
        for _,p in ipairs(partners) do
            local ptok = dmhub.GetCharacterById(p.charid)
            if ptok ~= nil and ptok.valid then
                local m_partnerid = p.charid
                local label = p.name
                if p.captain then
                    label = string.format("Captain: %s", ptok.name or p.name)
                end

                local pchildren = {
                    gui.CreateTokenImage(ptok, {
                        width = 18,
                        height = 18,
                        halign = "center",
                        valign = "center",
                    }),
                }
                if p.captain then
                    pchildren[#pchildren+1] = gui.Panel{
                        floating = true,
                        halign = "right",
                        valign = "top",
                        x = 4,
                        y = -4,
                        width = 11,
                        height = 11,
                        bgimage = "panels/hud/crown.png",
                        bgcolor = "white",
                        interactable = false,
                    }
                end

                partnerChildren[#partnerChildren+1] = gui.Panel{
                    flow = "none",
                    width = 20,
                    height = 20,
                    valign = "center",
                    lmargin = 2,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    hoverCursor = "pressbutton",
                    swallowPress = true,
                    linger = function(element)
                        gui.Tooltip(label)(element)
                    end,
                    hover = function(element)
                        local root = element:FindParentWithClass("encounterWranglerRoot")
                        if root ~= nil then
                            root:FireEventTree("highlightUnit", m_partnerid, true)
                        end
                    end,
                    dehover = function(element)
                        local root = element:FindParentWithClass("encounterWranglerRoot")
                        if root ~= nil then
                            root:FireEventTree("highlightUnit", m_partnerid, false)
                        end
                    end,
                    press = function(element)
                        dmhub.SelectToken(m_partnerid)
                        dmhub.CenterOnToken(m_partnerid, {smooth = true})
                    end,
                    children = pchildren,
                }
            end
        end
        if #partnerChildren > 0 then
            partnersPanel = gui.Panel{
                floating = true,
                halign = "right",
                valign = "center",
                x = -2,
                flow = "horizontal",
                width = "auto",
                height = "100%",
                children = partnerChildren,
            }
        end
    end

    local row
    row = gui.Panel{
        classes = {"wranglerRow"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 26,
        flow = "horizontal",

        refresh = function(element)
            element:FireEvent("refreshRow")
        end,

        --a partner icon on another row is hovered: light up if it is us.
        highlightUnit = function(element, charid, on)
            if m_charidSet[charid] then
                element:SetClass("partnerHighlight", on == true)
            end
        end,

        refreshRow = function(element)
            local tokens = ResolveTokens()
            if #tokens == 0 then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)

            --a live representative: for squads, any live member reads the
            --shared squad stamina pool.
            local rep = nil
            local liveCount = 0
            for _,tok in ipairs(tokens) do
                local dead = true
                pcall(function() dead = tok.properties:IsDead() end)
                if not dead then
                    liveCount = liveCount + 1
                    if rep == nil then
                        rep = tok
                    end
                end
            end
            rep = rep or tokens[1]

            local dead = liveCount == 0

            --initiative state: grey once the entry has moved (desaturated
            --token stack, greyed name), highlight the current turn, and
            --pulse the claim-swords while eligible (the map token's own
            --swords gate on the same initiativeStatus). Computed before the
            --name so squad name coloring below can respect the greyed state.
            local hadTurn = false
            local current = false
            local eligible = false
            local q = dmhub.initiativeQueue
            if q ~= nil and not q.hidden then
                local entry = q.entries[m_initid]
                if entry ~= nil then
                    hadTurn = not q:EntryUnmoved(entry)
                    current = q.currentTurn == m_initid
                end
                eligible = (not dead) and rep.initiativeStatus == "ActiveAndReady"
            end
            local greyed = hadTurn and not current
            element:SetClass("currentTurn", current)
            element:SetClass("hadTurn", greyed)
            stackPanel:SetClassTree("hadTurn", greyed)
            nameLabel:SetClass("hadTurn", greyed)
            swordsPanel.interactable = eligible
            swordsPanel.thinkTime = cond(eligible, 0.02)
            if not eligible then
                swordsPanel.selfStyle.opacity = 0
                swordsPanel.selfStyle.scale = 1
            end

            local name
            if m_squadName ~= nil then
                name = string.format("%s (%d)", m_squadName, liveCount)
                --squads display in their squad color.
                local squadColor = nil
                pcall(function() squadColor = DrawSteelMinion.GetSquadColor(m_squadName) end)
                --selfStyle wins over class rules, so a greyed squad row
                --gets the greyed color applied inline as well.
                if squadColor ~= nil then
                    nameLabel.selfStyle.color = cond(greyed, "#888888", squadColor)
                end
            else
                name = rep.name
                if name == nil or name == "" then
                    name = groupName
                end
                if #tokens > 1 then
                    name = string.format("%s +%d", name, #tokens - 1)
                end
            end
            nameLabel.text = name

            local winded, dying = false, false
            if dead then
                staminaLabel.text = "DEAD"
            elseif m_squadName == nil and #tokens > 1 then
                --several same-type monsters grouped onto one initiative:
                --one compact readout per living member.
                local parts = {}
                for _,tok in ipairs(tokens) do
                    local tdead = true
                    pcall(function() tdead = tok.properties:IsDead() end)
                    if not tdead then
                        local tcur, tmax = 0, 0
                        pcall(function()
                            tcur = tok.properties:CurrentHitpoints()
                            tmax = tok.properties:MaxHitpoints()
                            winded = winded or tcur <= tok.properties:BloodiedThreshold()
                            dying = dying or tok.properties:IsDying()
                        end)
                        parts[#parts+1] = string.format("%d/%d", tcur, tmax)
                    end
                end
                staminaLabel.text = table.concat(parts, " ")
            else
                local cur, max, temp = 0, 0, 0
                pcall(function()
                    local props = rep.properties
                    cur = props:CurrentHitpoints()
                    max = props:MaxHitpoints()
                    temp = props:TemporaryHitpoints() or 0
                    winded = cur <= props:BloodiedThreshold()
                    dying = props:IsDying()
                end)
                local text = string.format("%d/%d", cur, max)
                if temp > 0 then
                    text = string.format("%s +%d", text, temp)
                end
                staminaLabel.text = text
            end
            staminaLabel:SetClass("dead", dead)
            staminaLabel:SetClass("dying", (not dead) and dying)
            staminaLabel:SetClass("winded", (not dead) and (not dying) and winded)

            local children = {}
            for _,entry in ipairs(CollectConditionEntries(tokens)) do
                children[#children+1] = ConditionIcon(entry)
            end
            children[#children+1] = addButton
            conditionsPanel.children = children
        end,

        selectPanel,
        swordsPanel,
        staminaLabel,
        conditionsPanel,
    }

    if partnersPanel ~= nil then
        row:AddChild(partnersPanel)
    end

    row:FireEvent("refreshRow")
    return row
end

--Of a card's tokens, the one whose turn it currently is (preferring the
--selected one when several share the turn), or nil when none has the turn.
--This is the caster the statblock's ability overlays act for.
local function FindCurrentTurnCaster(charids)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return nil
    end

    local candidates = {}
    for _,charid in ipairs(charids) do
        local tok = dmhub.GetCharacterById(charid)
        if tok ~= nil and tok.valid and tok.properties ~= nil and tok.initiativeStatus == "OurTurn" then
            local dead = false
            pcall(function() dead = tok.properties:IsDead() end)
            if not dead then
                candidates[#candidates+1] = tok
            end
        end
    end
    if #candidates == 0 then
        return nil
    end

    for _,sel in ipairs(dmhub.selectedTokens or {}) do
        for _,c in ipairs(candidates) do
            if c.charid == sel.charid then
                return c
            end
        end
    end
    return candidates[1]
end

--The name of the ability the action bar is currently casting/targeting,
--or nil. IsCastingSpell returns the action bar's current ability object.
local function GetCastingAbilityName()
    local name = nil
    pcall(function()
        local casting = gamehud.actionBarPanel.data.IsCastingSpell()
        if casting ~= nil and casting ~= false then
            name = casting.name
        end
    end)
    return name
end

--Find a token's own copy of an ability by name, bound to it as caster.
--includeGlobal also searches the group-supplied abilities (malice
--features, free strikes), which GetActivatedAbilities only returns when
--the excludeGlobal option is off.
local function FindAbilityOnToken(tok, abilityName, includeGlobal)
    local found = nil
    pcall(function()
        local abilities = tok.properties:GetActivatedAbilities{excludeGlobal = not includeGlobal, allLoadouts = true, bindCaster = true}
        for _,a in ipairs(abilities) do
            if a.name == abilityName then
                found = a
                break
            end
        end
    end)
    return found
end

--A transparent hit panel floated over one rendered ability in the
--statblock. While a monster of this card's type has the turn, the overlay
--is interactable: pressing starts using the ability through the action
--bar's own invoke flow (targeting UI and all), cast by the current-turn
--monster. Visual feedback goes through the ability's color-keyed title
--band (the abilityHeadBand holding nameLabel, the 'spellName' label
--inside the render): while the ability is usable the band swells bright
--with a pulsing white border, and any ability the current-turn monster
--can NOT use dims and desaturates (the action bar's unaffordable
--treatment) so the ready ones pop by contrast. Hovering steadies the
--band fully bright; the name itself holds solid white throughout.
--State arrives via updateAbilityUsable from the card's refresh handler.
--includeGlobal is passed through to the by-name ability lookup on press:
--the Malice card's overlays need it because malice features are
--group-supplied "global" abilities.
local function CreateAbilityOverlay(abilityName, nameLabel, includeGlobal)
    local m_casterid = nil
    local m_usable = false
    local m_active = false

    --the name label sits directly inside the abilityHeadBand.
    local m_headBand = nil
    if nameLabel ~= nil and nameLabel.valid then
        m_headBand = nameLabel.parent
    end

    --One writer for every band state, inline on the band's selfStyle (the
    --statblock carries its own style root, so cascaded wrangler rules
    --cannot reach it). borderColor == nil clears the border entirely.
    --brightness/saturation reach the band's children too; the name label
    --is pure white, so >= 1 brightness leaves it solid white while the
    --dimmed (< 1) state deliberately grays name and band together.
    local function SetBandVisual(brightness, saturation, borderColor)
        if m_headBand == nil or not m_headBand.valid then
            return
        end
        m_headBand.selfStyle.brightness = brightness
        m_headBand.selfStyle.saturation = saturation
        if borderColor ~= nil then
            m_headBand.selfStyle.border = 2
            m_headBand.selfStyle.borderColor = borderColor
        else
            m_headBand.selfStyle.border = 0
        end
    end

    --Geometry gotchas learned the hard way: a floating child sized
    --height="100%" inside the ability card (height "auto") is circular and
    --blew the card up to fill its parent, so the hit strip has a FIXED
    --height covering just the title/header area. And bgcolor must be an
    --INLINE "clear": the statblock's own style root kept an ancestor rule
    --from reaching this panel, which then painted opaque.
    return gui.Panel{
        classes = {"wranglerAbilityOverlay"},
        floating = true,
        width = "100%",
        height = 70,
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        interactable = false,
        swallowPress = true,
        hoverCursor = "pressbutton",

        updateAbilityUsable = function(element, casterid, usableByName, castingName)
            m_casterid = casterid

            --while ANY ability is being cast, the one in flight underlines
            --and everything else goes ineligible: no pulse, no clicks.
            m_active = castingName ~= nil and castingName == abilityName
            local castingInProgress = castingName ~= nil

            m_usable = casterid ~= nil and (not castingInProgress) and usableByName[abilityName] == true
            element.interactable = casterid ~= nil and not castingInProgress

            if nameLabel ~= nil and nameLabel.valid then
                nameLabel.selfStyle.underline = m_active
                --the name holds solid white; the band carries the highlight.
                nameLabel.selfStyle.brightness = 1
            end

            if m_usable then
                element.thinkTime = 0.05
            else
                element.thinkTime = nil
                if m_active then
                    SetBandVisual(1.3, 1, "#FFFFFF")
                elseif element.interactable and element:HasClass("hover") then
                    SetBandVisual(1.4, 1, nil)
                elseif casterid ~= nil then
                    --this type has the turn but this ability is not
                    --currently usable: dim and desaturate (the action
                    --bar's unaffordable treatment) so ready ones pop.
                    SetBandVisual(0.6, 0.5, nil)
                else
                    SetBandVisual(1, 1, nil)
                end
            end
        end,

        --while usable, a bright swell plus a pulsing white border on the
        --band. Brightness only ever goes >= 1, so the white name stays
        --solid white even though brightness reaches the band's children.
        think = function(element)
            if element:HasClass("hover") then
                SetBandVisual(1.5, 1, "#FFFFFF")
                return
            end
            --0..1 sine ramp shared by the brightness swell and the
            --border's alpha so the whole treatment breathes together.
            local t = (math.sin(dmhub.Time() * 2 * math.pi / 1.8) + 1) / 2
            local alpha = 0x55 + math.floor(t * (0xFF - 0x55))
            SetBandVisual(1.1 + t * 0.4, 1, string.format("#FFFFFF%02X", alpha))
        end,

        hover = function(element)
            if m_usable then
                SetBandVisual(1.5, 1, "#FFFFFF")
            else
                SetBandVisual(1.4, 1, nil)
            end
        end,

        dehover = function(element)
            if m_active then
                SetBandVisual(1.3, 1, "#FFFFFF")
            elseif m_usable then
                --the think pulse takes back over on its next tick.
                SetBandVisual(1.15, 1, "#FFFFFFAA")
            elseif m_casterid ~= nil then
                SetBandVisual(0.6, 0.5, nil)
            else
                SetBandVisual(1, 1, nil)
            end
        end,

        press = function(element)
            if m_casterid == nil then
                return
            end
            local caster = dmhub.GetCharacterById(m_casterid)
            if caster == nil or not caster.valid or caster.properties == nil then
                return
            end
            local ability = FindAbilityOnToken(caster, abilityName, includeGlobal)
            if ability == nil then
                return
            end
            dmhub.SelectToken(caster.charid)
            pcall(function()
                gamehud.actionBarPanel:FireEventTree("invokeAbility", caster, ability, {}, nil, {})
            end)
        end,
    }
end

--Compact one rendered ability card's title band for the wrangler's
--density: less padding and a smaller name/cost than the full-size
--render. The render carries its own style root, so a cascaded wrangler
--rule cannot reach inside it; the band and name label are restyled
--directly, the same way the goldTab cleanup works.
local function CompactAbilityHeadBand(rendered)
    pcall(function()
        local band = rendered:FindChildRecursive(function(p)
            return p:HasClass("abilityHeadBand")
        end)
        if band ~= nil then
            --Repeat the percentage width in this inline style alongside the
            --smaller padding. borderBox resolves width against the padding in
            --the same style layer; changing only hpad leaves the band's outer
            --width 12px short (the difference from the render's 14px padding).
            band.selfStyle.width = "100%"
            band.selfStyle.hpad = 8
            band.selfStyle.vpad = 4
        end
        local nameLabel = rendered:FindChildRecursive(function(p)
            return p:HasClass("abilityName")
        end)
        if nameLabel ~= nil then
            nameLabel.selfStyle.fontSize = 18
            --the cost rides inside the text as a rich-text size tag keyed
            --to the full-size render; scale it down to match.
            nameLabel.text = string.gsub(nameLabel.text, "<size=18>", "<size=14>")
        end
    end)
end

--Every malice ability available in the encounter, aggregated across the
--monster type groups and deduped by name, arranged into display sections.
--An ability every monster type shares (the default malice features, or a
--single-band encounter) goes under "Common"; band-specific abilities go
--under their band's name ("Goblin", "Orc") -- an ability several bands
--share via inheritance lists every band's name. Sections order Common
--first, then alphabetically; abilities within a section order by malice
--cost, then name. Each ability entry carries the charids of every monster
--that can use it, for the current-turn caster lookup.
local function CollectMaliceSections(groups)
    local byName = {}
    local entries = {}
    local groupsWithMalice = 0

    for _,group in ipairs(groups) do
        local ref = group.tokens[1]
        if ref ~= nil and ref.properties ~= nil then
            local abilities = nil
            pcall(function()
                abilities = ref.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
            end)

            local bandName = nil
            pcall(function()
                local band = ref.properties:MonsterGroup()
                if band ~= nil then
                    bandName = band.name
                end
            end)
            bandName = bandName or group.name

            local sawMalice = false
            for _,a in ipairs(abilities or {}) do
                if a.categorization == "Malice" then
                    sawMalice = true
                    local entry = byName[a.name]
                    if entry == nil then
                        entry = {
                            name = a.name,
                            ability = a,
                            token = ref,
                            groupCount = 0,
                            bandNames = {},
                            seenGroups = {},
                            charids = {},
                        }
                        byName[a.name] = entry
                        entries[#entries+1] = entry
                    end
                    if not entry.seenGroups[group.key] then
                        entry.seenGroups[group.key] = true
                        entry.groupCount = entry.groupCount + 1
                        entry.bandNames[bandName] = true
                        for _,tok in ipairs(group.tokens) do
                            entry.charids[#entry.charids+1] = tok.charid
                        end
                    end
                end
            end
            if sawMalice then
                groupsWithMalice = groupsWithMalice + 1
            end
        end
    end

    --the ability's malice cost, for cheap-to-expensive ordering: the same
    --cost breakdown the action bar's malice drawer reads.
    local function MaliceCost(entry)
        if entry.cost == nil then
            local costValue = 0
            pcall(function()
                local cost = entry.ability:GetCost(entry.token, {mode = 1, charges = entry.ability:DefaultCharges()})
                for _,detail in ipairs((cost ~= nil and cost.details) or {}) do
                    if detail.cost == CharacterResource.maliceResourceId then
                        costValue = detail.quantity or 0
                        break
                    end
                end
            end)
            entry.cost = costValue
        end
        return entry.cost
    end

    local sections = {}
    local sectionsByTitle = {}
    for _,entry in ipairs(entries) do
        local title
        if entry.groupCount >= groupsWithMalice then
            title = "Common"
        else
            local names = {}
            for name,_ in pairs(entry.bandNames) do
                names[#names+1] = name
            end
            table.sort(names)
            title = table.concat(names, ", ")
        end

        local section = sectionsByTitle[title]
        if section == nil then
            section = { title = title, abilities = {} }
            sectionsByTitle[title] = section
            sections[#sections+1] = section
        end
        section.abilities[#section.abilities+1] = entry
    end

    table.sort(sections, function(a, b)
        if (a.title == "Common") ~= (b.title == "Common") then
            return a.title == "Common"
        end
        return a.title < b.title
    end)
    for _,section in ipairs(sections) do
        table.sort(section.abilities, function(a, b)
            local ca = MaliceCost(a)
            local cb = MaliceCost(b)
            if ca ~= cb then
                return ca < cb
            end
            return a.name < b.name
        end)
    end

    return sections
end

--All the malice abilities this caster can use right now, keyed by name:
--affordable from the shared malice pool (CanAfford resolves the monster's
--malice resource against the global pool) and passing the ability's own
--filters. Cached per caster for the duration of one refresh pass, since
--Common abilities share the same caster across many overlays.
local function UsableMaliceByName(caster, cache)
    local cached = cache[caster.charid]
    if cached ~= nil then
        return cached
    end
    local usable = {}
    pcall(function()
        local abilities = caster.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
        for _,a in ipairs(abilities) do
            if a.categorization == "Malice" then
                local ok = false
                pcall(function()
                    ok = a:CanAfford(caster)
                        and a:AbilityFilterFailureMessage(caster.properties) == nil
                        and a:try_get("suppressExplanation") == nil
                end)
                if ok then
                    usable[a.name] = true
                end
            end
        end
    end)
    cache[caster.charid] = usable
    return usable
end

--The Malice card, shown before the first monster card: the encounter's
--aggregated malice abilities under their section headers, with the shared
--malice pool in the card header. Each rendered ability carries the same
--interactive overlay the statblocks use -- while a monster whose band
--grants the ability has the turn, an affordable ability's name pulses and
--clicking casts it through the action bar's invoke flow for that monster.
--Returns nil when the encounter has no malice abilities to show.
local function CreateMaliceCard(groups)
    local sections = CollectMaliceSections(groups)
    if #sections == 0 then
        return nil
    end

    --one record per rendered ability, for the refresh pass to drive its
    --overlay: which current-turn monster (if any) can cast it, and whether
    --it is affordable.
    local wired = {}

    local sectionPanels = {}
    for _,section in ipairs(sections) do
        sectionPanels[#sectionPanels+1] = gui.Label{
            classes = {"wranglerMaliceSection"},
            text = section.title,
            width = "100%",
            height = "auto",
            tmargin = 8,
            bmargin = 2,
        }
        for _,entry in ipairs(section.abilities) do
            local rendered = nil
            pcall(function()
                rendered = entry.ability:Render({
                    pad = 12,
                    width = "100%",
                }, {
                    token = entry.token,
                })
            end)
            if rendered ~= nil then
                --same cleanup the statblocks get: the decorative bookmark
                --tabs are collapsed directly (the render carries its own
                --style root, so a cascaded rule cannot reach them).
                pcall(function()
                    for _,tab in ipairs(rendered:GetChildrenWithClassRecursive("goldTab") or {}) do
                        tab:SetClass("collapsed", true)
                    end
                end)

                CompactAbilityHeadBand(rendered)

                local nameLabel = rendered:FindChildRecursive(function(p)
                    return p:HasClass("abilityName")
                end)
                local overlay = CreateAbilityOverlay(entry.name, nameLabel, true)
                rendered:AddChild(overlay)
                wired[#wired+1] = {
                    name = entry.name,
                    charids = entry.charids,
                    overlay = overlay,
                }
                sectionPanels[#sectionPanels+1] = rendered
            end
        end
    end

    --The malice pool readout: the Draw Steel "cost diamond" from the action
    --bar -- a square rotated 45 degrees (white base + maliceDiamondGradient
    --shading) with a red inner diamond. The value label is counter-rotated
    --so it stays upright; the outer wrapper reserves room for the rotated
    --bounding box.
    local maliceValueLabel = gui.Label{
        width = "auto",
        height = "auto",
        minWidth = 24,
        fontSize = 14,
        bold = true,
        color = "white",
        textAlignment = "center",
        halign = "center",
        valign = "center",
        rotate = -135,
        text = "",

        --editable, exactly like the action bar's malice drawer counter.
        editable = true,
        numeric = true,
        characterLimit = 2,
        swallowPress = true,
        change = function(element)
            local value = tonumber(element.text) or 0
            if value < 0 then
                value = 0
            end
            CharacterResource.SetMalice(value, "Manually set")
            element.text = string.format("%d", value)
        end,
        hover = function(element)
            local history = CharacterResource.GetGlobalResourceHistory(CharacterResource.maliceResourceId)
            element.tooltip = gui.StatsHistoryTooltip{ description = "Malice", entries = history }
        end,
    }

    local maliceDiamond = gui.Panel{
        width = 40,
        height = 40,
        halign = "right",
        valign = "center",
        gui.Panel{
            width = 27,
            height = 27,
            halign = "center",
            valign = "center",
            rotate = 135,
            bgimage = true,
            bgcolor = "white",
            gradient = Styles.Ability.maliceDiamondGradient,
            border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
            borderColor = "grey",
            gui.Panel{
                width = "65%",
                height = "65%",
                halign = "center",
                valign = "center",
                bgimage = true,
                bgcolor = "#DE1E47",
                borderWidth = 2,
                borderColor = "#FF5076",
                maliceValueLabel,
            },
        },
    }

    local card
    card = gui.Panel{
        classes = {"wranglerCard"},
        bgimage = "panels/square.png",
        width = CARD_WIDTH,
        height = "auto",
        halign = "left",
        valign = "top",
        hmargin = 6,
        vmargin = 6,
        flow = "vertical",
        pad = 8,
        borderBox = true,

        data = {
            lastCastingName = nil,
        },

        --malice lives in a shared global-resource document, so it can
        --change from another client or a journal counter without a hud
        --refresh firing here: monitor the document so the pool readout
        --and affordability pulses stay live.
        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = function(element)
            element:FireEvent("refresh")
        end,

        refresh = function(element)
            pcall(function()
                maliceValueLabel.text = string.format("%d", CharacterResource.GetMalice())
            end)

            local castingName = GetCastingAbilityName()
            element.data.lastCastingName = castingName

            local anyCaster = false
            local usableCache = {}
            for _,w in ipairs(wired) do
                local caster = FindCurrentTurnCaster(w.charids)
                local casterid = nil
                local usableByName = {}
                if caster ~= nil then
                    casterid = caster.charid
                    anyCaster = true
                    usableByName = UsableMaliceByName(caster, usableCache)
                end
                w.overlay:FireEvent("updateAbilityUsable", casterid, usableByName, castingName)
            end

            --the cast state is action-bar UI state, not game state: poll
            --it lightly while any monster that can use malice has the turn.
            element.thinkTime = cond(anyCaster, 0.25)
        end,

        think = function(element)
            if GetCastingAbilityName() ~= element.data.lastCastingName then
                element:FireEvent("refresh")
            end
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 4,
            gui.Label{
                classes = {"wranglerCardTitle"},
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "Malice",
            },
            maliceDiamond,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = sectionPanels,
        },
    }

    card:FireEvent("refresh")
    return card
end

--Float an interactive overlay onto each rendered ability in a statblock.
--monster:Render builds one ability card (root id 'spellInfo') per entry of
--GetActivatedAbilities, in order, so the panels are paired with abilities
--by document order; on any mismatch the statblock is left inert.
local function WireStatblockAbilities(statblock, reference)
    local abilityPanels = {}
    local function scan(p)
        if p == nil or not p.valid then
            return
        end
        if p.id == "spellInfo" then
            abilityPanels[#abilityPanels+1] = p
            return
        end
        for _,c in ipairs(p.children or {}) do
            scan(c)
        end
    end
    scan(statblock)

    local abilityNames = nil
    pcall(function()
        local abilities = reference.properties:GetActivatedAbilities{excludeGlobal = true, allLoadouts = true, bindCaster = true}
        if #abilities == #abilityPanels then
            abilityNames = {}
            for i,a in ipairs(abilities) do
                abilityNames[i] = a.name
            end
        end
    end)
    if abilityNames == nil then
        return
    end

    for i,panel in ipairs(abilityPanels) do
        CompactAbilityHeadBand(panel)

        --the ability's title band carries the highlight visuals.
        local nameLabel = panel:FindChildRecursive(function(p)
            return p:HasClass("abilityName")
        end)
        panel:AddChild(CreateAbilityOverlay(abilityNames[i], nameLabel))
    end
end

--One card per monster type: the instance rows on top, then the type's
--statblock rendered once at full height (the dialog's outer scrollbar
--handles overflow). The statblock is bound to the first instance -- the
--same creature the encounter is actually running -- and its abilities are
--overlaid with hover/click handlers so the Director can use them directly
--for whichever monster of this type has the turn.
local function CreateGroupCard(group)
    local rows = {}
    for _,unit in ipairs(PartitionUnits(group.tokens)) do
        rows[#rows+1] = CreateInstanceRow(unit, group.name)
    end

    --TacPanel.AllStyles: the + button's AddConditionMenu popup inherits
    --this cascade (popupsInheritStyles) for its menu-option styling.
    --No inner scrolling: the dialog's single outer scrollbar handles
    --overflow for the whole card grid.
    local rowsPanel = gui.Panel{
        styles = TacPanel.AllStyles(),
        flow = "vertical",
        width = "100%",
        height = "auto",
        bmargin = 4,
        children = rows,
    }

    local statblock = nil
    local reference = group.tokens[1]
    if reference ~= nil and reference.properties ~= nil then
        --Rendered at full height with no scrollbar of its own: the dialog's
        --single outer scrollbar handles overflow for the whole card grid.
        pcall(function()
            statblock = reference.properties:Render({
                width = STATBLOCK_WIDTH,
            }, { token = reference })
        end)
    end

    --drop the decorative bookmark/walkthrough tabs from the rendered
    --abilities, and the statblock's own name/role row -- the card's header
    --line above the instance list replaces it. Done directly on the panels:
    --the statblock carries its own style root, so a cascaded rule from our
    --content root cannot reach them.
    if statblock ~= nil then
        pcall(function()
            for _,tab in ipairs(statblock:GetChildrenWithClassRecursive("goldTab") or {}) do
                tab:SetClass("collapsed", true)
            end
            for _,row in ipairs(statblock:GetChildrenWithClassRecursive("statblockNameRow") or {}) do
                row:SetClass("collapsed", true)
            end
        end)
    end

    local statblockHost
    if statblock == nil then
        statblockHost = gui.Label{
            classes = {"wranglerNote"},
            text = "No statblock is available for this creature.",
            width = "100%",
            height = "auto",
            vmargin = 8,
        }
    else
        WireStatblockAbilities(statblock, reference)

        local m_hostCharids = {}
        for _,tok in ipairs(group.tokens) do
            m_hostCharids[#m_hostCharids+1] = tok.charid
        end

        --the host recomputes, on each hud refresh, which token of this
        --type has the turn and which abilities it can afford, and pushes
        --that into every ability overlay below.
        statblockHost = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            data = {
                lastCastingName = nil,
            },

            refresh = function(element)
                local caster = FindCurrentTurnCaster(m_hostCharids)
                local casterid = nil
                local usableByName = {}
                if caster ~= nil then
                    casterid = caster.charid
                    pcall(function()
                        local abilities = caster.properties:GetActivatedAbilities{excludeGlobal = true, allLoadouts = true, bindCaster = true}
                        for _,a in ipairs(abilities) do
                            local usable = false
                            pcall(function()
                                usable = a:CanAfford(caster)
                                    and a:AbilityFilterFailureMessage(caster.properties) == nil
                                    and a:try_get("suppressExplanation") == nil
                            end)
                            if usable then
                                usableByName[a.name] = true
                            end
                        end
                    end)
                end

                local castingName = GetCastingAbilityName()
                element.data.lastCastingName = castingName

                --the cast state is action-bar UI state, not game state, so
                --no refresh broadcast fires when targeting begins or is
                --cancelled: poll it lightly while this type has the turn.
                element.thinkTime = cond(casterid ~= nil, 0.25)

                element:FireEventTree("updateAbilityUsable", casterid, usableByName, castingName)
            end,

            think = function(element)
                if GetCastingAbilityName() ~= element.data.lastCastingName then
                    element:FireEvent("refresh")
                end
            end,

            statblock,
        }
        statblockHost:FireEvent("refresh")
    end

    --The card header stands in for the statblock's collapsed name row: the
    --monster type (with a xN count) on the left, the statblock's level/role
    --line on the right.
    local roleText = ""
    if reference ~= nil and reference.properties ~= nil then
        pcall(function()
            roleText = reference.properties:RoleDescription()
        end)
    end

    --header children are built as a list so the xN count can be omitted
    --without leaving a nil hole in the positional child args.
    local headerChildren = {
        gui.Label{
            classes = {"wranglerCardTitle"},
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = group.name,
        },
    }
    if #group.tokens > 1 then
        headerChildren[#headerChildren+1] = gui.Label{
            classes = {"wranglerCardCount"},
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 6,
            text = string.format("x%d", #group.tokens),
        }
    end
    headerChildren[#headerChildren+1] = gui.Label{
        classes = {"wranglerCardRole"},
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        text = roleText,
    }

    return gui.Panel{
        classes = {"wranglerCard"},
        bgimage = "panels/square.png",
        width = CARD_WIDTH,
        height = "auto",
        halign = "left",
        valign = "top",
        hmargin = 6,
        vmargin = 6,
        flow = "vertical",
        pad = 8,
        borderBox = true,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 4,
            children = headerChildren,
        },
        rowsPanel,
        statblockHost,
    }
end

function EncounterWrangler.CreateContent()
    local m_signature = nil

    --Masonry packing state. m_cards is every card in build order, m_heights
    --their measured heights (a parallel array, nil until they have been laid
    --out once), m_fitColumns the column count the current pack was made for.
    local m_cards = {}
    local m_heights = nil
    local m_columns = {}
    local m_fitColumns = 0
    local m_measureTries = 0

    local cardsPanel

    local function NewColumn()
        return gui.Panel{
            classes = {"collapsed"},
            width = COLUMN_WIDTH,
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
        }
    end

    --how many fixed-width columns fit across the given width.
    local function ColumnsForWidth(width)
        local n = math.floor(((width or 0) - SCROLLBAR_GUTTER) / COLUMN_WIDTH)
        return math.max(1, math.min(n, MAX_COLUMNS))
    end

    --Moves every card into the column it has been assigned. Detach
    --everything first: a card moving from one column to another would
    --otherwise be marked as orphaned by its old column AFTER the new one had
    --already claimed it, and orphans are destroyed at the end of the frame.
    --Both passes run inside this one call, so the re-attach rescues it.
    local function AssignColumns(assignments, ncolumns)
        if #m_columns < ncolumns then
            while #m_columns < ncolumns do
                m_columns[#m_columns+1] = NewColumn()
            end
            cardsPanel.children = m_columns
        end

        for _,column in ipairs(m_columns) do
            column.children = {}
        end

        for i,column in ipairs(m_columns) do
            column.children = assignments[i] or {}
            column:SetClass("collapsed", i > ncolumns)
        end
    end

    --Greedy masonry: each card drops into whichever column is shortest so
    --far. The engine's wrap flow is row-based -- it starts each wrapped row
    --below the TALLEST card of the row above -- so a short card leaves a
    --gap the height of its row-mates beneath it, glaring next to the Malice
    --card that dwarfs a small statblock. Cards are a fixed width, so a
    --card's height does not depend on which column it lands in: one
    --measurement pass is enough, and repacking never invalidates it.
    local function PackCards(width)
        m_fitColumns = ColumnsForWidth(width)
        local ncolumns = math.min(m_fitColumns, math.max(#m_cards, 1))

        local assignments = {}
        local totals = {}
        for i=1,ncolumns do
            assignments[i] = {}
            totals[i] = 0
        end

        for i,card in ipairs(m_cards) do
            local best = 1
            for j=2,ncolumns do
                --ties break to the leftmost column, so an unmeasured set of
                --cards falls back to a plain round robin.
                if totals[j] < totals[best] - 0.5 then
                    best = j
                end
            end

            local column = assignments[best]
            column[#column+1] = card
            totals[best] = totals[best] + ((m_heights ~= nil and m_heights[i]) or 1)
        end

        AssignColumns(assignments, ncolumns)
    end

    cardsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        --run a frame after a rebuild, once layout has given every card its
        --natural height, and then repacked for real.
        measurecards = function(element)
            local heights = {}
            for i,card in ipairs(m_cards) do
                local h = card.renderedHeight
                if h == nil or h <= 0 then
                    --layout has not caught up with the rebuild yet.
                    m_measureTries = m_measureTries + 1
                    if m_measureTries < 40 then
                        element:ScheduleEvent("measurecards", 0.05)
                    end
                    --otherwise leave the round-robin pack in place.
                    return
                end

                --the card carries a vmargin on each side.
                heights[i] = h + 12
            end

            m_heights = heights
            PackCards(element.renderedWidth)
        end,

        --the window is resizable, so repack when a different number of
        --columns fits. Packing changes the height, which fires this event
        --again -- hence the guard on the fitting column count, not on size.
        rendered = function(element, width, height)
            if #m_cards > 0 and ColumnsForWidth(width) ~= m_fitColumns then
                PackCards(width)
            end
        end,
    }

    local emptyLabel = gui.Label{
        classes = {"wranglerNote", "collapsed"},
        text = "There are no monsters in the encounter.",
        width = "100%",
        height = "auto",
        vmargin = 24,
    }

    local resultPanel
    resultPanel = gui.Panel{
        --the class partner icons use to find this root and broadcast
        --highlightUnit into every row.
        classes = {"encounterWranglerRoot"},
        width = "100%",
        height = "100%",
        flow = "vertical",
        styles = g_wranglerStyles,

        --deferred first build so the window chrome paints immediately
        --instead of blocking the click on the statblock builds. Routed
        --through 'refresh' so it no-ops if the host's own mount-time
        --refresh broadcast already built the cards.
        create = function(element)
            element:ScheduleEvent("refresh", 0.01)
        end,

        --the hud broadcasts 'refresh' whenever game state dirties; the
        --roster rarely changes, so only rebuild when membership actually
        --did. Each row keeps its own stamina/conditions current.
        refresh = function(element)
            local groups = CollectGroups()
            if GroupsSignature(groups) ~= m_signature then
                element:FireEvent("rebuild", groups)
            end
        end,

        rebuild = function(element, groups)
            groups = groups or CollectGroups()
            m_signature = GroupsSignature(groups)

            local cards = {}
            --the Malice card leads, before the first monster card.
            local maliceCard = CreateMaliceCard(groups)
            if maliceCard ~= nil then
                cards[#cards+1] = maliceCard
            end
            for _,group in ipairs(groups) do
                cards[#cards+1] = CreateGroupCard(group)
            end

            --the measured heights belong to the cards we just threw away;
            --pack round robin for the one frame it takes to measure these.
            m_cards = cards
            m_heights = nil
            m_measureTries = 0
            PackCards(cardsPanel.renderedWidth)
            cardsPanel:ScheduleEvent("measurecards", 0.01)

            emptyLabel:SetClass("collapsed", #groups > 0)
        end,

        gui.Panel{
            width = "100%",
            height = "100%",
            vscroll = true,
            flow = "vertical",
            emptyLabel,
            cardsPanel,
        },
    }

    return resultPanel
end

--Registered so the icon-rail window machinery can host it, but filtered
--out of the panel menus and the rail: the notebook button on the
--initiative bar is its only entry point.
DockablePanel.Register{
    name = EncounterWrangler.panelName,
    icon = "phosphor/notebook.png",
    dmonly = true,
    filtered = function() return true end,
    minWidth = 560,
    minHeight = 320,
    vscroll = false,
    content = function()
        return EncounterWrangler.CreateContent()
    end,
}

--Open the wrangler window (or raise it if it is already open somewhere).
function EncounterWrangler.Open()
    if not dmhub.isDM or not EncounterWrangler.Enabled() then
        return
    end

    local key = string.lower(EncounterWrangler.panelName)

    --already popped out into its own OS window: raise that instead of
    --opening a second copy in-app.
    if PanelDocument.IsPoppedOut ~= nil and PanelDocument.IsPoppedOut(key) then
        local host = PanelDocument.PopoutHost(key)
        if host ~= nil and host.valid then
            pcall(function() host:RaiseNativeWindow() end)
        end
        return
    end

    local doc = PanelDocument.Get(EncounterWrangler.panelName)
    if doc == nil then
        return
    end

    doc:PresentPanel{
        --room for two statblock cards side by side; PresentDocument
        --centers the window and remembers drags/resizes for the session.
        width = 1120,
        height = 880,
        close = function()
            doc:ClosePanel()
        end,
        escapeClose = function()
            doc:ClosePanel()
        end,
        popout = function()
            local d = doc:try_get("_tmp_dialog")
            local geometry = nil
            if d ~= nil and d.valid then
                geometry = { width = d.renderedWidth, height = d.renderedHeight }
            end
            doc:ClosePanel()
            PanelDocument.OpenPopout(key, geometry)
        end,
    }
end

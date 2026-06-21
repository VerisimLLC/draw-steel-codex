local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- Stats Debugger
--
-- Developer-only window (Developer menu -> Stats Debugger) that previews the
-- per-encounter hero statistics the victory screen turns into "combat roles"
-- (see DSVictoryScreen.lua). For the live encounter of the current combat it
-- lists every participating hero with:
--   * their current count of every tracked stat,
--   * the full list of roles they currently qualify for (priority order), and
--   * which single role they would win if combat ended right now.
--
-- All role/eligibility math is delegated to
-- DSVictoryScreen.ComputeHeroRoleDebugInfo, so this window stays in lockstep
-- with what the victory screen would actually award. It updates live as stats
-- accumulate (it monitors the initiative queue), so it can be left open during
-- a fight to watch the roles shift.
----------------------------------------------------------------------

-- The tracked stats we always show, in a sensible reading order, even when a
-- hero has not recorded one yet (it then reads 0 / empty). Any extra stat that
-- turns up in the data but is not listed here is appended after these, sorted,
-- so newly added stats still appear without editing this file.
local g_knownStats = {
    "damageDealt",
    "damageTaken",
    "damagePrevention",
    "overkill",
    "kills",
    "minionKills",
    "criticals",
    "spacesMoved",
    "forcedMovementDealt",
    "forcedMovementTaken",
    "standsFirm",
    "allyDamageDealt",
    "enemyTurnDamage",
    "heroicResourcesGained",
    "heroicResourcesSpent",
    "edges",
    "banes",
    "tierRolls",
    "conditionsInflicted",
}

-- Stats stored as keyed sub-tables rather than a single number. Used to default
-- an unrecorded one to an empty table (shown as "{}") instead of 0.
local g_nestedStats = {
    tierRolls = true,
    conditionsInflicted = true,
}

local g_styles = {
    gui.Style{
        classes = {"heroCard"},
        bgimage = "panels/square.png",
        bgcolor = "#1c1c22ee",
        borderColor = "#555566",
        borderWidth = 1,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 6,
        pad = 10,
        borderBox = true,
    },
    gui.Style{
        classes = {"heroName"},
        fontSize = 20,
        bold = true,
        color = "white",
        width = "auto",
        height = "auto",
        halign = "left",
    },
    gui.Style{
        classes = {"heroWins"},
        fontSize = 18,
        bold = true,
        color = "#88dd88",
        width = "auto",
        height = "auto",
        halign = "right",
    },
    gui.Style{
        classes = {"heroWins", "noRole"},
        color = "#888888",
    },
    gui.Style{
        classes = {"sectionHeader"},
        fontSize = 14,
        bold = true,
        color = "#cccccc",
        width = "auto",
        height = "auto",
        tmargin = 8,
        bmargin = 2,
    },
    gui.Style{
        classes = {"roleLine"},
        fontSize = 14,
        color = "#b5b5c0",
        width = "100%",
        height = "auto",
    },
    gui.Style{
        classes = {"roleLine", "winner"},
        color = "#88ff88",
        bold = true,
    },
    gui.Style{
        classes = {"roleLine", "empty"},
        color = "#777777",
        italics = true,
    },
    gui.Style{
        classes = {"statChip"},
        fontSize = 13,
        color = "#dcdce6",
        width = "auto",
        height = "auto",
        minWidth = 150,
        hmargin = 6,
        vmargin = 2,
    },
    gui.Style{
        classes = {"emptyMessage"},
        fontSize = 16,
        color = "#aaaaaa",
        width = "90%",
        height = "auto",
        halign = "center",
        valign = "center",
        textWrap = true,
        textAlignment = "center",
        vmargin = 40,
    },
}

-- The live encounter of the current combat, or nil if there is none. Unlike the
-- victory screen we deliberately do NOT gate on the queue's "hidden" flag: as a
-- debugger we want to show the recorded stats whenever a live encounter exists,
-- including a paused combat or one whose bar is currently hidden.
local function GetLiveEncounter()
    local q = dmhub.initiativeQueue
    if q == nil then
        return nil
    end
    local live = q:try_get("liveEncounter")
    if type(live) ~= "table" then
        return nil
    end
    return live
end

-- Render one stat value as a short string: a bare number, or "{k=v, k=v}" for
-- the nested sub-table stats (tierRolls, conditionsInflicted).
local function FormatStatValue(v)
    if type(v) == "number" then
        return tostring(v)
    end
    if type(v) == "table" then
        local keys = {}
        for k, sub in pairs(v) do
            if type(sub) == "number" then
                keys[#keys+1] = k
            end
        end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts+1] = string.format("%s=%s", k, tostring(v[k]))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

-- Ordered list of { name, value } for a hero's totals: known stats first
-- (defaulting to 0 / {} when unrecorded), then any extra recorded stats, sorted.
local function OrderedStats(totals)
    local result = {}
    local seen = {}
    for _, name in ipairs(g_knownStats) do
        seen[name] = true
        local v = totals[name]
        if v == nil then
            v = cond(g_nestedStats[name], {}, 0)
        end
        result[#result+1] = { name = name, value = v }
    end

    local extras = {}
    for name, _ in pairs(totals) do
        if not seen[name] then
            extras[#extras+1] = name
        end
    end
    table.sort(extras)
    for _, name in ipairs(extras) do
        result[#result+1] = { name = name, value = totals[name] }
    end

    return result
end

-- Build the card for a single hero from one entry of
-- DSVictoryScreen.ComputeHeroRoleDebugInfo.
local function HeroCard(hero)
    local awardedRole = hero.awarded ~= nil and hero.awarded.role or nil

    -- Eligible roles, in priority order; the one they would actually win is
    -- highlighted and marked with a "*".
    local roleChildren = {}
    if #hero.eligible == 0 then
        roleChildren[1] = gui.Label{
            classes = {"roleLine", "empty"},
            text = "(qualifies for no roles yet)",
        }
    else
        for _, r in ipairs(hero.eligible) do
            local isWinner = (awardedRole ~= nil and r.role == awardedRole)
            local floorTag = cond(r.isFloor, " [floor]", "")
            roleChildren[#roleChildren+1] = gui.Label{
                classes = cond(isWinner, {"roleLine", "winner"}, {"roleLine"}),
                text = string.format("%s%s (rank %d)%s -- %s",
                    cond(isWinner, "* ", "   "), r.role, r.rank, floorTag, r.text),
                linger = r.tooltip ~= nil and gui.Tooltip(r.tooltip) or nil,
            }
        end
    end

    -- Every tracked stat with its current count.
    local statChildren = {}
    for _, s in ipairs(OrderedStats(hero.totals)) do
        statChildren[#statChildren+1] = gui.Label{
            classes = {"statChip"},
            text = string.format("%s: %s", s.name, FormatStatValue(s.value)),
        }
    end

    return gui.Panel{
        classes = {"heroCard"},

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Label{
                classes = {"heroName"},
                text = hero.name or "Hero",
            },
            gui.Label{
                classes = cond(awardedRole ~= nil, {"heroWins"}, {"heroWins", "noRole"}),
                text = cond(awardedRole ~= nil, "WINS: " .. tostring(awardedRole), "WINS: (no role)"),
                linger = (hero.awarded ~= nil and hero.awarded.tooltip ~= nil)
                    and gui.Tooltip(hero.awarded.tooltip) or nil,
            },
        },

        gui.Label{
            classes = {"sectionHeader"},
            text = "Eligible roles (priority order):",
        },
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            children = roleChildren,
        },

        gui.Label{
            classes = {"sectionHeader"},
            text = "Stats:",
        },
        gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = "100%",
            height = "auto",
            children = statChildren,
        },
    }
end

LaunchablePanel.Register{
    name = "Stats Debugger",
    folder = "Development Tools",

    halign = "center",
    valign = "center",
    draggable = true,

    content = function(args)
        local statusLabel
        local listPanel

        -- listEl is the scroll panel to populate. It is passed in (rather than
        -- read from the listPanel upvalue) so the initial create-time call works
        -- even if the create event fires before the upvalue is assigned.
        local function Refresh(listEl)
            if listEl == nil or not listEl.valid then
                return
            end

            local q = dmhub.initiativeQueue
            local live = GetLiveEncounter()

            if live == nil then
                if statusLabel ~= nil then
                    statusLabel.text = "No active combat."
                end
                listEl.children = {
                    gui.Label{
                        classes = {"emptyMessage"},
                        text = "No active combat with a live encounter.\nHero stats are only tracked while a live encounter is running.",
                    },
                }
                return
            end

            local info = DSVictoryScreen.ComputeHeroRoleDebugInfo(live)

            if statusLabel ~= nil then
                statusLabel.text = string.format("Round %d -- %d %s",
                    (q ~= nil and q.round) or 0, #info, cond(#info == 1, "hero", "heroes"))
            end

            if #info == 0 then
                listEl.children = {
                    gui.Label{
                        classes = {"emptyMessage"},
                        text = "No heroes are participating in this encounter.",
                    },
                }
                return
            end

            local children = {}
            for _, hero in ipairs(info) do
                children[#children+1] = HeroCard(hero)
            end
            listEl.children = children
        end

        statusLabel = gui.Label{
            fontSize = 16,
            color = "#cccccc",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            text = "",
        }

        listPanel = gui.Panel{
            width = "100%",
            height = "100%-70",
            valign = "bottom",
            flow = "vertical",
            vscroll = true,

            -- Refresh whenever the initiative queue changes (any stat increment
            -- networks back through the queue), and once on create.
            monitorGame = "/initiativeQueue",
            refreshGame = function(element)
                Refresh(element)
            end,
            create = function(element)
                Refresh(element)
            end,
        }

        return gui.Panel{
            width = 780,
            height = 820,
            flow = "vertical",
            styles = { Styles.Default, g_styles },

            -- Nice X close button in the top-right corner, styled like the
            -- launchable host's own close button (see game-hud-menu.txt). It
            -- bubbles the host panel's "close" event, whose handler destroys
            -- the window (see CreateLaunchablePanel).
            gui.Button{
                classes = {"closeButton", "sizeXs"},
                floating = true,
                halign = "right",
                valign = "top",
                click = function(element)
                    element:FireEventOnParents("close")
                end,
            },

            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 36,
                valign = "top",

                gui.Label{
                    fontSize = 24,
                    bold = true,
                    color = "white",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    text = "Stats Debugger",
                },

                statusLabel,
            },

            listPanel,
        }
    end,
}

local mod = dmhub.GetModLoading()

--- The Fishing dock panel
--- One shared panel for the whole table: roles differ only in which controls
--- are live. This is the feature's entire voice, so nothing here goes to chat.
--- @class FSHPanel
FSHPanel = RegisterGameType("FSHPanel")

--- Builds dropdown options from a list of DTConstant instances
--- @param constants table The DTConstant list
--- @return DropdownOption[] options List of { id, text } options
local function ConstantOptions(constants)
    local options = {}
    for _, constant in ipairs(constants) do
        options[#options + 1] = {
            id = constant.key,
            text = constant.displayText
        }
    end
    return options
end

--- Prompts the Director for a water's optional name and required type
local function ShowOpenWaterDialog()
    local nameInput = gui.Input{
        classes = { "input", "form" },
        text = "The Dunn River",
        placeholderText = "Optional...",
        lineType = "Single"
    }

    local typeDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = ConstantOptions(FSHConstants.WATER_TYPE),
        idChosen = FSHConstants.WATER_TYPE.FRESH.key
    }

    local dialog
    dialog = gui.Panel{
        classes = { "dialog" },
        styles = ThemeEngine.GetStyles(),
        width = 500,
        height = 260,
        flow = "vertical",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,

        escape = function()
            gui.CloseModal()
        end,

        gui.Label{
            classes = { "modalTitle" },
            text = "Open Water"
        },

        gui.Panel{
            width = "98%",
            height = "auto",
            flow = "vertical",
            valign = "top",

            gui.Panel{
                classes = { "formRow" },
                gui.Label{
                    classes = { "label", "form" },
                    text = "Name:"
                },
                nameInput
            },

            gui.Panel{
                classes = { "formRow" },
                gui.Label{
                    classes = { "label", "form" },
                    text = "Type:"
                },
                typeDropdown
            }
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "top",
            vmargin = 16,

            gui.Button{
                classes = { "sizeL" },
                text = "Cancel",
                hmargin = 8,
                click = function()
                    gui.CloseModal()
                end
            },

            gui.Button{
                classes = { "sizeL" },
                text = "Open",
                hmargin = 8,
                click = function()
                    FSHWater.Open(nameInput.text, typeDropdown.idChosen)
                    gui.CloseModal()
                end
            }
        }
    }

    gui.ShowModal(dialog)
end

--- Lists every hero this client could be running a Trip for
--- Used for harvesting and for finding a Trip already in progress, so it stays
--- wider than what may start a new one.
--- @return table heroes The controllable hero tokens
local function ControllableHeroes()
    local heroes = {}

    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        if token.playerControlled then
            heroes[#heroes + 1] = token
        end
    end

    table.sort(heroes, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    return heroes
end

--- Lists the selected heroes that could start fishing right now
--- Fishing is something a hero does somewhere, so the token has to be one this
--- client controls, picked deliberately, and actually standing on the map.
--- GetTokenById is map-only, which is exactly the test wanted here.
--- @return table heroes The selected, controllable, on-map hero tokens
local function SelectedFishableHeroes()
    local heroes = {}

    for _, token in ipairs(dmhub.selectedTokens or {}) do
        if token ~= nil
            and token.valid
            and token.properties ~= nil
            and token.properties:IsHero()
            and token.playerControlled
            and dmhub.GetTokenById(token.id) ~= nil then
            heroes[#heroes + 1] = token
        end
    end

    --Deliberately unsorted: selection order is meaningful here, and the first
    --token selected is the one the start dialog should open on.
    return heroes
end

--- Prompts for the character and the optional skill, then starts the Trip
--- The characteristic is shown but not offered: the rules allow three and
--- nobody would pick anything but their best, so the module derives it.
--- @param heroes table The controllable tokens; the hero row hides for one
--- @param args table|nil rollHolderId for a follower fishing on their hero's
---   rolls, and onStarted for what to do once the Trip is running
function FSHPanel.ShowStartFishingDialog(heroes, args)
    args = args or {}
    local m_token = heroes[1]

    local characteristicLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        text = ""
    }

    local skillDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = {},
        textDefault = "No skill"
    }

    local RefreshForHero = function()
        if m_token == nil then
            return
        end

        local attrid, value = FSHTrip.DeriveCharacteristic(m_token.properties)
        characteristicLabel.text = string.format("Casting with %s (%+d)",
            DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, attrid), value)

        local options = { { id = "", text = "No skill" } }
        for _, option in ipairs(FSHTrip.SkillOptions(m_token.properties)) do
            options[#options + 1] = option
        end
        skillDropdown.options = options
        skillDropdown.idChosen = ""
    end

    local heroOptions = {}
    for _, token in ipairs(heroes) do
        heroOptions[#heroOptions + 1] = {
            id = token.id,
            text = token.name or "Unnamed Hero"
        }
    end

    local heroDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = heroOptions,
        idChosen = m_token ~= nil and m_token.id or nil,
        change = function(element)
            for _, token in ipairs(heroes) do
                if token.id == element.idChosen then
                    m_token = token
                end
            end
            RefreshForHero()
        end
    }

    local heroRow = gui.Panel{
        classes = { "formRow", cond(#heroes < 2, "collapsed") },
        gui.Label{
            classes = { "label", "form" },
            text = "Hero:"
        },
        heroDropdown
    }

    local dialog
    dialog = gui.Panel{
        classes = { "dialog" },
        styles = ThemeEngine.GetStyles(),
        width = 500,
        height = 240,
        flow = "vertical",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,

        create = function()
            RefreshForHero()
        end,

        escape = function()
            gui.CloseModal()
        end,

        gui.Label{
            classes = { "modalTitle" },
            text = "Start Fishing"
        },

        gui.Panel{
            width = "98%",
            height = "auto",
            flow = "vertical",
            valign = "top",

            heroRow,

            gui.Panel{
                classes = { "formRow" },
                gui.Label{
                    classes = { "label", "form" },
                    text = "Skill:"
                },
                skillDropdown
            },

            characteristicLabel
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "bottom",
            vmargin = 16,

            gui.Button{
                classes = { "sizeL" },
                text = "Cancel",
                hmargin = 8,
                click = function()
                    gui.CloseModal()
                end
            },

            gui.Button{
                classes = { "sizeL" },
                text = "Start",
                hmargin = 8,
                click = function()
                    if m_token == nil then
                        return
                    end

                    local skill = nil
                    local chosen = skillDropdown.idChosen
                    if chosen ~= nil and chosen ~= "" then
                        for _, option in ipairs(skillDropdown.options or {}) do
                            if option.id == chosen then
                                skill = {
                                    id = option.id,
                                    name = option.text
                                }
                            end
                        end
                    end

                    local started = FSHTrip.Start(m_token, skill, args.rollHolderId)
                    gui.CloseModal()

                    --The Trip document has to land before anything reads it,
                    --so hand off rather than opening in the same breath.
                    if started then
                        dmhub.Schedule(0.2, function()
                            if args.onStarted ~= nil then
                                args.onStarted()
                            else
                                FSHPanel.OpenWindow()
                            end
                        end)
                    end
                end
            }
        }
    }

    gui.ShowModal(dialog)
end

--- Declared ahead of the Trip dialog, which closes over it, and defined further
--- down beside the rest of the stringer rendering.
local CastRow

--- The fishing art is 484x682; these preserve that ratio exactly.
local ART_WIDTH = 341
local ART_HEIGHT = 480

--- Opens the fishing window
--- LaunchPanelByName does not find a panel registered inside a folder, so the
--- registered menu entry is invoked directly, which is exactly what choosing it
--- from the menu does.
--- @return boolean opened True when the window was opened
function FSHPanel.OpenWindow()
    for _, item in ipairs(LaunchablePanel.GetMenuItems() or {}) do
        if item.text == FSHConstants.windowName and item.click ~= nil then
            item.click()
            return true
        end

        for _, entry in ipairs(item.submenu or {}) do
            if entry.text == FSHConstants.windowName and entry.click ~= nil then
                entry.click()
                return true
            end
        end
    end

    return false
end

--- Builds the event block for a Trip
--- The full text is shown rather than a summary: half these results are fiction
--- for a human to run, and a paraphrase would lose them.
--- @param charid string The hero's token id
--- @param trip table The Trip
--- @return Panel[] children The event rows
function FSHPanel.EventChildren(charid, trip)
    local children = {}

    for _, event in ipairs(trip.events or {}) do
        children[#children + 1] = gui.Label{
            classes = { "tableLabel", "sizeXs" },
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 6,
            text = string.format("Event %d -- %s", event.roll or 0, event.name or "")
        }

        children[#children + 1] = gui.Label{
            classes = { "sizeXxs" },
            width = "100%",
            height = "auto",
            halign = "left",
            textWrap = true,
            text = event.text or ""
        }

        for _, line in ipairs(event.applied or {}) do
            children[#children + 1] = gui.Label{
                classes = { "sizeXxs" },
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                text = string.format("Applied: %s", line)
            }
        end

        for _, line in ipairs(event.owed or {}) do
            children[#children + 1] = gui.Label{
                classes = { "sizeXxs", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                text = string.format("Owed: %s", line)
            }
        end

        if event.resolved ~= true and FSHTrip.IsOwnedByThisClient(charid) then
            children[#children + 1] = FSHPanel.EventPrompt(charid, event)
        end
    end

    return children
end

--- Builds the answer controls for an unresolved event
--- @param charid string The hero's token id
--- @param event table The event
--- @return Panel panel The prompt row
function FSHPanel.EventPrompt(charid, event)
    if event.roll == 2 then
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 4,

            gui.Button{
                classes = { "sizeXs" },
                width = 130,
                height = 24,
                halign = "left",
                rmargin = 6,
                text = "Read it aloud",
                click = function()
                    FSHEvents.AnswerNote(charid, true)
                end
            },

            gui.Button{
                classes = { "sizeXs" },
                width = 130,
                height = 24,
                halign = "left",
                text = "Leave it",
                click = function()
                    FSHEvents.AnswerNote(charid, false)
                end
            }
        }
    end

    if event.roll == 9 then
        local trip = FSHTrip.Get(charid)
        local waiting = trip ~= nil and trip.eventActionId ~= nil

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 4,

            gui.Button{
                classes = { "sizeXs", cond(waiting, "disabled") },
                width = 130,
                height = 24,
                halign = "left",
                rmargin = 6,
                interactable = not waiting,
                text = "Roll Might",
                hover = gui.Tooltip("Make the hard Might test"),
                click = function()
                    FSHEvents.RequestMightTest(charid)
                end
            },

            gui.Label{
                classes = { "sizeXxs", "fgMuted" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = cond(waiting, "Waiting on the roll...", "")
            }
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top"
    }
end

--- Builds the Tackle table rows
--- Every row stays visible whether or not it is affordable: the table is part
--- of the fiction, and seeing the 300 you cannot reach is the point.
--- @param charid string The hero's token id
--- @param trip table The Trip
--- @return Panel[] children The shop rows
function FSHPanel.ShopChildren(charid, trip)
    local children = {}

    children[#children + 1] = gui.Label{
        classes = { "tableLabel", "sizeXs" },
        width = "100%",
        height = "auto",
        halign = "left",
        tmargin = 6,
        text = "Tackle"
    }

    for _, reward in ipairs(FSHShop.REWARDS) do
        local affordable = (trip.points or 0) >= reward.cost
        local rewardId = reward.id

        --A tight action line with the description beneath it. The earlier
        --version stacked the description alongside the button, which is what
        --made the rows tall enough to push the table off the window.
        --Inset from the scroll region so the Buy button clears the scrollbar
        --gutter instead of being clipped by it.
        children[#children + 1] = gui.Panel{
            width = "100%-12",
            height = "auto",
            flow = "vertical",
            valign = "top",
            halign = "left",
            tmargin = 5,

            gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",
                valign = "top",

                --Leaves room for the cost column, its gutter, and the button.
                gui.Label{
                    classes = { "sizeXs", cond(not affordable, "fgMuted") },
                    width = "100%-112",
                    height = "100%",
                    halign = "left",
                    valign = "center",
                    text = reward.name
                },

                gui.Label{
                    classes = { "sizeXs", cond(not affordable, "fgMuted") },
                    width = 44,
                    height = "100%",
                    halign = "right",
                    valign = "center",
                    textAlignment = "right",
                    rmargin = 8,
                    text = tostring(reward.cost)
                },

                gui.Button{
                    classes = { "sizeXs", cond(not affordable, "disabled") },
                    width = 60,
                    height = 22,
                    halign = "right",
                    valign = "center",
                    interactable = affordable,
                    text = "Buy",
                    click = function()
                        FSHShop.Buy(charid, rewardId)
                    end
                }
            },

            gui.Label{
                classes = { "sizeXxs", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "left",
                valign = "top",
                textWrap = true,
                text = reward.detail
            }
        }
    end

    return children
end

--- Closes the fishing window from a control inside it
--- The launchable panel exposes no close call. It wraps whatever content()
--- returned in a window panel, so that wrapper is exactly the parent of this
--- window's own root. Anything above it is a full-screen hud layer and must be
--- left alone, which is why this steps to a known node rather than searching.
--- @param element Panel A control inside the window
function FSHPanel.CloseWindowFrom(element)
    local root = element:FindParentWithClass("fshTripWindow")
    if root == nil or not root.valid then
        return
    end

    local window = root.parent
    if window ~= nil and window.valid then
        window:DestroySelf()
    end
end

--- The Trip this client is running, if any
--- @return string|nil charid The hero's token id
function FSHPanel.OwnedTripCharId()
    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        if token.playerControlled
            and FSHTrip.IsLive(token.id)
            and FSHTrip.IsOwnedByThisClient(token.id) then
            return token.id
        end
    end
    return nil
end

--- A Trip, everything but the picture
--- The whole outing lives here: the stringer, the events, the Tackle table, and
--- the buttons that move between them. Sized to whatever hosts it, so the
--- standalone window and the Respite show the same thing.
--- @param args table charid, and onClose called when the Trip is closed up
--- @return Panel|nil pane The Trip, or nil when there is no such character
function FSHPanel.TripPane(args)
    local charid = args.charid
    local token = charid ~= nil and dmhub.GetCharacterById(charid) or nil

    if token == nil or not token.valid then
        return nil
    end

    local m_signature = ""

    --The stringer is home. Nothing navigates away from it on its own: the
    --player presses to roll the breakthrough or to walk to the Tackle table,
    --which is what keeps a Goldenrod reroll reachable after any result.
    local m_page = "stringer"

    --Where, not who: whoever is fishing is already selected in the list beside
    --this, and their characteristic was settled when they started. Name and
    --type share one line at one size, between the old heading and the line
    --under it, so the water costs a row rather than three.
    --Not modalTitle: that carries a 24px top margin and a 28px face meant for
    --a dialog heading, which is most of the space this line was costing. The
    --section-heading class is what the rest of the Trip already uses.
    local headerLabel = gui.Label{
        classes = { "tableLabel", "sizeS" },
        width = "100%",
        height = "auto",
        halign = "left",
        text = "Fishing"
    }

    local stringerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top"
    }

    --Sized to its own text rather than claiming a share of the row, so adding a
    --button never pushes one off the edge of the window.
    local pointsLabel = gui.Label{
        classes = { "sizeL" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        text = "Points: 0"
    }

    --One primary action at a time, and always a deliberate press: what it does
    --follows from how the last cast landed.
    local primaryAction = "cast"

    local primaryButton = gui.Button{
        classes = { "sizeM" },
        width = 150,
        height = 30,
        halign = "right",
        valign = "center",
        text = "Cast",
        click = function()
            if primaryAction == "cast" then
                FSHCast.Cast(charid)
            elseif primaryAction == "breakthrough" then
                FSHEvents.Roll(charid)
            elseif primaryAction == "shop" then
                m_page = "shop"
                m_signature = ""
            end
        end
    }

    local backButton = gui.Button{
        classes = { "sizeM", "collapsed" },
        width = 110,
        height = 30,
        halign = "right",
        valign = "center",
        rmargin = 6,
        text = "Back",
        hover = gui.Tooltip("Back to the stringer"),
        click = function()
            m_page = "stringer"
            m_signature = ""
        end
    }

    --A way off the casting loop. Late in a Trip the odds can settle where no
    --cast can reach tier 1 and a breakthrough is a rounding error, and a player
    --who reads that should not have to keep casting at a 3% chance to reach the
    --Tackle table. Ends casting, not the Trip: the points are still theirs to
    --spend. Small and quiet, so it never competes with Cast.
    local stopFishingButton = gui.Button{
        classes = { "withDanger", "collapsed" },
        icon = "phosphor/toolbox-duotone.png",
        halign = "right",
        valign = "center",
        rmargin = 6,
        hover = gui.Tooltip("Stop Fishing and head for the Tackle table"),
        click = function()
            FSHTrip.SetStatus(charid, FSHTrip.STATUS.SHOPPING.key)
            m_page = "shop"
            m_signature = ""
        end
    }

    local closeUpButton = gui.Button{
        classes = { "sizeM", "collapsed" },
        width = 110,
        height = 30,
        halign = "right",
        valign = "center",
        text = "Close Up",
        hover = gui.Tooltip("End the Trip. Unspent points are lost"),
        click = function(element)
            FSHTrip.Close(charid)
            if args.onClose ~= nil then
                args.onClose(element)
            end
        end
    }

    --The only way past the single-writer rule, and the player's way out of a
    --Trip that has stopped moving: the client running it has gone, or the roll
    --it waits on died with that client. Takes the Trip over rather than ending
    --it, so the outing carries on from exactly where it stopped.
    local takeOverButton = gui.Button{
        classes = { "sizeM", "collapsed" },
        width = 110,
        height = 30,
        halign = "right",
        valign = "center",
        rmargin = 6,
        text = "Take Over",
        hover = gui.Tooltip("Run this trip from here instead. Nothing already caught is lost"),
        click = function()
            FSHTrip.Reset(charid)
            m_signature = ""
        end
    }

    local goldenrodButton = gui.Button{
        classes = { "sizeM", "collapsed" },
        width = 110,
        height = 30,
        halign = "right",
        valign = "center",
        rmargin = 6,
        text = "Goldenrod",
        hover = gui.Tooltip("Reroll that cast. One per trip, and the new result stands"),
        click = function()
            FSHCast.Goldenrod(charid)
        end
    }

    --TEMPORARY, FOR TESTING. Forces or suppresses breakthroughs so both rare
    --branches can be reached on demand. Goes when events and the shop land.
    local testModeDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        width = 170,
        height = 22,
        halign = "left",
        valign = "center",
        options = ConstantOptions(FSHCast.TEST_MODE),
        idChosen = FSHCast.testMode,
        change = function(element)
            FSHCast.testMode = element.idChosen
        end
    }

    --TEMPORARY, FOR TESTING. Forces a specific events-table result so each
    --branch can be reached without waiting on a d10.
    local testEventDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        width = 210,
        height = 22,
        halign = "left",
        valign = "center",
        lmargin = 8,
        options = FSHEvents.TestRollOptions(),
        idChosen = tostring(FSHEvents.testRoll),
        change = function(element)
            FSHEvents.testRoll = tonumber(element.idChosen) or 0
        end
    }

    local noticeLabel = gui.Label{
        classes = { "sizeXs", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        text = ""
    }

    --The events table gets its own block: several results are pure fiction the
    --Director runs, so the full text has to be readable, not summarised.
    local eventPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        tmargin = 6
    }

    --Stops short of the scrolling region's right edge so the Buy buttons are
    --not painted under the scroll bar, and left aligned so the rows hold that
    --edge rather than centring in what is left.
    local shopPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%-8",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top"
    }

    local dialog
    dialog = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        rebuild = function()
            local trip = FSHTrip.Get(charid)
            if trip == nil then
                return
            end

            --The Trip's own record of the water rather than what is open now:
            --a Trip outlives the water it started on, and it should still say
            --where it happened.
            local typeText = string.format("%s Water",
                DTConstants.GetDisplayText(FSHConstants.WATER_TYPE,
                    trip.waterType or FSHConstants.WATER_TYPE.FRESH.key))
            local waterName = (trip.waterName ~= nil and trip.waterName ~= "")
                and trip.waterName or "Open water"
            headerLabel.text = string.format("%s  |  %s", waterName, typeText)

            local rows = {}
            for _, cast in ipairs(trip.casts or {}) do
                rows[#rows + 1] = CastRow(cast)
            end
            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = { "sizeXs", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 8,
                    text = "Nothing on the stringer yet."
                }
            end
            stringerPanel.children = rows

            pointsLabel.text = string.format("Points: %d", trip.points or 0)

            eventPanel.children = FSHPanel.EventChildren(charid, trip)
            eventPanel:SetClass("collapsed", #(trip.events or {}) == 0)

            local shopping = trip.status == FSHTrip.STATUS.SHOPPING.key
            if shopping then
                shopPanel.children = FSHPanel.ShopChildren(charid, trip)
            end
            shopPanel:SetClass("collapsed", not shopping)

            local casting = trip.status == FSHTrip.STATUS.CASTING.key
            local waiting = trip.actionId ~= nil
            local finished = trip.status == FSHTrip.STATUS.CLOSED.key

            local owned = FSHTrip.IsOwnedByThisClient(charid)
            local inEvent = trip.status == FSHTrip.STATUS.EVENT.key
            local owesEvent = inEvent
                and FSHEvents.Pending(trip) == nil
                and trip.eventActionId == nil
            local castingOver = not casting and not finished
            local onShop = m_page == "shop"

            --The stringer and the Tackle table are separate pages, and the
            --player walks between them. An event outranks both: the Tackle
            --table can buy one, and it has to be rolled and settled where the
            --player already is rather than on a page they cannot reach.
            stringerPanel:SetClass("collapsed", onShop)
            eventPanel:SetClass("collapsed",
                #(trip.events or {}) == 0 or (onShop and not inEvent))
            shopPanel:SetClass("collapsed", not onShop or inEvent)

            --Whether anything on the table is within reach at all.
            local cheapest = nil
            for _, reward in ipairs(FSHShop.REWARDS) do
                if cheapest == nil or reward.cost < cheapest then
                    cheapest = reward.cost
                end
            end
            --Not while an event is live: it may still hand over points, and
            --those are meant to be spendable when the table reopens.
            local canShop = castingOver
                and not inEvent
                and (trip.points or 0) >= (cheapest or 0)

            if casting then
                primaryAction = "cast"
                primaryButton.text = "Cast"
            elseif owesEvent then
                primaryAction = "breakthrough"
                primaryButton.text = "Roll Breakthrough"
            else
                primaryAction = "shop"
                primaryButton.text = "Go Shopping"
            end

            local primaryLive = owned and not waiting and not finished
                and (casting or owesEvent or canShop)
            primaryButton:SetClass("collapsed",
                (onShop and not inEvent) or not (casting or owesEvent or canShop))
            primaryButton.interactable = primaryLive
            primaryButton:SetClass("disabled", not primaryLive)

            backButton:SetClass("collapsed", not onShop)

            --Shown exactly when Cast is. Those are the states whose only other
            --move is to cast again, so they are the ones that need a door.
            local showStop = owned
                and not finished
                and not waiting
                and casting
            stopFishingButton:SetClass("collapsed", not showStop)
            stopFishingButton.interactable = showStop
            stopFishingButton:SetClass("disabled", not showStop)

            --Close Up ends the Trip, and stays the exit of last resort: offered
            --at the Tackle table and once casting is over with nothing left to
            --buy. Never mid-event, which owes a result first.
            local showCloseUp = owned
                and not finished
                and not inEvent
                and (onShop or (castingOver and not canShop))
            closeUpButton:SetClass("collapsed", not showCloseUp)
            closeUpButton.interactable = owned
            closeUpButton:SetClass("disabled", not owned)

            --Offered after any result and only on the stringer, which is what
            --keeps the reroll reachable: nothing moves on without a press.
            local canGoldenrod = owned
                and not onShop
                and not waiting
                and not finished
                and #(trip.casts or {}) > 0
                and FSHTrip.HasGoldenrodReroll(charid)
            goldenrodButton:SetClass("collapsed", not canGoldenrod)

            --Every control above this one is dead while the Trip belongs to
            --another client, so this is the only thing to offer. A finished
            --Trip is not offered it: there is nothing left to drive.
            takeOverButton:SetClass("collapsed", owned or finished)

            --Say why rather than leaving a dead button: a Trip started on
            --another client cannot be driven from here.
            if not owned then
                noticeLabel.text = "This trip is being run from another client."
            elseif waiting then
                noticeLabel.text = "Waiting on the roll..."
            elseif trip.status == FSHTrip.STATUS.EVENT.key then
                noticeLabel.text = "A breakthrough. Something else is happening."
            elseif trip.status == FSHTrip.STATUS.SHOPPING.key then
                noticeLabel.text = "Casting is over."
            elseif finished then
                --Closing up is meant to land rather than fade: the rules are
                --cheerful about taking every unspent point, so say so.
                local summary = trip.summary or {}
                local parts = {}

                parts[#parts + 1] = string.format("%d fish", summary.catches or 0)
                if summary.largest ~= nil then
                    parts[#parts + 1] = string.format("largest %d %s",
                        summary.largest.points or 0, summary.largest.species or "fish")
                end
                for _, bought in ipairs(summary.bought or {}) do
                    parts[#parts + 1] = string.format("bought %s", bought)
                end
                if (summary.lost or 0) > 0 then
                    parts[#parts + 1] = string.format("%d points lost", summary.lost)
                end

                noticeLabel.text = string.format("Trip over.  %s",
                    table.concat(parts, "  ·  "))
            else
                noticeLabel.text = ""
            end
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        thinkTime = 0.4,
        think = function(element)
            FSHCast.Pump(charid)
            FSHEvents.Pump(charid)

            local trip = FSHTrip.Get(charid)

            --Events have to be part of this: one arriving changes neither the
            --status, the cast count, nor the points, so leaving them out meant
            --the window never repainted to show the event at all.
            local signature = "gone"
            if trip ~= nil then
                local pending = FSHEvents.Pending(trip)
                --Who is running it belongs here too: a Trip taken over changes
                --which controls are live on both clients, and can move without
                --anything else about the Trip moving with it.
                signature = string.format("%s:%d:%d:%s:%d:%s:%s:%d:%s",
                    trip.status or "", #(trip.casts or {}), trip.points or 0,
                    trip.actionId or "", #(trip.events or {}),
                    pending ~= nil and tostring(pending.roll) or "-",
                    trip.eventActionId or "", #(trip.purchases or {}),
                    trip.runByUserId or "")
            end

            if signature ~= m_signature then
                m_signature = signature
                element:FireEvent("rebuild")
            end
        end,

        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",

            headerLabel,

            --Stringer, events, and the Tackle table share one scrolling region.
            --Giving the stringer the leftover space instead meant a long shop
            --was simply cut off below the fold with no way to reach it.
            gui.Panel{
                width = "100%-12",
                height = "100% available",
                flow = "vertical",
                valign = "top",
                vscroll = true,

                stringerPanel,
                eventPanel,
                shopPanel
            },

            --Points share the button row: every button in it is right aligned,
            --so a left aligned column takes the empty half rather than a row of
            --its own. The notice sits directly on top of the points, which is
            --where the player is already looking.
            gui.Panel{
                width = "100%",
                height = 48,
                flow = "horizontal",
                valign = "bottom",
                tmargin = 4,

                gui.Panel{
                    width = "50%",
                    height = "100%",
                    flow = "vertical",
                    halign = "left",
                    valign = "center",

                    noticeLabel,
                    pointsLabel,
                },

                takeOverButton,
                goldenrodButton,
                primaryButton,
                backButton,
                stopFishingButton,
                closeUpButton
            },

            gui.Panel{
                classes = { cond(not FSHConstants.DEBUG_MODE, "collapsed") },
                width = "100%",
                height = "auto",
                flow = "horizontal",
                valign = "bottom",

                gui.Label{
                    classes = { "sizeXxs", "fgMuted" },
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    rmargin = 6,
                    text = "Testing:"
                },

                testModeDropdown,
                testEventDropdown
            }
        }
    }

    return dialog
end

--- The standalone fishing window: the picture, and the Trip beside it
--- A launchable window rather than a modal: the roll dialog draws above the
--- window layer but below the modal layer, so a modal here would swallow the
--- very dice the player is casting.
--- @return Panel panel The window contents
function FSHPanel.CreateTripWindow()
    local charid = FSHPanel.OwnedTripCharId()
    local pane = FSHPanel.TripPane{
        charid = charid,
        onClose = FSHPanel.CloseWindowFrom,
    }

    if pane == nil then
        return gui.Panel{
            classes = { "fshTripWindow" },
            styles = ThemeEngine.GetStyles(),
            width = 400,
            height = 120,
            flow = "vertical",

            gui.Label{
                classes = { "sizeM", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "center",
                valign = "center",
                text = "You are not fishing right now."
            }
        }
    end

    return gui.Panel{
        classes = { "fshTripWindow" },
        styles = ThemeEngine.GetStyles(),
        width = ART_WIDTH + 420,
        height = ART_HEIGHT + 40,
        flow = "horizontal",
        pad = 8,

        gui.Panel{
            classes = { "image", "bordered" },
            width = ART_WIDTH,
            height = ART_HEIGHT,
            halign = "left",
            valign = "center",
            bgimage = mod.images.fishing
        },

        gui.Panel{
            width = "100%-" .. tostring(ART_WIDTH + 20),
            height = "100%",
            flow = "vertical",
            halign = "right",
            valign = "top",
            hmargin = 10,

            pane,
        },
    }
end

LaunchablePanel.Register{
    name = FSHConstants.windowName,
    folder = "Game",
    halign = "center",
    valign = "center",
    draggable = true,
    content = function()
        return FSHPanel.CreateTripWindow()
    end,
}

--- Gathers the fishing standings
--- Only player-controlled heroes who have actually landed something appear: the
--- bestiary is full of hero-typed tokens nobody plays, and a wall of "no catch"
--- rows buries the standing this section exists to show. Reads only, so
--- rendering never creates downtime storage for a character who has none.
--- @return table entries Sorted standings rows
--- @return number best The largest catch in the campaign
local function GatherRecords()
    local entries = {}
    local best = 0

    --Followers fish on the same terms as their heroes, so the standings have
    --to be able to show an artisan taking the record off the party.
    local candidates = {}
    for _, token in ipairs(DTBusinessRules.GetAllHeroTokens()) do
        candidates[#candidates + 1] = token

        local session = rawget(_G, "RSPSession")
        if session ~= nil then
            for _, followerId in ipairs(session.FollowersOf(token.id)) do
                local follower = dmhub.GetCharacterById(followerId)
                if follower ~= nil and follower.valid then
                    candidates[#candidates + 1] = follower
                end
            end
        end
    end

    for _, token in ipairs(candidates) do
        --playerControlled covers both a directly owned token and one shared
        --through a player party.
        if token.playerControlled then
            local fishing = token.properties:GetFishingRecord() or {}
            local biggest = fishing.biggest

            if biggest ~= nil then
                entries[#entries + 1] = {
                    token = token,
                    name = token.name or "Unnamed Hero",
                    biggest = biggest,
                    catches = fishing.lifetimeCatches or 0,
                    trips = fishing.lifetimeTrips or 0
                }

                if (biggest.points or 0) > best then
                    best = biggest.points
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        local ap = a.biggest.points or 0
        local bp = b.biggest.points or 0
        if ap ~= bp then
            return ap > bp
        end
        return a.name < b.name
    end)

    return entries, best
end

--- Glyph size per band, so a bigger fish is literally bigger on the stringer.
local BAND_GLYPH = {
    tiny = 16,
    small = 20,
    good = 24,
    big = 28,
    monster = 34,
    ancient = 40
}

--- Builds one row of the stringer
--- The three outcomes are meant to feel nothing alike, so they do not share a
--- shape: a catch is its species, rendered at its size and colour; a miss is a
--- slack grey line; a breakthrough stops looking like fishing at all.
--- @param cast table The cast record
--- @return Panel row The cast row
CastRow = function(cast)
    local seq = gui.Label{
        classes = { "sizeXxs", "fgMuted" },
        width = 22,
        height = "auto",
        halign = "left",
        valign = "center",
        text = string.format("%d.", cast.seq or 0)
    }

    if cast.result == FSHTrip.RESULT.CATCH.key then
        local species = cast.species or {}
        local size = BAND_GLYPH[species.band or ""] or 24

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 2,

            seq,

            --A fixed cell so the names still line up even though the fish
            --themselves do not.
            gui.Panel{
                width = 44,
                height = BAND_GLYPH.ancient,
                halign = "left",
                valign = "center",

                gui.Panel{
                    width = size,
                    height = size,
                    halign = "center",
                    valign = "center",
                    bgimage = species.icon or FSHConstants.GENERIC_FISH.icon,
                    bgcolor = species.color or FSHConstants.GENERIC_FISH.color
                }
            },

            gui.Panel{
                width = "100%-66",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",

                gui.Label{
                    classes = { "sizeXs" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    text = string.format("%d  %s", cast.points or 0,
                        species.name or "fish")
                },

                gui.Label{
                    classes = { "sizeXxs", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    text = DTConstants.GetDisplayText(FSHConstants.BAND,
                        species.band or "")
                }
            }
        }
    end

    if cast.result == FSHTrip.RESULT.BREAKTHROUGH.key then
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "top",
            tmargin = 2,

            seq,

            gui.Panel{
                width = 44,
                height = 28,
                halign = "left",
                valign = "center",

                gui.Panel{
                    width = 26,
                    height = 26,
                    halign = "center",
                    valign = "center",
                    bgimage = "phosphor/waves-fill.png",
                    bgcolor = "#d9b44a"
                }
            },

            gui.Label{
                classes = { "sizeXs", "bold" },
                width = "100%-66",
                height = "auto",
                halign = "left",
                valign = "center",
                color = "#d9b44a",
                text = string.format("Something else is happening  (%d)",
                    cast.total or 0)
            }
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        tmargin = 2,

        seq,

        gui.Panel{
            width = 44,
            height = 18,
            halign = "left",
            valign = "center",

            gui.Panel{
                width = 18,
                height = 2,
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                bgcolor = "#6b6b6b"
            }
        },

        gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "100%-66",
            height = "auto",
            halign = "left",
            valign = "center",
            text = string.format("the one that got away  (%d)", cast.total or 0)
        }
    }
end

--- Builds the block a finished Trip keeps behind its caret
--- Every line here is already on the Trip document. An event keeps its verbatim
--- text next to what the module applied and what a human still owes, so the
--- whole outing can be read back without a summary being stored anywhere new.
--- @param trip table The Trip
--- @return Panel detail The detail block, collapsed
local function LogDetail(trip)
    local children = {}

    local summary = trip.summary
    if summary ~= nil then
        local parts = { string.format("%d caught", summary.catches or 0) }

        if summary.largest ~= nil then
            parts[#parts + 1] = string.format("best %d %s",
                summary.largest.points or 0, summary.largest.species or "fish")
        end

        if (summary.lost or 0) > 0 then
            parts[#parts + 1] = string.format("%d points unspent", summary.lost)
        end

        children[#children + 1] = gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            text = table.concat(parts, ", ")
        }
    end

    --Titles and items change the character sheet, so they are called out rather
    --than left to be inferred from the points that went missing.
    local bought = {}
    for _, purchase in ipairs(trip.purchases or {}) do
        bought[#bought + 1] = purchase.name
    end

    if #bought > 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXxs" },
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 4,
            text = string.format("Gained: %s", table.concat(bought, ", "))
        }
    end

    for _, event in ipairs(trip.events or {}) do
        children[#children + 1] = gui.Label{
            classes = { "sizeXs" },
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 8,
            text = string.format("Breakthrough %d: %s", event.roll or 0, event.name or "")
        }

        children[#children + 1] = gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 2,
            text = event.text or ""
        }

        for _, line in ipairs(event.applied or {}) do
            children[#children + 1] = gui.Label{
                classes = { "sizeXxs" },
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 2,
                text = string.format("Applied: %s", line)
            }
        end

        for _, line in ipairs(event.owed or {}) do
            children[#children + 1] = gui.Label{
                classes = { "sizeXxs" },
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 2,
                text = string.format("Owed: %s", line)
            }
        end
    end

    if #children == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            text = "Nothing beyond the casts."
        }
    end

    return gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        lmargin = 22,
        tmargin = 2,
        children = children
    }
end

--- Builds one Fishing Log row
--- A finished Trip gets a caret: the outing is over, so there is a whole story
--- to read back. A live one does not, because the detail is still being written
--- and the fisher's own window is where it is happening.
--- @param trip table The Trip
--- @param expanded boolean Whether this row is currently open
--- @param onToggle function|nil Called with the new open state when the caret is pressed
--- @return Panel panel The log row
--- @param title string|nil names the row instead of the character; the
---   portrait goes with the name, since a surface that knows whose Trips these
---   are does not need telling twice
function FSHPanel.LogRow(trip, expanded, onToggle, title)
    local catches = 0
    for _, cast in ipairs(trip.casts or {}) do
        if cast.result == FSHTrip.RESULT.CATCH.key then
            catches = catches + 1
        end
    end

    local live = trip.status ~= FSHTrip.STATUS.CLOSED.key
    local skillText = trip.skill ~= nil and trip.skill.name or "no skill"

    --Same portrait the standings use, so a hero looks the same in both tabs.
    --A titled row drops it: the surface asking for a title is one that already
    --says whose Trips these are.
    local token = dmhub.GetCharacterById(trip.charid or "")
    local portrait = title == nil and gui.Panel{
        width = 32,
        height = 32,
        halign = "left",
        valign = "center",
        rmargin = 6,
        children = (token ~= nil and token.valid) and {
            gui.CreateTokenImage(token, {
                width = 32,
                height = 32,
                halign = "center",
                valign = "center",
                refresh = function(element)
                    if token == nil or not token.valid then
                        return
                    end
                    element:FireEventTree("token", token)
                end
            })
        } or {}
    } or nil

    --A breakthrough marks the Trip it happened on, not just the character: the
    --Director sees the warning on the roster row, and this is what says which
    --of the household's Trips to open. Same icon as the roster's, so the two
    --read as one thing. The Respite's cascade colours it; a host without that
    --class still gets the glyph.
    local breakthrough = nil
    local respiteConstants = rawget(_G, "RSPConstants")
    if respiteConstants ~= nil and #(trip.events or {}) > 0 then
        breakthrough = gui.Panel{
            classes = { "rspAttention" },
            bgimage = respiteConstants.iconAttention,
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
            hmargin = 4,
            hover = gui.Tooltip("A breakthrough happened on this Trip"),
        }
    end

    --Leaves room for the caret column, its margins, the portrait where there
    --is one, and the breakthrough marker when the Trip carries one.
    local taken = 22
    if portrait ~= nil then
        taken = taken + 38
    end
    if breakthrough ~= nil then
        taken = taken + 24
    end

    local labels = gui.Panel{
        width = "100%-" .. tostring(taken),
        height = "auto",
        flow = "vertical",
        valign = "center",

        --The name and how the Trip stands, on one line: an asterisk needed
        --explaining, and there is room to just say it.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",

            --Both bottom aligned: the status is the smaller of the two, and
            --centring them leaves it floating against the name rather than
            --sitting on the same line.
            gui.Label{
                classes = { "sizeXs" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "bottom",
                text = title or trip.tokenName or "Hero"
            },

            gui.Label{
                classes = { "sizeXxs", "fgMuted" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "bottom",
                lmargin = 6,
                text = cond(live, "still fishing", "trip complete")
            },
        },

        gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            text = string.format("%s  ·  %d casts  ·  %d caught  ·  %d points",
                skillText, #(trip.casts or {}), catches, trip.points or 0)
        }
    }

    -- A Trip in progress opens like any other. It used to be a header alone,
    -- which meant a breakthrough marked a row the Director could not open: the
    -- marker landed when the breakthrough resolved but the reason for it only
    -- arrived once the Trip closed. The "*" is what says it is still running.
    local headerChildren = {}

    local detail = LogDetail(trip)

    local caret
    caret = gui.ExpandoArrow{
        classes = { "sizeXs" },
        valign = "center",
        hmargin = 3,
        press = function(element)
            expanded = not expanded
            element:SetClass("expanded", expanded)
            detail:SetClass("collapsed", not expanded)

            --Handed back so the open rows survive the next rebuild: somebody
            --else's cast repaints this list and would otherwise shut them all.
            if onToggle ~= nil then
                onToggle(expanded)
            end
        end
    }
    caret:SetClass("expanded", expanded)
    detail:SetClass("collapsed", not expanded)

    headerChildren[#headerChildren + 1] = caret
    headerChildren[#headerChildren + 1] = portrait
    headerChildren[#headerChildren + 1] = labels
    headerChildren[#headerChildren + 1] = breakthrough

    local header = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        children = headerChildren
    }

    local row = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        tmargin = 4,

        header,
        detail
    }

    return row
end

--- Creates the panel
--- @return Panel panel The dock panel content
function FSHPanel.Create()
    local m_tab = dmhub.GetPref(string.format("fsh_tab:%s", dmhub.gameid or "default")) or "Fishing"
    local m_signature = ""

    --Which log rows are open, by hero. Held out here rather than in the row so
    --a rebuild does not collapse everything somebody was reading.
    local m_expanded = {}

    --hover is fixed at construction, so the changing reason is held here and
    --read by the button's linger handler.
    local m_startReason = "Begin a Trip"

    local statusLabel = gui.Label{
        classes = { "sizeS" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "center",
        tmargin = 4,
        lmargin = 8,
        text = ""
    }

    local openButton = gui.Button{
        classes = { "sizeXs" },
        width = 110,
        height = 22,
        halign = "left",
        text = "Open Water",
        hover = gui.Tooltip("Open a body of water so players can fish"),
        click = function()
            ShowOpenWaterDialog()
        end
    }

    local closeButton = gui.Button{
        classes = { "sizeXs" },
        width = 110,
        height = 22,
        halign = "left",
        hmargin = 4,
        text = "Close Water",
        hover = gui.Tooltip("Block new Trips. Trips already running finish normally"),
        click = function()
            FSHWater.Close()
        end
    }

    local startButton = gui.Button{
        classes = { "sizeXs" },
        width = 110,
        height = 22,
        halign = "left",
        text = "Go Fishing!",
        linger = function(element)
            gui.Tooltip(m_startReason)(element)
        end,
        click = function()
            --A Trip already running on this client just wants its window back.
            for _, token in ipairs(ControllableHeroes()) do
                if FSHTrip.IsLive(token.id) and FSHTrip.IsOwnedByThisClient(token.id) then
                    FSHPanel.OpenWindow()
                    return
                end
            end

            local available = {}
            for _, token in ipairs(SelectedFishableHeroes()) do
                if FSHTrip.CanStart(token.id) then
                    available[#available + 1] = token
                end
            end

            if #available > 0 then
                FSHPanel.ShowStartFishingDialog(available)
            end
        end
    }

    local controlsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        vmargin = 4,

        openButton,
        closeButton,
        startButton
    }

    local waterTabBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top"
    }

    local recordsTabBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top"
    }

    local tabsPanel

    local SelectTab = function(tabName)
        m_tab = tabName
        waterTabBody:SetClass("collapsed", tabName ~= "Fishing")
        recordsTabBody:SetClass("collapsed", tabName ~= "Records")

        for _, tab in ipairs(tabsPanel.children) do
            if tab.data ~= nil and tab.data.tabName ~= nil then
                tab:SetClass("selected", tab.data.tabName == tabName)
            end
        end

        dmhub.SetPref(string.format("fsh_tab:%s", dmhub.gameid or "default"), tabName)
    end

    tabsPanel = gui.Panel{
        classes = { "tabBar" },
        width = "100%",
        height = 24,

        gui.Label{
            classes = { "tab", cond(m_tab == "Fishing", "selected") },
            text = "Fishing",
            width = "50%",
            height = "100%",
            data = { tabName = "Fishing" },
            press = function()
                SelectTab("Fishing")
            end
        },

        gui.Label{
            classes = { "tab", cond(m_tab == "Records", "selected") },
            text = "Records",
            width = "50%",
            height = "100%",
            data = { tabName = "Records" },
            press = function()
                SelectTab("Records")
            end
        }
    }

    --Only the bodies scroll. The status line, controls, and tab bar stay put,
    --so the tab bar never narrows when a scrollbar appears. The 12px inset is
    --the scrollbar gutter.
    local bodyScroll = gui.Panel{
        width = "100%-12",
        height = "100% available",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        waterTabBody,
        recordsTabBody
    }

    local resultPanel
    resultPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "100%",
        flow = "vertical",

        monitorGame = FSHWater.GetDocumentPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        --Trips live in a document per hero, and which of them exist changes as
        --people start and finish. Rather than juggle a monitor per hero, watch
        --a cheap signature of the session's Trips and rebuild when it moves.
        thinkTime = 0.5,
        think = function(element)
            --A cast is answered wherever the hero is controlled, so the client
            --that asked has to come back and collect the result.
            for _, token in ipairs(ControllableHeroes()) do
                FSHCast.Pump(token.id)
            end

            local parts = {}
            for _, trip in ipairs(FSHTrip.TripsThisSession(true)) do
                parts[#parts + 1] = string.format("%s:%s:%d:%d:%s:%d",
                    trip.charid or "", trip.status or "",
                    #(trip.casts or {}), trip.points or 0,
                    trip.actionId or "", #(trip.events or {}))
            end

            --Selection gates Start Fishing, so the button has to follow it.
            for _, token in ipairs(SelectedFishableHeroes()) do
                parts[#parts + 1] = string.format("sel:%s", token.id)
            end

            local signature = table.concat(parts, "|")
            if signature ~= m_signature then
                m_signature = signature
                element:FireEvent("rebuild")
            end
        end,

        rebuild = function()
            local isOpen = FSHWater.IsOpen()

            statusLabel.text = FSHWater.Describe()

            openButton:SetClass("collapsed", not dmhub.isDM)
            closeButton:SetClass("collapsed", not dmhub.isDM or not isOpen)
            openButton.text = cond(isOpen, "Change Water", "Open Water")

            --A Trip in progress is always reachable. Starting a new one needs a
            --hero selected and standing on the map.
            local resumable = 0
            for _, token in ipairs(ControllableHeroes()) do
                if FSHTrip.IsLive(token.id) and FSHTrip.IsOwnedByThisClient(token.id) then
                    resumable = resumable + 1
                end
            end

            local startable = 0
            for _, token in ipairs(SelectedFishableHeroes()) do
                if FSHTrip.CanStart(token.id) then
                    startable = startable + 1
                end
            end

            local canFish = startable > 0 or resumable > 0

            startButton.text = cond(resumable > 0, "Back to Fishing", "Go Fishing!")
            startButton:SetClass("collapsed", false)
            startButton.interactable = canFish
            startButton:SetClass("disabled", not canFish)

            --Say what is missing rather than leaving a dead button.
            if resumable > 0 then
                m_startReason = "Open your fishing window"
            elseif startable > 0 then
                m_startReason = "Begin a Trip"
            elseif not isOpen then
                m_startReason = "No water is open"
            elseif #SelectedFishableHeroes() == 0 then
                m_startReason = "Select one of your heroes on the map"
            else
                m_startReason = "That hero is already fishing"
            end

            --The dock is the table's view of the water: who is out there and
            --how they are doing. Your own outing lives in the fishing window,
            --which is the only place casting happens.
            local body = {}

            local log = FSHTrip.TripsThisSession(true)
            if #log > 0 then
                body[#body + 1] = gui.Label{
                    classes = { "tableLabel", "sizeXs" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 10,
                    text = "Fishing Log"
                }

                for _, trip in ipairs(log) do
                    local charid = trip.charid or ""
                    body[#body + 1] = FSHPanel.LogRow(trip, m_expanded[charid] == true,
                        function(open)
                            m_expanded[charid] = cond(open, true, nil)
                        end)
                end
            end

            if #body == 0 then
                body[#body + 1] = gui.Label{
                    classes = { "sizeXs", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    tmargin = 8,
                    text = cond(isOpen,
                        "Nobody has fished here yet.",
                        "The Director has not opened any water.")
                }
            end

            waterTabBody.children = body

            local entries, best = GatherRecords()
            local rows = {}

            if #entries == 0 then
                rows[#rows + 1] = gui.Label{
                    classes = { "sizeXs", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    tmargin = 8,
                    text = "Nobody has landed a fish yet."
                }
            end

            for _, entry in ipairs(entries) do
                local waterName = entry.biggest.waterName or ""
                local detail = string.format("%d  %s%s  ·  %d caught  ·  %d trips",
                    entry.biggest.points or 0,
                    entry.biggest.species or "fish",
                    cond(waterName ~= "", string.format(", %s", waterName), ""),
                    entry.catches,
                    entry.trips)

                local isLeader = best > 0 and (entry.biggest.points or 0) == best

                local token = entry.token
                local portrait = gui.Panel{
                    width = 32,
                    height = 32,
                    halign = "left",
                    valign = "center",
                    rmargin = 6,
                    children = (token ~= nil and token.valid) and {
                        gui.CreateTokenImage(token, {
                            width = 32,
                            height = 32,
                            halign = "center",
                            valign = "center",
                            refresh = function(element)
                                if token == nil or not token.valid then
                                    return
                                end
                                element:FireEventTree("token", token)
                            end
                        })
                    } or {}
                }

                rows[#rows + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    valign = "top",
                    tmargin = 6,

                    portrait,

                    gui.Panel{
                        width = "100%-38",
                        height = "auto",
                        flow = "vertical",
                        halign = "left",
                        valign = "center",

                        gui.Label{
                            classes = { "sizeXs", cond(isLeader, "bold") },
                            width = "100%",
                            height = "auto",
                            halign = "left",
                            text = string.format("%s%s",
                                cond(isLeader, "* ", ""),
                                entry.name)
                        },

                        gui.Label{
                            classes = { "sizeXxs", "fgMuted" },
                            width = "100%",
                            height = "auto",
                            halign = "left",
                            text = detail
                        }
                    }
                }
            end

            recordsTabBody.children = rows

            waterTabBody:SetClass("collapsed", m_tab ~= "Fishing")
            recordsTabBody:SetClass("collapsed", m_tab ~= "Records")
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        statusLabel,
        controlsPanel,
        tabsPanel,
        bodyScroll
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

DockablePanel.Register{
    name = "Fishing",
    icon = "phosphor/fish-simple.png",
    minHeight = 160,
    maxHeight = 600,
    --The panel scrolls its own body below the tab bar, so the dock must not
    --also scroll the whole thing and drag the tabs out from under the user.
    vscroll = false,
    content = function()
        return FSHPanel.Create()
    end,
}

--- Fishing's key in the Respite's activity registry. Fixed, so a reload
--- refreshes the entry rather than adding a second one.
local RESPITE_ACTIVITY_KEY = "ad441633-2345-46d0-aa40-8918df586475"

--- The fields the Respite shows under "Fishing Available". They settle what
--- the water will be; nothing is opened until the Respite starts.
--- Painted into the Respite's own cascade, so no styles are rooted here.
--- @return Panel
local function PaintRespiteFields()
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        RSPWidgets.FormRow("Water Name", gui.Input{
            classes = { "input", "form" },
            text = FSHWater.GetName(),
            placeholderText = "Optional...",
            lineType = "Single",
            respiteChanged = function(element)
                element.text = FSHWater.GetName()
            end,
            change = function(element)
                FSHWater.SetName(element.text)
            end,
        }),

        RSPWidgets.FormRow("Water Type", gui.Dropdown{
            classes = { "dropdown", "form" },
            options = DTConstants.GetDropdownOptions(FSHConstants.WATER_TYPE),
            idChosen = FSHWater.GetWaterType(),
            respiteChanged = function(element)
                element.idChosen = FSHWater.GetWaterType()
            end,
            change = function(element)
                FSHWater.SetWaterType(element.idChosen)
            end,
        }),

        -- The water lives in this module's document, not the Respite's, so a
        -- change made from the fishing panel has to reach these fields too.
        RSPWidgets.DocumentMonitor(FSHWater.GetDocumentPath()),
    }
end

--- The Trips a character has run in this Respite
--- A follower's Trips belong on their hero's row, since the Director's roster
--- is heroes: asking for a hero returns their household's outings.
--- @param charid string The hero's id
--- @return table[] trips Oldest first
local function RespiteTrips(charid)
    local trips = {}

    local ids = { charid }
    local session = rawget(_G, "RSPSession")
    if session ~= nil then
        for _, followerId in ipairs(session.FollowersOf(charid)) do
            ids[#ids + 1] = followerId
        end
    end

    for _, id in ipairs(ids) do
        for _, trip in ipairs(FSHTrip.SessionTrips(id)) do
            trips[#trips + 1] = trip
        end
    end

    table.sort(trips, function(a, b)
        return (a.openedAt or 0) < (b.openedAt or 0)
    end)

    return trips
end

--- Does a Trip want the Director's eye?
--- Any breakthrough does. Half the table is fiction a human runs, and even the
--- ones the module settles by itself are worth knowing about, so the whole
--- events list counts rather than only what is still owed.
--- @param trip table The Trip
--- @return boolean
local function TripWantsTheDirector(trip)
    return #(trip.events or {}) > 0
end

--- Whether this hero's fishing wants the Director's eye
--- @param args table charid
--- @return boolean
function FSHPanel.RespiteNeedsAttention(args)
    for _, trip in ipairs(RespiteTrips(args.charid)) do
        if TripWantsTheDirector(trip) then
            return true
        end
    end
    return false
end

--- What this hero's household got up to fishing, for the Director
--- Rendered through the same log row the Water Log uses rather than a second
--- renderer, so a Trip reads the same wherever it is shown.
--- @param args table charid
--- @return Panel
function FSHPanel.PaintRespiteDirectorFeed(args)
    local charid = args.charid

    --Which rows are open, kept out here so a repaint does not collapse
    --whatever the Director was reading.
    local m_expanded = {}

    local list

    --What the rows amount to, so a tick that changes nothing does not rebuild
    --the list under a Director who is reading it.
    local m_signature = ""

    local function Children()
        local children = {}

        for index, trip in ipairs(RespiteTrips(charid)) do
            local key = string.format("%s:%d", trip.charid or "", index)
            children[#children + 1] = FSHPanel.LogRow(trip, m_expanded[key] == true,
                function()
                    m_expanded[key] = not (m_expanded[key] == true)
                    m_signature = ""
                end,
                --Whose Trip it is, is the row the Director already selected on
                --the left; what they need here is which outing of theirs.
                string.format("Trip %d", index))
        end

        if #children == 0 then
            children[1] = gui.Label{
                classes = { "sizeXs", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "left",
                text = "No fishing this Respite."
            }
        end

        return children
    end

    local function Signature()
        local parts = {}

        for _, trip in ipairs(RespiteTrips(charid)) do
            parts[#parts + 1] = string.format("%s:%s:%d:%d:%d",
                trip.charid or "", trip.status or "",
                #(trip.casts or {}), #(trip.events or {}), #(trip.purchases or {}))
        end
        for key, open in pairs(m_expanded) do
            if open then
                parts[#parts + 1] = key
            end
        end
        return table.concat(parts, "|")
    end

    m_signature = Signature()

    list = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",

        --Trips move while the Director is watching, and nothing else here
        --tells the panel so.
        thinkTime = 1,
        think = function(element)
            local signature = Signature()
            if signature ~= m_signature then
                m_signature = signature
                element.children = Children()
            end
        end,

        children = Children(),
    }

    return list
end

--- Where a character fishes during a Respite
--- The Trip itself is the standalone window's pane, unchanged; this adds the
--- way into one and the reason there is not one yet.
--- @param args table charid, and owner when the character is a follower
--- @return Panel
function FSHPanel.PaintRespitePlayer(args)
    local charid = args.charid

    --A follower fishes on the rolls their hero holds for them.
    local rollHolderId = args.owner or charid

    local body
    local m_signature = ""

    --Which earlier Trips are open, kept out here so a repaint does not shut
    --whatever the player was reading.
    local m_expanded = {}

    --This character's earlier outings, the live one left out: it has the whole
    --pane above and does not want a second, smaller telling of itself.
    --SessionTrips puts the live Trip last and only when it is live, so that is
    --exactly the entry to drop.
    local function FinishedTrips()
        local trips = FSHTrip.SessionTrips(charid)
        if FSHTrip.IsLive(charid) then
            trips[#trips] = nil
        end
        return trips
    end

    --The pane is rebuilt only when the shape of the thing changes: a Trip
    --appearing or ending, or the water opening. Rebuilding on every cast would
    --throw away the scroll position mid-outing.
    local function Signature()
        local trip = FSHTrip.Get(charid)
        --IsLive stands apart from the session: a Trip left over from a closed
        --water still shows and still blocks starting another, so the pane has
        --to notice it arriving and going away.
        local shown = trip ~= nil
            and (FSHTrip.IsLive(charid) or trip.sessionId == FSHWater.GetSessionID())

        local parts = {
            FSHWater.GetSessionID(),
            tostring(FSHWater.IsOpen()),
            tostring(FSHTrip.IsLive(charid)),
            shown and (trip.status or "") or "none",
            tostring(FSHTrip.RollsAvailable(charid, rollHolderId)),
            tostring(#FinishedTrips()),
        }
        for key, open in pairs(m_expanded) do
            if open then
                parts[#parts + 1] = key
            end
        end
        table.sort(parts)

        return table.concat(parts, "|")
    end

    local function Rebuild()
        if body == nil or not body.valid then
            return
        end

        if not FSHWater.IsOpen() then
            body.children = {
                gui.Label{
                    classes = { "sizeM", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 8,
                    text = "No water is open."
                }
            }
            return
        end

        local children = {}

        --A record nobody can read is the one thing there is no showing and no
        --carrying on from, and it would otherwise block this hero from fishing
        --for the rest of the Respite. Everything else is repairable, and is
        --repaired in the Trip rather than thrown away.
        if not FSHTrip.IsUsable(charid) then
            FSHTrip.Abandon(charid)
        end

        local canStart, reason = FSHTrip.CanStart(charid, rollHolderId)
        local token = dmhub.GetCharacterById(charid)

        if canStart and token ~= nil then
            children[#children + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                bmargin = 6,

                gui.Button{
                    classes = { "sizeM" },
                    width = 150,
                    height = 30,
                    halign = "left",
                    text = "Start Fishing",
                    hover = gui.Tooltip("Costs one downtime roll, taken on your first cast"),
                    click = function()
                        FSHPanel.ShowStartFishingDialog({ token }, {
                            rollHolderId = rollHolderId,
                            onStarted = function()
                                m_signature = ""
                            end,
                        })
                    end
                },

                --Where they would be fishing, not what it costs: the roll
                --count is already on their row in the list beside this.
                gui.Label{
                    classes = { "sizeXs", "fgMuted" },
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    lmargin = 8,
                    text = FSHWater.Describe()
                },
            }
        end

        --The pane is for the outing still going on, whatever water it started
        --on: it is what blocks starting another, so hiding it is what leaves a
        --player staring at a refusal with nothing to act on, and the Trip
        --carries its own water in it so it reads correctly after that water has
        --closed. A finished Trip does not get the pane - it has become one of
        --the rows below, which is a better ending than a summary line sitting
        --where a live Trip used to be.
        local hasTrip = FSHTrip.IsLive(charid)

        if hasTrip then
            local pane = FSHPanel.TripPane{
                charid = charid,
                --Nothing to close: closing up turns the Trip into the newest
                --row of the log underneath, and the way back in is Start
                --Fishing above it.
                onClose = function()
                    m_signature = ""
                end,
            }
            children[#children + 1] = gui.Panel{
                width = "100%",
                height = "100% available",
                flow = "vertical",
                halign = "left",
                valign = "top",

                pane,
            }
        elseif not canStart then
            children[#children + 1] = gui.Label{
                classes = { "sizeM", "fgMuted" },
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 8,
                text = reason
            }
        end

        --What they have already caught today. Rendered through the same log row
        --the Water Log and the Director's feed use, so a Trip reads the same
        --wherever it is shown.
        local finished = FinishedTrips()
        if #finished > 0 then
            children[#children + 1] = gui.Label{
                classes = { "tableLabel", "sizeXs" },
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 8,
                text = "Earlier Trips"
            }

            for index, entry in ipairs(finished) do
                local key = string.format("%d", index)
                children[#children + 1] = FSHPanel.LogRow(entry, m_expanded[key] == true,
                    function()
                        m_expanded[key] = not (m_expanded[key] == true)
                        m_signature = ""
                    end,
                    --Which outing of theirs, not whose: the player is looking
                    --at their own character.
                    string.format("Trip %d", index))
            end
        end

        body.children = children
    end

    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        create = function()
            m_signature = Signature()
            Rebuild()
        end,

        thinkTime = 0.4,
        think = function()
            local signature = Signature()
            if signature ~= m_signature then
                m_signature = signature
                Rebuild()
            end
        end,
    }

    return body
end

--- Where the fishing happened, for the Respite's write-up
--- @return string|nil
function FSHPanel.RespiteJournalDetail()
    if not FSHWater.IsOpen() then
        return nil
    end

    -- Describe() separates with a pipe for the panel header; a sentence in a
    -- document wants a comma.
    return (FSHWater.Describe():gsub("%s*|%s*", ", "))
end

--- What this household's fishing amounted to, for the Respite's write-up
--- Trips and their tally, then the moments worth naming: a breakthrough is
--- fiction somebody has to remember, and the biggest fish is the bragging.
--- @param args table charid
--- @return string[]|nil lines nil when nobody fished
function FSHPanel.RespiteJournalSummary(args)
    --- Names whoever it was when that is not the hero the section belongs to.
    --- @param who string|nil
    --- @param what string
    --- @return string
    local function Attribute(who, what)
        if who == nil then
            return what
        end
        return string.format("%s: %s", who, what)
    end

    local trips = 0
    local catches = 0
    local largest = nil
    local events = {}
    local bought = {}

    -- The same household the Director's feed reads, so the write-up and the
    -- monitor can never tell different stories. Each Trip carries whose it was.
    for _, trip in ipairs(RespiteTrips(args.charid)) do
        -- Only a follower needs naming: the hero's own name is the heading
        -- this sits under, and repeating it reads as a stutter.
        local name = nil
        if trip.charid ~= args.charid then
            name = trip.tokenName or "A follower"
        end
        trips = trips + 1

        for _, cast in ipairs(trip.casts or {}) do
            if cast.result == FSHTrip.RESULT.CATCH.key then
                catches = catches + 1
                if largest == nil or (cast.points or 0) > largest.points then
                    largest = {
                        points = cast.points or 0,
                        species = cast.species ~= nil and cast.species.name
                            or "fish",
                        who = name,
                    }
                end
            end
        end

        for _, event in ipairs(trip.events or {}) do
            events[#events + 1] = Attribute(name, event.name or "a breakthrough")
        end

        for _, purchase in ipairs(trip.purchases or {}) do
            bought[#bought + 1] = Attribute(name, purchase.name or "something")
        end
    end

    if trips == 0 then
        return nil
    end

    local lines = {
        string.format("Went fishing %d %s and landed %d %s", trips,
            cond(trips == 1, "time", "times"), catches,
            cond(catches == 1, "fish", "fish")),
    }

    if largest ~= nil then
        lines[#lines + 1] = Attribute(largest.who, string.format(
            "Biggest catch: %d %s", largest.points, largest.species))
    end

    for _, line in ipairs(events) do
        lines[#lines + 1] = string.format("Breakthrough - %s", line)
    end

    for _, line in ipairs(bought) do
        lines[#lines + 1] = string.format("Bought at the Tackle table - %s", line)
    end

    return lines
end

--- Offers fishing to the Respite, if the Respite module is installed.
--- Registering the same key twice is a replace, so running this more than
--- once costs nothing.
local function RegisterWithRespite()
    if mod.unloaded then
        return
    end

    -- Reading an unset global raises, and the Respite module is not
    -- guaranteed to be installed alongside this one.
    local registry = rawget(_G, "RSPActivity")
    if registry == nil then
        return
    end

    registry.Register{
        key = RESPITE_ACTIVITY_KEY,
        name = "Fishing",
        paint = PaintRespiteFields,
        paintPlayer = FSHPanel.PaintRespitePlayer,
        paintDirector = FSHPanel.PaintRespiteDirectorFeed,
        needsAttention = FSHPanel.RespiteNeedsAttention,

        --The Respite is the outing: opening mints a session, which is what
        --separates this Respite's Trips from the last one's, and the name and
        --type are whatever the Director set up.
        onStart = function()
            FSHWater.Open(FSHWater.GetName(), FSHWater.GetWaterType())
        end,

        onComplete = function()
            FSHWater.Close()
        end,

        journalDetail = FSHPanel.RespiteJournalDetail,
        journalSummary = FSHPanel.RespiteJournalSummary,
    }
end

-- The Respite module loads after this one, so it announces its registry and
-- we answer. Must match RSPConstants.registryEvent. The direct call covers
-- the reverse load order, where the registry is already up.
dmhub.RegisterEventHandler("rspActivityRegistry", RegisterWithRespite)
RegisterWithRespite()

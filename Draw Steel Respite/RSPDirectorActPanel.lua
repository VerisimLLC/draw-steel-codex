local mod = dmhub.GetModLoading()

--- Director Step 3: the Respite in progress, and how far along everyone is.
RSPDirectorActPanel = {}

local INSTRUCTIONS = [[
### Activities

The Respite is underway. Each hero is marked complete once their player is finished.

Completing the Respite closes it for everyone.
]]

--- The heroes this Respite covers. Followers do not appear here: the hero is
--- the unit of completion.
--- @return string[] charids
local function Roster()
    return RSPSession.CoveredHeroes(RSPSession.Roster())
end

--- Every row here is a hero, so every row carries a completion state.
--- @param charid string
--- @return boolean
local function Completion(charid)
    return RSPSession.IsDone(charid)
end

--- Does this hero have something the Director must act on? Asked of every
--- registered activity, so the Respite never learns what any of them track.
--- @param charid string
--- @return boolean
local function NeedsAttention(charid)
    local registry = rawget(_G, "RSPActivity")
    if registry == nil then
        return false
    end

    return registry.AnyNeedsAttention{
        charid = charid,
        since = RSPSession.StartedAt(),
    }
end

--- What each activity has to report about the selected hero, under a heading
--- of its own. Rebuilt when the selection moves; each activity keeps its own
--- section current from there.
--- @param charid string|nil
--- @return Panel[]
local function BuildFeedSections(charid)
    local sections = {}

    local registry = rawget(_G, "RSPActivity")
    if charid == nil or registry == nil then
        return sections
    end

    for _, activity in ipairs(registry.All()) do
        local paint = activity:try_get("paintDirector")
        if paint ~= nil and RSPSession.IsActivityAvailable(activity.key) then
            -- Inset in pixels rather than a share: the pane scrolls, and the
            -- bar has to sit clear of the text rather than over it.
            sections[#sections + 1] = gui.Panel{
                width = RSPConstants.feedSectionWidth,
                height = "auto",
                flow = "vertical",
                halign = "left",
                lmargin = RSPConstants.feedSectionInset,
                vmargin = 6,

                gui.Label{
                    classes = {"sizeM", "bold"},
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    bmargin = 2,
                    text = activity.name,
                },

                paint{charid = charid, since = RSPSession.StartedAt()},
            }
        end
    end

    return sections
end

--- @return Panel
local function BuildWorkingArea()
    -- Which hero the Director is looking at. One viewer's state, so it stays
    -- on the panel rather than in the document. The highlight follows the
    -- selection, never the completion: that is the icon's job.
    local list
    local feed

    list = RSPWidgets.CharacterList{
        roster = Roster(),
        rolls = RSPSession.CombinedRolls,
        status = Completion,
        attention = NeedsAttention,

        highlight = function(charid)
            return list ~= nil and list.data.selected == charid
        end,

        click = function(charid)
            if list ~= nil and list.valid then
                list.data.selected = charid
                list:FireEventTree("respiteChanged")
            end
            if feed ~= nil and feed.valid then
                feed:FireEvent("showCharacter", charid)
            end
        end,
    }

    -- The scrolling panel is inside the bordered one rather than being it: a
    -- panel that both scrolls and carries a border draws the bar on top of
    -- that border.
    feed = gui.Panel{
        width = RSPConstants.feedScrollWidth,
        height = RSPConstants.feedScrollHeight,
        flow = "vertical",
        halign = "left",
        -- Centred so the height it gives up is split between the top and
        -- bottom borders instead of all coming off the bottom.
        valign = "center",
        vscroll = true,

        data = {
            charid = nil,
        },

        showCharacter = function(element, charid)
            if element.data.charid == charid then
                return
            end
            element.data.charid = charid

            local sections = BuildFeedSections(charid)
            if #sections == 0 then
                sections = {
                    gui.Label{
                        classes = {"sizeL", "noBold", "fgMuted"},
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        valign = "center",
                        tmargin = 24,
                        text = charid == nil and "Activities Tracked Here"
                            or "Nothing tracked for this character.",
                    },
                }
            end

            element.children = sections
        end,

        -- Open on the first hero rather than an empty pane. Deferred because
        -- the list has to exist before its selection can be read.
        create = function(element)
            dmhub.Schedule(0.1, function()
                if element.valid then
                    element:FireEvent("showCharacter",
                        list ~= nil and list.data.selected or nil)
                end
            end)
        end,
    }

    local roster = Roster()
    if list ~= nil and #roster > 0 then
        list.data.selected = roster[1]
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        gui.Panel{
            width = RSPConstants.activityListWidth,
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",

            list,
        },

        gui.Panel{
            classes = {"bordered"},
            width = RSPConstants.activityPaneWidth,
            height = RSPConstants.feedPaneHeight,
            flow = "vertical",
            halign = "right",
            valign = "top",

            feed,
        },
    }
end

--- Asks how much longer the Respite runs, then adds it on
--- The two steppers hold their own numbers rather than writing through: this
--- is a question about an extension, and nothing should move until OK.
function RSPDirectorActPanel.ShowExtendDialog()
    local days = RSPConstants.daysMin
    local activities = RSPConstants.daysMin

    local dialog
    dialog = gui.Panel{
        classes = {"dialog"},
        styles = ThemeEngine.GetStyles(),
        width = RSPConstants.extendDialogWidth,
        height = RSPConstants.extendDialogHeight,
        flow = "vertical",
        halign = "center",
        valign = "center",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,

        escape = function()
            gui.CloseModal()
        end,

        gui.Label{
            classes = {"modalTitle"},
            text = "Extend Respite",
        },

        gui.Panel{
            width = "92%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            vmargin = 8,

            RSPWidgets.FormRow("# Days Elapsed", RSPWidgets.Stepper{
                get = function() return days end,
                set = function(n) days = n end,
                min = RSPConstants.activitiesMin,
                max = RSPConstants.daysMax,
            }),

            RSPWidgets.FormRow("# Downtime Activities", RSPWidgets.Stepper{
                get = function() return activities end,
                set = function(n) activities = n end,
                min = RSPConstants.activitiesMin,
                max = RSPConstants.activitiesMax,
            }),
        },

        gui.Panel{
            width = "92%",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "bottom",
            bmargin = RSPConstants.extendDialogButtonLift,

            gui.Button{
                classes = {"sizeL"},
                text = "Cancel",
                halign = "left",
                press = function()
                    gui.CloseModal()
                end,
            },

            gui.Button{
                classes = {"sizeL"},
                text = "OK",
                halign = "right",
                press = function()
                    RSPSession.Extend(days, activities)
                    gui.CloseModal()
                end,
            },
        },
    }

    gui.ShowModal(dialog)
end

--- @return string
local function CompletionCountText()
    local roster = Roster()
    local done = 0
    for _, charid in ipairs(roster) do
        if RSPSession.IsDone(charid) then
            done = done + 1
        end
    end

    if #roster > 0 and done >= #roster then
        return "All Characters Complete"
    end
    return string.format("%d/%d Characters Complete", done, #roster)
end

--- Build the Activities step.
--- @param onComplete fun() invoked when the Director finishes the Respite
--- @return table step args for RSPShell
function RSPDirectorActPanel.Step(onComplete)
    return {
        phase = RSPConstants.phaseActive,
        headerInfo = RSPWidgets.RespiteSummary,
        orientation = RSPConstants.orientTop,
        instructions = INSTRUCTIONS,
        working = BuildWorkingArea(),

        footerLeft = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "center",

            gui.Button{
                classes = {"sizeS"},
                text = "Extend",
                halign = "left",
                valign = "center",
                rmargin = 8,
                hover = gui.Tooltip("Add days or downtime activities to this Respite"),
                press = function()
                    RSPDirectorActPanel.ShowExtendDialog()
                end,
            },

            gui.Label{
                classes = {"sizeM", "noBold"},
                width = "100%-65",
                height = "auto",
                halign = "left",
                valign = "center",
                text = CompletionCountText(),
                respiteChanged = function(element)
                    element.text = CompletionCountText()
                end,
            },
        },

        footerCenter = gui.Check{
            classes = {"form"},
            halign = "center",
            valign = "center",
            text = "Create Journal Record",
            value = RSPSession.JournalWanted(),
            respiteChanged = function(element)
                element.value = RSPSession.JournalWanted()
            end,
            change = function(element)
                RSPSession.SetJournalWanted(element.value)
            end,
        },

        footerRight = gui.Button{
            classes = {"sizeL"},
            text = "Complete Respite",
            halign = "right",
            valign = "center",
            press = function()
                onComplete()
            end,
        },
    }
end

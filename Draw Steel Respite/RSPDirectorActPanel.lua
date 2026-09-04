local mod = dmhub.GetModLoading()

--- Director Step 3: the Respite in progress, and how far along everyone is.
RSPDirectorActPanel = RegisterGameType("RSPDirectorActPanel")

local INSTRUCTIONS = [[
### Activities

The Respite is underway. Each hero is marked complete once their player is finished.
Note that activity counts reflect hero and followers combined.
Completing the Respite closes it for everyone.
]]

--- The phase the Respite is in, or Setup when there is none.
--- @return string
local function CurrentPhase()
    local session = RSPSession.Active()
    return session ~= nil and session.phase or RSPConstants.phaseSetup
end

--- Every hero the Respite covers, each with its followers beneath it, as the
--- players see their own. A hero the non-participants setting excluded still
--- appears when they have followers, since followers may always act.
--- @return table[] entries
local function Entries()
    return RSPSession.ActingEntries(RSPSession.Roster())
end

--- The row the pane opens on. The first entry rather than the first hero: when
--- every hero is sitting the Respite out, the list starts on a follower.
--- @return string|nil charid
local function FirstSelectable()
    local entries = Entries()
    return entries[1] ~= nil and entries[1].charid or nil
end

--- A follower's rolls live on the hero it follows, so the entry's owner is
--- what gets asked.
--- @param charid string
--- @param owner nil|string the hero this row follows
--- @return number rolls
local function RollsFor(charid, owner)
    if owner ~= nil then
        return RSPSession.FollowerRolls(owner, charid)
    end
    return RSPSession.HeroRolls(charid)
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
        since = RSPSession.StartedAt,
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

                --The accessor, not the number: a section built before the
                --Respite started would otherwise hold a zero forever, and a
                --window of "everything after time zero" admits every roll the
                --campaign has ever recorded.
                paint{charid = charid, since = RSPSession.StartedAt},
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
        roster = Entries,
        rolls = RollsFor,
        attention = NeedsAttention,

        -- A hero opens straight onto their Downtime tab, which is what the
        -- Director wants from this list. That tab is registered hero-only, so a
        -- follower has none and opens on the sheet's default panel instead.
        sheet = function(charid, owner)
            local token = dmhub.GetCharacterById(charid)
            if token == nil then
                return
            end

            if owner ~= nil then
                token:ShowSheet()
            else
                token:ShowSheet(RSPConstants.sheetTabDowntime)
            end
        end,

        highlight = function(charid)
            return list ~= nil and list.data.selected == charid
        end,

        -- Selecting a follower highlights that row but reports on the hero it
        -- follows: the feed is written per hero, and a follower's work is part
        -- of its hero's story rather than a story of its own.
        click = function(charid, owner)
            if list ~= nil and list.valid then
                list.data.selected = charid
                list:FireEventTree("respiteChanged")
            end
            if feed ~= nil and feed.valid then
                feed:FireEvent("showCharacter", owner or charid)
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
            phase = nil,
        },

        -- A section built before the Respite started can be holding anything
        -- it worked out from a Respite that had not begun. Crossing into a new
        -- phase throws the lot away and asks the activities again.
        respiteChanged = function(element)
            local phase = CurrentPhase()
            if element.data.phase == phase then
                return
            end
            element.data.phase = phase

            local charid = element.data.charid
            element.data.charid = nil
            element:FireEvent("showCharacter", charid)
        end,

        showCharacter = function(element, charid)
            -- Asking for what is already shown is only cheap to ignore once
            -- something is actually shown: an opening pane starts on nil, and
            -- swallowing the nil that follows leaves it blank for good.
            if element.data.charid == charid and #(element.children or {}) > 0 then
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

        -- Open on the first row rather than an empty pane. The roster is read
        -- directly: by the time this is on screen the list has its selection,
        -- and the pane must not depend on a later tick to have any content.
        create = function(element)
            element:FireEvent("showCharacter",
                (list ~= nil and list.data.selected) or FirstSelectable())
        end,
    }

    local opening = FirstSelectable()
    if list ~= nil and opening ~= nil then
        list.data.selected = opening
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        gui.Panel{
            width = RSPConstants.directorListWidth,
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",

            -- The list scrolls on its own, so a long roster stays inside the
            -- pane rather than pushing it taller.
            gui.Panel{
                width = "100%",
                height = RSPConstants.directorListHeight,
                flow = "vertical",
                halign = "left",
                valign = "top",

                list,
            },

        },

        gui.Panel{
            classes = {"bordered"},
            width = RSPConstants.directorPaneWidth,
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
--- is a question about an extension, and nothing should move until OK. Days
--- carries activities along with it as it does on the Setup step, so the pair
--- has to be repainted by hand once the numbers are only locals.
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
                set = function(n)
                    days = n
                    activities = n
                    if dialog ~= nil and dialog.valid then
                        dialog:FireEventTree("respiteChanged")
                    end
                end,
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

        footerCellWidths = RSPConstants.directorFooterCells,

        -- Matched to Complete Respite: they are the two things this step does,
        -- and one of them is not a lesser control than the other.
        footerLeft = gui.Button{
            classes = {"sizeL"},
            width = RSPConstants.extendButtonWidth,
            text = "Extend",
            halign = "left",
            valign = "center",
            hover = gui.Tooltip("Add days or downtime activities to this Respite"),
            press = function()
                RSPDirectorActPanel.ShowExtendDialog()
            end,
        },

        -- Two answers about what closing the Respite does, side by side
        -- between the buttons. Sized to the pair rather than to the cell, so
        -- the cell centres them as a group instead of the checkboxes having to
        -- space themselves inside it.
        footerCenter = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "center",

            gui.Check{
                classes = {"form"},
                halign = "left",
                hmargin = RSPConstants.footerCheckboxMargin,
                text = "Revoke Unused Activities",
                hover = gui.Tooltip(
                    "Take back every downtime roll nobody spent, participant or not"),
                value = RSPSession.RevokeWanted(),
                respiteChanged = function(element)
                    element.value = RSPSession.RevokeWanted()
                end,
                change = function(element)
                    RSPSession.SetRevokeWanted(element.value)
                end,
            },

            gui.Check{
                classes = {"form"},
                halign = "left",
                hmargin = RSPConstants.footerCheckboxMargin,
                text = "Create Journal Record",
                value = RSPSession.JournalWanted(),
                respiteChanged = function(element)
                    element.value = RSPSession.JournalWanted()
                end,
                change = function(element)
                    RSPSession.SetJournalWanted(element.value)
                end,
            },
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

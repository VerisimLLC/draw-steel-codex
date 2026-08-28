--- Whether a follower is one that can spend downtime activities
--- Only artisans and sages take downtime actions, so they are the only ones
--- worth granting or editing activities for.
--- @param token any The follower's token
--- @return boolean
local function IsDowntimeFollower(token)
    local follower = token ~= nil and token.properties or nil
    if follower == nil then
        return false
    end

    local followerType = follower:try_get("followerType")
    if type(followerType) ~= "string" then
        return false
    end

    followerType = followerType:lower()
    return followerType == "artisan" or followerType == "sage"
end

--- Activities Dialog - Edits how many downtime activities a household holds
--- One hero and their downtime followers, each with their own count. Where the
--- Grant dialog deals in deltas across the whole party, this one sets the
--- numbers outright for a single hero.
--- @class DTActivitiesDialog
DTActivitiesDialog = RegisterGameType("DTActivitiesDialog")

--- Widths of the "- [n] +" control, which reads the same as the Respite's.
--- The well carries a minWidth of its own because the theme gives inputs one,
--- and a bare width loses to it - which is what ran the stepper off the edge.
local STEPPER_BUTTON_WIDTH = 30
local STEPPER_WELL_WIDTH = 54
local STEPPER_WIDTH = STEPPER_BUTTON_WIDTH * 2 + STEPPER_WELL_WIDTH

local ROW_WIDTH = "100%-36"
local ROW_HEIGHT = 40
local ROW_IMAGE_SIZE = 32
local ROW_INDENT = 24

--- The name takes whatever the image, the stepper and the margins leave, which
--- is what lands every stepper in the same column. An indented row gives up the
--- indent from its name so its stepper does not shift with it.
local NAME_WIDTH = "100%-180"
local NAME_WIDTH_INDENTED = "100%-204"

--- A "- [n] +" stepper over a bounded integer
--- The well holds no state of its own: every edit routes through set() and the
--- text is read back from get(), so the caller stays the only place the number
--- lives.
--- @param args table get, set, min and max
--- @return Panel
local function Stepper(args)
    local well

    local function Commit(value)
        local n = math.floor(tonumber(value) or args.min)
        n = math.max(args.min, math.min(args.max, n))
        args.set(n)
        if well ~= nil and well.valid then
            well.text = tostring(args.get())
        end
    end

    --An editable label rather than gui.Input: the theme sizes a form input at
    --180 wide, which is most of this dialog, and the well has to be narrow
    --enough that the + button still fits beside it.
    well = gui.Label{
        classes = {"number", "bordered"},
        width = STEPPER_WELL_WIDTH,
        height = 26,
        halign = "left",
        valign = "center",
        editable = true,
        numeric = true,
        characterLimit = 2,
        swallowPress = true,
        bgimage = true,
        border = 1,
        cornerRadius = 4,
        fontSize = 18,
        textAlignment = "center",
        text = tostring(args.get()),
        change = function(element)
            Commit(element.text)
        end,
    }

    return gui.Panel{
        width = STEPPER_WIDTH,
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",

        gui.Button{
            classes = {"sizeS"},
            width = STEPPER_BUTTON_WIDTH,
            minWidth = STEPPER_BUTTON_WIDTH,
            text = "-",
            valign = "center",
            press = function()
                Commit(args.get() - 1)
            end,
        },

        well,

        gui.Button{
            classes = {"sizeS"},
            width = STEPPER_BUTTON_WIDTH,
            minWidth = STEPPER_BUTTON_WIDTH,
            text = "+",
            valign = "center",
            press = function()
                Commit(args.get() + 1)
            end,
        },
    }
end

--- One character's row: who they are, and how many activities they hold
--- Indent sits a follower under the hero it belongs to.
--- @param args table token, indent, get and set
--- @return Panel
local function ActivityRow(args)
    return gui.Panel{
        classes = {"row"},
        --Stops short of the scrolling region's right edge, so the + button is
        --not painted under the scroll bar.
        width = ROW_WIDTH,
        height = ROW_HEIGHT,
        flow = "horizontal",
        halign = "left",
        valign = "top",

        --The indent shifts the image rather than padding the row, which would
        --widen it past 100% and push the stepper off the end.
        gui.CreateTokenImage(args.token, {
            width = ROW_IMAGE_SIZE,
            height = ROW_IMAGE_SIZE,
            halign = "left",
            valign = "center",
            lmargin = args.indent and ROW_INDENT or 0,
        }),

        gui.Label{
            classes = {"sizeM", "noBold"},
            width = args.indent and NAME_WIDTH_INDENTED or NAME_WIDTH,
            height = "auto",
            halign = "left",
            valign = "center",
            hmargin = 8,
            --A long name shortens rather than wrapping, which would push the
            --row taller than the rest of the list.
            textWrap = false,
            text = args.token.name or "Unnamed",
        },

        Stepper{
            get = args.get,
            set = args.set,
            min = 0,
            max = 99,
        },
    }
end

--- Shows the activities dialog for one hero
--- Nothing is written while the dialog is open: every edit lands in a table
--- here, and only Close spends it on the token. That is what lets Cancel leave
--- the character exactly as it found them.
--- @param token any The hero whose household this is
function DTActivitiesDialog.ShowDialog(token)
    if token == nil or token.properties == nil or not token.properties:IsHero() then
        return
    end

    local downtimeInfo = token.properties:GetDowntimeInfo()
    if downtimeInfo == nil then
        return
    end

    --What Close will write, keyed by whose it is. The hero holds the token's
    --own id, which no follower of theirs can collide with.
    local values = {}
    values[token.id] = downtimeInfo:GetAvailableRolls()

    local followers = {}
    local downtimeFollowers = token.properties:GetDowntimeFollowers()
    for followerId, follower in pairs(downtimeFollowers ~= nil and downtimeFollowers.followers or {}) do
        if IsDowntimeFollower(follower) then
            followers[#followers + 1] = follower
            values[followerId] = downtimeInfo:GetFollowerRolls(followerId)
        end
    end

    --The map they arrive in has no order of its own, so the list would shuffle
    --between openings without this.
    table.sort(followers, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    local function RowFor(rowToken, indent)
        local id = rowToken.id
        return ActivityRow{
            token = rowToken,
            indent = indent,
            get = function()
                return values[id] or 0
            end,
            set = function(n)
                values[id] = n
            end,
        }
    end

    local rows = { RowFor(token, false) }
    for _, follower in ipairs(followers) do
        rows[#rows + 1] = RowFor(follower, true)
    end

    if #followers == 0 then
        rows[#rows + 1] = gui.Label{
            classes = {"sizeS", "fgMuted"},
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 8,
            text = "No artisans or sages to spend activities."
        }
    end

    local function Save()
        token:ModifyProperties{
            description = "Set Downtime Activities",
            undoable = false,
            execute = function()
                local info = token.properties:GetDowntimeInfo()
                if info == nil then
                    return
                end

                info:SetAvailableRolls(values[token.id] or 0)
                for _, follower in ipairs(followers) do
                    info:SetFollowerRolls(follower.id, values[follower.id] or 0)
                end
            end,
        }

        --The counters on the tab watch this document, so touching it is what
        --brings them up to date behind the closing dialog.
        DTSettings.Touch()
        gui.CloseModal()
    end

    gui.ShowModal(gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = {"dialog"},
        width = 560,
        height = 460,
        flow = "vertical",

        gui.Label{
            classes = {"modalTitle"},
            text = "Downtime Activities",
        },

        --However many followers a hero collects, the list scrolls rather than
        --growing the dialog past the screen.
        gui.Panel{
            width = "96%",
            height = "100%-124",
            halign = "center",
            valign = "top",
            flow = "vertical",
            vscroll = true,

            children = rows,
        },

        gui.Panel{
            width = "96%",
            height = 72,
            halign = "center",
            valign = "bottom",
            flow = "horizontal",

            gui.Button{
                classes = {"sizeL"},
                text = "Cancel",
                valign = "top",
                click = function()
                    gui.CloseModal()
                end,
            },

            gui.Button{
                classes = {"sizeL"},
                text = "Save",
                valign = "top",
                click = function()
                    Save()
                end,
            },
        },

        escape = function()
            gui.CloseModal()
        end,
    })
end
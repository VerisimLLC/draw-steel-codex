local mod = dmhub.GetModLoading()

--Encounter of the Week moderation: what a warned or banned player is shown
--when they come into the town, and the admins' tools to warn and ban.
--
--The City keeps the records and refuses a banned account the town's own
--actions (cloudflare-game-server src/city-core.ts, "Moderation"); this file
--only shows them. A game the player is already in is never touched: its
--city connection ignores the /moderation push, and the check runs only when
--the town is on screen.
--
--  * The town calls EotwModeration.CheckArrival(conn) on every connect, and
--    again when the City pushes /moderation (a warning or ban just issued).
--  * A ban closes the town and shows its message over the titlescreen; a
--    warning is shown over the town until the player acknowledges it.
--  * EncounterOfTheWeek.ShowScreen asks EotwModeration.HoldEntry first, so a
--    player already seen banned this run is turned away before the town loads.
--
--The admin dialogs are left in code (not UIText): only admins see them.

local T = UIText.T
local TP = UIText.Plural

EotwModeration = {}

--What an admin can do from the Warn or Ban dialog. days = nil on a ban is
--permanent.
local ACTIONS = {
    { id = "warning", text = "Warning (no ban)", kind = "warning" },
    { id = "ban1", text = "Ban for 1 day", kind = "ban", days = 1 },
    { id = "ban3", text = "Ban for 3 days", kind = "ban", days = 3 },
    { id = "ban7", text = "Ban for 7 days", kind = "ban", days = 7 },
    { id = "ban30", text = "Ban for 30 days", kind = "ban", days = 30 },
    { id = "permanent", text = "Ban permanently", kind = "ban" },
}

--True once this run has seen a ban in force on this account, so the next
--attempt to open the town asks the city before building it (HoldEntry).
local m_banSeen = false
--A moderation-status request is in flight; m_recheck asks for another
--after it (a push that arrived meanwhile may be newer than its answer).
local m_checking = false
local m_recheck = false
--The warning or ban dialog on screen, so a second check never stacks one.
local m_playerDialog = nil
--HoldEntry is asking the city on the player's behalf.
local m_holding = false

---- shared pieces --------------------------------------------------------

--The titlescreen root: player dialogs mount there, above the town screen
--and everything in it, and survive the town closing under them.
---@return Panel|nil
local function Root()
    local root = rawget(_G, "CodexTitlescreenRoot")
    if root == nil or not root.valid then
        return nil
    end
    return root
end

--The town screen's authoring scale (same math as CreateScreen), so a
--dialog on the root is the size of the town's own.
local function UiScale(root)
    local dialog = root.data.dialog
    if dialog == nil then
        return 1
    end
    local uiscale = dialog.width / 1920
    if 1920 * (dialog.height / dialog.width) < 1080 then
        uiscale = dialog.height / 1080
    end
    return uiscale
end

local function FormatDate(ms)
    if type(ms) ~= "number" then
        return "?"
    end
    return os.date("%b %d %Y, %H:%M", math.floor(ms / 1000)) --[[@as string]]
end

--A full-screen overlay holding one centered card: the backdrop swallows
--clicks, so nothing under it can be used while it is up. args: title,
--children, buttons, escape, width.
local function Overlay(root, args)
    return gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        styles = { Styles.Default },

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            args.escape(element)
        end,

        gui.Panel{
            width = args.width or 760,
            height = "auto",
            halign = "center",
            valign = "center",
            uiscale = UiScale(root),
            bgimage = "panels/square.png",
            bgcolor = "#14110dff",
            borderWidth = 2,
            borderColor = "#8c7a55",
            cornerRadius = 10,
            flow = "vertical",
            pad = 20,
            borderBox = true,

            gui.Label{
                text = args.title,
                fontSize = 30,
                bold = true,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                textWrap = true,
                vmargin = 8,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                maxHeight = 640,
                vscroll = true,
                flow = "vertical",
                rpad = 12,
                borderBox = true,
                vmargin = 8,
                children = args.children,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                flow = "horizontal",
                vmargin = 8,
                children = args.buttons,
            },
        },
    }
end

--Text shown as typed: rich-text tags in it are not applied (as the town chat).
local function Plain(text)
    return "<noparse>" .. string.gsub(tostring(text or ""), "</?[nN][oO][pP][aA][rR][sS][eE]>", "") .. "</noparse>"
end

local function Text(text, fontSize, color, extra)
    local args = {
        text = text,
        fontSize = fontSize or 18,
        color = color or Styles.textColor,
        width = "100%",
        height = "auto",
        textWrap = true,
        vmargin = 4,
    }
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Label(args)
end

--The admin's words, shown as typed (rich-text tags in them are not applied).
local function Quoted(message)
    return Text(Plain(message), 20, "#efe4cc", {
        italics = true,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff0e",
        cornerRadius = 8,
        pad = 12,
        borderBox = true,
    })
end

local function CloseDialog()
    if m_playerDialog ~= nil and m_playerDialog.valid then
        m_playerDialog:DestroySelf()
    end
    m_playerDialog = nil
end

---- what the player sees -------------------------------------------------

--"for 3 more days", "permanently"... from the server's own count of the
--time left, so a wrong clock on this machine cannot misreport it.
local function BanLengthText(ban)
    if type(ban.remainingMs) ~= "number" then
        return T("moderation.ban.length_permanent")
    end
    local hours = ban.remainingMs / 3600000
    if hours < 1 then
        return T("moderation.ban.length_under_an_hour")
    end
    if hours < 48 then
        return TP("moderation.ban.length_hours", math.ceil(hours))
    end
    return TP("moderation.ban.length_days", math.ceil(hours / 24))
end

--The ban's message over the titlescreen. The town is already closed.
local function ShowBan(ban)
    local root = Root()
    if root == nil then
        return
    end
    CloseDialog()
    local note = type(ban.remainingMs) == "number" and T("moderation.ban.come_back_note") or nil
    local dlg
    dlg = Overlay(root, {
        title = T("moderation.ban.title"),
        escape = function()
            CloseDialog()
        end,
        children = {
            Text(T("moderation.ban.body", { length = BanLengthText(ban) }), 20),
            Text(T("moderation.message_heading"), 16, "#b8ad96", { tmargin = 12 }),
            Quoted(ban.message),
            note ~= nil and Text(note, 16, "#b8ad96", { tmargin = 12 }) or nil,
        },
        buttons = {
            gui.Button{
                text = T("moderation.ban.ok_button"),
                fontSize = 20,
                width = 200,
                height = 44,
                click = function()
                    CloseDialog()
                end,
            },
        },
    })
    m_playerDialog = dlg
    root:AddChild(dlg)
end

--The warnings the player has not read, one at a time, over the town. Each
--is acknowledged as it is dismissed; one whose acknowledgement does not
--reach the city simply shows again next time.
local function ShowWarnings(conn, warnings, index)
    local warning = warnings[index]
    local root = Root()
    if warning == nil or root == nil or not EncounterOfTheWeek.IsScreenOpen() then
        CloseDialog()
        return
    end
    CloseDialog()
    local function Dismiss()
        if conn ~= nil and conn.connected then
            conn:Request{
                action = "acknowledge-warning",
                args = { id = warning.id },
                error = function(message)
                    printf("EotW moderation: could not acknowledge a warning: %s", tostring(message))
                end,
            }
        end
        ShowWarnings(conn, warnings, index + 1)
    end
    --a hero the moderators scrubbed comes as the same kind of notice, with
    --its own words; its message is optional.
    local removal = warning.kind == "removal"
    local children
    if removal then
        children = {
            Text(T("moderation.removal.body", { hero = Plain(warning.subject or "") }), 20),
        }
        if type(warning.message) == "string" and warning.message:match("%S") ~= nil then
            children[#children + 1] = Text(T("moderation.message_heading"), 16, "#b8ad96", { tmargin = 12 })
            children[#children + 1] = Quoted(warning.message)
        end
    else
        children = {
            Text(T("moderation.warning.body"), 20),
            Text(T("moderation.message_heading"), 16, "#b8ad96", { tmargin = 12 }),
            Quoted(warning.message),
        }
    end
    children[#children + 1] = Text(T("moderation.warning.sent_on", { date = FormatDate(warning.at) }), 15, "#b8ad96", { tmargin = 8 })
    local dlg
    dlg = Overlay(root, {
        title = cond(removal, T("moderation.removal.title"), T("moderation.warning.title")),
        escape = Dismiss,
        children = children,
        buttons = {
            gui.Button{
                text = T("moderation.warning.ok_button"),
                fontSize = 20,
                width = 200,
                height = 44,
                click = Dismiss,
            },
        },
    })
    m_playerDialog = dlg
    root:AddChild(dlg)
end

local function ApplyStatus(conn, status)
    if type(status) ~= "table" then
        return
    end
    if type(status.ban) == "table" then
        m_banSeen = true
        --a game the player is in keeps going: only a town on screen (or
        --opening) is closed. CloseScreen leaves a hidden one alone.
        EncounterOfTheWeek.CloseScreen()
        ShowBan(status.ban)
        return
    end
    m_banSeen = false
    local warnings = type(status.warnings) == "table" and status.warnings or {}
    if #warnings == 0 then
        return
    end
    --a town still behind its loading veil shows the warning once revealed.
    local screen = EncounterOfTheWeek.TownScreen()
    if screen ~= nil and screen:HasClass("eotwOpening") then
        dmhub.Schedule(1, function()
            if not mod.unloaded then
                ApplyStatus(conn, status)
            end
        end)
        return
    end
    if m_playerDialog ~= nil and m_playerDialog.valid then
        --already showing them; the rest come one by one.
        return
    end
    ShowWarnings(conn, warnings, 1)
end

--Ask the city what this account must be shown, and show it. The town calls
--this on every connect and when the city pushes /moderation.
function EotwModeration.CheckArrival(conn)
    if conn == nil or not conn.connected then
        return
    end
    if m_checking then
        m_recheck = true
        return
    end
    m_checking = true
    conn:Request{
        action = "moderation-status",
        success = function(status)
            m_checking = false
            if mod.unloaded then
                return
            end
            ApplyStatus(conn, status)
            if m_recheck then
                m_recheck = false
                EotwModeration.CheckArrival(conn)
            end
        end,
        error = function(message)
            m_checking = false
            m_recheck = false
            --a city from before moderation answers "Unknown action".
            printf("EotW moderation: could not read the moderation status: %s", tostring(message))
        end,
    }
end

--Called by EncounterOfTheWeek.ShowScreen before it builds the town. Returns
--true when it is handling the open itself: this run already saw the
--account banned, so it asks the city first, shows the ban if it still
--stands, and otherwise calls `reopen` (the town's own check runs as usual).
function EotwModeration.HoldEntry(reopen)
    if not m_banSeen then
        return false
    end
    if m_holding then
        return true
    end
    m_holding = true
    EncounterOfTheWeek.CityRequest("moderation-status", nil, function(ok, status)
        m_holding = false
        if mod.unloaded then
            return
        end
        if ok and type(status) == "table" and type(status.ban) == "table" then
            ShowBan(status.ban)
            return
        end
        --lifted or ended (or the city could not be asked): let the town open
        --and check on its own connection.
        m_banSeen = false
        reopen()
    end)
    return true
end

---- the admins' tools ----------------------------------------------------

local m_adminDialog = nil

--Warn or ban one account. args: userid, name (display name, may be empty),
--onDone (after a sanction is issued).
function EotwModeration.ShowIssueDialog(args)
    local root = Root()
    if root == nil or not dmhub.isAdminAccount then
        return
    end
    local userid = args.userid
    local name = args.name ~= nil and args.name ~= "" and args.name or userid
    local m_action = "warning"
    local m_message = ""
    local m_sending = false
    local statusLabel = nil

    local function SetStatus(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    local options = {}
    for _, a in ipairs(ACTIONS) do
        options[#options + 1] = { id = a.id, text = a.text }
    end

    local dlg
    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end
    dlg = Overlay(root, {
        title = "Warn or Ban " .. Plain(name),
        width = 700,
        escape = Close,
        children = {
            Text("Account: " .. Plain(userid), 15, "#b8ad96"),
            Text("The player sees your message the next time they arrive in town (at once if they are there now). A ban also sends them back to the titlescreen and keeps them out until it ends; a game they are already in carries on and its results count. They are taken out of any party still forming.", 15, "#b8ad96"),
            gui.Dropdown{
                width = 300,
                height = 36,
                fontSize = 18,
                vmargin = 8,
                --the open list needs the themed sheet; the titlescreen's
                --legacy styles leave it as bare labels.
                styles = ThemeEngine.GetStyles(),
                options = options,
                idChosen = m_action,
                change = function(element)
                    ---@cast element Dropdown
                    m_action = tostring(element.idChosen)
                end,
            },
            Text("Message to the player (they see it word for word):", 16, nil, { tmargin = 8 }),
            gui.Input{
                width = "100%",
                height = 130,
                fontSize = 17,
                multiline = true,
                textAlignment = "topleft",
                characterLimit = 1000,
                placeholderText = "What they did, and what is expected of them...",
                change = function(element)
                    m_message = element.text or ""
                end,
            },
            gui.Label{
                text = "",
                fontSize = 16,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                minHeight = 22,
                textWrap = true,
                textAlignment = "center",
                vmargin = 4,
                create = function(element)
                    statusLabel = element
                end,
            },
        },
        buttons = {
            gui.Button{
                text = "Send",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 8,
                data = { confirming = false },
                resetConfirm = function(element)
                    element.data.confirming = false
                    element.text = "Send"
                end,
                click = function(element)
                    if m_sending then
                        return
                    end
                    if m_message:match("%S") == nil then
                        SetStatus("Write a message for the player first.", true)
                        return
                    end
                    local chosen = nil
                    for _, a in ipairs(ACTIONS) do
                        if a.id == m_action then
                            chosen = a
                        end
                    end
                    if chosen == nil then
                        return
                    end
                    --a ban is hard to walk back in the player's eyes: confirm it.
                    if chosen.kind == "ban" and not element.data.confirming then
                        element.data.confirming = true
                        element.text = "Click to confirm"
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    m_sending = true
                    SetStatus("Sending...")
                    EncounterOfTheWeek.CityRequest("moderate", {
                        userid = userid,
                        name = args.name or "",
                        kind = chosen.kind,
                        message = m_message,
                        days = chosen.days,
                    }, function(ok, result)
                        m_sending = false
                        if not ok then
                            SetStatus("Could not send it: " .. tostring(result), true)
                            return
                        end
                        printf("EotW moderation: %s sent to %s (%s)", chosen.text, name, userid)
                        Close()
                        if args.onDone ~= nil then
                            args.onDone()
                        end
                    end)
                end,
            },
            gui.Button{
                text = "Cancel",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 8,
                click = Close,
            },
        },
    })
    root:AddChild(dlg)
end

--One sanction in the admin list.
local function SanctionRow(s, onLift)
    local what
    if s.kind == "warning" then
        local state = "unread"
        if s.liftedAt ~= nil then
            state = "withdrawn"
        elseif s.seenAt ~= nil then
            state = "read " .. FormatDate(s.seenAt)
        end
        what = string.format("Warning (%s)", state)
    else
        local length = s["until"] == nil and "permanent" or ("until " .. FormatDate(s["until"]))
        local state = ""
        if s.liftedAt ~= nil then
            state = ", lifted " .. FormatDate(s.liftedAt)
        elseif not s.active then
            state = ", ended"
        end
        what = string.format("Ban, %s%s", length, state)
    end
    local who = s.name ~= nil and s.name ~= "" and s.name or "?"
    local canLift = s.active == true
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = cond(s.active, "#ffffff14", "#ffffff08"),
        cornerRadius = 8,
        pad = 10,
        borderBox = true,
        vmargin = 3,
        gui.Panel{
            width = cond(canLift, "100%-130", "100%"),
            height = "auto",
            flow = "vertical",
            valign = "center",
            Text(string.format("<b>%s</b>  <color=#b8ad96><size=80%%>%s</size></color>", Plain(who), Plain(s.userid)), 18, nil, { vmargin = 1 }),
            Text(what, 15, cond(s.active, "#ffcc66", "#b8ad96"), { vmargin = 1 }),
            Text(Plain(s.message), 15, "#efe4cc", { italics = true, vmargin = 1 }),
            Text(string.format("by %s, %s", Plain(s.issuedByName or s.issuedBy or "?"), FormatDate(s.at)), 13, "#8c8270", { vmargin = 1 }),
        },
        gui.Button{
            classes = { cond(canLift, nil, "collapsed") },
            text = cond(s.kind == "ban", "Lift Ban", "Withdraw"),
            fontSize = 16,
            width = 120,
            height = 36,
            valign = "center",
            data = { confirming = false },
            resetConfirm = function(element)
                element.data.confirming = false
                element.text = cond(s.kind == "ban", "Lift Ban", "Withdraw")
            end,
            click = function(element)
                if not element.data.confirming then
                    element.data.confirming = true
                    element.text = "Confirm"
                    element:ScheduleEvent("resetConfirm", 4)
                    return
                end
                onLift(s)
            end,
        },
    }
end

--The admins' moderation dialog (Codex menu > Moderation..., town open):
--the players in town now, any account by id, and recent warnings and bans
--with Lift on the ones still in force.
function EotwModeration.ShowAdminDialog()
    local root = Root()
    if root == nil or not dmhub.isAdminAccount then
        return
    end
    if m_adminDialog ~= nil and m_adminDialog.valid then
        return
    end

    local presentPanel = nil
    local listPanel = nil
    local statusLabel = nil
    local m_userid = ""

    local function SetStatus(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    local Reload

    local function Issue(userid, name)
        EotwModeration.ShowIssueDialog{ userid = userid, name = name, onDone = function() Reload() end }
    end

    local function RebuildPresent()
        if presentPanel == nil or not presentPanel.valid then
            return
        end
        local conn = EotwRoster.Connection()
        local presence = conn ~= nil and conn:GetPath("/presence") or nil
        local people = {}
        for userid, entry in pairs(presence or {}) do
            if userid ~= dmhub.loginUserid then
                people[#people + 1] = { userid = userid, name = tostring(entry.name or "?") }
            end
        end
        table.sort(people, function(a, b) return a.name:lower() < b.name:lower() end)
        local rows = {}
        for _, p in ipairs(people) do
            rows[#rows + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 2,
                Text(string.format("%s  <color=#b8ad96><size=80%%>%s</size></color>", Plain(p.name), Plain(p.userid)), 17, nil, { width = "100%-140", valign = "center" }),
                gui.Button{
                    text = "Warn / Ban...",
                    fontSize = 15,
                    width = 130,
                    height = 32,
                    valign = "center",
                    click = function()
                        Issue(p.userid, p.name)
                    end,
                },
            }
        end
        if #rows == 0 then
            rows[1] = Text("Nobody else is in town.", 15, "#b8ad96")
        end
        presentPanel.children = rows
    end

    Reload = function()
        RebuildPresent()
        SetStatus("Loading warnings and bans...")
        EncounterOfTheWeek.CityRequest("list-sanctions", nil, function(ok, result)
            if listPanel == nil or not listPanel.valid then
                return
            end
            if not ok then
                SetStatus("Could not load them: " .. tostring(result), true)
                return
            end
            SetStatus("")
            local rows = {}
            for _, s in ipairs(type(result) == "table" and result.sanctions or {}) do
                rows[#rows + 1] = SanctionRow(s, function(sanction)
                    SetStatus("Lifting...")
                    EncounterOfTheWeek.CityRequest("lift-sanction", { id = sanction.id }, function(okLift, liftResult)
                        if not okLift then
                            SetStatus("Could not lift it: " .. tostring(liftResult), true)
                            return
                        end
                        Reload()
                    end)
                end)
            end
            if #rows == 0 then
                rows[1] = Text("No warnings or bans yet.", 15, "#b8ad96")
            end
            listPanel.children = rows
        end)
    end

    local function Heading(text)
        return Text(text, 20, "#d9b56a", { bold = true, tmargin = 10 })
    end

    local dlg
    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end
    dlg = Overlay(root, {
        title = "Moderation",
        width = 900,
        escape = Close,
        children = {
            Heading("In town now"),
            gui.Panel{
                width = "100%",
                height = "auto",
                maxHeight = 220,
                vscroll = true,
                flow = "vertical",
                create = function(element)
                    presentPanel = element
                end,
            },
            Heading("Any account"),
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Input{
                    width = "100%-140",
                    height = 34,
                    fontSize = 16,
                    valign = "center",
                    placeholderText = "User id (from a chat line's right-click, or the account)",
                    change = function(element)
                        m_userid = (element.text or ""):match("^%s*(.-)%s*$")
                    end,
                },
                gui.Button{
                    text = "Warn / Ban...",
                    fontSize = 15,
                    width = 130,
                    height = 34,
                    valign = "center",
                    click = function()
                        if m_userid == "" then
                            SetStatus("Enter a user id first.", true)
                            return
                        end
                        Issue(m_userid, "")
                    end,
                },
            },
            Heading("Recent warnings and bans"),
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    listPanel = element
                end,
            },
            gui.Label{
                text = "",
                fontSize = 16,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                minHeight = 22,
                textAlignment = "center",
                textWrap = true,
                create = function(element)
                    statusLabel = element
                end,
            },
        },
        buttons = {
            gui.Button{
                text = "Close",
                fontSize = 20,
                width = 140,
                height = 42,
                click = Close,
            },
        },
    })
    m_adminDialog = dlg
    root:AddChild(dlg)
    Reload()
end

--Context-menu rows for a town chat line written by `userid` (admins only;
--empty otherwise). Used by the town's chat drawer.
function EotwModeration.ChatLineMenu(userid, name)
    if not dmhub.isAdminAccount or type(userid) ~= "string" or userid == "" or userid == dmhub.loginUserid then
        return {}
    end
    return {
        {
            text = string.format("Warn or Ban %s...", tostring(name or "?")),
            click = function()
                EotwModeration.ShowIssueDialog{ userid = userid, name = name }
            end,
        },
        {
            text = "Copy User Id",
            click = function()
                dmhub.CopyToClipboard(userid)
            end,
        },
    }
end

---- scrubbing a hero ------------------------------------------------------

--Remove one hero from the Encounter of the Week entirely: its owner's
--roster, the Graveyard and every Hall of Heroes entry its party is in. The
--owner is shown a notice (with the optional message) next time they arrive.
--args: userid, heroid, heroName, ownerName, onDone.
function EotwModeration.ShowScrubDialog(args)
    local root = Root()
    if root == nil or not dmhub.isAdminAccount then
        return
    end
    local heroName = args.heroName ~= nil and args.heroName ~= "" and args.heroName or args.heroid
    local m_message = ""
    local m_sending = false
    local statusLabel = nil

    local function SetStatus(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    local dlg
    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end
    dlg = Overlay(root, {
        title = "Remove " .. Plain(heroName) .. " from Encounter of the Week",
        width = 700,
        escape = Close,
        children = {
            Text("Owner: " .. Plain(args.ownerName or "?") .. "  <color=#b8ad96><size=80%>" .. Plain(args.userid) .. "</size></color>", 16),
            Text("This deletes the hero for good: from its owner's roster, the Graveyard and any Hall of Heroes entry its party is in (the whole entry goes). A party still forming loses the hero; a game it is in now carries on. It cannot be undone. The owner is told the hero was removed, with your message if you write one.", 15, "#b8ad96"),
            Text("Message to the owner (optional):", 16, nil, { tmargin = 8 }),
            gui.Input{
                width = "100%",
                height = 100,
                fontSize = 17,
                multiline = true,
                textAlignment = "topleft",
                characterLimit = 1000,
                placeholderText = "e.g. This name is not allowed in Blackbottom.",
                change = function(element)
                    m_message = element.text or ""
                end,
            },
            gui.Label{
                text = "",
                fontSize = 16,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                minHeight = 22,
                textWrap = true,
                textAlignment = "center",
                vmargin = 4,
                create = function(element)
                    statusLabel = element
                end,
            },
        },
        buttons = {
            gui.Button{
                text = "Remove Hero",
                fontSize = 20,
                width = 180,
                height = 44,
                hmargin = 8,
                data = { confirming = false },
                resetConfirm = function(element)
                    element.data.confirming = false
                    element.text = "Remove Hero"
                end,
                click = function(element)
                    if m_sending then
                        return
                    end
                    if not element.data.confirming then
                        element.data.confirming = true
                        element.text = "Click to confirm"
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    m_sending = true
                    SetStatus("Removing...")
                    EncounterOfTheWeek.CityRequest("scrub-hero", {
                        userid = args.userid,
                        heroid = args.heroid,
                        ownerName = args.ownerName or "",
                        message = m_message,
                    }, function(ok, result)
                        m_sending = false
                        if not ok then
                            SetStatus("Could not remove it: " .. tostring(result), true)
                            return
                        end
                        printf("EotW moderation: removed hero %s (%s) of %s; %s Hall entries deleted",
                            tostring(heroName), tostring(args.heroid), tostring(args.userid), tostring(type(result) == "table" and result.hall or 0))
                        Close()
                        if args.onDone ~= nil then
                            args.onDone()
                        end
                    end)
                end,
            },
            gui.Button{
                text = "Cancel",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 8,
                click = Close,
            },
        },
    })
    root:AddChild(dlg)
end

--Context-menu rows for a player's hero (admins only; empty otherwise):
--remove it, warn or ban its owner, copy the owner's user id.
--args: userid, heroid, heroName, ownerName, onScrubbed.
function EotwModeration.HeroMenu(args)
    if not dmhub.isAdminAccount or type(args.userid) ~= "string" or args.userid == "" or type(args.heroid) ~= "string" then
        return {}
    end
    local owner = args.ownerName ~= nil and args.ownerName ~= "" and args.ownerName or args.userid
    local entries = {
        {
            text = string.format("Remove %s from EotW...", tostring(args.heroName or "hero")),
            click = function()
                EotwModeration.ShowScrubDialog{
                    userid = args.userid,
                    heroid = args.heroid,
                    heroName = args.heroName,
                    ownerName = args.ownerName,
                    onDone = args.onScrubbed,
                }
            end,
        },
    }
    --admins cannot be warned or banned (the city refuses), so skip it for yourself.
    if args.userid ~= dmhub.loginUserid then
        entries[#entries + 1] = {
            text = string.format("Warn or Ban %s...", tostring(owner)),
            click = function()
                EotwModeration.ShowIssueDialog{ userid = args.userid, name = args.ownerName }
            end,
        }
    end
    entries[#entries + 1] = {
        text = "Copy Owner's User Id",
        click = function()
            dmhub.CopyToClipboard(args.userid)
        end,
    }
    return entries
end

--Show HeroMenu's rows as a context menu on `element` (a rightClick handler).
function EotwModeration.PopupHeroMenu(element, args)
    local entries = EotwModeration.HeroMenu(args)
    if #entries == 0 then
        return
    end
    element.popup = gui.ContextMenu{
        width = 300,
        entries = entries,
        click = function() element.popup = nil end,
    }
end

--Admin hero search (the Guild's Find Heroes button): every hero, living or
--fallen, whose name contains the search, or that belongs to a user id.
--Right-click a result to remove the hero or warn/ban its owner.
function EotwModeration.ShowFindHeroesDialog()
    local root = Root()
    if root == nil or not dmhub.isAdminAccount then
        return
    end
    local m_query = ""
    local resultsPanel = nil
    local statusLabel = nil

    local function SetStatus(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    --a name for each owner who is in town now (heroes carry only the user id).
    local function OwnerNames()
        local names = {}
        local conn = EotwRoster.Connection()
        local presence = conn ~= nil and conn:GetPath("/presence") or nil
        for userid, entry in pairs(presence or {}) do
            names[userid] = entry.name
        end
        return names
    end

    local Search
    Search = function()
        if m_query:len() < 2 then
            SetStatus("Type at least 2 characters.", true)
            return
        end
        SetStatus("Searching...")
        EncounterOfTheWeek.CityRequest("find-heroes", { query = m_query }, function(ok, result)
            if resultsPanel == nil or not resultsPanel.valid then
                return
            end
            if not ok then
                SetStatus("Could not search: " .. tostring(result), true)
                return
            end
            local heroes = type(result) == "table" and result.heroes or {}
            if #heroes == 0 then
                SetStatus("No heroes match.")
            elseif result.more then
                SetStatus("Showing the first 50; narrow the search.")
            else
                SetStatus("")
            end
            local owners = OwnerNames()
            local rows = {}
            for _, hero in ipairs(heroes) do
                local summary = type(hero.summary) == "table" and hero.summary or {}
                local name = tostring(summary.name or "?")
                local ownerName = owners[hero.userid]
                local details = EotwRoster.FormatDetails(summary.level, summary.ancestry, summary.className)
                rows[#rows + 1] = gui.Panel{
                    classes = { "eotwFoundHero" },
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    bgimage = "panels/square.png",
                    cornerRadius = 8,
                    pad = 10,
                    borderBox = true,
                    vmargin = 3,
                    styles = {
                        { selectors = { "eotwFoundHero" }, bgcolor = "#ffffff0a" },
                        { selectors = { "eotwFoundHero", "hover" }, bgcolor = "#ffffff1a" },
                    },
                    rightClick = function(element)
                        EotwModeration.PopupHeroMenu(element, {
                            userid = hero.userid,
                            heroid = hero.heroid,
                            heroName = name,
                            ownerName = ownerName,
                            onScrubbed = Search,
                        })
                    end,
                    Text(string.format("<b>%s</b>%s", Plain(name), cond(hero.status == "fallen", "  <color=#b8ad96>(fallen)</color>", "")), 19, nil, { vmargin = 1, interactable = false }),
                    Text(Plain(details or ""), 14, "#b8ad96", { vmargin = 1, interactable = false }),
                    Text("Owner: " .. Plain(ownerName or "not in town") .. "  <color=#8c8270>" .. Plain(hero.userid) .. "</color>", 14, "#b8ad96", { vmargin = 1, interactable = false }),
                }
            end
            resultsPanel.children = rows
        end)
    end

    local dlg
    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end
    dlg = Overlay(root, {
        title = "Find Heroes",
        width = 820,
        escape = Close,
        children = {
            Text("Search every hero in Blackbottom, living or fallen, by part of its name or by its owner's user id. Right-click a hero to remove it or to warn or ban its owner.", 15, "#b8ad96"),
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 6,
                gui.Input{
                    width = "100%-140",
                    height = 36,
                    fontSize = 17,
                    valign = "center",
                    placeholderText = "Hero name, or a user id",
                    change = function(element)
                        m_query = (element.text or ""):match("^%s*(.-)%s*$")
                    end,
                },
                gui.Button{
                    text = "Search",
                    fontSize = 17,
                    width = 130,
                    height = 36,
                    valign = "center",
                    click = function()
                        Search()
                    end,
                },
            },
            gui.Label{
                text = "",
                fontSize = 16,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                minHeight = 22,
                textWrap = true,
                textAlignment = "center",
                create = function(element)
                    statusLabel = element
                end,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    resultsPanel = element
                end,
            },
        },
        buttons = {
            gui.Button{
                text = "Close",
                fontSize = 20,
                width = 140,
                height = 42,
                click = Close,
            },
        },
    })
    root:AddChild(dlg)
end

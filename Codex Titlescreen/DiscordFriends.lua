local mod = dmhub.GetModLoading()

--Discord friends and direct messages, opened from a rail-style Discord button
--in the titlescreen's top-right corner (CodexTitlescreen.lua places it).
--
--Everything is read live from the engine (dmhub.DiscordGetRelationships,
--dmhub.DiscordGetMessages; engine side in DiscordControllerSocial.cs) and
--nothing about friends is stored here: Discord's rules forbid keeping a copy,
--and unlinking must empty the list, which it does because an unlinked account
--has no relationships. The panel polls two counters in dmhub.discordStatus
--(socialRevision, messageRevision) and re-reads when one moves.
--
--Without a linked account the button still shows; clicking it calls the
--caller's offerLink (the titlescreen opens its Discord link offer).
--
--Views: Friends (grouped the way Discord groups them: in the Codex, online
--elsewhere, offline), Pending (requests both ways; its tab shows only while
--there are any), Settings (the header's gear: blocked users), plus a chat
--view per friend. Destructive actions (remove, block, unlink) confirm in a
--strip inside the panel, so nothing depends on a game HUD being present.

---@class DiscordFriendsModule
DiscordFriends = {}

local PANEL_WIDTH = 400
local PANEL_HEIGHT = 640
local POLL_SECONDS = 0.25
local HISTORY_LIMIT = 50
local INVITE_MESSAGE = "Come play the Draw Steel Codex with me!"
local BUTTON_SIZE = 40

--a message's text width: the panel less the message group's hpad either side.
local MESSAGE_WIDTH = PANEL_WIDTH - 24

--a message within this many seconds of the previous one by the same author
--joins its group instead of repeating the author line.
local GROUP_SECONDS = 5 * 60

--the open friends panel, if any.
local g_panel = nil

--every Discord button created, so a theme change can restyle them.
local g_buttons = {}

--- @return table
local function Status()
    local s = nil
    pcall(function() s = dmhub.discordStatus end)
    return s or {account = "off"}
end

--a build with Discord where linking can be offered.
local function Available(s)
    return s.account ~= "off" and s.account ~= "unsupported"
end

--"connecting" counts: a linked user's token is still being fetched.
local function Linked(s)
    return s.account == "ready" or s.account == "connecting"
end

--How each Discord status is drawn. A distinct glyph per status as well as a
--color, so it reads without color vision (the statusIcons accessibility rule).
local STATUS_INFO = {
    online = {icon = "phosphor/circle-fill.png", class = "dfStatusOnline", text = "Online"},
    streaming = {icon = "phosphor/circle-fill.png", class = "dfStatusOnline", text = "Streaming"},
    idle = {icon = "phosphor/moon-fill.png", class = "dfStatusIdle", text = "Idle"},
    dnd = {icon = "phosphor/minus-circle-fill.png", class = "dfStatusDnd", text = "Do Not Disturb"},
    offline = {icon = "phosphor/circle-bold.png", class = "dfStatusOffline", text = "Offline"},
}

local function StatusInfoFor(status)
    return STATUS_INFO[status or "offline"] or STATUS_INFO.offline
end

--The second line under a friend's name: what they are doing in the Codex
--(Discord only shares activity in our own game), else their status.
local function SubText(entry)
    if entry.relationship == "incoming" then
        return "Wants to be your friend"
    elseif entry.relationship == "outgoing" then
        return "Friend request sent"
    elseif entry.relationship == "blocked" then
        return "Blocked"
    end

    local activity = entry.activity
    if activity ~= nil then
        local parts = {}
        if activity.details ~= nil then parts[#parts + 1] = activity.details end
        if activity.state ~= nil then parts[#parts + 1] = activity.state end
        if #parts > 0 then
            return table.concat(parts, " - ")
        end
        return "In the Draw Steel Codex"
    end

    return StatusInfoFor(entry.status).text
end

local function FormatTime(seconds)
    local now = os.date("*t") --[[@as osdate]]
    local t = os.date("*t", math.floor(seconds)) --[[@as osdate]]
    if t.year == now.year and t.yday == now.yday then
        return os.date("%H:%M", math.floor(seconds)) --[[@as string]]
    end
    return os.date("%b %d, %H:%M", math.floor(seconds)) --[[@as string]]
end

--Panel styles. Colors are theme tokens except Discord's blurple on its logo,
--which is the brand mark and deliberately the same in every color scheme.
local function BuildStyles()
    return {
        {
            selectors = {"dfHeader"},
            flow = "horizontal",
            width = "100%",
            height = 44,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"dfBrand"},
            bgcolor = "#5865F2",
        },
        {
            selectors = {"dfTitle"},
            fontSize = 18,
            bold = true,
            color = "@fgStrong",
            width = "100% available",
            height = "auto",
            valign = "center",
            lmargin = 8,
        },
        --sizes only; the shared {tab} rule colors it. priority beats {tab}'s size.
        {
            selectors = {"dfTab"},
            width = "auto",
            minWidth = 80,
            height = 28,
            hpad = 10,
            borderBox = true,
            fontSize = 14,
            textAlignment = "center",
            priority = 5,
        },
        --clickable text: labels only take clicks with a bgimage behind them,
        --so this gives one that cannot be seen (scheme-independent on purpose).
        {
            selectors = {"dfHit"},
            bgimage = "panels/square.png",
            bgcolor = "#00000001",
        },
        --a quiet strip (add friend, confirmations) set apart from the list.
        {
            selectors = {"dfStrip"},
            flow = "vertical",
            width = "100%",
            height = "auto",
            bgimage = true,
            bgcolor = "@bgAlt",
            hpad = 12,
            vpad = 8,
            borderBox = true,
        },
        {
            selectors = {"dfStripText"},
            fontSize = 13,
            color = "@fg",
            width = "100%",
            height = "auto",
        },
        {
            selectors = {"dfStatusText"},
            fontSize = 12,
            italics = true,
            color = "@fgMuted",
            width = "100%",
            height = "auto",
            hpad = 12,
            borderBox = true,
            vmargin = 2,
        },
        {
            selectors = {"dfStatusText", "error"},
            color = "@danger",
        },
        --Row grammar (STYLE_GUIDE.md): transparent rows that surface on hover.
        {
            selectors = {"dfRow"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 48,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"dfRow", "hover"},
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = {"dfName"},
            fontSize = 14,
            color = "@fg",
            width = "100%",
            height = "auto",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        {
            selectors = {"dfName", "unread"},
            color = "@fgStrong",
            bold = true,
        },
        {
            selectors = {"dfSub"},
            fontSize = 11,
            color = "@fgMuted",
            width = "100%",
            height = "auto",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        {
            selectors = {"dfSub", "warning"},
            color = "@warning",
        },
        --Avatars: a round well that shows a person glyph until (or unless)
        --the Discord picture arrives on top of it.
        {
            selectors = {"dfAvatarHolder"},
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 16,
        },
        {
            selectors = {"dfAvatarFallback"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"dfAvatar"},
            bgcolor = "white",
            cornerRadius = 16,
        },
        {
            selectors = {"dfStatusRing"},
            bgimage = true,
            bgcolor = "@bg",
            cornerRadius = 7,
        },
        {
            selectors = {"dfStatusOnline"},
            bgcolor = "@success",
        },
        {
            selectors = {"dfStatusIdle"},
            bgcolor = "@warning",
        },
        {
            selectors = {"dfStatusDnd"},
            bgcolor = "@danger",
        },
        {
            selectors = {"dfStatusOffline"},
            bgcolor = "@fgMuted",
        },
        {
            selectors = {"dfBadge"},
            bgimage = true,
            bgcolor = "@danger",
            cornerRadius = 9,
            minWidth = 18,
            width = "auto",
            height = 18,
            hpad = 5,
            borderBox = true,
            fontSize = 11,
            bold = true,
            color = "@fgStrong",
            textAlignment = "center",
        },
        --Row chrome recedes until approached (STYLE_GUIDE.md).
        {
            selectors = {"buttonIcon", "parent:dfRowAction"},
            bgcolor = "@fgMuted",
            opacity = 0.6,
            priority = 10,
        },
        {
            selectors = {"buttonIcon", "parent:dfRowAction", "parent:hover"},
            bgcolor = "@fg",
            opacity = 1,
            priority = 15,
            transitionTime = 0.1,
        },
        --Section headers: the folder-header grammar from MapsPanel.lua.
        {
            selectors = {"dfSection"},
            flow = "horizontal",
            width = "100%",
            height = 28,
            tmargin = 8,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"dfSectionLabel"},
            fontSize = 13,
            bold = true,
            color = "@fg",
            width = "auto",
            height = "auto",
            valign = "center",
        },
        {
            selectors = {"dfSectionCount"},
            fontSize = 11,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"dfRule"},
            bgimage = true,
            bgcolor = "@border",
            opacity = 0.35,
            width = "100%",
            height = 1,
        },
        {
            selectors = {"dfEmpty"},
            fontSize = 13,
            color = "@fgMuted",
            width = "100%",
            height = "auto",
            hpad = 24,
            vmargin = 24,
            borderBox = true,
            textAlignment = "center",
        },
        --Chat.
        --a freshly loaded history, kept invisible until it has laid out.
        {
            selectors = {"dfSettling"},
            groupOpacity = 0,
        },
        {
            selectors = {"dfMsgGroup"},
            flow = "vertical",
            width = "100%",
            height = "auto",
            hpad = 12,
            tmargin = 8,
            borderBox = true,
        },
        {
            selectors = {"dfMsgAuthorRow"},
            flow = "horizontal",
            width = "100%",
            height = "auto",
        },
        {
            selectors = {"dfMsgAuthor"},
            fontSize = 13,
            bold = true,
            color = "@fgStrong",
            width = "auto",
            height = "auto",
            valign = "center",
        },
        {
            selectors = {"dfMsgTime"},
            fontSize = 10,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
        },
        {
            selectors = {"dfMsgText"},
            fontSize = 14,
            color = "@fg",
            width = "100%",
            height = "auto",
            vmargin = 1,
        },
        {
            selectors = {"dfMsgText", "pending"},
            color = "@fgPending",
        },
        {
            selectors = {"dfNotice"},
            fontSize = 11,
            italics = true,
            color = "@fgMuted",
            width = "100%",
            height = "auto",
            hpad = 12,
            vmargin = 6,
            borderBox = true,
            textAlignment = "center",
        },
        {
            selectors = {"dfFooter"},
            flow = "horizontal",
            width = "100%",
            height = 36,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"dfFooterText"},
            fontSize = 12,
            color = "@fgMuted",
            width = "100% available",
            height = "auto",
            valign = "center",
            lmargin = 8,
            textWrap = false,
            textOverflow = "ellipsis",
        },
    }
end

--True once DocumentSystem (which loads after the titlescreen is built) has
--published the icon rail's styles.
local function RailStylesReady()
    local panelDocument = rawget(_G, "PanelDocument")
    return panelDocument ~= nil and panelDocument.IconRailStyles ~= nil
end

--The rail button's styles: the icon rail's own (so it matches the in-game
--rail exactly) plus the unread badge. rawget: PanelDocument lives in another
--file of the core codemod.
local function ButtonStyles()
    local result = {}
    local panelDocument = rawget(_G, "PanelDocument")
    if panelDocument ~= nil and panelDocument.IconRailStyles ~= nil then
        for _, rule in ipairs(panelDocument.IconRailStyles() or {}) do
            result[#result + 1] = rule
        end
    end
    local badgeRules = ThemeEngine.MergeTokens({
        {
            selectors = {"dfBadge"},
            bgimage = true,
            bgcolor = "@danger",
            cornerRadius = 8,
            minWidth = 16,
            width = "auto",
            height = 16,
            hpad = 4,
            borderBox = true,
            fontSize = 10,
            bold = true,
            color = "@fgStrong",
            textAlignment = "center",
        },
        --spelled out because the titlescreen's legacy cascade may not carry
        --the theme's generic hidden/collapsed rules.
        {
            selectors = {"dfBadge", "collapsed"},
            collapsed = 1,
        },
        {
            selectors = {"iconRailButton", "hidden"},
            hidden = 1,
        },
    })
    for _, rule in ipairs(badgeRules or {}) do
        result[#result + 1] = rule
    end
    return result
end

--A round avatar with the status glyph in a ring on its corner.
--  entry: a relationship (or {avatar, status}) from dmhub.DiscordGetRelationships.
--  size: diameter in pixels.
--  showStatus: false to leave the status ring off (our own avatar).
local function AvatarPanel(entry, size, showStatus)
    local info = StatusInfoFor(entry.status)
    local children = {
        gui.Panel{
            classes = {"dfAvatarFallback"},
            bgimage = "phosphor/user-circle-fill.png",
            width = size,
            height = size,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    if entry.avatar ~= nil then
        children[#children + 1] = gui.Panel{
            classes = {"dfAvatar"},
            floating = true,
            bgimage = entry.avatar,
            width = size,
            height = size,
            halign = "center",
            valign = "center",
            interactable = false,
            selfStyle = {cornerRadius = size / 2},
        }
    end
    if showStatus ~= false then
        children[#children + 1] = gui.Panel{
            classes = {"dfStatusRing"},
            floating = true,
            width = 14,
            height = 14,
            halign = "right",
            valign = "bottom",
            x = 2,
            y = 2,
            interactable = false,
            gui.Panel{
                classes = {info.class},
                bgimage = info.icon,
                width = 10,
                height = 10,
                halign = "center",
                valign = "center",
            },
        }
    end
    return gui.Panel{
        classes = {"dfAvatarHolder"},
        width = size,
        height = size,
        valign = "center",
        flow = "none",
        interactable = false,
        selfStyle = {cornerRadius = size / 2},
        children = children,
    }
end

--Builds the friends panel.
--  args.onClose: called after the panel is destroyed.
--  args.offerLink: opens the link offer (the panel shows it when unlinked).
local function CreatePanel(args)
    --Invite mode ({connect, title}): opened from a feature's own Invite button
    --(an Encounter of the Week party). Each friend row gets an Invite button
    --that invites them to that target rather than to our presence.
    local m_invite = args.invite
    --friend ids invited from this panel, so their button reads "Invited".
    local m_invited = {}
    --"friends", "pending", or "blocked" (the Settings view).
    local m_tab = "friends"
    local m_search = ""
    local m_entries = {}
    local m_socialRev = nil
    local m_messageRev = nil
    local m_account = nil
    local m_chat = nil          --the relationship entry being chatted with.
    local m_chatLoading = false
    local m_confirm = nil       --{text, button, run} while a confirmation shows.

    local root
    local tabBar
    local settingsBar
    local addStrip
    local addInput
    local addStatus
    local searchInput
    local confirmStrip
    local statusText
    local listPanel
    local listView
    local chatHeader
    local msgList
    local msgScroll
    local chatInput
    local chatView
    local footer

    local function SetStatus(text, isError)
        statusText.text = text or ""
        statusText:SetClass("collapsed", text == nil or text == "")
        statusText:SetClass("error", isError == true)
    end

    local function FindEntry(id)
        for _, entry in ipairs(m_entries) do
            if entry.id == id then
                return entry
            end
        end
        return nil
    end

    local RebuildList
    local OpenChat
    local CloseChat

    local function HideConfirm()
        m_confirm = nil
        confirmStrip:SetClass("collapsed", true)
    end

    --Asks for a yes inside the panel before something destructive.
    local function Confirm(text, buttonText, run)
        m_confirm = {run = run}
        confirmStrip.children = {
            gui.Label{
                classes = {"dfStripText"},
                text = text,
            },
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                tmargin = 6,
                gui.Button{
                    classes = {"sizeS"},
                    text = buttonText,
                    halign = "left",
                    click = function()
                        local confirm = m_confirm
                        HideConfirm()
                        if confirm ~= nil then
                            confirm.run()
                        end
                    end,
                },
                gui.Button{
                    classes = {"sizeS"},
                    text = "Cancel",
                    halign = "left",
                    lmargin = 8,
                    click = function()
                        HideConfirm()
                    end,
                },
            },
        }
        confirmStrip:SetClass("collapsed", false)
    end

    --Runs a relationship change and reports the outcome in the status line.
    local function RunAction(action, entry, doneText)
        SetStatus("Working...", false)
        local started = dmhub.DiscordRelationshipAction(action, entry.id, function(err)
            if not root.valid then
                return
            end
            if err ~= nil then
                SetStatus(err, true)
            else
                SetStatus(doneText, false)
            end
        end)
        if not started then
            SetStatus("Discord is not connected right now.", true)
        end
    end

    local function ReportOutcome(text, isError)
        if root.valid then
            SetStatus(text, isError)
        end
    end

    --Invites go through Discord and the Codex's invite store at once, so an
    --offline friend still gets it (DiscordFriends.SendInvite).
    local function Invite(entry)
        SetStatus("Sending invite...", false)
        DiscordFriends.SendInvite(entry, function(text, isError)
            if not isError then
                m_invited[entry.id] = true
                RebuildList()
            end
            ReportOutcome(text, isError)
        end, m_invite)
    end

    local function AskToJoin(entry)
        SetStatus("Asking to join...", false)
        DiscordFriends.AskToJoin(entry, ReportOutcome)
    end

    --a friend in a Codex game or party we could ask to join.
    local function CanAskToJoin(entry)
        return entry.relationship == "friend" and entry.activity ~= nil and entry.activity.joinable == true
    end

    local function ConfirmRemove(entry)
        Confirm(string.format("Remove %s from your Discord friends? This removes them in Discord too.", entry.displayName), "Remove", function()
            RunAction("remove", entry, string.format("%s is no longer your friend.", entry.displayName))
        end)
    end

    local function ConfirmBlock(entry)
        Confirm(string.format("Block %s? They will not be able to message you or send you friend requests, here or in Discord.", entry.displayName), "Block", function()
            if m_chat ~= nil and m_chat.id == entry.id then
                CloseChat()
            end
            RunAction("block", entry, string.format("%s is blocked.", entry.displayName))
        end)
    end

    --The right-click / "..." menu for a row.
    local function ShowMenu(element, entry)
        local s = Status()
        local entries = {}
        local function Add(text, fn)
            entries[#entries + 1] = {
                text = text,
                click = function()
                    element.popup = nil
                    fn()
                end,
            }
        end
        if entry.relationship == "friend" then
            Add("Message", function() OpenChat(entry) end)
            if m_invite ~= nil or s.joinable then
                Add(cond(m_invite ~= nil, "Invite", "Invite to Game"), function() Invite(entry) end)
            end
            if CanAskToJoin(entry) then
                Add("Ask to Join", function() AskToJoin(entry) end)
            end
            Add("Remove Friend...", function() ConfirmRemove(entry) end)
            Add("Block...", function() ConfirmBlock(entry) end)
        elseif entry.relationship == "incoming" then
            Add("Accept", function() RunAction("accept", entry, string.format("You and %s are now friends.", entry.displayName)) end)
            Add("Ignore", function() RunAction("reject", entry, "Request ignored.") end)
            Add("Block...", function() ConfirmBlock(entry) end)
        elseif entry.relationship == "outgoing" then
            Add("Cancel Request", function() RunAction("cancel", entry, "Request cancelled.") end)
        elseif entry.relationship == "blocked" then
            Add("Unblock", function() RunAction("unblock", entry, string.format("%s is unblocked.", entry.displayName)) end)
        end
        --like every codex context menu: its look comes from the globally
        --registered theme styles, so the popup does not inherit this panel's.
        element.popup = gui.ContextMenu{entries = entries}
    end

    local function RowActionButton(icon, tooltip, click, extraClass)
        return gui.Button{
            classes = {"sizeS", "dfRowAction", extraClass},
            icon = icon,
            tooltip = tooltip,
            valign = "center",
            lmargin = 4,
            click = click,
        }
    end

    local function FriendRow(entry)
        local isFriend = entry.relationship == "friend"
        local actions = {}
        if isFriend and m_invite ~= nil then
            local invited = m_invited[entry.id] == true
            actions[#actions + 1] = gui.Button{
                classes = {"sizeS"},
                text = cond(invited, "Invited", "Invite"),
                valign = "center",
                interactable = not invited,
                click = function()
                    Invite(entry)
                end,
            }
        end
        if isFriend then
            if CanAskToJoin(entry) then
                actions[#actions + 1] = RowActionButton("phosphor/sign-in-bold.png", "Ask to Join", function() AskToJoin(entry) end)
            end
            actions[#actions + 1] = RowActionButton("phosphor/chat-circle-dots.png", "Message", function() OpenChat(entry) end)
        elseif entry.relationship == "incoming" then
            actions[#actions + 1] = RowActionButton("phosphor/check-bold.png", "Accept", function()
                RunAction("accept", entry, string.format("You and %s are now friends.", entry.displayName))
            end, "withSuccess")
            actions[#actions + 1] = RowActionButton("phosphor/x-bold.png", "Ignore", function()
                RunAction("reject", entry, "Request ignored.")
            end, "withDanger")
        elseif entry.relationship == "outgoing" then
            actions[#actions + 1] = RowActionButton("phosphor/x-bold.png", "Cancel request", function()
                RunAction("cancel", entry, "Request cancelled.")
            end, "withDanger")
        elseif entry.relationship == "blocked" then
            actions[#actions + 1] = gui.Button{
                classes = {"sizeS"},
                text = "Unblock",
                valign = "center",
                click = function()
                    RunAction("unblock", entry, string.format("%s is unblocked.", entry.displayName))
                end,
            }
        end

        --blocked rows have only Unblock; a button built and not attached is a leak.
        if entry.relationship ~= "blocked" then
            local moreButton
            moreButton = RowActionButton("phosphor/dots-three-vertical-bold.png", "More", function()
                ShowMenu(moreButton, entry)
            end)
            actions[#actions + 1] = moreButton
        end

        local unread = entry.unread or 0
        local children = {
            AvatarPanel(entry, 32),
            gui.Panel{
                flow = "vertical",
                width = "100% available",
                height = "auto",
                valign = "center",
                lmargin = 10,
                interactable = false,
                gui.Label{
                    classes = {"dfName", cond(unread > 0, "unread")},
                    text = entry.displayName,
                },
                gui.Label{
                    classes = {"dfSub", cond(entry.spam, "warning")},
                    text = cond(entry.spam, "Possible spam - " .. SubText(entry), SubText(entry)),
                },
            },
        }
        if unread > 0 then
            children[#children + 1] = gui.Label{
                classes = {"dfBadge"},
                text = tostring(unread),
                valign = "center",
                lmargin = 4,
                interactable = false,
            }
        end
        for _, action in ipairs(actions) do
            children[#children + 1] = action
        end

        return gui.Panel{
            classes = {"dfRow"},
            click = function(element)
                if isFriend then
                    OpenChat(entry)
                end
            end,
            rightClick = function(element)
                ShowMenu(element, entry)
            end,
            children = children,
        }
    end

    --A group's heading. Returns {panel, count}: count is the label RebuildList
    --updates as the group's size changes.
    local function SectionHeader(text)
        local countLabel = gui.Label{
            classes = {"dfSectionCount"},
            text = "",
        }
        return {
            count = countLabel,
            panel = gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                gui.Panel{
                    classes = {"dfSection"},
                    gui.Label{
                        classes = {"dfSectionLabel"},
                        text = text,
                    },
                    countLabel,
                },
                gui.Panel{
                    classes = {"dfRule"},
                },
            },
        }
    end

    local function Matches(entry)
        if m_search == "" then
            return true
        end
        local needle = string.lower(m_search)
        return string.find(string.lower(entry.displayName or ""), needle, 1, true) ~= nil
            or string.find(string.lower(entry.username or ""), needle, 1, true) ~= nil
    end

    local function EmptyLabel(text)
        return gui.Label{
            classes = {"dfEmpty"},
            text = text,
        }
    end

    --The not-linked / connecting / error face of the list.
    local function AccountPlaceholder(s)
        if s.account == "connecting" then
            return {EmptyLabel("Connecting to Discord...")}
        end
        local text = "Link your Discord account to see your Discord friends here, message them, and let them see what you're playing and ask to join you."
        if s.account == "error" and s.accountError ~= nil then
            text = s.accountError
        end
        return {
            EmptyLabel(text),
            gui.Button{
                classes = {"sizeM"},
                text = "Link Discord",
                halign = "center",
                click = function()
                    if args.offerLink ~= nil then
                        args.offerLink()
                    else
                        dmhub.DiscordLink()
                    end
                end,
            },
        }
    end

    ---- The list ----
    --A few hundred friends is common, and Discord bumps socialRevision every
    --time any of them changes status, so the list is never rebuilt wholesale:
    --  - every relationship gets a fixed-height slot that lives as long as the
    --    relationship does; tabs and search collapse slots instead of removing
    --    them (removed panels are destroyed).
    --  - a slot's row is built only once it scrolls near the view
    --    (BuildVisibleRows), and rebuilt only when what it shows changes.

    local ROW_HEIGHT = 48
    local HEADER_HEIGHT = 37    --until a header has been laid out.

    --the sections in display order, with the tab each belongs to.
    local GROUPS = {
        {key = "playing", title = "IN THE CODEX", tab = "friends"},
        {key = "online", title = "ONLINE", tab = "friends"},
        {key = "offline", title = "OFFLINE", tab = "friends"},
        {key = "incoming", title = "RECEIVED", tab = "pending"},
        {key = "outgoing", title = "SENT", tab = "pending"},
        {key = "blocked", title = "BLOCKED", tab = "blocked"},
    }

    local m_slots = {}          --relationship id -> {panel, entry, sig, built, visible}
    local m_headers = {}        --group key -> SectionHeader result
    local m_layout = {}         --listPanel's items in order: {slot = ...} or {header = ...}
    local m_order = nil         --the ids in m_layout, to skip reassigning unchanged children.
    local m_emptyLabel = nil

    local function GroupKey(entry)
        if entry.relationship == "friend" then
            return entry.group or "offline"
        end
        return entry.relationship
    end

    --everything a row shows; the row is rebuilt when this changes.
    local function RowSignature(entry)
        return table.concat({
            entry.relationship or "",
            entry.displayName or "",
            entry.status or "",
            SubText(entry),
            tostring(entry.unread or 0),
            tostring(entry.spam == true),
            entry.avatar or "",
            tostring(entry.activity ~= nil and entry.activity.joinable == true),
            tostring(m_invited[entry.id] == true),
        }, "|")
    end

    --Builds the rows of slots within a viewport's height of what is on screen.
    --Rows and headers have known heights, so their positions are worked out
    --here rather than waiting for layout.
    local function BuildVisibleRows()
        if not listPanel.valid then
            return
        end
        local viewport = listPanel.renderedHeight
        if viewport == nil or viewport <= 0 then
            viewport = PANEL_HEIGHT
        end

        local function ItemHeight(item)
            if item.slot ~= nil then
                return cond(item.slot.visible, ROW_HEIGHT, 0)
            end
            if item.header.panel:HasClass("collapsed") then
                return 0
            end
            local h = item.header.panel.renderedHeight
            return cond(h ~= nil and h > 0, h, HEADER_HEIGHT)
        end

        local content = 0
        for _, item in ipairs(m_layout) do
            content = content + ItemHeight(item)
        end
        --vscrollPosition: 1 = top, 0 = bottom.
        local top = (1 - (listPanel.vscrollPosition or 1)) * math.max(0, content - viewport)
        local bandTop = top - viewport
        local bandBottom = top + viewport * 2

        local y = 0
        for _, item in ipairs(m_layout) do
            local h = ItemHeight(item)
            local slot = item.slot
            if slot ~= nil and h > 0 and not slot.built and y + h >= bandTop and y <= bandBottom then
                slot.built = true
                slot.panel.children = {FriendRow(slot.entry)}
            end
            y = y + h
            if y > bandBottom then
                break
            end
        end
    end

    local function ClearSlots()
        m_slots = {}
        m_headers = {}
        m_layout = {}
        m_order = nil
        m_emptyLabel = nil
    end

    RebuildList = function()
        local s = Status()
        if s.account ~= "ready" then
            ClearSlots()
            listPanel.children = AccountPlaceholder(s)
            return
        end
        if m_chat ~= nil then
            --the list is hidden behind the chat; CloseChat rebuilds it.
            return
        end

        --bucket the entries, creating or refreshing their slots.
        local buckets = {}
        local live = {}
        for _, entry in ipairs(m_entries) do
            local key = GroupKey(entry)
            buckets[key] = buckets[key] or {}
            local bucket = buckets[key]
            bucket[#bucket + 1] = entry
            live[entry.id] = true

            local slot = m_slots[entry.id]
            local sig = RowSignature(entry)
            if slot == nil or not slot.panel.valid then
                slot = {
                    entry = entry,
                    sig = sig,
                    built = false,
                    visible = true,
                    panel = gui.Panel{
                        width = "100%",
                        height = ROW_HEIGHT,
                    },
                }
                m_slots[entry.id] = slot
            else
                slot.entry = entry
                if slot.sig ~= sig then
                    slot.sig = sig
                    if slot.built then
                        slot.panel.children = {FriendRow(entry)}
                    end
                end
            end
        end
        for id, _ in pairs(m_slots) do
            if not live[id] then
                m_slots[id] = nil
            end
        end

        --lay the slots out in group order, showing only this tab's matches.
        local layout = {}
        local children = {}
        local order = {}
        local anyShown = false
        for _, group in ipairs(GROUPS) do
            local header = m_headers[group.key]
            if header == nil then
                header = SectionHeader(group.title)
                m_headers[group.key] = header
            end
            layout[#layout + 1] = {header = header}
            children[#children + 1] = header.panel
            order[#order + 1] = group.key

            local shown = 0
            for _, entry in ipairs(buckets[group.key] or {}) do
                local slot = m_slots[entry.id]
                slot.visible = group.tab == m_tab and Matches(entry)
                slot.panel:SetClass("collapsed", not slot.visible)
                if slot.visible then
                    shown = shown + 1
                end
                layout[#layout + 1] = {slot = slot}
                children[#children + 1] = slot.panel
                order[#order + 1] = entry.id
            end
            header.panel:SetClass("collapsed", shown == 0)
            header.count.text = tostring(shown)
            anyShown = anyShown or shown > 0
        end

        if m_emptyLabel == nil then
            m_emptyLabel = EmptyLabel("")
        end
        if m_tab == "friends" then
            m_emptyLabel.text = cond(m_search ~= "", "No friends match your search.", "No Discord friends yet. Add one with the + button above.")
        elseif m_tab == "pending" then
            m_emptyLabel.text = "No pending friend requests."
        else
            m_emptyLabel.text = "You have not blocked anyone."
        end
        m_emptyLabel:SetClass("collapsed", anyShown)
        children[#children + 1] = m_emptyLabel

        m_layout = layout
        local orderKey = table.concat(order, ",")
        if orderKey ~= m_order then
            m_order = orderKey
            listPanel.children = children
        end

        BuildVisibleRows()
    end

    --Shows the list's chrome for the current view. The tab bar only appears
    --while there are requests (Friends alone needs no tabs), and Settings
    --swaps it for a bar with a back button.
    local function RefreshTabs()
        local pending = 0
        local anyPending = false
        for _, entry in ipairs(m_entries) do
            if entry.relationship == "incoming" then
                pending = pending + 1
                anyPending = true
            elseif entry.relationship == "outgoing" then
                anyPending = true
            end
        end
        --the last request was answered: there is no Pending tab to stay on.
        if m_tab == "pending" and not anyPending then
            m_tab = "friends"
        end
        local inList = m_chat == nil
        tabBar:SetClass("collapsed", not (inList and anyPending and m_tab ~= "blocked"))
        settingsBar:SetClass("collapsed", not (inList and m_tab == "blocked"))
        searchInput:SetClass("collapsed", m_tab == "blocked")
        for _, child in ipairs(tabBar.children) do
            child:SetClass("selected", child.data.tab == m_tab)
            if child.data.tab == "pending" then
                child.text = cond(pending > 0, string.format("Pending (%d)", pending), "Pending")
            end
        end
    end

    local function ReadRelationships()
        m_entries = dmhub.DiscordGetRelationships() or {}
        RefreshTabs()
        RebuildList()
        if m_chat ~= nil then
            local fresh = FindEntry(m_chat.id)
            if fresh ~= nil then
                m_chat = fresh
                chatHeader:FireEvent("refreshChatHeader")
            end
        end
    end

    ---- Chat ----

    local function MessageGroup(first, authorName)
        return {
            author = first.authorId,
            last = first.sent,
            panel = nil,
            children = {
                gui.Panel{
                    classes = {"dfMsgAuthorRow"},
                    gui.Label{
                        classes = {"dfMsgAuthor"},
                        text = authorName,
                    },
                    gui.Label{
                        classes = {"dfMsgTime"},
                        text = FormatTime(first.sent),
                    },
                },
            },
        }
    end

    --One message's body: its text, with a Discord mark on messages written in
    --Discord itself (Discord asks that cross-platform messages be marked), and
    --a link for content the Codex cannot show.
    local function MessageBody(msg)
        local rows = {}
        if msg.content ~= nil and msg.content ~= "" then
            --a fixed width: a relative one starts near zero, so long messages
            --first wrap a letter per line and take many frames to settle.
            local label = gui.Label{
                classes = {"dfMsgText"},
                text = msg.content,
                markdown = false,
                width = cond(msg.sentFromGame, MESSAGE_WIDTH, MESSAGE_WIDTH - 18),
            }
            if msg.sentFromGame then
                rows[#rows + 1] = label
            else
                rows[#rows + 1] = gui.Panel{
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    gui.Panel{
                        classes = {"dfBrand"},
                        bgimage = "phosphor/discord-logo-fill.png",
                        width = 12,
                        height = 12,
                        valign = "top",
                        tmargin = 3,
                        rmargin = 6,
                        hover = gui.Tooltip("Sent from Discord"),
                    },
                    label,
                }
            end
        end
        if msg.hasAttachment then
            rows[#rows + 1] = gui.Label{
                classes = {"label", "link", "dfHit"},
                fontSize = 13,
                width = "auto",
                height = "auto",
                text = cond(msg.canOpenInDiscord, "Attachment - open in Discord", "Attachment (view it in Discord)"),
                click = function()
                    if msg.canOpenInDiscord then
                        dmhub.DiscordOpenMessageInDiscord(msg.id)
                    end
                end,
            }
        end
        return rows
    end

    --What the chat shows, so a refresh can append instead of rebuilding:
    --the shown message ids (id -> true), the newest one, and the open group.
    local m_shownIds = {}
    local m_lastShownId = nil
    local m_openGroup = nil     --{panel, author, last}
    local m_chatStale = false   --messages arrived while a fetch was running.

    --Keeps the chat pinned to its newest message until its height stops
    --changing. Long messages take a few frames to lay out, so scrolling once
    --lands mid-conversation. hideList also keeps the list invisible until
    --then, so it never shows half-laid-out.
    local m_settle = nil        --{height, stable, deadline}

    local function SettleToBottom(hideList)
        m_settle = {height = -1, stable = 0, deadline = dmhub.Time() + 1}
        msgList:SetClass("dfSettling", hideList == true)
        msgScroll.vscrollPosition = 0
    end

    local function ResetChatView(rows)
        m_shownIds = {}
        m_lastShownId = nil
        m_openGroup = nil
        msgList.children = rows
    end

    --Adds messages after what is shown, joining the open group when the same
    --author keeps writing.
    local function AppendMessages(messages)
        local s = Status()
        for _, msg in ipairs(messages) do
            m_shownIds[msg.id] = true
            m_lastShownId = msg.id
            if msg.disclosure then
                m_openGroup = nil
                msgList:AddChild(gui.Label{
                    classes = {"dfNotice"},
                    text = cond(msg.content ~= nil and msg.content ~= "", msg.content, "Messages in this conversation are also visible in Discord."),
                })
            else
                local group = m_openGroup
                if group == nil or not group.panel.valid or group.author ~= msg.authorId or msg.sent - group.last > GROUP_SECONDS then
                    local name = cond(msg.fromSelf, s.displayName or "You", m_chat ~= nil and m_chat.displayName or "")
                    local parts = MessageGroup(msg, name)
                    group = {
                        author = parts.author,
                        last = msg.sent,
                        panel = gui.Panel{
                            classes = {"dfMsgGroup"},
                            children = parts.children,
                        },
                    }
                    m_openGroup = group
                    msgList:AddChild(group.panel)
                end
                group.last = msg.sent
                for _, body in ipairs(MessageBody(msg)) do
                    group.panel:AddChild(body)
                end
            end
        end
    end

    --Shows a fetched history (oldest first). When it only adds to what is on
    --screen, the new messages are appended; otherwise the view is rebuilt.
    local function ShowMessages(messages)
        local newer = nil
        if m_lastShownId ~= nil then
            for i, msg in ipairs(messages) do
                if msg.id == m_lastShownId then
                    newer = {}
                    for j = i + 1, #messages do
                        if not m_shownIds[messages[j].id] then
                            newer[#newer + 1] = messages[j]
                        end
                    end
                    break
                end
            end
        end

        if newer ~= nil then
            if #newer > 0 then
                --follow new messages only when already reading the newest.
                local atBottom = (msgScroll.vscrollPosition or 0) < 0.02
                AppendMessages(newer)
                if atBottom then
                    SettleToBottom(false)
                end
            end
            return
        end

        if #messages == 0 then
            ResetChatView({EmptyLabel("No messages yet. Say hello!")})
            return
        end
        ResetChatView({})
        AppendMessages(messages)
        SettleToBottom(true)
    end

    local function FetchMessages()
        if m_chat == nil then
            return
        end
        if m_chatLoading then
            m_chatStale = true
            return
        end
        local chatId = m_chat.id
        m_chatLoading = true
        m_chatStale = false
        local started = dmhub.DiscordGetMessages(chatId, HISTORY_LIMIT, function(messages, err)
            m_chatLoading = false
            if not root.valid then
                return
            end
            if m_chat ~= nil and m_chat.id == chatId then
                if messages == nil then
                    ResetChatView({EmptyLabel(string.format("Could not load messages: %s", err or "unknown error"))})
                else
                    ShowMessages(messages)
                end
            end
            --also covers a chat opened while another one's history was loading.
            if m_chatStale then
                FetchMessages()
            end
        end)
        if not started then
            m_chatLoading = false
            ResetChatView({EmptyLabel("Discord is not connected right now.")})
        end
    end

    local function SendChat()
        if m_chat == nil then
            return
        end
        local text = chatInput.text or ""
        if string.find(text, "%S") == nil then
            return
        end
        local chatId = m_chat.id
        chatInput.text = ""
        SetStatus(nil)
        local started = dmhub.DiscordSendMessage(chatId, text, function(err)
            if not root.valid then
                return
            end
            if err ~= nil then
                --give the text back so it is not lost.
                if m_chat ~= nil and m_chat.id == chatId and (chatInput.text or "") == "" then
                    chatInput.text = text
                end
                SetStatus(string.format("Not sent: %s", err), true)
            end
        end)
        if not started then
            chatInput.text = text
            SetStatus("Discord is not connected right now.", true)
        end
    end

    OpenChat = function(entry)
        HideConfirm()
        SetStatus(nil)
        m_chat = entry
        dmhub.DiscordSetOpenConversation(entry.id)
        --the list's own chrome (tabs, add friend) goes away while chatting.
        RefreshTabs()
        addStrip:SetClass("collapsed", true)
        listView:SetClass("collapsed", true)
        chatView:SetClass("collapsed", false)
        chatHeader:FireEvent("refreshChatHeader")
        m_settle = nil
        msgList:SetClass("dfSettling", false)
        ResetChatView({EmptyLabel("Loading messages...")})
        FetchMessages()
        chatInput.hasInputFocus = true
    end

    CloseChat = function()
        m_chat = nil
        dmhub.DiscordSetOpenConversation(nil)
        chatView:SetClass("collapsed", true)
        listView:SetClass("collapsed", false)
        SetStatus(nil)
        RefreshTabs()
        RebuildList()
    end

    --Settings (the header's gear) lists blocked users in place of friends.
    local function ShowSettings(show)
        if m_chat ~= nil then
            CloseChat()
        end
        m_tab = cond(show, "blocked", "friends")
        HideConfirm()
        addStrip:SetClass("collapsed", true)
        RefreshTabs()
        listPanel.vscrollPosition = 1
        RebuildList()
    end

    ---- Layout ----

    local function Tab(text, tab)
        return gui.Label{
            classes = {"tab", "dfTab", cond(tab == m_tab, "selected")},
            text = text,
            data = {tab = tab},
            press = function(element)
                m_tab = tab
                HideConfirm()
                RefreshTabs()
                listPanel.vscrollPosition = 1
                RebuildList()
            end,
        }
    end

    --RefreshTabs shows it once there are requests.
    tabBar = gui.Panel{
        classes = {"tabBar", "collapsed"},
        flow = "horizontal",
        width = "100%",
        height = "auto",
        hpad = 12,
        borderBox = true,
        Tab("Friends", "friends"),
        Tab("Pending", "pending"),
    }

    settingsBar = gui.Panel{
        classes = {"dfHeader", "collapsed"},
        height = 36,
        gui.Button{
            classes = {"sizeS", "dfRowAction"},
            icon = "phosphor/arrow-left-bold.png",
            tooltip = "Back to friends",
            valign = "center",
            click = function()
                ShowSettings(false)
            end,
        },
        gui.Label{
            classes = {"dfTitle"},
            text = "Settings",
        },
    }

    addStatus = gui.Label{
        classes = {"dfStripText", "collapsed"},
        fontSize = 12,
        italics = true,
        tmargin = 4,
        text = "",
    }

    local function SendRequest()
        local name = addInput.text or ""
        if string.find(name, "%S") == nil then
            return
        end
        addStatus:SetClass("collapsed", false)
        addStatus.text = "Sending..."
        local started = dmhub.DiscordSendFriendRequest(name, function(err)
            if not root.valid then
                return
            end
            if err ~= nil then
                addStatus.text = err
            else
                addStatus.text = string.format("Friend request sent to %s.", name)
                addInput.text = ""
            end
        end)
        if not started then
            addStatus.text = "Discord is not connected right now."
        end
    end

    addInput = gui.Input{
        classes = {"bordered"},
        placeholderText = "Discord username...",
        characterLimit = 64,
        width = "100% available",
        height = 28,
        fontSize = 14,
        valign = "center",
        enter = function(element)
            SendRequest()
        end,
    }

    addStrip = gui.Panel{
        classes = {"dfStrip", "collapsed"},
        gui.Label{
            classes = {"dfStripText"},
            text = "Add a friend by their Discord username.",
            bmargin = 6,
        },
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            addInput,
            gui.Button{
                classes = {"sizeM"},
                text = "Send Request",
                valign = "center",
                lmargin = 8,
                click = function()
                    SendRequest()
                end,
            },
        },
        addStatus,
    }

    searchInput = gui.SearchInput{
        width = "100%-24",
        height = 24,
        --SearchInput ships hpad = 24 for its magnifier; borderBox keeps the
        --declared width inclusive of it.
        borderBox = true,
        halign = "center",
        vmargin = 8,
        placeholderText = "Search friends...",
        edit = function(element)
            m_search = element.text or ""
            RebuildList()
        end,
    }

    confirmStrip = gui.Panel{
        classes = {"dfStrip", "collapsed"},
    }

    statusText = gui.Label{
        classes = {"dfStatusText", "collapsed"},
        text = "",
    }

    --scrolls the slots directly, so its scroll position maps onto them.
    listPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100% available",
        vscroll = true,
        scroll = function(element)
            BuildVisibleRows()
        end,
    }

    listView = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100% available",
        searchInput,
        listPanel,
    }

    chatHeader = gui.Panel{
        classes = {"dfRow"},
        refreshChatHeader = function(element)
            if m_chat == nil then
                return
            end
            element.children = {
                gui.Button{
                    classes = {"sizeS", "dfRowAction"},
                    icon = "phosphor/arrow-left-bold.png",
                    tooltip = "Back to friends",
                    valign = "center",
                    rmargin = 8,
                    click = function()
                        CloseChat()
                    end,
                },
                AvatarPanel(m_chat, 32),
                gui.Panel{
                    flow = "vertical",
                    width = "100% available",
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                    interactable = false,
                    gui.Label{
                        classes = {"dfName", "unread"},
                        text = m_chat.displayName,
                    },
                    gui.Label{
                        classes = {"dfSub"},
                        text = SubText(m_chat),
                    },
                },
                (function()
                    local more
                    more = gui.Button{
                        classes = {"sizeS", "dfRowAction"},
                        icon = "phosphor/dots-three-vertical-bold.png",
                        tooltip = "More",
                        valign = "center",
                        click = function()
                            if m_chat ~= nil then
                                ShowMenu(more, m_chat)
                            end
                        end,
                    }
                    return more
                end)(),
            }
        end,
    }

    msgList = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
        bmargin = 8,
    }

    msgScroll = gui.Panel{
        width = "100%",
        height = "100% available",
        vscroll = true,
        --runs SettleToBottom's pinning; idle otherwise.
        thinkTime = 0.03,
        think = function(element)
            local settle = m_settle
            if settle == nil then
                return
            end
            element.vscrollPosition = 0
            local h = msgList.renderedHeight or 0
            if h == settle.height then
                settle.stable = settle.stable + 1
            else
                settle.height = h
                settle.stable = 0
            end
            if settle.stable >= 2 or dmhub.Time() > settle.deadline then
                m_settle = nil
                msgList:SetClass("dfSettling", false)
            end
        end,
        msgList,
    }

    chatInput = gui.Input{
        classes = {"bordered"},
        placeholderText = "Message...",
        characterLimit = 2000,
        width = "100% available",
        height = 30,
        fontSize = 14,
        valign = "center",
        enter = function(element)
            SendChat()
            element.hasInputFocus = true
        end,
    }

    chatView = gui.Panel{
        classes = {"collapsed"},
        flow = "vertical",
        width = "100%",
        height = "100% available",
        chatHeader,
        gui.Panel{
            classes = {"dfRule"},
        },
        msgScroll,
        --Discord asks that cross-platform conversations say so.
        gui.Label{
            classes = {"dfNotice"},
            text = "These messages sync with your Discord DMs.",
        },
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            hpad = 12,
            bmargin = 8,
            borderBox = true,
            chatInput,
            gui.Button{
                classes = {"sizeM", "dfRowAction"},
                icon = "phosphor/paper-plane-right-fill.png",
                tooltip = "Send",
                valign = "center",
                lmargin = 6,
                click = function()
                    SendChat()
                end,
            },
        },
    }

    footer = gui.Panel{
        classes = {"dfFooter"},
        refreshFooter = function(element)
            local s = Status()
            if s.account ~= "ready" then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            element.children = {
                AvatarPanel({avatar = s.avatar}, 22, false),
                gui.Label{
                    classes = {"dfFooterText"},
                    text = string.format("Linked as %s", s.displayName or "you"),
                },
                gui.Label{
                    classes = {"label", "link", "dfHit"},
                    fontSize = 12,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    text = "Unlink",
                    click = function()
                        Confirm("Unlink your Discord account? Your Discord friends and messages will no longer show in the Codex. You can link it again at any time.", "Unlink", function()
                            dmhub.DiscordUnlink()
                        end)
                    end,
                },
            }
        end,
    }

    local function Close()
        if root.valid then
            root:DestroySelf()
        end
    end

    root = gui.Panel{
        id = "discordFriendsPanel",
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles(BuildStyles()),
        floating = true,
        halign = "right",
        valign = "top",
        x = args.x or -20,
        y = args.y or 68,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
        flow = "vertical",
        swallowPress = true,

        captureEscape = true,
        escape = function(element)
            Close()
        end,

        restyle = function(element)
            element.styles = ThemeEngine.MergeStyles(BuildStyles())
        end,

        --Poll the engine's counters and re-read whatever moved.
        thinkTime = POLL_SECONDS,
        think = function(element)
            local s = Status()
            if s.account ~= m_account then
                m_account = s.account
                m_socialRev = nil
                footer:FireEvent("refreshFooter")
                if s.account ~= "ready" and m_chat ~= nil then
                    CloseChat()
                end
                if s.account ~= "ready" then
                    --no account, no requests: drop the tabs with the list.
                    m_entries = {}
                    m_tab = "friends"
                    RefreshTabs()
                end
                RebuildList()
            end
            if s.account ~= "ready" then
                return
            end
            if s.socialRevision ~= m_socialRev then
                m_socialRev = s.socialRevision
                ReadRelationships()
            end
            if s.messageRevision ~= m_messageRev then
                m_messageRev = s.messageRevision
                if m_chat ~= nil then
                    FetchMessages()
                else
                    --rows show each friend's unread count.
                    ReadRelationships()
                end
            end
        end,

        destroy = function(element)
            dmhub.DiscordSetOpenConversation(nil)
            if args.onClose ~= nil then
                args.onClose()
            end
        end,

        gui.Panel{
            classes = {"dfHeader"},
            gui.Panel{
                classes = {"dfBrand"},
                bgimage = "phosphor/discord-logo-fill.png",
                width = 24,
                height = 24,
                valign = "center",
            },
            gui.Label{
                classes = {"dfTitle"},
                text = cond(m_invite ~= nil, "Invite Discord Friends", "Discord Friends"),
            },
            gui.Button{
                classes = {"sizeM"},
                icon = "phosphor/user-plus-bold.png",
                tooltip = "Add Friend",
                valign = "center",
                click = function()
                    if Status().account ~= "ready" then
                        return
                    end
                    if m_tab == "blocked" or m_chat ~= nil then
                        ShowSettings(false)
                    end
                    local show = addStrip:HasClass("collapsed")
                    addStrip:SetClass("collapsed", not show)
                    if show then
                        addInput.hasInputFocus = true
                    end
                end,
            },
            gui.Button{
                classes = {"sizeM"},
                icon = "phosphor/gear-six-bold.png",
                tooltip = "Settings",
                valign = "center",
                lmargin = 4,
                click = function()
                    if Status().account ~= "ready" then
                        return
                    end
                    ShowSettings(m_tab ~= "blocked" or m_chat ~= nil)
                end,
            },
            gui.Button{
                classes = {"sizeM"},
                icon = "phosphor/x-bold.png",
                tooltip = "Close",
                valign = "center",
                lmargin = 4,
                click = function()
                    Close()
                end,
            },
        },
        tabBar,
        settingsBar,
        addStrip,
        confirmStrip,
        statusText,
        listView,
        chatView,
        gui.Panel{
            classes = {"dfRule"},
        },
        footer,
    }

    return root
end

--- True while the friends panel is open.
--- @return boolean
function DiscordFriends.IsOpen()
    return g_panel ~= nil and g_panel.valid
end

--- Closes the friends panel if it is open.
function DiscordFriends.Close()
    local panel = g_panel
    g_panel = nil
    if panel ~= nil and panel.valid then
        panel:DestroySelf()
    end
end

--- Opens the friends panel in parent, or closes it if it is open.
--- @param parent Panel the panel to float the friends panel in.
--- @param args nil|{x: number|nil, y: number|nil, offerLink: nil|fun(), invite: nil|{connect: string, title: string}}
function DiscordFriends.Toggle(parent, args)
    if DiscordFriends.IsOpen() then
        DiscordFriends.Close()
        return
    end
    args = args or {}
    g_panel = CreatePanel{
        x = args.x,
        y = args.y,
        offerLink = args.offerLink,
        invite = args.invite,
        onClose = function()
            g_panel = nil
        end,
    }
    parent:AddChild(g_panel)
end

--- True where Discord invites can be offered: the feature is switched on
--- (the hidden discordsocial preference) and this build has Discord. The
--- account may still need linking; the friends panel offers that itself.
--- @return boolean
function DiscordFriends.CanInvite()
    return dmhub.GetSettingValue("discordsocial") == true and Available(Status())
end

--- Opens the friends panel in invite mode: every friend gets an Invite
--- button that invites them to target (not to our presence), stored for
--- friends who are offline. Replaces a friends panel already open.
--- @param parent Panel the panel to float the friends panel in.
--- @param target {connect: string, title: string}
--- @param args nil|{x: number|nil, y: number|nil}
function DiscordFriends.OpenInvite(parent, target, args)
    DiscordFriends.Close()
    args = args or {}
    DiscordFriends.Toggle(parent, {x = args.x, y = args.y, invite = target})
end

--- The Discord button: an icon-rail button with the Discord logo and an
--- unread-message badge, floating at the top right of its parent (offset by
--- x, y). Hidden in builds without Discord. Clicking it opens the friends
--- panel in parent (offset by panelX, panelY) when an account is linked, and
--- calls offerLink when not.
--- @param args {parent: Panel, offerLink: fun(), x: number|nil, y: number|nil, panelX: number|nil, panelY: number|nil}
--- @return Panel
function DiscordFriends.CreateButton(args)
    local badge = gui.Label{
        classes = {"dfBadge", "collapsed"},
        floating = true,
        halign = "right",
        valign = "top",
        x = 6,
        y = -6,
        text = "",
        interactable = false,
    }

    --whether the styles include the rail's; the titlescreen is built before
    --DocumentSystem loads, so the first think usually adds them.
    local railStyled = RailStylesReady()

    local button
    button = gui.Panel{
        classes = {"iconRailButton"},
        styles = ButtonStyles(),
        bgimage = true,
        blurBackground = true,
        floating = true,
        halign = "right",
        valign = "top",
        x = args.x or 0,
        y = args.y or 0,
        width = BUTTON_SIZE,
        height = BUTTON_SIZE,
        flow = "none",
        swallowPress = true,

        restyle = function(element)
            element.styles = ButtonStyles()
        end,

        thinkTime = 0.5,
        think = function(element)
            if not railStyled and RailStylesReady() then
                railStyled = true
                element.styles = ButtonStyles()
            end
            local s = Status()
            element:SetClass("hidden", not Available(s))
            element:SetClass("active", DiscordFriends.IsOpen())
            local unread = s.unreadTotal or 0
            badge:SetClass("collapsed", unread <= 0)
            if unread > 0 then
                badge.text = cond(unread > 99, "99+", tostring(unread))
            end
        end,

        hover = function(element)
            local s = Status()
            gui.Tooltip(cond(Linked(s), "Discord Friends", "Link Discord"))(element)
        end,

        click = function(element)
            local s = Status()
            if Linked(s) then
                DiscordFriends.Toggle(args.parent, {
                    x = args.panelX,
                    y = args.panelY,
                    offerLink = args.offerLink,
                })
            elseif args.offerLink ~= nil then
                args.offerLink()
            end
        end,

        gui.Panel{
            classes = {"iconRailIcon"},
            bgimage = "phosphor/discord-logo-fill.png",
            width = 22,
            height = 22,
            halign = "center",
            valign = "center",
            interactable = false,
        },
        gui.Panel{
            classes = {"iconRailActiveMark"},
            bgimage = true,
            width = 16,
            height = 2,
            halign = "center",
            valign = "bottom",
            y = -3,
            interactable = false,
        },
        badge,
    }

    g_buttons[#g_buttons + 1] = button
    return button
end

--------------------------------------------------------------------------------
--Invites and Ask to Join.
--
--Sending: an invite goes two ways at once. Discord's own invite
--(dmhub.DiscordSendInvite) shows in the friend's Discord DMs and reaches a
--running Codex at once, but it only works while we are still in the game,
--because Discord hands over our CURRENT join secret. So the Codex also stores
--it (the discordInviteSend cloud function) under the friend's Discord id, with
--our join secret as it is now; a campaign invite then lasts 30 days, a party
--invite until the party sets out (12 hours at most).
--
--Receiving: invites arrive live from Discord (dmhub.DiscordGetInvites, also
--Ask to Join requests) and from the Codex's store (discordInvitesList, read
--when the Discord account comes up, a moment after any live one arrives, and
--every 10 minutes). Both from the same friend merge into one. Each is shown in
--a dialog above everything else, one at a time. Stored invites from people who
--are not our Discord friends are never shown. "Not now" hides a stored invite
--until the Codex next starts.
--------------------------------------------------------------------------------

local STORE_POLL_SECONDS = 10 * 60
--after a live invite, wait this long so the sender's stored copy is there.
local STORE_AFTER_LIVE_SECONDS = 3

--- What we would invite a friend into right now, for the stored invite and
--- the receiver's dialog: the campaign's name, or a description of the party.
--- @param secret string
--- @return string
local function InviteTitle(secret)
    if string.find(secret, "^dshub2:eotw:") ~= nil then
        return "an Encounter of the Week party"
    end
    local gameid = dmhub.gameid
    if gameid ~= nil and gameid == lobby.eotwGameid then
        return "an Encounter of the Week game"
    end
    for _, info in ipairs(lobby.games or {}) do
        if info.gameid == gameid and type(info.description) == "string" and info.description ~= "" then
            return info.description
        end
    end
    return ""
end

--- Invites a Discord friend to whatever we can be joined in right now (a
--- campaign, or the Encounter of the Week party we are in), both through
--- Discord and the Codex's invite store, so a friend who is offline sees it
--- when they next open the Codex. done(text, isError) reports the outcome.
--- target ({connect, title}) invites to something other than our presence,
--- such as an Encounter of the Week party we are looking at.
--- @param friend {id: string, displayName: string, status: string|nil}
--- @param done fun(text: string, isError: boolean)
--- @param target nil|{connect: string, title: string}
function DiscordFriends.SendInvite(friend, done, target)
    local presence = Status().joinSecret
    local secret = presence
    local title = nil
    if target ~= nil then
        secret = target.connect
        title = target.title
    end
    if secret == nil then
        done("There is no game to invite them to right now.", true)
        return
    end
    title = title or InviteTitle(secret)
    --Discord's own invite carries our CURRENT presence, so it is only sent
    --when that is what we are inviting to.
    local sendLive = presence == secret

    --nil while waiting, false on success, else the error text.
    local liveErr = nil
    local storedErr = nil
    local remaining = 2
    local function Finish()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end
        if storedErr == false then
            if friend.status == "offline" then
                done(string.format("Invite sent to %s. They will see it the next time they open the Codex.", friend.displayName), false)
            else
                done(string.format("Invite sent to %s.", friend.displayName), false)
            end
        elseif liveErr == false then
            done(string.format("Invite sent to %s on Discord.", friend.displayName), false)
        else
            done(tostring(storedErr or liveErr), true)
        end
    end

    local started = sendLive and dmhub.DiscordSendInvite(friend.id, INVITE_MESSAGE, function(err)
        liveErr = err or false
        Finish()
    end)
    if not started then
        liveErr = cond(sendLive, "Discord is not connected right now.", nil)
        Finish()
    end

    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/discordInviteSend",
        data = {
            toDiscordUserId = friend.id,
            connect = secret,
            title = title,
        },
        success = function(response)
            if type(response) == "table" and response.ok then
                storedErr = false
            else
                storedErr = (type(response) == "table" and response.error) or "The invite could not be saved."
            end
            Finish()
        end,
        error = function(message)
            storedErr = "Could not reach the Codex servers."
            Finish()
        end,
    }
end

--- Asks a Discord friend who is in a joinable Codex game or party to let us
--- join. When they accept, we join them automatically.
--- @param friend {id: string, displayName: string}
--- @param done fun(text: string, isError: boolean)
function DiscordFriends.AskToJoin(friend, done)
    local started = dmhub.DiscordSendJoinRequest(friend.id, function(err)
        if err ~= nil then
            done(err, true)
        else
            done(string.format("Asked to join %s. You will join them as soon as they accept.", friend.displayName), false)
        end
    end)
    if not started then
        done("Discord is not connected right now.", true)
    end
end

--Received invites by sender's Discord id, each {senderId, name, avatar,
--live = a DiscordGetInvites entry or nil, stored = a stored invite or nil}.
--Join requests are kept apart, under "req:" .. senderId.
local g_inbox = {}
--stored invite ids hidden with "Not now" (until the Codex next starts).
local g_snoozed = {}
--the invite dialog on screen, and the inbox key it shows.
local g_dialog = nil
local g_dialogKey = nil
local g_dialogLayer = nil
local g_dialogHost = nil

local g_lastInviteRev = nil
local g_lastAccount = nil
local g_nextStoreFetch = nil
local g_fetching = false

local function Gated()
    return dmhub.GetSettingValue("discordsocial") == true
end

--Our Discord friends by id, read live (nothing is kept between calls).
local function FriendsById()
    local result = {}
    for _, entry in ipairs(dmhub.DiscordGetRelationships() or {}) do
        if entry.relationship == "friend" then
            result[entry.id] = entry
        end
    end
    return result
end

--Rebuilds the live half of the inbox from the engine's list.
local function MergeLive()
    for key, item in pairs(g_inbox) do
        item.live = nil
        if item.stored == nil then
            g_inbox[key] = nil
        end
    end
    for _, invite in ipairs(dmhub.DiscordGetInvites() or {}) do
        local key = cond(invite.type == "joinrequest", "req:" .. invite.senderId, invite.senderId)
        local item = g_inbox[key] or {senderId = invite.senderId, arrived = dmhub.Time()}
        item.live = invite
        item.name = item.name or invite.senderName
        item.avatar = item.avatar or invite.avatar
        g_inbox[key] = item
    end
end

local function FetchStored()
    if g_fetching then
        return
    end
    g_fetching = true
    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/discordInvitesList",
        data = {},
        success = function(response)
            g_fetching = false
            if mod.unloaded or type(response) ~= "table" or not response.ok then
                return
            end
            local friends = FriendsById()
            --right after linking, Discord may not have sent the friends list
            --yet: try again shortly rather than dropping every invite.
            if next(friends) == nil and #(response.invites or {}) > 0 then
                g_nextStoreFetch = dmhub.Time() + 5
                return
            end
            for key, item in pairs(g_inbox) do
                item.stored = nil
                if item.live == nil then
                    g_inbox[key] = nil
                end
            end
            for _, invite in ipairs(response.invites or {}) do
                local friend = friends[invite.fromDiscordId]
                local key = invite.fromDiscordId
                --one invite per sender: the newest (the list is newest first).
                if friend ~= nil and not g_snoozed[invite.id] and (g_inbox[key] == nil or g_inbox[key].stored == nil) then
                    local item = g_inbox[key] or {senderId = key, arrived = dmhub.Time()}
                    item.stored = invite
                    item.name = friend.displayName or invite.fromName
                    item.avatar = friend.avatar
                    g_inbox[key] = item
                end
            end
        end,
        error = function(message)
            g_fetching = false
        end,
    }
end

--Tells the store a stored invite is answered (accepted or declined).
local function AnswerStored(invite)
    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/discordInviteAnswer",
        data = {id = invite.id},
    }
end

--Where the dialog can go right now: "titlescreen", "game", or nil to wait
--(the press-any-key screen, no hud yet). Not gameLoadingProgress: it can sit
--below 1 in a fully loaded game.
local function DialogHost()
    if dmhub.isLobbyGame then
        local root = rawget(_G, "CodexTitlescreenRoot")
        if root ~= nil and root.valid and not root:HasClass("starting-screen") and not root:HasClass("hidden") then
            return "titlescreen"
        end
        return nil
    end
    if dmhub.inGame and rawget(_G, "gamehud") ~= nil then
        return "game"
    end
    return nil
end

local function CloseDialog()
    local dialog = g_dialog
    local layer = g_dialogLayer
    g_dialog = nil
    g_dialogKey = nil
    g_dialogLayer = nil
    g_dialogHost = nil
    if layer ~= nil then
        gui.CloseModalInLayer(layer)
    elseif dialog ~= nil and dialog.valid then
        dialog:DestroySelf()
    end
end

--What the dialog says about an inbox item: title, message, and whether it can
--still be accepted.
local function DescribeItem(item)
    local name = item.name or "A friend"
    if item.live ~= nil and item.live.type == "joinrequest" then
        return "Ask to Join", string.format("%s wants to join you.", name), true
    end
    local stored = item.stored
    if stored ~= nil then
        if stored.kind == "party" then
            return "Invitation", string.format("%s invited you to join %s.", name, cond(stored.title ~= "", stored.title, "their Encounter of the Week party")), true
        end
        --a description ("an Encounter of the Week game") rather than a name.
        if string.find(stored.title, "^an? ") ~= nil then
            return "Invitation", string.format("%s invited you to join %s.", name, stored.title), true
        end
        if stored.title ~= "" then
            return "Invitation", string.format("%s invited you to join their campaign, %s.", name, stored.title), true
        end
        return "Invitation", string.format("%s invited you to join their campaign.", name), true
    end
    if item.live ~= nil and item.live.valid == false then
        return "Invitation", string.format("%s invited you to play, but they are no longer in that game.", name), false
    end
    return "Invitation", string.format("%s invited you to play with them in the Codex.", name), true
end

--Answers an item: "accept", "decline" or "later". The item leaves the inbox.
local function Answer(key, item, answer)
    g_inbox[key] = nil
    CloseDialog()
    local live = item.live
    local stored = item.stored
    if answer == "accept" then
        if stored ~= nil and (live == nil or live.type ~= "joinrequest") then
            --the stored invite carries the join secret even if they left.
            AnswerStored(stored)
            if live ~= nil then
                dmhub.DiscordDismissInvite(live.id)
            end
            dmhub.DiscordJoin(stored.connect)
        elseif live ~= nil then
            dmhub.DiscordAcceptInvite(live.id, function(err)
                if err ~= nil then
                    printf("Discord: could not accept the invite: %s", err)
                end
            end)
        end
        return
    end

    if live ~= nil then
        dmhub.DiscordDismissInvite(live.id)
    end
    if stored ~= nil then
        if answer == "decline" then
            AnswerStored(stored)
        else
            g_snoozed[stored.id] = true
        end
    end
end

local function ShowDialog(key, item, host)
    local title, message, canAccept = DescribeItem(item)
    local isRequest = item.live ~= nil and item.live.type == "joinrequest"

    local buttons = {}
    if canAccept then
        buttons[#buttons + 1] = gui.Button{
            classes = {"sizeL"},
            text = cond(isRequest, "Let Them Join", "Join"),
            hmargin = 6,
            click = function()
                Answer(key, item, "accept")
            end,
        }
    end
    if item.stored ~= nil then
        buttons[#buttons + 1] = gui.Button{
            classes = {"sizeL"},
            text = "Not Now",
            hmargin = 6,
            click = function()
                Answer(key, item, "later")
            end,
        }
    end
    buttons[#buttons + 1] = gui.Button{
        classes = {"sizeL"},
        text = cond(canAccept, "Decline", "Dismiss"),
        hmargin = 6,
        click = function()
            Answer(key, item, "decline")
        end,
    }

    local dialog = gui.Panel{
        classes = {"framedPanel"},
        width = 560,
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        pad = 24,
        borderBox = true,
        swallowPress = true,

        --a fixed-height header with an auto-width title: a "100% available"
        --title (dfTitle's own width) in this auto-height dialog kept the layout
        --settling, and the buttons below never received their clicks.
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 56,
            halign = "center",
            AvatarPanel({avatar = item.avatar, status = "online"}, 56, false),
            gui.Panel{
                classes = {"dfBrand"},
                bgimage = "phosphor/discord-logo-fill.png",
                width = 24,
                height = 24,
                valign = "center",
                lmargin = 12,
            },
            gui.Label{
                classes = {"dfTitle"},
                width = "auto",
                text = title,
            },
        },
        gui.Label{
            classes = {"modalMessage"},
            width = "100%",
            height = "auto",
            vmargin = 18,
            text = message,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            children = buttons,
        },
    }

    --the titlescreen root is wider than the screen: cover the visible part.
    local onTitlescreen = host == "titlescreen"
    local backdrop = gui.Panel{
        floating = onTitlescreen,
        width = cond(onTitlescreen, 1080 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y), "100%"),
        height = cond(onTitlescreen, 1080, "100%"),
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        styles = ThemeEngine.MergeStyles(BuildStyles()),
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function()
            Answer(key, item, cond(item.stored ~= nil, "later", "decline"))
        end,
        dialog,
    }

    g_dialogKey = key
    g_dialogHost = host
    if host == "game" then
        g_dialog = backdrop
        g_dialogLayer = gui.ShowModal(backdrop)
        return
    end

    rawget(_G, "CodexTitlescreenRoot"):AddChild(backdrop)
    g_dialog = backdrop
end

local function PollInvites()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(1, PollInvites)
    if not Gated() then
        return
    end

    local s = Status()
    local ready = s.account == "ready"
    if s.account ~= g_lastAccount then
        g_lastAccount = s.account
        if ready then
            g_nextStoreFetch = dmhub.Time()
        else
            g_inbox = {}
            CloseDialog()
            g_nextStoreFetch = nil
        end
    end
    if not ready then
        return
    end

    if s.inviteRevision ~= g_lastInviteRev then
        g_lastInviteRev = s.inviteRevision
        MergeLive()
        local soon = dmhub.Time() + STORE_AFTER_LIVE_SECONDS
        if g_nextStoreFetch == nil or g_nextStoreFetch > soon then
            g_nextStoreFetch = soon
        end
    end

    if g_nextStoreFetch ~= nil and dmhub.Time() >= g_nextStoreFetch then
        g_nextStoreFetch = dmhub.Time() + STORE_POLL_SECONDS
        FetchStored()
    end

    --the dialog went with its host (left a game, a modal swept it away).
    if g_dialog ~= nil and not g_dialog.valid then
        g_dialog = nil
        g_dialogKey = nil
        g_dialogLayer = nil
    end
    local host = DialogHost()
    --shown on the titlescreen and we have since entered a game (or the
    --reverse): take it down; the invite stays and shows again where we are.
    if g_dialog ~= nil and host ~= g_dialogHost then
        CloseDialog()
    end
    if g_dialog ~= nil or host == nil then
        return
    end
    --the one that reached us first.
    local bestKey, bestItem = nil, nil
    for key, item in pairs(g_inbox) do
        if bestItem == nil or item.arrived < bestItem.arrived then
            bestKey, bestItem = key, item
        end
    end
    if bestItem ~= nil then
        ShowDialog(bestKey, bestItem, host)
    end
end
dmhub.Schedule(1, PollInvites)

--Scheme switches restyle the open panel and every button.
ThemeEngine.OnThemeChanged(mod, function()
    local panel = g_panel
    if panel ~= nil and panel.valid then
        panel:FireEvent("restyle")
    end
    local live = {}
    for _, button in ipairs(g_buttons) do
        if button.valid then
            button:FireEvent("restyle")
            live[#live + 1] = button
        end
    end
    g_buttons = live
end)

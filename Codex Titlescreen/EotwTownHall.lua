local mod = dmhub.GetModLoading()

--Encounter of the Week: the Town Hall, once the town has built it (the
--community project Build the Town Hall, EotwDowntime.lua). Two boards:
--
--  * Town Votes: questions the town's admins put to everyone, with 2-6
--    choices. Every account with a town hero casts one ballot and may change
--    it while the vote is open. The tallies stay hidden until you have voted
--    (admins always see them; everyone does once it closes).
--  * Petitions: any account with a town hero posts one (a few open at a
--    time); others vote it up or down. An admin may answer a petition, which
--    closes it with an official response, or remove it; its author may
--    withdraw it while it is open.
--
--The City (cloudflare-game-server src/city-core.ts, "The Town Hall") keeps
--both and checks every rule; this file only shows them. Any change bumps
--/city/townHallRev, which an open Town Hall watches to re-read its board.
--Design: EncounterOfTheWeek/EncounterOfTheWeek.md, "The Town Hall".

EotwTownHall = {}

local T = UIText.T
local TP = UIText.Plural

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local RED = "#ff8888"

--Server-enforced limits (city-core.ts); these only drive the UI.
local ISSUE_MAX_OPTIONS = 6
local ISSUE_MAX_QUESTION = 200
local ISSUE_MAX_DETAILS = 2000
local ISSUE_MAX_OPTION = 100
local PETITION_MIN_TITLE = 3
local PETITION_MAX_TITLE = 100
local PETITION_MAX_BODY = 1500
local PETITION_MAX_RESPONSE = 2000

--How long an admin's new vote runs: days (0 = until an admin closes it).
local VOTE_DURATIONS = { 0, 1, 3, 7, 14, 30 }

---- shared pieces --------------------------------------------------------

--Text shown as typed: rich-text tags in it are not applied (as the town chat).
local function Plain(text)
    return "<noparse>" .. string.gsub(tostring(text or ""), "</?[nN][oO][pP][aA][rR][sS][eE]>", "") .. "</noparse>"
end

--Trim a typed string.
local function Trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

--Send one Town Hall request to the City. onDone(result); onFail(message).
local function Request(action, args, onDone, onFail)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onFail ~= nil then
            onFail(T("townhall.error.not_connected"))
        end
        return
    end
    conn:Request{
        action = action,
        args = args,
        success = function(result)
            if mod.unloaded then
                return
            end
            onDone(result or {})
        end,
        error = function(message)
            if mod.unloaded then
                return
            end
            printf("EotW town hall: %s failed: %s", action, tostring(message))
            if onFail ~= nil then
                onFail(tostring(message))
            end
        end,
    }
end

local function Label(text, fontSize, color, extra)
    local args = {
        text = text,
        fontSize = fontSize or 16,
        color = color or TEXT,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Label(args)
end

local function Button(text, click, width, height, fontSize)
    return gui.Button{
        text = text,
        fontSize = fontSize or 18,
        width = width or 200,
        height = height or 40,
        hmargin = 4,
        vmargin = 2,
        click = function()
            click()
        end,
    }
end

--A button that asks for a second click before acting (reverts after 3s).
local function ConfirmButton(text, confirmText, click, width)
    return gui.Button{
        text = text,
        fontSize = 15,
        width = width or 140,
        height = 30,
        hmargin = 4,
        vmargin = 2,
        data = { armed = false },
        click = function(element)
            if not element.data.armed then
                element.data.armed = true
                element.text = confirmText
                dmhub.Schedule(3, function()
                    if element.valid and element.data.armed then
                        element.data.armed = false
                        element.text = text
                    end
                end)
                return
            end
            element.data.armed = false
            click()
        end,
    }
end

--A small toggle for the tab, board and sort strips (as the Hall of Heroes').
local function Chip(text, selected, click)
    return gui.Label{
        text = text,
        fontSize = 17,
        bold = selected,
        color = cond(selected, TEXT, DIM),
        width = "auto",
        height = "auto",
        hpad = 14,
        vpad = 6,
        borderBox = true,
        hmargin = 3,
        vmargin = 3,
        bgimage = "panels/square.png",
        bgcolor = cond(selected, "#8c7a5599", "#ffffff10"),
        cornerRadius = 6,
        styles = {
            { selectors = {"hover"}, bgcolor = cond(selected, "#8c7a55cc", "#ffffff22") },
        },
        click = function()
            audio.FireSoundEvent("Mouse.Click")
            click()
        end,
    }
end

--A dialog over `host` (the town screen). args: title, width, children,
--buttons. Escape closes it. Returns the dialog.
local function Dialog(host, args)
    ---@type Panel[]
    local children = {
        Label(args.title, 28, TEXT, { bold = true, textAlignment = "center", vmargin = 6 }),
    }
    for _, child in ipairs(args.children) do
        children[#children+1] = child
    end
    children[#children+1] = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        tmargin = 10,
        children = args.buttons,
    }
    local dlg = gui.Panel{
        floating = true,
        width = args.width or 680,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        --opaque: near-opaque alphas still let the scene show through.
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        pad = 20,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        --above the town screen's own escape, which would close the town.
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        children = children,
    }
    host:AddChild(dlg)
    return dlg
end

--A text box for a dialog. args: placeholder, limit, height, multiline, text.
--Returns the input; read its .text when the dialog is confirmed.
local function TextBox(args)
    return gui.Input{
        width = "100%",
        borderBox = true,
        height = args.height or 38,
        fontSize = args.fontSize or 18,
        multiline = args.multiline == true,
        textAlignment = cond(args.multiline == true, "topleft", "left"),
        characterLimit = args.limit,
        placeholderText = args.placeholder,
        text = args.text or "",
        vmargin = 4,
    }
end

--The red line a dialog shows when something is wrong; SetText to fill it.
local function StatusLine()
    return Label("", 15, RED, { textAlignment = "center", minHeight = 20, vmargin = 4 })
end

--"Closes in 3 days" / "Closed" / "Open until the council closes it".
local function ClosesText(issue)
    if issue.closed then
        return T("townhall.votes.closed")
    end
    if type(issue.closesAt) ~= "number" then
        return T("townhall.votes.no_end")
    end
    local left = -TimestampAgeInSeconds(issue.closesAt)
    if left < 3600 then
        return T("townhall.votes.closes_soon")
    end
    --rounded up: a vote with 4.9 days left "closes in 5 days".
    if left < 2 * 86400 then
        return TP("townhall.votes.closes_hours", math.ceil(left / 3600))
    end
    return TP("townhall.votes.closes_days", math.ceil(left / 86400))
end

---- dialogs ---------------------------------------------------------------

--Admin: put a new question to the town. onPosted(result) after the City takes it.
local function ShowPostVoteDialog(host, onPosted)
    local questionBox = TextBox{ placeholder = T("townhall.post_vote.question_placeholder"), limit = ISSUE_MAX_QUESTION }
    local detailsBox = TextBox{ placeholder = T("townhall.post_vote.details_placeholder"), limit = ISSUE_MAX_DETAILS, multiline = true, height = 100, fontSize = 16 }
    local optionBoxes = {}
    for i = 1, ISSUE_MAX_OPTIONS do
        optionBoxes[i] = TextBox{ placeholder = T("townhall.post_vote.choice_placeholder", { number = i }), limit = ISSUE_MAX_OPTION, height = 34, fontSize = 16 }
    end
    local durationOptions = {}
    for _, days in ipairs(VOTE_DURATIONS) do
        local text = T("townhall.post_vote.duration_none")
        if days > 0 then
            text = TP("townhall.post_vote.duration_days", days)
        end
        durationOptions[#durationOptions+1] = { id = tostring(days), text = text }
    end
    local duration = "7"
    local status = StatusLine()
    local posting = false

    local dlg
    ---@type Panel[]
    local children = {
        Label(T("townhall.post_vote.intro"), 15, DIM, { vmargin = 4 }),
        Label(T("townhall.post_vote.question_heading"), 16, TEXT, { bold = true, tmargin = 6 }),
        questionBox,
        Label(T("townhall.post_vote.details_heading"), 16, TEXT, { bold = true, tmargin = 6 }),
        detailsBox,
        Label(T("townhall.post_vote.choices_heading", { max = ISSUE_MAX_OPTIONS }), 16, TEXT, { bold = true, tmargin = 6 }),
    }
    for _, box in ipairs(optionBoxes) do
        children[#children+1] = box
    end
    children[#children+1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 8,
        gui.Label{ text = T("townhall.post_vote.duration_heading"), fontSize = 16, bold = true, color = TEXT, width = "auto", height = "auto", valign = "center", rmargin = 10 },
        gui.Dropdown{
            width = 260,
            height = 34,
            fontSize = 16,
            valign = "center",
            --the open list needs the themed sheet; the titlescreen's
            --legacy styles leave it as bare labels.
            styles = ThemeEngine.GetStyles(),
            options = durationOptions,
            idChosen = duration,
            change = function(element)
                ---@cast element Dropdown
                duration = tostring(element.idChosen)
            end,
        },
    }
    children[#children+1] = status

    local Post = function()
        if posting then
            return
        end
        local question = Trim(questionBox.text)
        local options = {}
        for _, box in ipairs(optionBoxes) do
            local option = Trim(box.text)
            if option ~= "" then
                options[#options+1] = option
            end
        end
        if question == "" then
            status.text = T("townhall.post_vote.need_question")
            return
        end
        if #options < 2 then
            status.text = T("townhall.post_vote.need_choices")
            return
        end
        posting = true
        status.text = ""
        Request("post-issue", {
            question = question,
            details = Trim(detailsBox.text),
            options = options,
            days = tonumber(duration) or 0,
        }, function(result)
            posting = false
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
            onPosted(result)
        end, function(message)
            posting = false
            if status.valid then
                status.text = message
            end
        end)
    end

    dlg = Dialog(host, {
        title = T("townhall.post_vote.title"),
        width = 720,
        children = children,
        buttons = {
            Button(T("townhall.post_vote.post_button"), Post, 180),
            Button(T("townhall.dialog.cancel_button"), function() dlg:DestroySelf() end, 180),
        },
    })
end

--Post a petition. onPosted(result) after the City takes it.
local function ShowPostPetitionDialog(host, onPosted)
    local titleBox = TextBox{ placeholder = T("townhall.post_petition.title_placeholder"), limit = PETITION_MAX_TITLE }
    local bodyBox = TextBox{ placeholder = T("townhall.post_petition.body_placeholder"), limit = PETITION_MAX_BODY, multiline = true, height = 180, fontSize = 16 }
    local status = StatusLine()
    local posting = false

    local dlg
    local Post = function()
        if posting then
            return
        end
        local title = Trim(titleBox.text)
        local body = Trim(bodyBox.text)
        if #title < PETITION_MIN_TITLE then
            status.text = T("townhall.post_petition.need_title")
            return
        end
        if body == "" then
            status.text = T("townhall.post_petition.need_body")
            return
        end
        posting = true
        status.text = ""
        Request("post-petition", { title = title, body = body }, function(result)
            posting = false
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
            onPosted(result)
        end, function(message)
            posting = false
            if status.valid then
                status.text = message
            end
        end)
    end

    dlg = Dialog(host, {
        title = T("townhall.post_petition.title"),
        width = 680,
        children = {
            Label(T("townhall.post_petition.intro"), 15, DIM, { vmargin = 4 }),
            Label(T("townhall.post_petition.title_heading"), 16, TEXT, { bold = true, tmargin = 6 }),
            titleBox,
            Label(T("townhall.post_petition.body_heading"), 16, TEXT, { bold = true, tmargin = 6 }),
            bodyBox,
            Label(T("townhall.post_petition.public_note"), 14, DIM, { italics = true, tmargin = 4 }),
            status,
        },
        buttons = {
            Button(T("townhall.post_petition.post_button"), Post, 180),
            Button(T("townhall.dialog.cancel_button"), function() dlg:DestroySelf() end, 180),
        },
    })
end

--Admin: answer a petition (or change its answer). onAnswered(result).
local function ShowAnswerDialog(host, petition, onAnswered)
    local responseBox = TextBox{ placeholder = T("townhall.answer.placeholder"), limit = PETITION_MAX_RESPONSE, multiline = true, height = 180, fontSize = 16, text = petition.response or "" }
    local status = StatusLine()
    local sending = false

    local dlg
    local Send = function()
        if sending then
            return
        end
        local response = Trim(responseBox.text)
        if response == "" then
            status.text = T("townhall.answer.need_response")
            return
        end
        sending = true
        status.text = ""
        Request("answer-petition", { petitionid = petition.petitionid, response = response }, function(result)
            sending = false
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
            onAnswered(result)
        end, function(message)
            sending = false
            if status.valid then
                status.text = message
            end
        end)
    end

    dlg = Dialog(host, {
        title = T("townhall.answer.title"),
        width = 680,
        children = {
            Label(Plain(petition.title), 19, GOLD, { bold = true, vmargin = 4 }),
            Label(T("townhall.answer.intro"), 15, DIM, { vmargin = 4 }),
            responseBox,
            status,
        },
        buttons = {
            Button(T("townhall.answer.send_button"), Send, 180),
            Button(T("townhall.dialog.cancel_button"), function() dlg:DestroySelf() end, 180),
        },
    })
end

---- the panel -------------------------------------------------------------

--The Town Hall location's card: the Town Votes and Petitions boards (the
--scene above it carries the title). host mounts the dialogs.
function EotwTownHall.Panel(host)
    local isAdmin = dmhub.isAdminAccount == true
    --"votes" or "petitions".
    local tab = "votes"
    --nil while loading.
    local issues = nil
    local petitions = nil
    --the petition board shown: "open" or "answered", and "top" or "new".
    local petStatus = "open"
    local petSort = "top"
    local petMore = false
    local myOpen = 0
    local maxOpen = 3
    --may this account vote and petition (the City says: a town hero, and built)?
    local canTakePart = true
    local errorText = nil
    --the /city/townHallRev this board last read; a newer one re-reads it.
    local seenRev = nil
    --bumped when the board is re-read; an answer for an older read is dropped.
    local generation = 0

    local tabsPanel = nil
    local toolbarPanel = nil
    local statusLabel = nil
    local listPanel = nil

    local Rebuild

    local function SetError(message)
        errorText = message
        Rebuild()
    end

    --An answer to our own action carries the revision it made, so the
    --watcher does not re-read the board for our own change.
    local function NoteRev(result)
        if type(result.townHallRev) == "number" then
            seenRev = result.townHallRev
        end
    end

    local function LoadIssues()
        local g = generation
        Request("list-issues", {}, function(result)
            if g ~= generation then
                return
            end
            issues = result.issues or {}
            canTakePart = result.canTakePart == true
            Rebuild()
        end, SetError)
    end

    --keep: re-read as many petitions as are shown (a live refresh), rather
    --than starting over at the first page.
    local function LoadPetitions(append, keep)
        local g = generation
        local offset = 0
        local limit = 30
        if append and petitions ~= nil then
            offset = #petitions
        elseif keep and petitions ~= nil then
            limit = math.max(30, #petitions)
        end
        Request("list-petitions", { status = petStatus, sort = petSort, offset = offset, limit = limit }, function(result)
            if g ~= generation then
                return
            end
            if not append or petitions == nil then
                petitions = {}
            end
            for _, p in ipairs(result.petitions or {}) do
                petitions[#petitions+1] = p
            end
            petMore = result.more == true
            myOpen = tonumber(result.myOpen) or 0
            maxOpen = tonumber(result.maxOpen) or maxOpen
            canTakePart = result.canTakePart == true
            Rebuild()
        end, SetError)
    end

    --Read the current board again. fresh: start over (a new tab, board or
    --sort), showing "Loading..." meanwhile.
    local function Reload(fresh)
        generation = generation + 1
        errorText = nil
        if tab == "votes" then
            if fresh then
                issues = nil
            end
            LoadIssues()
        else
            if fresh then
                petitions = nil
                petMore = false
            end
            LoadPetitions(false, not fresh)
        end
        Rebuild()
    end

    --Put an updated vote or petition in place without re-reading the board.
    local function Replace(list, key, item)
        if list == nil or type(item) ~= "table" then
            return
        end
        for i, existing in ipairs(list) do
            if existing[key] == item[key] then
                list[i] = item
                return
            end
        end
    end

    ---- town votes ----

    local function Vote(issue, choice)
        audio.FireSoundEvent("Mouse.Click")
        Request("vote-issue", { issueid = issue.issueid, choice = choice }, function(result)
            NoteRev(result)
            Replace(issues, "issueid", result.issue)
            Rebuild()
        end, SetError)
    end

    local function OptionRow(issue, index, option, voters, canVote)
        local mine = issue.myChoice == index
        local tally = nil
        if type(issue.tallies) == "table" then
            tally = tonumber(issue.tallies[index]) or 0
        end
        ---@type Panel[]
        local children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Panel{
                    width = 20,
                    height = 20,
                    valign = "center",
                    rmargin = 10,
                    bgimage = cond(mine, "phosphor/check-circle-fill.png", "panels/square.png"),
                    bgcolor = cond(mine, GOLD, "#ffffff18"),
                    cornerRadius = cond(mine, 0, 10),
                },
                gui.Label{ text = Plain(option), fontSize = 17, bold = mine, color = TEXT, width = "100%-130", height = "auto", valign = "center", textWrap = true },
                gui.Label{
                    text = cond(tally ~= nil, T("townhall.votes.tally", { count = tally or 0, percent = math.floor(100 * (tally or 0) / math.max(1, voters) + 0.5) }), ""),
                    fontSize = 15,
                    color = DIM,
                    width = 100,
                    height = "auto",
                    valign = "center",
                    textAlignment = "right",
                },
            },
        }
        if tally ~= nil then
            local fraction = tally / math.max(1, voters)
            children[#children+1] = gui.Panel{
                width = "100%",
                height = 6,
                tmargin = 6,
                bgimage = "panels/square.png",
                bgcolor = "#ffffff14",
                cornerRadius = 3,
                gui.Panel{
                    halign = "left",
                    width = string.format("%.1f%%", fraction * 100),
                    height = "100%",
                    bgimage = "panels/square.png",
                    bgcolor = cond(mine, GOLD, "#c9bfa999"),
                    cornerRadius = 3,
                },
            }
        end
        local tooltip = nil
        if canVote then
            tooltip = cond(mine, T("townhall.votes.your_choice_tooltip"), T("townhall.votes.vote_tooltip"))
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = cond(mine, "#8c7a5540", "#ffffff0a"),
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            vmargin = 3,
            styles = cond(canVote, { { selectors = {"hover"}, bgcolor = "#ffffff22" } }, nil),
            hover = cond(tooltip ~= nil, gui.Tooltip(tooltip or ""), nil),
            click = function()
                if canVote and not mine then
                    Vote(issue, index)
                end
            end,
            children = children,
        }
    end

    local function IssueCard(issue)
        local open = not issue.closed
        local voters = tonumber(issue.voters) or 0
        local canVote = open and canTakePart
        ---@type Panel[]
        local children = {
            Label(Plain(issue.question), 22, TEXT, { bold = true }),
        }
        if type(issue.details) == "string" and issue.details ~= "" then
            children[#children+1] = Label(Plain(issue.details), 15, DIM, { vmargin = 4 })
        end
        for i, option in ipairs(issue.options or {}) do
            children[#children+1] = OptionRow(issue, i, option, voters, canVote)
        end
        local footer = TP("townhall.votes.voters", voters)
        if issue.tallies == nil and open then
            footer = T("townhall.votes.footer_hidden", { voters = footer })
        end
        children[#children+1] = Label(T("townhall.votes.footer", { voters = footer, closes = ClosesText(issue) }), 14, DIM, { tmargin = 6 })
        children[#children+1] = Label(T("townhall.votes.posted_by", { name = Plain(issue.createdByName), when = DescribeServerTimestamp(issue.at) }), 13, DIM, { italics = true })
        if isAdmin then
            ---@type Panel[]
            local buttons = {}
            if open then
                buttons[#buttons+1] = ConfirmButton(T("townhall.votes.close_button"), T("townhall.dialog.confirm_click"), function()
                    Request("close-issue", { issueid = issue.issueid }, function(result)
                        NoteRev(result)
                        Replace(issues, "issueid", result.issue)
                        Rebuild()
                    end, SetError)
                end)
            end
            buttons[#buttons+1] = ConfirmButton(T("townhall.votes.delete_button"), T("townhall.dialog.confirm_click"), function()
                Request("delete-issue", { issueid = issue.issueid }, function(result)
                    Reload(false)
                end, SetError)
            end)
            children[#children+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", tmargin = 4, children = buttons }
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = cond(open, "#ffffff0c", "#00000040"),
            borderWidth = cond(open, 1, 0),
            borderColor = "#8c7a5566",
            cornerRadius = 8,
            pad = 12,
            borderBox = true,
            vmargin = 5,
            children = children,
        }
    end

    ---- petitions ----

    local function VotePetition(p, vote)
        audio.FireSoundEvent("Mouse.Click")
        Request("vote-petition", { petitionid = p.petitionid, vote = vote }, function(result)
            NoteRev(result)
            Replace(petitions, "petitionid", result.petition)
            Rebuild()
        end, SetError)
    end

    local function VoteArrow(icon, active, enabled, tooltip, press)
        return gui.Panel{
            width = 26,
            height = 26,
            halign = "center",
            vmargin = 2,
            bgimage = icon,
            bgcolor = cond(active, GOLD, cond(enabled, DIM, "#ffffff30")),
            styles = cond(enabled, { { selectors = {"hover"}, bgcolor = "#ffffff", scale = 1.12 } }, nil),
            hover = gui.Tooltip(tooltip),
            press = function()
                if enabled then
                    press()
                end
            end,
        }
    end

    local function PetitionRow(p)
        local open = p.status == "open"
        local canVote = open and canTakePart
        local myVote = tonumber(p.myVote) or 0
        local score = tonumber(p.score) or 0
        local scoreText = tostring(score)
        if score > 0 then
            scoreText = "+" .. scoreText
        end
        local upTooltip = T("townhall.petitions.closed_tooltip")
        local downTooltip = upTooltip
        if canVote then
            upTooltip = cond(myVote == 1, T("townhall.petitions.unvote_tooltip"), T("townhall.petitions.upvote_tooltip"))
            downTooltip = cond(myVote == -1, T("townhall.petitions.unvote_tooltip"), T("townhall.petitions.downvote_tooltip"))
        elseif open then
            upTooltip = T("townhall.need_hero")
            downTooltip = upTooltip
        end

        local voteColumn = gui.Panel{
            width = 110,
            height = "auto",
            flow = "vertical",
            valign = "top",
            VoteArrow("phosphor/thumbs-up-fill.png", myVote == 1, canVote, upTooltip, function()
                VotePetition(p, cond(myVote == 1, 0, 1))
            end),
            gui.Label{ text = scoreText, fontSize = 22, bold = true, color = cond(score > 0, GOLD, TEXT), width = "100%", height = "auto", textAlignment = "center" },
            VoteArrow("phosphor/thumbs-down-fill.png", myVote == -1, canVote, downTooltip, function()
                VotePetition(p, cond(myVote == -1, 0, -1))
            end),
            gui.Label{ text = T("townhall.petitions.tally", { up = tonumber(p.up) or 0, down = tonumber(p.down) or 0 }), fontSize = 12, color = DIM, width = "100%", height = "auto", textAlignment = "center", tmargin = 2 },
        }

        local byline = T("townhall.petitions.byline", { name = Plain(p.name), when = DescribeServerTimestamp(p.at) })
        if p.mine then
            byline = T("townhall.petitions.byline_mine", { when = DescribeServerTimestamp(p.at) })
        end
        ---@type Panel[]
        local content = {
            Label(Plain(p.title), 19, TEXT, { bold = true }),
            Label(byline, 13, DIM, { italics = true }),
            Label(Plain(p.body), 15, TEXT, { vmargin = 4 }),
        }
        if p.status == "answered" then
            content[#content+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                bgimage = "panels/square.png",
                bgcolor = "#d9b56a1c",
                borderWidth = 1,
                borderColor = "#d9b56a66",
                cornerRadius = 6,
                pad = 10,
                borderBox = true,
                tmargin = 6,
                Label(T("townhall.petitions.response_heading", { name = Plain(p.respondedByName), when = DescribeServerTimestamp(p.respondedAt) }), 14, GOLD, { bold = true }),
                Label(Plain(p.response), 15, TEXT, { tmargin = 2 }),
            }
        end
        ---@type Panel[]
        local buttons = {}
        if p.mine and open then
            buttons[#buttons+1] = ConfirmButton(T("townhall.petitions.withdraw_button"), T("townhall.dialog.confirm_click"), function()
                Request("delete-petition", { petitionid = p.petitionid }, function(result)
                    Reload(false)
                end, SetError)
            end)
        end
        if isAdmin then
            buttons[#buttons+1] = gui.Button{
                text = cond(open, T("townhall.petitions.answer_button"), T("townhall.petitions.edit_answer_button")),
                fontSize = 15,
                width = 140,
                height = 30,
                hmargin = 4,
                vmargin = 2,
                click = function()
                    ShowAnswerDialog(host, p, function(result)
                        Reload(false)
                    end)
                end,
            }
            buttons[#buttons+1] = ConfirmButton(T("townhall.petitions.remove_button"), T("townhall.dialog.confirm_click"), function()
                Request("delete-petition", { petitionid = p.petitionid }, function(result)
                    Reload(false)
                end, SetError)
            end)
        end
        if #buttons > 0 then
            content[#content+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", tmargin = 4, children = buttons }
        end

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = cond(p.mine, "#2a2418cc", "#ffffff0a"),
            cornerRadius = 8,
            pad = 10,
            borderBox = true,
            vmargin = 4,
            voteColumn,
            gui.Panel{
                width = "100%-120",
                height = "auto",
                flow = "vertical",
                lmargin = 10,
                children = content,
            },
        }
    end

    ---- building the board ----

    --Why this account cannot post a petition right now, or nil.
    local function PetitionBlocked()
        if not canTakePart then
            return T("townhall.need_hero")
        end
        if myOpen >= maxOpen then
            return T("townhall.petitions.limit_reached", { max = maxOpen })
        end
        return nil
    end

    Rebuild = function()
        if tabsPanel ~= nil and tabsPanel.valid then
            tabsPanel.children = {
                Chip(T("townhall.tabs.votes"), tab == "votes", function()
                    if tab ~= "votes" then
                        tab = "votes"
                        Reload(true)
                    end
                end),
                Chip(T("townhall.tabs.petitions"), tab == "petitions", function()
                    if tab ~= "petitions" then
                        tab = "petitions"
                        Reload(true)
                    end
                end),
            }
        end

        if toolbarPanel ~= nil and toolbarPanel.valid then
            ---@type Panel[]
            local tools = {}
            if tab == "votes" then
                if isAdmin then
                    tools[#tools+1] = Button(T("townhall.votes.post_button"), function()
                        ShowPostVoteDialog(host, function(result)
                            Reload(false)
                        end)
                    end, 260, 36, 16)
                end
            else
                tools[#tools+1] = Chip(T("townhall.petitions.board_open"), petStatus == "open", function()
                    if petStatus ~= "open" then
                        petStatus = "open"
                        Reload(true)
                    end
                end)
                tools[#tools+1] = Chip(T("townhall.petitions.board_answered"), petStatus == "answered", function()
                    if petStatus ~= "answered" then
                        petStatus = "answered"
                        Reload(true)
                    end
                end)
                tools[#tools+1] = gui.Label{ text = T("townhall.petitions.sort_label"), fontSize = 16, color = DIM, width = "auto", height = "auto", valign = "center", lmargin = 16, rmargin = 4 }
                tools[#tools+1] = Chip(T("townhall.petitions.sort_top"), petSort == "top", function()
                    if petSort ~= "top" then
                        petSort = "top"
                        Reload(true)
                    end
                end)
                tools[#tools+1] = Chip(T("townhall.petitions.sort_new"), petSort == "new", function()
                    if petSort ~= "new" then
                        petSort = "new"
                        Reload(true)
                    end
                end)
                local blocked = PetitionBlocked()
                local postButton = Button(T("townhall.petitions.post_button"), function()
                    local reason = PetitionBlocked()
                    if reason ~= nil then
                        SetError(reason)
                        return
                    end
                    ShowPostPetitionDialog(host, function(result)
                        NoteRev(result)
                        --show it where it lands: the open board, newest first.
                        petStatus = "open"
                        petSort = "new"
                        Reload(true)
                    end)
                end, 200, 36, 16)
                postButton.selfStyle.halign = "right"
                if blocked ~= nil then
                    postButton.selfStyle.opacity = 0.5
                end
                tools[#tools+1] = postButton
            end
            toolbarPanel.children = tools
        end

        if statusLabel ~= nil and statusLabel.valid then
            if errorText ~= nil then
                statusLabel.text = errorText
                statusLabel.selfStyle.color = RED
            elseif tab == "petitions" and canTakePart then
                statusLabel.text = T("townhall.petitions.my_open", { count = myOpen, max = maxOpen })
                statusLabel.selfStyle.color = DIM
            elseif not canTakePart then
                statusLabel.text = T("townhall.need_hero")
                statusLabel.selfStyle.color = DIM
            else
                statusLabel.text = ""
            end
        end

        if listPanel == nil or not listPanel.valid then
            return
        end
        ---@type Panel[]
        local rows = {}
        if tab == "votes" then
            rows[#rows+1] = Label(T("townhall.votes.intro"), 15, DIM, { italics = true, bmargin = 6 })
            if issues == nil then
                rows[#rows+1] = Label(T("townhall.loading"), 18, DIM, { textAlignment = "center", vmargin = 30 })
            elseif #issues == 0 then
                rows[#rows+1] = Label(T("townhall.votes.empty"), 18, DIM, { textAlignment = "center", vmargin = 30 })
            else
                for _, issue in ipairs(issues) do
                    rows[#rows+1] = IssueCard(issue)
                end
            end
        else
            rows[#rows+1] = Label(T("townhall.petitions.intro"), 15, DIM, { italics = true, bmargin = 6 })
            if petitions == nil then
                rows[#rows+1] = Label(T("townhall.loading"), 18, DIM, { textAlignment = "center", vmargin = 30 })
            elseif #petitions == 0 then
                rows[#rows+1] = Label(cond(petStatus == "open", T("townhall.petitions.empty_open"), T("townhall.petitions.empty_answered")), 18, DIM, { textAlignment = "center", vmargin = 30 })
            else
                for _, p in ipairs(petitions) do
                    rows[#rows+1] = PetitionRow(p)
                end
                if petMore then
                    local more = Button(T("townhall.petitions.more_button"), function()
                        LoadPetitions(true, false)
                    end, 220, 36, 16)
                    more.selfStyle.halign = "center"
                    rows[#rows+1] = more
                end
            end
        end
        listPanel.children = rows
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        create = function(element)
            Reload(true)
        end,
        --re-read the board when anyone in town changes it.
        thinkTime = 0.5,
        think = function(element)
            local conn = EotwRoster.Connection()
            if conn == nil or not conn.connected then
                return
            end
            local rev = conn:GetPath("/city/townHallRev")
            if seenRev == nil then
                seenRev = rev
                return
            end
            if rev ~= seenRev then
                seenRev = rev
                Reload(false)
            end
        end,
        children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                create = function(element)
                    tabsPanel = element
                    Rebuild()
                end,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                vmargin = 4,
                create = function(element)
                    toolbarPanel = element
                    Rebuild()
                end,
            },
            gui.Label{
                text = "",
                fontSize = 14,
                color = DIM,
                width = "100%",
                height = "auto",
                minHeight = 18,
                textWrap = true,
                create = function(element)
                    statusLabel = element
                    Rebuild()
                end,
            },
            --the strips above take about 130 (more if the toolbar wraps),
            --the tribute button below 45.
            gui.Panel{
                width = "100%",
                height = "100%-185",
                flow = "vertical",
                vscroll = true,
                rpad = 12,
                borderBox = true,
                tmargin = 6,
                create = function(element)
                    listPanel = element
                    Rebuild()
                end,
            },
            --who built the Town Hall.
            EotwDowntime.TributeButton(host, "build-town-hall"),
        },
    }
end

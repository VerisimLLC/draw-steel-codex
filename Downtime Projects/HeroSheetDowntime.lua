local mod = dmhub.GetModLoading()

--The Hero sheet's Downtime tab: the Hero's projects listed with progress bars
--beside the picked project's detail, and the Project rolls block in the card
--column. The old character sheet keeps its own Downtime tab (DTCharSheetTab).
--This mod loads after Draw Steel V, so the sheet's globals are there when
--these functions run.

HeroSheetDowntime = rawget(_G, "HeroSheetDowntime") or {}

--a project just started: the tab picks it, scrolls to it and makes it glow
--once its save has landed (HeroSheetDowntime.Select).
--- @type nil|string
local g_select = nil
--the built tab's way to pick g_select at once, when the project is already
--listed (a way in to a project that exists); set by HeroSheetDowntime.Create.
--- @type nil|fun()
local g_pick = nil

----------------------------------------------------------------------
--Sizes in sheet units.

--the list's widest and narrowest, and its share of the room beside the card
--column (500 is about a quarter of a maximized sheet).
local LIST_WIDTH = 500
local LIST_MIN_WIDTH = 320
local LIST_SHARE = 0.36
--At the Medium width the list keeps one fixed width, so the project beside it gets the rest.
local LIST_MEDIUM_WIDTH = 360
--Narrow's Projects / Rolls tabs over the list: their plate and the gap under it.
local NARROW_TABS = 40
local NARROW_TABS_GAP = 8
local COLUMN_GAP = 12
local HEADER_HEIGHT = 40
local ROW_HEIGHT = 70
--the window's card column at each width tier, and the sheet's padding.
local CARD_COLUMN = {wide = 384, medium = 320}
local CONTENT_PAD = 12
--the Project rolls block's header and foot.
local ROLLS_HEADER = 30
local ROLLS_FOOTER = 22
local ROLLS_ROW = 48
--a roller's picture: the switcher's portrait card shape (40 x 56), smaller.
local PORTRAIT_W = 30
local PORTRAIT_H = 42

local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

----------------------------------------------------------------------
--Reading the Hero's projects.

--- The Hero's downtime record, or nil. Never creates one: if another player
--- is only viewing the Hero, an empty record must not be written.
--- @param token nil|CharacterToken
--- @return nil|DTInfo
local function Info(token)
    return DTProjectEditor._peekDowntimeInfo(token)
end

--- The Director's project controls: the Director, or players the game hands them.
--- @return boolean
local function Manages()
    return DTCharSheetTab.CanManageProjects()
end

--- Roll as buttons show to the Director and, with the game setting, to players.
--- @return boolean
local function RollsHere()
    return dmhub.isDM or DTCharSheetTab.RollingFromSheetEnabled()
end

--- @class HeroDowntimeEntry
--- @field id string the project's id
--- @field project DTProject
--- @field owner CharacterToken the Hero whose record holds the project
--- @field shared boolean another Hero's project shared with this one
--- @field ownerName string

--- The Hero's own projects, then those shared with them.
--- @param token CharacterToken
--- @return HeroDowntimeEntry[]
local function Entries(token)
    local result = {}
    local info = Info(token)
    if info ~= nil then
        for _, project in ipairs(info:GetSortedProjects() or {}) do
            result[#result+1] = {id = project:GetID(), project = project, owner = token, shared = false, ownerName = token.name or ""}
        end
    end
    for _, entry in ipairs(DTBusinessRules.GetSharedProjectsForRecipient(token.charid)) do
        local owner = dmhub.GetCharacterById(entry.ownerId)
        if owner ~= nil and entry.project ~= nil then
            result[#result+1] = {id = entry.project:GetID(), project = entry.project, owner = owner, shared = true, ownerName = entry.ownerName or ""}
        end
    end
    return result
end

--- The list's groups, each in the record's order: Needs you (the
--- Director's new and milestone projects, moved out of Yours), Yours,
--- Shared with you, Complete.
--- @param entries HeroDowntimeEntry[]
--- @return HeroDowntimeEntry[] need
--- @return HeroDowntimeEntry[] own
--- @return HeroDowntimeEntry[] sharedIn shared with the Hero
--- @return HeroDowntimeEntry[] done
local function Groups(entries)
    local need, own, sharedIn, done = {}, {}, {}, {}
    for _, entry in ipairs(entries) do
        local project = entry.project
        if project:GetStatus() == DTConstants.STATUS.COMPLETE.key then
            done[#done+1] = entry
        elseif entry.shared then
            sharedIn[#sharedIn+1] = entry
        elseif dmhub.isDM and (project:IsWaitingForReview() or project:GetStatus() == DTConstants.STATUS.MILESTONE.key) then
            need[#need+1] = entry
        else
            own[#own+1] = entry
        end
    end
    return need, own, sharedIn, done
end

--- The ids of the Hero's projects in the order the tab lists them.
--- @param token CharacterToken
--- @return string[]
function HeroSheetDowntime.ListOrder(token)
    local ids = {}
    for _, group in ipairs({Groups(Entries(token))}) do
        for _, entry in ipairs(group) do
            ids[#ids+1] = entry.id
        end
    end
    return ids
end

--- @class HeroDowntimeRoller
--- @field charid string
--- @field name string
--- @field token CharacterToken
--- @field kind string "hero", "artisan", "sage" or "retainer"
--- @field rolls integer the rolls it holds (0 for a retainer)

--The line under each name in the Project rolls block.
local ROLLER_LINES = {
    hero = "From your last respite",
    artisan = "Artisan follower",
    sage = "Sage follower",
    retainer = "Retainers fight; they do not roll projects",
}

--- The Hero and their followers, the Hero first, followers by name. Only
--- artisans and sages roll; retainers are listed to say so.
--- @param token CharacterToken
--- @return HeroDowntimeRoller[]
local function Rollers(token)
    local info = Info(token)
    local result = {{
        charid = token.charid,
        name = token.name or "",
        token = token,
        kind = "hero",
        rolls = info ~= nil and info:GetAvailableRolls() or 0,
    }}
    local followers = {}
    for id, _ in pairs(token.properties:try_get(DTConstants.FOLLOWERS_STORAGE_KEY) or {}) do
        local follower = dmhub.GetCharacterById(id)
        local kind = DTFollowers.FollowerType(follower)
        if follower ~= nil and (kind == "artisan" or kind == "sage" or kind == "retainer") then
            followers[#followers+1] = {
                charid = follower.charid,
                name = follower.name or "",
                token = follower,
                kind = kind,
                rolls = (kind ~= "retainer" and info ~= nil) and info:GetFollowerRolls(id) or 0,
            }
        end
    end
    table.sort(followers, function(left, right)
        return left.name < right.name
    end)
    for _, follower in ipairs(followers) do
        result[#result+1] = follower
    end
    return result
end

--- The roller's own DTRoller, the one the roll dialog and the bane read.
--- @param roller HeroDowntimeRoller
--- @param hero CharacterToken
--- @return nil|DTRoller
local function MakeRoller(roller, hero)
    if roller.kind == "hero" then
        return DTRoller.CreateNew(roller.token.properties)
    end
    return DTRoller.CreateNew(roller.token.properties, hero.charid)
end

--- @param key string a characteristic key ("rea")
--- @return string
local function CharName(key)
    return DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, key)
end

--- The project's characteristic this roller rolls (their best), and its value.
--- @param roller DTRoller
--- @param project DTProject
--- @return nil|string key
--- @return number value
local function BestCharacteristic(roller, project)
    local allowed = project:GetTestCharacteristics() or {}
    if #allowed == 0 then
        return nil, 0
    end
    local key = DTProjectEditor._bestCharacteristic(roller, allowed)
    return key, roller:GetCharacteristic(key)
end

--- "A", "A and B", "A, B and C" (or "A, B or C" with word "or").
--- @param names string[]
--- @param word nil|string the joining word before the last name; "and" by default
--- @return string
local function JoinNames(names, word)
    if #names <= 1 then
        return names[1] or ""
    end
    return table.concat(names, ", ", 1, #names - 1) .. " " .. (word or "and") .. " " .. names[#names]
end
HeroSheetDowntime.JoinNames = JoinNames

--- The bane line: the source's language and whose rolls
--- take a bane for it, or nil when the source names no language.
--- @param langIds string[] the source's languages (a project's, or a source not yet started)
--- @param rollers {name: string, roller: DTRoller}[]
--- @return nil|string line
--- @return boolean hasBane someone's rolls take a bane
local function BaneLine(langIds, rollers)
    if #langIds == 0 or #rollers == 0 then
        return nil, false
    end
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    local langNames = {}
    for _, id in ipairs(langIds) do
        local lang = langTable[id]
        if lang ~= nil then
            langNames[#langNames+1] = lang.name
        end
    end
    if #langNames == 0 then
        return nil, false
    end
    local double, single = {}, {}
    for _, rollerEntry in ipairs(rollers) do
        local penalty = DTBusinessRules.CalcLangPenalty(langIds, rollerEntry.roller:GetLanguagesKnown())
        if penalty == DTConstants.LANGUAGE_PENALTY.UNKNOWN.key then
            double[#double+1] = rollerEntry.name
        elseif penalty == DTConstants.LANGUAGE_PENALTY.RELATED.key then
            single[#single+1] = rollerEntry.name
        end
    end
    local source = table.concat(langNames, " or ")
    if #double == 0 and #single == 0 then
        return string.format("The source is in %s, which everyone rolling knows.", source), false
    end
    local parts = {string.format("The source is in %s.", source)}
    if #double > 0 then
        parts[#parts+1] = string.format("%s %s neither it nor a related language, so their rolls have a double bane. A related language would make it a single bane.",
            JoinNames(double), cond(#double == 1, "knows", "know"))
    end
    if #single > 0 then
        parts[#parts+1] = string.format("%s %s a related language, so their rolls have a bane.",
            JoinNames(single), cond(#single == 1, "knows", "know"))
    end
    return table.concat(parts, " "), true
end

--- The bane line for a source the Hero has not started yet (New project):
--- the Hero, then their artisans and sages, as they would roll.
--- @param langIds string[]
--- @param token CharacterToken the Hero
--- @return nil|string line
--- @return boolean hasBane
function HeroSheetDowntime.BaneLine(langIds, token)
    local named = {}
    for _, roller in ipairs(Rollers(token)) do
        if roller.kind ~= "retainer" then
            local dtRoller = MakeRoller(roller, token)
            if dtRoller ~= nil then
                named[#named+1] = {name = roller.name, roller = dtRoller}
            end
        end
    end
    return BaneLine(langIds, named)
end

--- The project's kind, as the list and the detail name it.
--- @param project DTProject
--- @return string kind "Crafting", "Activity" or ""
--- @return string made the item a crafting project makes, or ""
local function Kind(project)
    local itemId = project:GetItemID()
    if itemId ~= "" then
        local item = (dmhub.GetTable("tbl_Gear") or {})[itemId]
        return "Crafting", item ~= nil and (item.name or "") or ""
    end
    if project:GetActivityID() ~= "" then
        return "Activity", ""
    end
    return "", ""
end

--- The names of the items this project has given.
--- @param project DTProject
--- @return string[]
local function GivenNames(project)
    local names = {}
    local gear = dmhub.GetTable("tbl_Gear") or {}
    for id, given in pairs(project:try_get("itemsGiven") or {}) do
        if given == true and gear[id] ~= nil then
            names[#names+1] = gear[id].name or ""
        end
    end
    table.sort(names)
    return names
end

--A stopped project's line on its row: short, so it fits; the project's
--detail shows the full line.
local SHORT_LINES = {
    waiting = "Waiting for approval",
    paused = "Paused by the Director",
    milestone = "Milestone reached",
}

--The status pill's words and look.
local PILLS = {
    active = {text = "Active", class = "heroSheetDtActive"},
    paused = {text = "Paused", class = "heroSheetDtPaused"},
    waiting = {text = "Waiting", class = "heroSheetDtPaused"},
    milestone = {text = "Milestone", class = "heroSheetDtMilestone"},
    complete = {text = "Complete", class = "heroSheetDtComplete"},
}

--- The pill a project shows: Waiting is a Paused project the Director has
--- not looked at yet.
--- @param project DTProject
--- @return string
local function PillKey(project)
    local status = project:GetStatus()
    local STATUS = DTConstants.STATUS
    if status == STATUS.ACTIVE.key then
        return "active"
    elseif status == STATUS.MILESTONE.key then
        return "milestone"
    elseif status == STATUS.COMPLETE.key then
        return "complete"
    end
    return cond(project:IsWaitingForReview(), "waiting", "paused")
end

--- The milestone a manager sees on the bar, or nil (players never see it).
--- @param project DTProject
--- @return nil|integer
local function Milestone(project)
    local threshold = project:GetMilestoneThreshold() or 0
    local goal = project:GetProjectGoal() or 0
    if not Manages() or threshold <= 0 or threshold >= goal or project:GetStatus() == DTConstants.STATUS.COMPLETE.key then
        return nil
    end
    return threshold
end

--- "16 Oct" from a progress item's commit date.
--- @param item DTProgressItem
--- @return string
local function DateText(item)
    local stamp = item:GetCommitDate()
    if type(stamp) ~= "string" then
        return ""
    end
    local _, month, day = string.match(stamp, "^(%d+)-(%d+)-(%d+)")
    local monthIndex = tonumber(month)
    if monthIndex == nil or MONTHS[monthIndex] == nil then
        return ""
    end
    return string.format("%d %s", tonumber(day) or 0, MONTHS[monthIndex])
end

--- A user's display name, plain, or nil.
--- @param userId nil|string
--- @return nil|string
local function PlayerName(userId)
    if userId == nil or userId == "" then
        return nil
    end
    local info = dmhub.GetSessionInfo(userId)
    if info ~= nil and type(info.displayName) == "string" and info.displayName ~= "" then
        return info.displayName
    end
    return nil
end

----------------------------------------------------------------------
--Small parts.

--- Paint a Hero's picture on a portrait panel: the crop of their card art,
--- else their token picture, else a blank card.
--- @param panel Panel
--- @param tok CharacterToken
--- @param aspect number the panel's width / height
function HeroSheetDowntime.ApplyPortrait(panel, tok, aspect)
    local applied = false
    --the card art helper is in another mod; any failure falls back to the
    --token picture.
    pcall(function() applied = EotwHeroCard.ApplyPortrait(panel, tok, aspect) end)
    if not applied then
        local image = tok.portrait
        local has = type(image) == "string" and image ~= ""
        panel.bgimage = has and image or "panels/square.png"
        panel.selfStyle.bgcolor = cond(has, "#ffffffff", nil)
        panel.selfStyle.imageRect = nil
    end
end

--- A small portrait card (the switcher's 40 x 56 shape): the card art's crop,
--- else the token picture. Built once per Hero; paint it again for another.
--- @param width number
--- @param height number
--- @return {panel: Panel, paint: fun(tok: nil|CharacterToken)}
local function PortraitCard(width, height)
    local panel = gui.Panel{
        classes = {"heroSheetFollowerPortrait"},
        bgimage = "panels/square.png",
        cornerRadius = 3,
        width = width,
        height = height,
        valign = "center",
        --data.tip, when set, shows on hover ("Shared with <Hero>").
        data = {tip = nil},
        linger = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
    }
    local shown = nil
    return {
        panel = panel,
        paint = function(tok)
            if tok == nil or shown == tok.charid then
                return
            end
            shown = tok.charid
            HeroSheetDowntime.ApplyPortrait(panel, tok, width / height)
        end,
    }
end

--- A small button in the sheet's style (Approve, Share, Withdraw).
--- @param text string
--- @param click fun(element: Panel)
--- @return Panel
local function SmallButton(text, click)
    return gui.Label{
        classes = {"heroSheetSmallButton", "hoverable"},
        text = text,
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 10,
        borderBox = true,
        fontSize = 12.5,
        bold = true,
        textWrap = false,
        valign = "center",
        textAlignment = "center",
        lmargin = 6,
        click = function(element)
            click(element)
        end,
    }
end

--- A small uppercase label (the sheet's section headings).
--- @param text string
--- @param args nil|table extra panel args
--- @return Panel
local function Heading(text, args)
    local labelArgs = {
        classes = {"heroSheetCardLabel"},
        text = string.upper(text),
        fontSize = 11,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    for key, value in pairs(args or {}) do
        labelArgs[key] = value
    end
    return gui.Label(labelArgs)
end

--- A status pill, painted with SetPill.
--- @return Panel
local function Pill()
    return gui.Label{
        classes = {"heroSheetDtPill"},
        text = "",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 9,
        width = "auto",
        height = 18,
        hpad = 8,
        borderBox = true,
        fontSize = 11.5,
        bold = true,
        textWrap = false,
        valign = "center",
    }
end

--- @param pill Panel
--- @param key string a PILLS key
local function SetPill(pill, key)
    local pillDef = PILLS[key] or PILLS.paused
    pill.text = pillDef.text
    for _, other in pairs(PILLS) do
        pill:SetClass(other.class, other.class == pillDef.class)
    end
end

--- @class HeroDowntimeBar
--- @field panel Panel
--- @field paint fun(project: DTProject)

--- A progress bar with the milestone notch: built once, painted per project.
--- @param height number
--- @return HeroDowntimeBar
local function Bar(height)
    local fill = gui.Panel{
        classes = {"heroSheetDtFill"},
        bgimage = "panels/square.png",
        cornerRadius = height / 2,
        floating = true,
        width = "0%",
        height = "100%",
        halign = "left",
        interactable = false,
    }
    --the notch sits after a spacer as wide as the milestone's share of the goal.
    local spacer = gui.Panel{
        width = "0%",
        height = 1,
        halign = "left",
        interactable = false,
    }
    local notch = gui.Panel{
        classes = {"heroSheetDtNotch"},
        bgimage = "panels/square.png",
        border = 1,
        width = 4,
        height = height + 6,
        halign = "left",
        valign = "center",
        interactable = false,
    }
    local notchRow = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = "100%",
        height = height + 6,
        flow = "horizontal",
        valign = "center",
        interactable = false,
        spacer,
        notch,
    }
    local panel = gui.Panel{
        classes = {"heroSheetDtTrack"},
        bgimage = "panels/square.png",
        cornerRadius = height / 2,
        width = "100%",
        height = height,
        interactable = false,
        fill,
        notchRow,
    }
    return {
        panel = panel,
        paint = function(project)
            local goal = project:GetProjectGoal() or 0
            local progress = project:GetProgress()
            local share = 0
            if goal > 0 then
                share = math.max(0, math.min(1, progress / goal))
            end
            fill.selfStyle.width = string.format("%.2f%%", share * 100)
            fill:SetClass("collapsed", share <= 0)
            local milestone = Milestone(project)
            notchRow:SetClass("collapsed", milestone == nil)
            if milestone ~= nil and goal > 0 then
                spacer.selfStyle.width = string.format("%.2f%%-2", milestone / goal * 100)
            end
        end,
    }
end

----------------------------------------------------------------------
--The Project rolls block: the Hero and their followers with the rolls each
--holds. It sits in the card column on the Downtime tab, under the card.
--Whoever has the project controls sets the counts there with - and +, as the
--old sheet's activities dialog did; a follower's count is held on the Hero.

--- Set one roller's project rolls from what they hold now, as one undo
--- step; never below 0.
--- @param charid string the Hero's own id or a follower's
--- @param change fun(current: integer): integer
local function SetRolls(charid, change)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() or not Manages() then
        return
    end
    local heroId = token.charid
    HeroSheetWrite.Save{
        description = "Set downtime rolls",
        execute = function(props)
            local info = HeroSheetDowntimeWindows.InfoForWrite(props)
            if info == nil then
                return
            end
            if charid == heroId then
                info:SetAvailableRolls(math.max(0, change(info:GetAvailableRolls())))
            else
                info:SetFollowerRolls(charid, math.max(0, change(info:GetFollowerRolls(charid))))
            end
        end,
    }
    --The Respite and the roll buttons watch the downtime settings document,
    --so touch it to make them reread the counts.
    HeroSheetDowntimeWindows.WakeWatchers(true)
end

--- @param args nil|{embedded: nil|boolean} embedded: Narrow's Rolls tab, which the tab shows and sizes
--- @return Panel
function HeroSheetDowntime.RollsPanel(args)
    local embedded = args ~= nil and args.embedded == true
    --- @class HeroDowntimeRollsRow
    --- @field panel Panel
    --- @field paint fun(roller: HeroDowntimeRoller, canSet: boolean)

    local holder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    --- @type HeroDowntimeRollsRow[]
    local rows = {}

    --- @return HeroDowntimeRollsRow
    local function NewRow()
        --a small portrait card, the switcher's 40 x 56 shape.
        local portrait = gui.Panel{
            classes = {"heroSheetFollowerPortrait"},
            bgimage = "panels/square.png",
            cornerRadius = 4,
            width = PORTRAIT_W,
            height = PORTRAIT_H,
            halign = "left",
            valign = "center",
            interactable = false,
            data = {},
        }
        local portraitFor = nil
        local name = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 14,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        local count = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        }
        local unit = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 4,
            textWrap = false,
        }
        local charid = nil
        local rolls = 0
        --- @param text string
        --- @param amount integer
        --- @return Panel
        local function Step(text, amount)
            return gui.Label{
                classes = {"heroSheetSmallButton", "hoverable"},
                text = text,
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 5,
                width = HeroSheetWindow.TargetSize(24),
                height = HeroSheetWindow.TargetSize(24),
                fontSize = 14,
                bold = true,
                textAlignment = "center",
                valign = "center",
                click = function(element)
                    if charid ~= nil then
                        SetRolls(charid, function(current)
                            return current + amount
                        end)
                    end
                end,
            }
        end
        local stepper = gui.Panel{
            classes = {"collapsed"},
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            Step("-", -1),
            --the count types in place too, as the sheet's other numbers do.
            HeroSheetTheme.ClickNumber{
                get = function()
                    return rolls
                end,
                set = function(typed)
                    if charid ~= nil then
                        SetRolls(charid, function()
                            return typed
                        end)
                    end
                end,
                fontSize = 15,
                classes = {"heroSheetCardStrong"},
            },
            Step("+", 1),
        }
        local right = gui.Panel{
            width = 90,
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                interactable = false,
                count,
                unit,
            },
            stepper,
        }
        local panel = gui.Panel{
            width = "100%",
            height = ROLLS_ROW,
            flow = "horizontal",
            portrait,
            gui.Panel{
                width = "100%-130",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                lmargin = 10,
                interactable = false,
                name,
                sub,
            },
            right,
        }
        return {
            panel = panel,
            paint = function(roller, canSet)
                charid = roller.charid
                rolls = roller.rolls
                --the card's crop of the art, as the switcher shows it; a token
                --with no card art shows its token picture.
                if portraitFor ~= roller.charid then
                    portraitFor = roller.charid
                    HeroSheetDowntime.ApplyPortrait(portrait, roller.token, PORTRAIT_W / PORTRAIT_H)
                end
                name.text = roller.name
                sub.text = ROLLER_LINES[roller.kind] or ""
                name.selfStyle.maxWidth = "100%"
                sub.selfStyle.maxWidth = "100%"
                if roller.kind == "retainer" then
                    count.text = "-"
                    unit.text = ""
                    count:SetClass("heroSheetCardStrong", false)
                    count:SetClass("heroSheetCardSub", true)
                else
                    count.text = tostring(roller.rolls)
                    unit.text = cond(roller.rolls == 1, "roll", "rolls")
                    count:SetClass("heroSheetCardStrong", true)
                    count:SetClass("heroSheetCardSub", false)
                end
                --a count someone can set shows as - n + instead.
                local stepping = canSet and roller.kind ~= "retainer"
                stepper:SetClass("collapsed", not stepping)
                count.parent:SetClass("collapsed", stepping)
                stepper:FireEventTree("refreshNumber")
            end,
        }
    end

    --The footer tells whoever sets the counts when to do it, and everyone
    --else where rolls come from.
    local footLabel = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "Rolls come from respites.",
        fontSize = 11.5,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        textWrap = false,
    }

    local block = HeroSheetRefresh.Block({
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = cond(embedded, "100%", HeroSheetCard.TREASURES_MIN_HEIGHT),
        flow = "vertical",
        vpad = 12,
        hpad = 16,
        borderBox = true,
        tmargin = cond(embedded, 0, 12),
        valign = "top",
        --in the card column on the Downtime tab beside the list; at Narrow the
        --tab's Rolls tab shows its own (embedded) one instead.
        heroSheetTab = function(element, tabid)
            if not embedded then
                element:SetClass("collapsed", tabid ~= "Downtime" or HeroSheet.Tier() == "narrow")
            end
        end,
        heroSheetTier = function(element)
            if not embedded then
                local state = HeroSheet.State()
                element:SetClass("collapsed", state == nil or state.tab ~= "Downtime" or HeroSheet.Tier() == "narrow")
            end
        end,
        gui.Panel{
            width = "100%",
            height = ROLLS_HEADER,
            flow = "horizontal",
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = "PROJECT ROLLS",
                fontSize = 16,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textWrap = false,
            },
        },
        gui.Panel{
            width = "100%",
            height = string.format("100%%-%d", ROLLS_HEADER + ROLLS_FOOTER),
            flow = "vertical",
            vscroll = true,
            holder,
        },
        gui.Panel{
            width = "100%",
            height = ROLLS_FOOTER,
            flow = "horizontal",
            footLabel,
        },
    }, {
        name = cond(embedded, "downtimeRollsNarrow", "downtimeRolls"),
        signature = function(token)
            local parts = {tostring(token.charid), tostring(Manages() and HeroSheetWrite.CanWrite())}
            for _, roller in ipairs(Rollers(token)) do
                parts[#parts+1] = table.concat({roller.charid, roller.name, roller.kind, tostring(roller.rolls)}, ":")
            end
            return table.concat(parts, "|")
        end,
        refresh = function(panel, token)
            local rollers = Rollers(token)
            local canSet = Manages() and HeroSheetWrite.CanWrite()
            footLabel.text = cond(canSet, "You set these after a respite.", "Rolls come from respites.")
            for i, roller in ipairs(rollers) do
                local row = rows[i]
                if row == nil then
                    row = NewRow()
                    rows[i] = row
                    holder:AddChild(row.panel)
                end
                row.panel:SetClass("collapsed", false)
                row.paint(roller, canSet)
            end
            for i = #rollers + 1, #rows do
                rows[i].panel:SetClass("collapsed", true)
            end
        end,
    })
    return block
end

----------------------------------------------------------------------
--The tab: the list beside the project.

--- The Downtime tab's body. A HeroSheetRefresh block: it paints when the
--- Hero's projects, the projects shared with them or the rolls they hold
--- change. Rows are kept and painted again; the detail is built once.
--- @return Panel
function HeroSheetDowntime.Create()
    local state = {
        --the project picked, by id; nil picks the first.
        --- @type nil|string
        sel = nil,
        --- @type HeroDowntimeEntry[]
        entries = {},
        --- @type nil|CharacterToken
        token = nil,
        write = false,
        --a roll just asked for: its buttons stay disabled for 2 seconds, so a
        --double click cannot roll twice.
        rollingUntil = 0,
        --At Narrow the tab splits into Projects / Rolls tabs, as the Inventory
        --does: which tab shows, and whether Projects shows the list or the
        --picked project ("list" / "project").
        narrow = false,
        --- @type nil|string the tier the rows were last painted for
        tier = nil,
        narrowTab = "projects",
        narrowView = "list",
    }
    --- @type fun()
    local PaintList
    --- @type fun()
    local PaintDetail
    --- @type fun()
    local Arrange

    --- The entry picked, else the first.
    --- @return nil|HeroDowntimeEntry
    local function Picked()
        for _, entry in ipairs(state.entries) do
            if entry.id == state.sel then
                return entry
            end
        end
        return state.entries[1]
    end

    --Save a change to one of the Hero's own projects as one undo step.
    local SaveProject = HeroSheetDowntimeWindows.SaveProject

    ------------------------------------------------------------------
    --The list's header.

    local countLabel = gui.Label{
        classes = {"heroSheetMuted"},
        text = "",
        fontSize = 14,
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    --New project, for whoever can change this Hero.
    local newButton = SmallButton("New project", function(element)
        if state.token ~= nil and state.write then
            HeroSheetDowntimeWindows.NewProject(state.token)
        end
    end)
    newButton.selfStyle.halign = "right"
    local header = gui.Panel{
        width = "100%",
        height = HEADER_HEIGHT,
        flow = "horizontal",
        gui.Label{
            classes = {"heroSheetTitle"},
            text = "Projects",
            fontSize = 20,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        countLabel,
        newButton,
    }

    ------------------------------------------------------------------
    --The rows.

    --- @class HeroDowntimeRow
    --- @field panel Panel
    --- @field paint fun(entry: HeroDowntimeEntry, needs: nil|boolean)
    --- @field entry nil|HeroDowntimeEntry

    --- Approve a project waiting for the Director: Active, reviewed, the
    --- book's next milestone when it has none.
    --- @param projectId string
    local function Approve(projectId)
        SaveProject(projectId, "Approve downtime project", function(project)
            project:Approve()
        end)
    end

    --- @return HeroDowntimeRow
    local function NewRow()
        local row = {entry = nil}
        local name = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 15,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        }
        local kind = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        local pill = Pill()
        pill.selfStyle.halign = "right"
        local bar = Bar(10)
        bar.panel.selfStyle.tmargin = 7
        local amount = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        local note = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
        }
        local top = gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            interactable = false,
            name,
            kind,
            pill,
        }
        --Needs you's Approve sits where the row's waiting line would be.
        local approve = SmallButton("Approve", function(element)
            if row.entry ~= nil then
                Approve(row.entry.id)
            end
        end)
        approve.selfStyle.halign = "right"
        approve.selfStyle.height = 20
        approve:SetClass("collapsed", true)
        local foot = gui.Panel{
            width = "100%",
            height = 20,
            flow = "horizontal",
            tmargin = 3,
            amount,
            note,
            approve,
        }
        local panel = gui.Panel{
            classes = {"heroSheetListRow", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 10,
            width = "100%",
            height = ROW_HEIGHT,
            flow = "vertical",
            hpad = 12,
            vpad = 9,
            borderBox = true,
            tmargin = 8,
            click = function(element)
                if row.entry ~= nil then
                    state.sel = row.entry.id
                    PaintList()
                    PaintDetail()
                    --at Narrow the project opens in place of the list.
                    if state.narrow then
                        state.narrowView = "project"
                        Arrange()
                    end
                end
            end,
            top,
            bar.panel,
            foot,
        }
        row.panel = panel
        row.paint = function(entry, needs)
            row.entry = entry
            local project = entry.project
            name.text = project:GetTitle()
            --a shared project names its owner where the kind would be.
            local kindText = Kind(project)
            if entry.shared and entry.ownerName ~= "" then
                kindText = "Shared by " .. entry.ownerName
            end
            kind.text = kindText
            --At Medium the list is narrow, so the kind is hidden and the name
            --gets the whole row; Narrow's list has the window's width.
            kind:SetClass("collapsed", kindText == "" or HeroSheet.Tier() == "medium")
            local key = PillKey(project)
            SetPill(pill, key)
            bar.paint(project)
            local goal = project:GetProjectGoal() or 0
            local progress = project:GetProgress()
            amount.text = string.format("<b>%d</b> / %d", progress, goal)
            --the right of the foot: what the project gave, what it waits for,
            --the next milestone (managers), or what is left.
            local right = ""
            if key == "complete" then
                local given = GivenNames(project)
                if #given > 0 then
                    right = "Gave you: " .. table.concat(given, ", ")
                end
            elseif key == "active" then
                local milestone = Milestone(project)
                if milestone ~= nil then
                    right = string.format("Next milestone %d", milestone)
                elseif goal > progress then
                    right = string.format("%d to go", goal - progress)
                end
            else
                --a stopped project's short line; the open project says it in full.
                right = SHORT_LINES[key] or ""
            end
            local approving = needs == true and project:IsWaitingForReview() and state.write
            approve:SetClass("collapsed", not approving)
            note:SetClass("collapsed", approving)
            note.text = right
            --the name takes what the kind and the pill leave.
            local room = HeroSheetTheme.TextWidth(PILLS[key].text, 11.5) + 24
            if not kind:HasClass("collapsed") then
                room = room + HeroSheetTheme.TextWidth(kindText, 12.5) + 10
            end
            name.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(room))
            note.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(HeroSheetTheme.TextWidth(string.format("%d / %d", progress, goal), 12.5) + 16))
            panel:SetClass("heroSheetRowPinned", entry.id == state.sel)
        end
        return row --[[@as HeroDowntimeRow]]
    end

    --- @class HeroDowntimeGroup
    --- @field panel Panel
    --- @field paint fun(entries: HeroDowntimeEntry[], first: boolean, showEmpty: nil|boolean)
    --- @field find fun(id: string): nil|Panel the shown row of a project

    --- @param title string
    --- @param needs nil|boolean the Director's Needs you group: rows offer Approve
    --- @param empty nil|Panel shown under the heading when the group has nothing (Yours)
    --- @return HeroDowntimeGroup
    local function NewGroup(title, needs, empty)
        local count = gui.Label{
            classes = {"heroSheetPill"},
            text = "",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            cornerRadius = 9,
            width = "auto",
            height = 18,
            hpad = 8,
            borderBox = true,
            fontSize = 12,
            bold = true,
            textWrap = false,
            halign = "right",
            valign = "center",
        }
        local holder = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
        }
        local panel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = 22,
                flow = "horizontal",
                tmargin = 16,
                Heading(title),
                count,
            },
            holder,
        }
        if empty ~= nil then
            panel:AddChild(empty)
        end
        --- @type HeroDowntimeRow[]
        local rows = {}
        return {
            panel = panel,
            find = function(id)
                for _, row in ipairs(rows) do
                    if row.entry ~= nil and row.entry.id == id and not row.panel:HasClass("collapsed") then
                        return row.panel
                    end
                end
                return nil
            end,
            paint = function(entries, first, showEmpty)
                panel:SetClass("collapsed", #entries == 0 and showEmpty ~= true)
                if empty ~= nil then
                    empty:SetClass("collapsed", showEmpty ~= true)
                end
                panel.children[1].selfStyle.tmargin = cond(first, 4, 16)
                count.text = tostring(#entries)
                for i, entry in ipairs(entries) do
                    local row = rows[i]
                    if row == nil then
                        row = NewRow()
                        rows[i] = row
                        holder:AddChild(row.panel)
                    end
                    row.panel:SetClass("collapsed", false)
                    row.paint(entry, needs)
                end
                for i = #entries + 1, #rows do
                    rows[i].panel:SetClass("collapsed", true)
                    rows[i].entry = nil
                end
            end,
        }
    end

    --The groups: Needs you (the Director's), Yours, Shared with you, Complete.
    --An empty Yours shows one line; the header's New project sits just above,
    --so it needs no second button.
    local emptyYours = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "No projects yet.",
        fontSize = 13.5,
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 8,
        textWrap = false,
    }
    local needsYou = NewGroup("Needs you", true)
    local yours = NewGroup("Yours", false, emptyYours)
    local sharedIn = NewGroup("Shared with you")
    local complete = NewGroup("Complete")
    local listContent = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bpad = 12,
        borderBox = true,
        needsYou.panel,
        yours.panel,
        sharedIn.panel,
        complete.panel,
    }
    local listScroll = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", HEADER_HEIGHT),
        flow = "vertical",
        vscroll = true,
        listContent,
    }
    local listPanel = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = LIST_WIDTH,
        height = "100%",
        flow = "vertical",
        tpad = 12,
        hpad = 16,
        borderBox = true,
        header,
        listScroll,
    }

    PaintList = function()
        local need, own, sharedEntries, done = Groups(state.entries)
        --"No projects yet." only while the Hero has none of their own at all.
        local ownAny = false
        for _, entry in ipairs(state.entries) do
            if not entry.shared then
                ownAny = true
            end
        end
        newButton:SetClass("collapsed", not state.write)
        needsYou.paint(need, true)
        yours.paint(own, #need == 0, not ownAny)
        sharedIn.paint(sharedEntries, #need == 0 and #own == 0)
        complete.paint(done, #need == 0 and #own == 0 and #sharedEntries == 0)
        countLabel.text = tostring(#state.entries)
    end

    --- Bring a new project's row into view and make it glow, once the list
    --- has laid out with it.
    --- @param id string
    local function ShowNew(id)
        --- @type nil|Panel
        local found = nil
        HeroSheetDowntimeWindows.ScrollIntoView(listScroll, listContent, function()
            local offset = 0
            for _, group in ipairs({needsYou, yours, sharedIn, complete}) do
                if found == nil and not group.panel:HasClass("collapsed") then
                    local row = group.find(id)
                    if row ~= nil then
                        found = row
                        offset = offset + group.panel.children[1].renderedHeight + 16
                        for _, other in ipairs(row.parent.children) do
                            if other == row then
                                break
                            end
                            if not other:HasClass("collapsed") then
                                offset = offset + other.renderedHeight + 8
                            end
                        end
                    else
                        offset = offset + group.panel.renderedHeight + 16
                    end
                end
            end
            if found == nil then
                return nil
            end
            --stop a little above the row so it does not sit flush on the edge.
            return offset - 20
        end, function()
            if found ~= nil and found.valid then
                HeroSheetInventory.Glow(found)
            end
        end)
    end

    ------------------------------------------------------------------
    --The project: its header, progress, the roll, details and history.

    --- @param tip string
    --- @param click fun(element: Panel)
    --- @return Panel
    local function Pencil(tip, click)
        return gui.Panel{
            classes = {"heroSheetIconButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = HeroSheetWindow.TargetSize(24),
            height = HeroSheetWindow.TargetSize(24),
            lmargin = 6,
            halign = "left",
            valign = "center",
            linger = function(element)
                gui.Tooltip(tip)(element)
            end,
            click = click,
            gui.Panel{
                classes = {"heroSheetIconButtonIcon"},
                bgimage = "phosphor/pencil-simple.png",
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end

    --- @class HeroDowntimeInPlace
    --- @field label Panel the text; a click on it starts typing when editable
    --- @field field Panel the input shown in its place while typing
    --- @field open fun()
    --- @field paint fun(text: string, editable: boolean)

    --- Text that edits in place, as the card's name does: an editable value
    --- has a dashed underline; a click (or its pencil) turns it into a field.
    --- Enter or a click away saves, Esc puts it back. While the field has the
    --- keyboard the tab does not redraw, so a change from another player never
    --- wipes what is being typed.
    --- @param args {classes: string[], fontSize: number, bold: nil|boolean, fieldWidth: string, numeric: nil|boolean, limit: integer, commit: fun(text: string)}
    --- @return HeroDowntimeInPlace
    local function InPlace(args)
        local opened = false
        local focused = false
        local editable = false
        local current = ""
        --- @type Panel
        local field
        --- @type Panel
        local label
        local function Close()
            opened = false
            focused = false
            field.captureEscape = false
            field:SetClass("collapsed", true)
            label:SetClass("collapsed", false)
        end
        --- @param text string
        local function Commit(text)
            if not opened then
                return
            end
            Close()
            text = trim((string.gsub(text or "", "%s+", " ")))
            if text == current or text == "" then
                return
            end
            if args.numeric and (tonumber(text) == nil or tonumber(text) < 1) then
                return
            end
            args.commit(text)
        end
        local function Open()
            if not editable or opened then
                return
            end
            opened = true
            field.captureEscape = true
            label:SetClass("collapsed", true)
            field:SetClass("collapsed", false)
            field.text = current
            dmhub.Schedule(0.01, function()
                if not mod.unloaded and field.valid and opened then
                    gui.SetFocus(field)
                end
            end)
        end
        label = HeroSheetTheme.EllipsisLabel{
            classes = args.classes,
            text = "",
            fontSize = args.fontSize,
            bold = args.bold == true,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            --a dashed line under an editable value (the card's name in Edit mode).
            border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
            borderStyle = "dashed",
            borderDash = 4,
            borderGap = 3,
            bpad = 2,
            borderBox = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            click = function(element)
                Open()
            end,
        }
        field = gui.Input{
            classes = {"heroSheetNameField", "collapsed"},
            width = args.fieldWidth,
            height = "auto",
            fontSize = args.fontSize,
            bold = args.bold == true,
            hpad = 4,
            borderBox = true,
            halign = "left",
            valign = "center",
            characterLimit = args.limit,
            selectAllOnFocus = true,
            placeholderText = "",
            text = "",
            captureEscape = false,
            escapePriority = EscapePriority.EXIT_DIALOG,
            escape = function(element)
                Close()
                gui.SetFocus(nil)
            end,
            focus = function(element)
                focused = true
            end,
            submit = function(element)
                local text = element.text
                focused = false
                gui.SetFocus(nil)
                Commit(text)
            end,
            --a click away saves (defocus fires whether or not anything was typed).
            defocus = function(element)
                if not focused then
                    return
                end
                focused = false
                Commit(element.text)
            end,
        }
        return {
            label = label,
            field = field,
            open = Open,
            paint = function(text, canEdit)
                --another project, or the value changed under an open field: stop typing.
                if opened and (text ~= current or not canEdit) then
                    Close()
                end
                current = text
                editable = canEdit
                label.text = text
                label:SetClass("heroSheetNameEdit", canEdit)
                label:SetClass("heroSheetDtNoEdit", not canEdit)
                label:SetClass("hoverable", canEdit)
            end,
        }
    end

    --the title edits in place: a click on it, no window.
    local titleEdit = InPlace{
        classes = {"heroSheetTitle"},
        fontSize = 20,
        bold = true,
        fieldWidth = "100%-120",
        limit = 80,
        commit = function(text)
            local entry = Picked()
            if entry ~= nil and not entry.shared then
                SaveProject(entry.id, "Rename downtime project", function(project)
                    project:SetTitle(text)
                end)
            end
        end,
    }
    local title = titleEdit.label
    local kindLine = HeroSheetTheme.EllipsisLabel{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 12.5,
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 2,
    }
    local detailPill = Pill()
    detailPill.selfStyle.halign = "right"
    --who a project is shared with (portrait cards), or its owner's on a
    --project shared with this Hero.
    --- @type {panel: Panel, paint: fun(tok: nil|CharacterToken), tip: string}[]
    local sharedCards = {}
    local sharedHolder = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        lmargin = 8,
        valign = "center",
    }
    local ownerLabel = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "Owner",
        fontSize = 12.5,
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 8,
        rmargin = 4,
        textWrap = false,
    }
    local shareButton = SmallButton("Share", function(element)
        local entry = Picked()
        if entry ~= nil and not entry.shared and state.token ~= nil then
            HeroSheetDowntimeWindows.Share(state.token, entry.id, entry.project:GetTitle())
        end
    end)
    local withdrawButton = SmallButton("Withdraw", function(element)
        local entry = Picked()
        if entry ~= nil and entry.shared and state.token ~= nil then
            HeroSheetDowntimeWindows.ConfirmWithdraw(state.token, entry.owner.charid, entry.id, entry.project:GetTitle())
        end
    end)
    --the project's "..." menu: Replace project and Delete project.
    local menuButton = gui.Panel{
        classes = {"heroSheetKeb", "hoverable", "heroSheetKebAlways"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = HeroSheetWindow.TargetSize(26),
        height = HeroSheetWindow.TargetSize(26),
        lmargin = 6,
        valign = "center",
        click = function(element)
            local entry = Picked()
            if entry == nil or entry.shared or state.token == nil then
                return
            end
            local token = state.token --[[@as CharacterToken]]
            --Opened under the button, right edges lined up: opened beside it,
            --the menu ran past the window edge and could not be clicked.
            --Replace swaps in another activity or item, so only while there
            --is no progress to lose; it keeps sharing, status and approval.
            local replaceable = entry.project:GetProgress() == 0
            HeroSheetLists.ShowMenu(element, {
                {text = "Replace project", reason = cond(replaceable, nil, "Only a project with no progress can be replaced."), click = function()
                    if replaceable then
                        local tab = cond(entry.project:GetItemID() ~= "", "crafting", "activity")
                        HeroSheetDowntimeWindows.NewProject(token, {tab = tab, projectId = entry.id})
                    end
                end},
                {text = "Delete project", danger = true, click = function()
                    HeroSheetDowntimeWindows.ConfirmDelete(token, entry.id, entry.project:GetTitle())
                end},
            }, nil, {below = true, alignRight = true})
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/dots-three-bold.png",
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    local titleActions = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        detailPill,
        ownerLabel,
        sharedHolder,
        shareButton,
        withdrawButton,
        menuButton,
    }
    local titleRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        title,
        titleEdit.field,
        titleActions,
    }

    --progress: "42 / 150 project points", Breakthroughs, Next milestone.
    local bigNumber = gui.Label{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 30,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        textWrap = false,
    }
    local ofGoal = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 14,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        lmargin = 4,
        bmargin = 4,
        textWrap = false,
    }
    local breakthroughs = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        lmargin = 24,
        bmargin = 4,
        textWrap = false,
    }
    local nextMilestone = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        lmargin = 24,
        bmargin = 4,
        textWrap = false,
    }
    local bigBar = Bar(16)
    bigBar.panel.selfStyle.tmargin = 10

    --the roll box (an Active project): the formula with the Hero's
    --characteristics, the bane line, Roll as buttons (or where to roll), why
    --a roll is off, and the breakthrough rule.
    local formula = gui.Label{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 16,
        bold = true,
        width = "auto",
        height = "auto",
        lmargin = 10,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    local charChips = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        lmargin = 6,
        halign = "left",
        valign = "center",
    }
    --- @type Panel[]
    local charChipLabels = {}
    local formulaRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        Heading("Project roll"),
        formula,
        charChips,
    }
    local baneLine = gui.Label{
        classes = {"heroSheetCardWarning"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 8,
    }
    local rollButtons = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        tmargin = 10,
    }
    --- @class HeroDowntimeRollButton
    --- @field panel Panel
    --- @field paint fun(roller: HeroDowntimeRoller, dtRoller: DTRoller, project: DTProject, blocked: boolean)

    --- @type HeroDowntimeRollButton[]
    local rollButtonPool = {}
    --- @type fun(roller: HeroDowntimeRoller, dtRoller: DTRoller)
    local Roll

    --- @return HeroDowntimeRollButton
    local function NewRollButton()
        local button = {roller = nil, dtRoller = nil, enabled = false}
        local main = gui.Label{
            classes = {"heroSheetDtRollText"},
            text = "",
            fontSize = 14,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        }
        local small = gui.Label{
            classes = {"heroSheetDtRollText"},
            text = "",
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            textWrap = false,
            interactable = false,
        }
        local panel = gui.Panel{
            classes = {"heroSheetLevelButton", "heroSheetLevelReady", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "auto",
            height = HeroSheetWindow.TargetSize(34),
            hpad = 14,
            borderBox = true,
            flow = "horizontal",
            halign = "left",
            rmargin = 8,
            bmargin = 6,
            click = function(element)
                if button.enabled and button.roller ~= nil and button.dtRoller ~= nil then
                    Roll(button.roller, button.dtRoller)
                end
            end,
            main,
            small,
        }
        button.panel = panel
        button.paint = function(roller, dtRoller, project, blocked)
            button.roller = roller
            button.dtRoller = dtRoller
            main.text = "Roll as " .. roller.name
            local key, value = BestCharacteristic(dtRoller, project)
            local bonus = ""
            if key ~= nil then
                bonus = string.format("%s %s ", CharName(key), ModStr(value))
            end
            small.text = string.format("%s(%d left)", bonus, roller.rolls)
            button.enabled = not blocked and roller.rolls > 0
            --a roll that cannot be made is a plain button, dimmed.
            panel:SetClass("heroSheetLevelReady", button.enabled)
            panel:SetClass("heroSheetDisabled", not button.enabled)
            panel:SetClass("hoverable", button.enabled)
        end
        return button --[[@as HeroDowntimeRollButton]]
    end

    --Roll in the Respite, shown instead of the Roll as buttons when the game
    --setting keeps players from rolling on the sheet.
    local respiteButton = gui.Label{
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        text = "Roll in the Respite",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(34),
        hpad = 14,
        borderBox = true,
        fontSize = 14,
        textWrap = false,
        halign = "left",
        textAlignment = "center",
        tmargin = 10,
        click = function(element)
            local shell = rawget(_G, "RSPShell")
            if shell ~= nil and shell.IsOpen() then
                return
            end
            LaunchablePanel.LaunchPanelByName("Respite")
        end,
    }
    local respiteNote = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "Project rolls happen in the Respite (Game menu). The Director can turn on rolling from the sheet with \"Players Manage Downtime Projects\" in Settings.",
        fontSize = 12.5,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 6,
    }
    --why the Roll as buttons are off.
    local setupLine = gui.Label{
        classes = {"heroSheetCardWarning"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 4,
    }
    local breakthroughRule = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "A natural 19 or 20 is a breakthrough: keep the points and roll again.",
        fontSize = 12.5,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 8,
    }
    local rollBox = gui.Panel{
        classes = {"heroSheetDtRollBox"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 12,
        hpad = 14,
        borderBox = true,
        tmargin = 26,
        formulaRow,
        baneLine,
        rollButtons,
        respiteButton,
        respiteNote,
        setupLine,
        breakthroughRule,
    }
    --a stopped project's line instead: Waiting or Paused in the roll
    --box's place, a milestone in gold with the Director's reason under it.
    local stopLine = gui.Label{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 15,
        bold = true,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    local stopReason = gui.Label{
        classes = {"heroSheetCardText"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 3,
    }
    --Approve on a waiting project, Roll the event at a milestone (managers).
    local stopApprove = SmallButton("Approve", function(element)
        local entry = Picked()
        if entry ~= nil and not entry.shared then
            Approve(entry.id)
        end
    end)
    local stopEvent = SmallButton("Roll the event", function(element)
        local entry = Picked()
        if entry ~= nil and not entry.shared and state.token ~= nil then
            HeroSheetDowntimeWindows.Event(state.token, entry.project)
        end
    end)
    for _, button in ipairs({stopApprove, stopEvent}) do
        button.selfStyle.lmargin = 0
        button.selfStyle.height = HeroSheetWindow.TargetSize(32)
        button.selfStyle.fontSize = 13.5
        button.selfStyle.halign = "left"
    end
    local stopActions = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 10,
        stopApprove,
        stopEvent,
    }
    local stopBox = gui.Panel{
        classes = {"heroSheetDtRollBox"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 12,
        hpad = 14,
        borderBox = true,
        tmargin = 26,
        stopLine,
        stopReason,
        stopActions,
    }
    --a finished project: what it gave you.
    local doneText = gui.Label{
        classes = {"heroSheetCardText"},
        text = "",
        fontSize = 14.5,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    local doneBox = gui.Panel{
        classes = {"heroSheetDtDoneBox"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 11,
        hpad = 14,
        borderBox = true,
        tmargin = 26,
        doneText,
    }

    --Details: Goal, Prerequisite and Source with pencils; the
    --characteristics and languages as chips that add and remove.
    --- @class HeroDowntimeDetailRow
    --- @field panel Panel
    --- @field value Panel the value's slot
    --- @field pencil nil|Panel

    --- @param label string
    --- @param value Panel
    --- @param pencil nil|Panel
    --- @param field nil|Panel the value's in-place field, beside it
    --- @return HeroDowntimeDetailRow
    local function DetailRow(label, value, pencil, field)
        local children = {
            gui.Panel{
                width = 130,
                height = "auto",
                flow = "horizontal",
                halign = "left",
                valign = "top",
                tmargin = 3,
                Heading(label),
            },
            value,
        }
        if field ~= nil then
            children[#children+1] = field
        end
        if pencil ~= nil then
            pencil.selfStyle.halign = "right"
            pencil.selfStyle.valign = "top"
            children[#children+1] = pencil
        end
        local panel = gui.Panel{
            classes = {"heroSheetCardRowLine"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vpad = 7,
            borderBox = true,
            children = children,
        }
        return {panel = panel, value = value, pencil = pencil}
    end

    --- An editable detail: its value in place, with the pencil that opens it.
    --- @param name string the row's heading
    --- @param tip string the pencil's tooltip
    --- @param numeric boolean
    --- @param commit fun(entry: HeroDowntimeEntry, text: string)
    --- @return HeroDowntimeDetailRow row
    --- @return HeroDowntimeInPlace edit
    local function EditRow(name, tip, numeric, commit)
        local edit = InPlace{
            classes = {"heroSheetCardText"},
            fontSize = 13.5,
            fieldWidth = "100%-180",
            numeric = numeric,
            limit = cond(numeric, 6, 200),
            commit = function(text)
                local entry = Picked()
                if entry ~= nil and not entry.shared then
                    commit(entry, text)
                end
            end,
        }
        edit.label.selfStyle.maxWidth = "100%-180"
        local row = DetailRow(name, edit.label, Pencil(tip, function(element)
            edit.open()
        end), edit.field)
        return row, edit
    end

    local goalRow, goalEdit = EditRow("Goal", "Edit goal", true, function(entry, text)
        local goal = math.max(1, math.floor(tonumber(text) or 1))
        SaveProject(entry.id, "Change downtime project goal", function(project)
            project:ChangeProjectGoal(goal)
        end)
    end)
    local prereqRow, prereqEdit = EditRow("Prerequisite", "Edit prerequisite", false, function(entry, text)
        SaveProject(entry.id, "Change downtime project prerequisite", function(project)
            project:SetItemPrerequisite(text)
        end)
    end)
    local sourceRow, sourceEdit = EditRow("Source", "Edit source", false, function(entry, text)
        SaveProject(entry.id, "Change downtime project source", function(project)
            project:SetProjectSource(text)
        end)
    end)

    --- @class HeroDowntimeChips
    --- @field panel Panel
    --- @field paint fun(chosen: string[], names: table<string, string>, options: DropdownOption[], editable: boolean, unknown: table<string, boolean>)

    --- A chip multi-select in the sheet's look (the old sheet's Multiselect, restyled):
    --- a chip per choice with an x, and a dropdown that adds one. The chips
    --- are a pool built with the row, so the dropdown never moves (moving a
    --- dropdown to another place in its parent loses its text styles).
    --- @param placeholder string the dropdown's words ("Select...")
    --- @param change fun(ids: string[])
    --- @param tail nil|Panel shown after the dropdown
    --- @return HeroDowntimeChips
    local function Chips(placeholder, change, tail)
        local chosenIds = {}
        --- @type Panel[]
        local chipPanels = {}
        local adder = gui.Dropdown{
            classes = {"heroSheetField"},
            width = 170,
            height = HeroSheetWindow.TargetSize(24),
            halign = "left",
            valign = "center",
            textDefault = placeholder,
            sort = true,
            options = {},
            idChosen = nil,
            change = function(element)
                ---@cast element Dropdown
                local id = element.idChosen
                if id == nil then
                    return
                end
                local ids = {}
                for _, chosen in ipairs(chosenIds) do
                    ids[#ids+1] = chosen
                end
                ids[#ids+1] = tostring(id)
                element.idChosen = nil
                change(ids)
            end,
        }
        --- @return Panel
        local function Chip()
            local label = gui.Label{
                classes = {"heroSheetCardText"},
                text = "",
                fontSize = 12.5,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            }
            local removeButton = gui.Panel{
                classes = {"hoverable"},
                bgimage = "panels/square.png",
                bgcolor = "clear",
                width = HeroSheetWindow.TargetSize(20),
                height = HeroSheetWindow.TargetSize(20),
                lmargin = 2,
                valign = "center",
                data = {id = nil},
                click = function(element)
                    local ids = {}
                    for _, chosen in ipairs(chosenIds) do
                        if chosen ~= element.data.id then
                            ids[#ids+1] = chosen
                        end
                    end
                    change(ids)
                end,
                gui.Panel{
                    classes = {"heroSheetXIcon"},
                    bgimage = "phosphor/x-bold.png",
                    width = 8,
                    height = 8,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            }
            return gui.Panel{
                classes = {"heroSheetDtChip"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 10,
                width = "auto",
                height = HeroSheetWindow.TargetSize(24),
                lpad = 8,
                rpad = 2,
                borderBox = true,
                flow = "horizontal",
                halign = "left",
                valign = "center",
                rmargin = 6,
                bmargin = 4,
                data = {label = label, remove = removeButton},
                label,
                removeButton,
            }
        end
        --- @return Panel[]
        local function Children()
            local children = {}
            for _, chip in ipairs(chipPanels) do
                children[#children+1] = chip
            end
            children[#children+1] = adder
            if tail ~= nil then
                children[#children+1] = tail
            end
            return children
        end
        --five fits every characteristic; more chips than the pool (a long
        --language list) rebuild the row once.
        for i = 1, 5 do
            chipPanels[i] = Chip()
            chipPanels[i]:SetClass("collapsed", true)
        end
        local holder = gui.Panel{
            width = "100%-170",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            halign = "left",
            valign = "top",
            children = Children(),
        }
        return {
            panel = holder,
            paint = function(chosen, names, options, editable, unknown)
                chosenIds = chosen
                if #chosen > #chipPanels then
                    for i = #chipPanels + 1, #chosen do
                        chipPanels[i] = Chip()
                    end
                    holder.children = Children()
                end
                for i, id in ipairs(chosen) do
                    local chip = chipPanels[i]
                    chip:SetClass("collapsed", false)
                    chip.data.label.text = names[id] or id
                    chip.data.remove.data.id = id
                    chip.data.remove:SetClass("collapsed", not editable)
                    chip.selfStyle.rpad = cond(editable, 2, 8)
                    chip:SetClass("heroSheetDtUnknown", unknown[id] == true)
                    chip.data.label:SetClass("heroSheetCardWarning", unknown[id] == true)
                    chip.data.label:SetClass("heroSheetCardText", unknown[id] ~= true)
                end
                for i = #chosen + 1, #chipPanels do
                    chipPanels[i]:SetClass("collapsed", true)
                end
                adder.options = options
                adder.idChosen = nil
                adder:SetClass("collapsed", not editable or #options == 0)
            end,
        }
    end

    local charChipsField = Chips("Select...", function(ids)
        local entry = Picked()
        if entry == nil or entry.shared then
            return
        end
        SaveProject(entry.id, "Change downtime project characteristics", function(project)
            project:SetTestCharacteristics(ids)
        end)
    end)
    local unknownNote = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "",
        fontSize = 12.5,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 2,
        textWrap = false,
    }
    local langChipsField = Chips("Select languages...", function(ids)
        local entry = Picked()
        if entry == nil or entry.shared then
            return
        end
        SaveProject(entry.id, "Change downtime project languages", function(project)
            project:SetProjectSourceLanguages(ids)
        end)
    end, unknownNote)
    local charRow = DetailRow("Characteristics", charChipsField.panel, nil)
    local langRow = DetailRow("Languages", langChipsField.panel, nil)
    local details = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 22,
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            Heading("Details"),
        },
        goalRow.panel,
        prereqRow.panel,
        sourceRow.panel,
        charRow.panel,
        langRow.panel,
    }

    --The Director's box: Status, Reason and Next milestone, for the
    --Director and players the game hands the controls; above the history.
    --- @param text string
    --- @return Panel
    local function BoxLabel(text)
        return gui.Label{
            classes = {"heroSheetFieldLabel"},
            text = string.upper(text),
            fontSize = 11,
            bold = true,
            width = "100%",
            height = 18,
            textWrap = false,
        }
    end
    local WAITING_ID = "WAITING"
    local statusDropdown = gui.Dropdown{
        classes = {"heroSheetField"},
        width = "100%",
        height = HeroSheetWindow.TargetSize(30),
        options = {},
        idChosen = nil,
        change = function(element)
            ---@cast element Dropdown
            local entry = Picked()
            local id = element.idChosen
            if entry == nil or entry.shared or id == nil or id == WAITING_ID then
                return
            end
            if id == entry.project:GetStatus() and not entry.project:IsWaitingForReview() then
                return
            end
            --any status picked by hand means the Director has dealt with it.
            SaveProject(entry.id, "Set downtime project status", function(project)
                project:SetStatus(tostring(id))
                project.reviewed = true
            end)
        end,
    }
    --- A field in the box that saves on Enter or a click away.
    --- @param numeric boolean
    --- @param placeholder string
    --- @param save fun(entry: HeroDowntimeEntry, text: string)
    --- @return Input
    local function BoxField(numeric, placeholder, save)
        local focused = false
        local function Apply(element)
            if not focused then
                return
            end
            focused = false
            local entry = Picked()
            if entry ~= nil and not entry.shared then
                save(entry, trim(element.text or ""))
            end
        end
        return gui.Input{
            classes = {"heroSheetField"},
            text = "",
            placeholderText = placeholder,
            width = "100%",
            height = HeroSheetWindow.TargetSize(30),
            hpad = 8,
            borderBox = true,
            border = 1,
            cornerRadius = 5,
            fontSize = 13.5,
            characterLimit = cond(numeric, 6, 160),
            selectAllOnFocus = numeric,
            focus = function(element)
                focused = true
            end,
            submit = function(element)
                Apply(element)
                gui.SetFocus(nil)
            end,
            defocus = function(element)
                Apply(element)
            end,
        }
    end
    local reasonField = BoxField(false, "Shown to the player", function(entry, text)
        if text ~= entry.project:GetOwnReason() then
            SaveProject(entry.id, "Set downtime project reason", function(project)
                project:SetStatusReason(text)
            end)
        end
    end)
    local milestoneField = BoxField(true, "", function(entry, text)
        local typed = tonumber(text)
        if typed ~= nil and math.floor(typed) ~= (entry.project:GetMilestoneThreshold() or 0) then
            SaveProject(entry.id, "Set next milestone", function(project)
                project:SetMilestoneThreshold(math.max(0, math.floor(typed)))
            end)
        end
    end)
    --sets the next milestone the book gives for this project's goal, or
    --blanks it when the book has none above the progress.
    local bookButton = gui.Panel{
        classes = {"heroSheetIconButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = HeroSheetWindow.TargetSize(30),
        height = HeroSheetWindow.TargetSize(30),
        lmargin = 6,
        valign = "center",
        data = {suggest = nil, clears = false},
        linger = function(element)
            if element.data.suggest ~= nil then
                gui.Tooltip(string.format("Set the next milestone to %d.", element.data.suggest))(element)
            elseif element.data.clears then
                gui.Tooltip("Clear the next milestone.")(element)
            end
        end,
        click = function(element)
            local entry = Picked()
            if entry ~= nil and not entry.shared and (element.data.suggest ~= nil or element.data.clears) then
                SaveProject(entry.id, "Set next milestone", function(project)
                    local suggest = DTBusinessRules.CalcNextMilestone(project)
                    if suggest == nil or suggest <= project:GetProgress() then
                        suggest = 0
                    end
                    project:SetMilestoneThreshold(suggest)
                end)
            end
        end,
        gui.Panel{
            classes = {"heroSheetIconButtonIcon"},
            bgimage = "phosphor/book-open.png",
            width = 15,
            height = 15,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    local directorNote = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "Your Director has given players these controls.",
        fontSize = 12.5,
        width = "100%",
        height = "auto",
        bmargin = 6,
    }
    local directorBox = gui.Panel{
        classes = {"heroSheetDtRollBox", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 12,
        hpad = 14,
        borderBox = true,
        tmargin = 22,
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            Heading("Director"),
        },
        directorNote,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = "28%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                BoxLabel("Status"),
                statusDropdown,
            },
            gui.Panel{
                width = "42%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                lmargin = 12,
                BoxLabel("Reason"),
                reasonField,
            },
            gui.Panel{
                width = "30%-24",
                height = "auto",
                flow = "vertical",
                halign = "left",
                lmargin = 12,
                BoxLabel("Next milestone"),
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    gui.Panel{
                        width = string.format("100%%-%d", HeroSheetWindow.TargetSize(30) + 6),
                        height = "auto",
                        halign = "left",
                        milestoneField,
                    },
                    bookButton,
                },
            },
        },
    }

    --History: rolls, adjustments, events and what the project gave, newest
    --first; a roll's formula shows on hover, and a roll can be deleted.
    local historyCount = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 12,
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        textWrap = false,
    }
    local historyHolder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    --- @class HeroDowntimeHistoryItem
    --- @field kind string "roll", "adjustment", "event" or "gave"
    --- @field item nil|DTProgressItem
    --- @field date string
    --- @field text string
    --- @field small string
    --- @field breakthrough boolean
    --- @field amount nil|number
    --- @field tip nil|string
    --- @field rollId nil|string a roll that can be deleted
    --- @field adjustmentId nil|string an adjustment that can be deleted
    --- @field tipDelete nil|string the delete button's tooltip

    --- @class HeroDowntimeHistoryRow
    --- @field panel Panel
    --- @field paint fun(item: HeroDowntimeHistoryItem, deletable: boolean)

    --- @type HeroDowntimeHistoryRow[]
    local historyRows = {}
    --- @type fun(rollId: string)
    local DeleteRoll

    --- Delete an adjustment: its points come off; no confirm, one Undo.
    --- @param adjustmentId string
    local function DeleteAdjustment(adjustmentId)
        local entry = Picked()
        if entry == nil or entry.shared or not state.write or not Manages() then
            return
        end
        SaveProject(entry.id, "Delete downtime adjustment", function(project)
            project:RemoveAdjustment(adjustmentId)
        end)
    end

    --- @return HeroDowntimeHistoryRow
    local function NewHistoryRow()
        local row = {item = nil}
        local date = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = 56,
            height = "auto",
            valign = "center",
            textWrap = false,
        }
        local text = gui.Label{
            classes = {"heroSheetCardText"},
            text = "",
            fontSize = 13,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        local small = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        }
        local breakthroughPill = gui.Label{
            classes = {"heroSheetDtBreakthrough", "collapsed"},
            text = "Breakthrough",
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "auto",
            height = 17,
            hpad = 7,
            borderBox = true,
            fontSize = 11,
            bold = true,
            halign = "left",
            valign = "center",
            lmargin = 6,
            textWrap = false,
        }
        local words = gui.Panel{
            width = "100%-140",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            interactable = false,
            text,
            small,
            breakthroughPill,
        }
        local amount = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 13,
            bold = true,
            width = 44,
            height = "auto",
            halign = "right",
            valign = "center",
            textAlignment = "right",
            textWrap = false,
        }
        local deleteButton = gui.Panel{
            classes = {"heroSheetXButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = HeroSheetWindow.TargetSize(22),
            height = HeroSheetWindow.TargetSize(22),
            lmargin = 8,
            halign = "right",
            valign = "center",
            linger = function(element)
                local item = row.item
                if item ~= nil and item.tipDelete ~= nil then
                    gui.Tooltip(item.tipDelete)(element)
                end
            end,
            click = function(element)
                local item = row.item
                if item ~= nil and item.rollId ~= nil then
                    DeleteRoll(item.rollId)
                elseif item ~= nil and item.adjustmentId ~= nil then
                    DeleteAdjustment(item.adjustmentId)
                end
            end,
            gui.Panel{
                classes = {"heroSheetXIcon"},
                bgimage = "phosphor/x-bold.png",
                width = 9,
                height = 9,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
        --keeps the delete button's room when there is none, so amounts line up.
        local xRoom = gui.Panel{
            width = HeroSheetWindow.TargetSize(22) + 8,
            height = 1,
            halign = "right",
            interactable = false,
        }
        local panel = gui.Panel{
            classes = {"heroSheetCardRowLine"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
            width = "100%",
            height = 34,
            flow = "horizontal",
            linger = function(element)
                local item = row.item
                if item ~= nil and item.tip ~= nil then
                    gui.Tooltip(item.tip)(element)
                end
            end,
            date,
            words,
            amount,
            deleteButton,
            xRoom,
        }
        row.panel = panel
        row.paint = function(item, deletable)
            row.item = item
            date.text = item.date
            text.text = item.text
            small.text = item.small
            small:SetClass("collapsed", item.small == "")
            --a long event text is cut to the row; its full text shows on hover.
            --100 leaves room for the Breakthrough pill when it shows.
            small.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(HeroSheetTheme.TextWidth(item.text, 13) + 6 + cond(item.breakthrough, 100, 0)))
            breakthroughPill:SetClass("collapsed", not item.breakthrough)
            amount.text = item.amount ~= nil and ModStr(item.amount) or ""
            local canDelete = deletable and (item.rollId ~= nil or item.adjustmentId ~= nil)
            deleteButton:SetClass("collapsed", not canDelete)
            xRoom:SetClass("collapsed", canDelete)
        end
        return row --[[@as HeroDowntimeHistoryRow]]
    end

    --+ Add adjustment beside the heading, for managers.
    local addAdjustment = gui.Panel{
        classes = {"heroSheetHeadPill", "hoverable", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = HeroSheetWindow.TargetSize(24),
        hpad = 9,
        borderBox = true,
        flow = "horizontal",
        halign = "right",
        valign = "center",
        click = function(element)
            local entry = Picked()
            if entry ~= nil and not entry.shared then
                HeroSheetDowntimeWindows.Adjust(entry.id, entry.project:GetTitle())
            end
        end,
        gui.Panel{
            classes = {"heroSheetHeadPillIcon"},
            bgimage = "phosphor/plus-bold.png",
            width = 11,
            height = 11,
            rmargin = 5,
            valign = "center",
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "Add adjustment",
            fontSize = 12,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local history = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 22,
        bmargin = 12,
        gui.Panel{
            width = "100%",
            height = HeroSheetWindow.TargetSize(26),
            flow = "horizontal",
            Heading("History"),
            historyCount,
            addAdjustment,
        },
        historyHolder,
    }

    --- The project's history, newest first: every roll, adjustment and
    --- event, and what it gave. An item given before projects kept a dated
    --- record of their gifts shows undated, after everything else.
    --- @param project DTProject
    --- @return HeroDowntimeHistoryItem[]
    local function HistoryItems(project)
        local dated = {}
        for _, roll in ipairs(project:GetRolls()) do
            local who = roll:GetRolledBy()
            local player = PlayerName(roll:GetCommitBy())
            local natural = roll:GetNaturalRoll() or 0
            local smallText = ""
            if roll:GetBreakthrough() then
                smallText = "Breakthrough roll"
            elseif natural >= 19 then
                smallText = string.format("Natural %d", natural)
            end
            local name = cond(who ~= nil and who ~= "", who, "")
            dated[#dated+1] = {
                time = roll.serverTime or 0,
                entry = {
                    kind = "roll",
                    item = roll,
                    date = DateText(roll),
                    text = string.format("%s%s \u{00B7} Rolled %d", name, player ~= nil and string.format(" (%s)", player) or "", roll:GetAmount()),
                    small = smallText,
                    breakthrough = natural >= 19 and not roll:GetBreakthrough(),
                    amount = roll:GetAmount(),
                    tip = roll:GetAudit(),
                    rollId = roll:GetID(),
                    --a breakthrough roll was free, so deleting it refunds nothing.
                    tipDelete = roll:GetBreakthrough() and "Delete this roll. It was a free breakthrough roll, so nothing is returned."
                        or string.format("Delete this roll and return it to %s.", cond(name ~= "", name, "the Hero")),
                },
            }
        end
        for _, adjustment in ipairs(project:GetAdjustments()) do
            local player = PlayerName(adjustment:GetCommitBy())
            dated[#dated+1] = {
                time = adjustment.serverTime or 0,
                entry = {
                    kind = "adjustment",
                    item = adjustment,
                    date = DateText(adjustment),
                    text = string.format("%s \u{00B7} Adjustment", player or "Director"),
                    small = adjustment:GetReason(),
                    breakthrough = false,
                    amount = adjustment:GetAmount(),
                    adjustmentId = adjustment:GetID(),
                    tipDelete = "Delete this adjustment.",
                },
            }
        end
        local gaveDated = {}
        for _, event in ipairs(project:GetProjectEvents()) do
            if event:GetKind() == DTProjectEvent.KIND_GAVE then
                gaveDated[event:GetItemID()] = true
                local item = (dmhub.GetTable("tbl_Gear") or {})[event:GetItemID()]
                dated[#dated+1] = {
                    time = event.serverTime or 0,
                    entry = {
                        kind = "gave",
                        item = event,
                        date = DateText(event),
                        text = "Gave you: " .. (item ~= nil and (item.name or "") or ""),
                        small = "",
                        breakthrough = false,
                    },
                }
            else
                local player = PlayerName(event:GetCommitBy())
                dated[#dated+1] = {
                    time = event.serverTime or 0,
                    entry = {
                        kind = "event",
                        item = event,
                        date = DateText(event),
                        text = string.format("%s \u{00B7} Event %d", player or "Director", event:GetTotal()),
                        small = event:GetText(),
                        breakthrough = false,
                        tip = event:GetText(),
                    },
                }
            end
        end
        table.sort(dated, function(left, right)
            return left.time > right.time
        end)
        local result = {}
        for _, datedItem in ipairs(dated) do
            result[#result+1] = datedItem.entry
        end
        local gear = dmhub.GetTable("tbl_Gear") or {}
        for id, given in pairs(project:try_get("itemsGiven") or {}) do
            if given == true and not gaveDated[id] and gear[id] ~= nil then
                result[#result+1] = {
                    kind = "gave",
                    date = "",
                    text = "Gave you: " .. (gear[id].name or ""),
                    small = "",
                    breakthrough = false,
                }
            end
        end
        return result
    end

    --Back to the list at Narrow; Esc does the same.
    local backButton = gui.Panel{
        classes = {"heroSheetPlateButton", "hoverable", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 10,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        bmargin = 10,
        click = function(element)
            state.narrowView = "list"
            Arrange()
        end,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/caret-left-bold.png",
            width = 11,
            height = 11,
            valign = "center",
            rmargin = 6,
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = "All projects",
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local detailContent = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bpad = 12,
        borderBox = true,
        backButton,
        titleRow,
        kindLine,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 10,
            bigNumber,
            ofGoal,
            breakthroughs,
            nextMilestone,
        },
        bigBar.panel,
        rollBox,
        stopBox,
        doneBox,
        details,
        directorBox,
        history,
    }
    local detailEmpty = gui.Label{
        classes = {"heroSheetMuted", "collapsed"},
        text = "",
        fontSize = 14,
        width = "100%",
        height = "auto",
        tmargin = 6,
    }
    local detailPanel = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = string.format("100%%-%d", LIST_WIDTH + COLUMN_GAP),
        height = "100%",
        flow = "vertical",
        lmargin = COLUMN_GAP,
        tpad = 14,
        hpad = 16,
        borderBox = true,
        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vscroll = true,
            detailContent,
            detailEmpty,
        },
    }

    --- Ask for a roll as one roller on the picked project; the roll records
    --- on the project's owner and spends the roller's roll from this Hero
    --- (shared projects included), as the Respite does.
    Roll = function(roller, dtRoller)
        local entry = Picked()
        local token = state.token
        if entry == nil or token == nil or dmhub.Time() < state.rollingUntil then
            return
        end
        state.rollingUntil = dmhub.Time() + 2
        --the tab repaints only when its data changes, so repaint once the
        --lock ends or a repaint during it leaves the buttons disabled.
        dmhub.Schedule(2.05, function()
            if not mod.unloaded and detailContent.valid then
                PaintDetail()
            end
        end)
        local project = entry.project
        local projectId = entry.id
        local owner = entry.owner
        local rollerCharid = roller.charid
        DTProjectEditor.PerformProjectRoll{
            project = project,
            roller = dtRoller,
            heroToken = token,
            onRolls = function(rolls)
                DTProjectEditor.RecordProjectRolls{
                    projectToken = owner,
                    projectId = projectId,
                    rolls = rolls,
                    rollHolderToken = token,
                    rollerCharid = rollerCharid,
                }
            end,
        }
    end

    --- Delete a roll on the Hero's own project and give its roll back to
    --- whoever spent it. When this Hero paid, both happen in one save,
    --- so one Undo puts the roll back and takes the refund away again.
    DeleteRoll = function(rollId)
        local entry = Picked()
        local token = state.token
        if entry == nil or entry.shared or token == nil or not state.write or not Manages() then
            return
        end
        local roll = entry.project:GetRoll(rollId)
        if roll == nil then
            return
        end
        local projectId = entry.id
        local holder, key = DTProjectEditor.RefundTarget(roll, token, nil)
        local here = holder ~= nil and holder.charid == token.charid
        HeroSheetWrite.Save{
            description = "Delete downtime project roll",
            execute = function(props)
                local info = HeroSheetDowntimeWindows.InfoForWrite(props)
                if info == nil then
                    return
                end
                local project = info:GetProject(projectId)
                if project == nil then
                    return
                end
                project:RemoveRoll(rollId)
                if here and key ~= nil then
                    if key == token.charid then
                        info:GrantRolls(1)
                    else
                        info:GrantFollowerRolls(key, 1)
                    end
                end
            end,
        }
        --another Hero paid (a shared project's roller): their own save.
        if holder ~= nil and key ~= nil and not here then
            DTProjectEditor.AdjustDowntimeRolls(holder, key, 1)
        end
        HeroSheetDowntimeWindows.WakeWatchers()
    end

    PaintDetail = function()
        local entry = Picked()
        detailContent:SetClass("collapsed", entry == nil)
        detailEmpty:SetClass("collapsed", entry ~= nil)
        local token = state.token
        if entry == nil or token == nil then
            return
        end
        local project = entry.project
        local own = not entry.shared and state.write
        local manages = Manages()

        titleEdit.paint(project:GetTitle(), own)

        --the header's right: Share and the menu on the Hero's own project
        --(whoever writes this Hero), the owner and Withdraw on a shared one.
        shareButton:SetClass("collapsed", not own)
        menuButton:SetClass("collapsed", not own)
        withdrawButton:SetClass("collapsed", not (entry.shared and state.write))
        ownerLabel:SetClass("collapsed", not entry.shared)
        local cardTokens = {}
        if entry.shared then
            cardTokens[1] = {tok = entry.owner, tip = nil}
        else
            for _, id in ipairs(DTShares.CreateNew():GetProjectSharedWith(token.charid, entry.id)) do
                local tok = dmhub.GetCharacterById(id)
                if tok ~= nil then
                    cardTokens[#cardTokens+1] = {tok = tok, tip = string.format("Shared with %s", tok.name or "")}
                end
            end
        end
        for i, card in ipairs(cardTokens) do
            local slot = sharedCards[i]
            if slot == nil then
                local made = PortraitCard(20, 28)
                slot = {panel = made.panel, paint = made.paint, tip = ""}
                made.panel.selfStyle.lmargin = 3
                sharedCards[i] = slot
                sharedHolder:AddChild(made.panel)
            end
            slot.panel:SetClass("collapsed", false)
            slot.paint(card.tok)
            slot.panel.data.tip = card.tip
        end
        for i = #cardTokens + 1, #sharedCards do
            sharedCards[i].panel:SetClass("collapsed", true)
        end
        sharedHolder:SetClass("collapsed", #cardTokens == 0)
        --the room the header's right side takes, so the title stops short of
        --it: each pill or button's text plus its padding and margins (a
        --shared portrait card is 20 wide plus a 3 margin).
        local actionsWidth = HeroSheetTheme.TextWidth(PILLS[PillKey(project)].text, 11.5) + 24
            + #cardTokens * 23 + 12
            + cond(own, HeroSheetTheme.TextWidth("Share", 12.5) + 26 + HeroSheetWindow.TargetSize(26) + 12, 0)
            + cond(entry.shared, HeroSheetTheme.TextWidth("Owner", 12.5) + 12 + cond(state.write, HeroSheetTheme.TextWidth("Withdraw", 12.5) + 26, 0), 0)
        title.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(actionsWidth + 10))
        titleEdit.field.selfStyle.width = string.format("100%%-%d", math.ceil(actionsWidth + 10))
        local kindText, itemName = Kind(project)
        local kindParts = {}
        if kindText ~= "" then
            kindParts[#kindParts+1] = kindText
        end
        if itemName ~= "" then
            kindParts[#kindParts+1] = itemName
        end
        if entry.shared and entry.ownerName ~= "" then
            kindParts[#kindParts+1] = "Shared by " .. entry.ownerName
        end
        kindLine.text = table.concat(kindParts, " \u{00B7} ")
        kindLine:SetClass("collapsed", #kindParts == 0)
        kindLine.selfStyle.maxWidth = "100%"
        local key = PillKey(project)
        SetPill(detailPill, key)

        local goal = project:GetProjectGoal() or 0
        local progress = project:GetProgress()
        bigNumber.text = tostring(progress)
        ofGoal.text = string.format("/ %d project points", goal)
        breakthroughs.text = string.format("Breakthroughs <b>%d</b>", project:GetBreakthroughRollCount())
        local milestone = Milestone(project)
        nextMilestone:SetClass("collapsed", milestone == nil or key ~= "active")
        nextMilestone.text = milestone ~= nil and string.format("Next milestone <b>%d</b>", milestone) or ""
        bigBar.paint(project)

        rollBox:SetClass("collapsed", key ~= "active")
        stopBox:SetClass("collapsed", key == "active" or key == "complete")
        doneBox:SetClass("collapsed", key ~= "complete")
        stopBox:SetClass("heroSheetDtGoldBox", key == "milestone")
        stopBox:SetClass("heroSheetDtRollBox", key ~= "milestone")

        if key == "complete" then
            local given = GivenNames(project)
            doneBox:SetClass("collapsed", #given == 0)
            doneText.text = "Gave you: <b>" .. table.concat(given, ", ") .. "</b>"
        elseif key ~= "active" then
            local line, reason = project:GetStatusLine()
            stopLine.text = line or ""
            stopReason.text = reason or ""
            stopReason:SetClass("collapsed", reason == nil)
            --managers act here: Approve a waiting project, roll a milestone's event.
            local canApprove = own and manages and key == "waiting"
            local canEvent = own and manages and key == "milestone"
            stopApprove:SetClass("collapsed", not canApprove)
            stopEvent:SetClass("collapsed", not canEvent)
            stopActions:SetClass("collapsed", not (canApprove or canEvent))
        else
            --the roll, spelled out for this Hero.
            local heroDt = DTRoller.CreateNew(token.properties)
            local rollers = {}
            for _, roller in ipairs(Rollers(token)) do
                if roller.kind ~= "retainer" then
                    local dtRoller = MakeRoller(roller, token)
                    if dtRoller ~= nil then
                        rollers[#rollers+1] = {roller = roller, dtRoller = dtRoller}
                    end
                end
            end
            local bestKey, bestValue = nil, 0
            if heroDt ~= nil then
                bestKey, bestValue = BestCharacteristic(heroDt, project)
            end
            formula.text = bestKey ~= nil and string.format("2d10 + %s %s", CharName(bestKey), ModStr(bestValue)) or ""
            local allowed = project:GetTestCharacteristics() or {}
            for i, charKey in ipairs(allowed) do
                local chip = charChipLabels[i]
                if chip == nil then
                    chip = gui.Label{
                        classes = {"heroSheetDtChip"},
                        text = "",
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 9,
                        width = "auto",
                        height = 20,
                        hpad = 8,
                        borderBox = true,
                        fontSize = 12,
                        textWrap = false,
                        valign = "center",
                        rmargin = 6,
                    }
                    charChipLabels[i] = chip
                    charChips:AddChild(chip)
                end
                chip:SetClass("collapsed", false)
                local value = heroDt ~= nil and heroDt:GetCharacteristic(charKey) or 0
                chip.text = string.format("%s %s", CharName(charKey), ModStr(value))
                chip:SetClass("heroSheetDtBest", charKey == bestKey)
            end
            for i = #allowed + 1, #charChipLabels do
                charChipLabels[i]:SetClass("collapsed", true)
            end
            local named = {}
            for _, rollerEntry in ipairs(rollers) do
                named[#named+1] = {name = rollerEntry.roller.name, roller = rollerEntry.dtRoller}
            end
            local bane, hasBane = BaneLine(project:GetProjectSourceLanguages() or {}, named)
            baneLine.text = bane or ""
            baneLine:SetClass("collapsed", bane == nil)
            --a bane is a warning; "everyone knows it" is only information.
            baneLine:SetClass("heroSheetCardWarning", hasBane)
            baneLine:SetClass("heroSheetCardSub", not hasBane)

            local setup = project:GetSetupLine()
            local here = RollsHere() and state.write
            rollButtons:SetClass("collapsed", not here)
            respiteButton:SetClass("collapsed", here)
            respiteNote:SetClass("collapsed", here)
            setupLine.text = setup or ""
            setupLine:SetClass("collapsed", setup == nil or not here)
            if here then
                local blocked = setup ~= nil or dmhub.Time() < state.rollingUntil
                for i, rollerEntry in ipairs(rollers) do
                    local button = rollButtonPool[i]
                    if button == nil then
                        button = NewRollButton()
                        rollButtonPool[i] = button
                        rollButtons:AddChild(button.panel)
                    end
                    button.panel:SetClass("collapsed", false)
                    button.paint(rollerEntry.roller, rollerEntry.dtRoller, project, blocked)
                end
                for i = #rollers + 1, #rollButtonPool do
                    rollButtonPool[i].panel:SetClass("collapsed", true)
                end
            end
        end

        --details: the owner's to edit; a shared project reads only.
        --the goal reads "150 project points"; its field takes the number alone.
        local goalEditable = own and DTProjectEditor.CanEditGoal(project)
        goalEdit.paint(tostring(goal), goalEditable)
        goalEdit.label.text = string.format("%d project points", goal)
        prereqEdit.paint(project:GetItemPrerequisite(), own)
        sourceEdit.paint(project:GetProjectSource(), own)
        goalRow.pencil:SetClass("collapsed", not goalEditable)
        prereqRow.pencil:SetClass("collapsed", not own)
        sourceRow.pencil:SetClass("collapsed", not own)

        local charNames, charOptions = {}, {}
        local chosenChars = project:GetTestCharacteristics() or {}
        local isChosen = {}
        for _, charKey in ipairs(chosenChars) do
            isChosen[charKey] = true
        end
        for _, characteristic in ipairs(DTConstants.CHARACTERISTICS) do
            charNames[characteristic.key] = characteristic.displayText
            if not isChosen[characteristic.key] then
                charOptions[#charOptions+1] = {id = characteristic.key, text = characteristic.displayText}
            end
        end
        charChipsField.paint(chosenChars, charNames, charOptions, own, {})

        local langTable = dmhub.GetTableVisible(Language.tableName) or {}
        local chosenLangs = project:GetProjectSourceLanguages() or {}
        local langChosen = {}
        for _, id in ipairs(chosenLangs) do
            langChosen[id] = true
        end
        local langNames, langOptions = {}, {}
        for id, lang in pairs(langTable) do
            langNames[id] = lang.name
            if not langChosen[id] then
                langOptions[#langOptions+1] = {id = id, text = lang.name}
            end
        end
        --a language the Hero does not know is marked, with a note after the chips.
        local known = {}
        local heroDt = DTRoller.CreateNew(token.properties)
        if heroDt ~= nil then
            known = heroDt:GetLanguagesKnown() or {}
        end
        local unknown = {}
        local anyUnknown = false
        for _, id in ipairs(chosenLangs) do
            if not known[id] then
                unknown[id] = true
                anyUnknown = true
            end
        end
        langChipsField.paint(chosenLangs, langNames, langOptions, own, unknown)
        unknownNote.text = string.format("(unknown to %s)", token.name or "")
        unknownNote:SetClass("collapsed", not anyUnknown)

        --the Director's box: the Director, or players with the controls.
        local boxShown = own and manages
        directorBox:SetClass("collapsed", not boxShown)
        if boxShown then
            directorNote:SetClass("collapsed", dmhub.isDM)
            local statusOptions = {}
            local waiting = project:IsWaitingForReview()
            if waiting then
                statusOptions[#statusOptions+1] = {id = WAITING_ID, text = "Waiting"}
            end
            for _, status in ipairs({"ACTIVE", "PAUSED", "MILESTONE", "COMPLETE"}) do
                statusOptions[#statusOptions+1] = {id = DTConstants.STATUS[status].key, text = DTConstants.STATUS[status].displayText}
            end
            statusDropdown.options = statusOptions
            statusDropdown.idChosen = cond(waiting, WAITING_ID, project:GetStatus())
            --a field being typed in keeps what is typed.
            if not reasonField.hasInputFocus then
                reasonField.text = project:GetOwnReason()
            end
            if not milestoneField.hasInputFocus then
                local threshold = project:GetMilestoneThreshold() or 0
                milestoneField.text = cond(threshold > 0, tostring(threshold), "")
            end
            local suggest = DTBusinessRules.CalcNextMilestone(project)
            if suggest ~= nil and suggest <= project:GetProgress() then
                suggest = nil
            end
            --with no stop ahead, the button blanks a milestone that is still set.
            local clears = suggest == nil and (project:GetMilestoneThreshold() or 0) > 0
            bookButton.data.suggest = suggest
            bookButton.data.clears = clears
            bookButton:SetClass("heroSheetDisabled", suggest == nil and not clears)
        end

        --history
        local items = HistoryItems(project)
        historyCount.text = cond(#items == 1, "1 entry", string.format("%d entries", #items))
        --managers get + Add adjustment where the count was.
        addAdjustment:SetClass("collapsed", not boxShown)
        historyCount:SetClass("collapsed", boxShown)
        local deletable = own and manages
        for i, item in ipairs(items) do
            local row = historyRows[i]
            if row == nil then
                row = NewHistoryRow()
                historyRows[i] = row
                historyHolder:AddChild(row.panel)
            end
            row.panel:SetClass("collapsed", false)
            row.paint(item, deletable)
        end
        for i = #items + 1, #historyRows do
            historyRows[i].panel:SetClass("collapsed", true)
        end
    end

    ------------------------------------------------------------------

    --Narrow's tabs over the list, in the sheet's list-tab look.
    --- @type table<string, Panel>
    local narrowTabs = {}
    --- @param id string
    --- @param text string
    --- @return Panel
    local function NarrowTab(id, text)
        local tab = gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable", cond(id == "projects", "selected", nil)},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 26,
            rmargin = 16,
            flow = "horizontal",
            halign = "left",
            valign = "bottom",
            click = function(element)
                state.narrowTab = id
                state.narrowView = "list"
                Arrange()
            end,
            gui.Label{
                classes = {"heroSheetListTab", cond(id == "projects", "selected", nil)},
                text = string.upper(text),
                fontSize = 16,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        narrowTabs[id] = tab
        return tab
    end
    --on a plate of its own: the frosted window would show through the tabs.
    local tabRow = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = NARROW_TABS,
        flow = "horizontal",
        hpad = 16,
        borderBox = true,
        bmargin = NARROW_TABS_GAP,
        NarrowTab("projects", "Projects"),
        NarrowTab("rolls", "Rolls"),
    }
    --Narrow's Rolls tab: a Project rolls block of its own, built the first
    --time the tab is opened (the card column, which holds the other, is
    --hidden at Narrow).
    --- @type nil|Panel
    local narrowRolls = nil

    local body
    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            state.narrowView = "list"
            Arrange()
        end,
        listPanel,
        detailPanel,
    }

    --- Show what the tier, the Narrow tab and view call for: at Wide and Medium
    --- the list beside the project; at Narrow one of the list, the project or
    --- the rolls, under the tabs.
    Arrange = function()
        local narrow = state.narrow
        tabRow:SetClass("collapsed", not narrow)
        for id, tab in pairs(narrowTabs) do
            tab:SetClassTree("selected", id == state.narrowTab)
        end
        local rolls = narrow and state.narrowTab == "rolls"
        if rolls and narrowRolls == nil then
            narrowRolls = HeroSheetDowntime.RollsPanel{embedded = true}
            body:AddChild(narrowRolls)
        end
        if narrowRolls ~= nil then
            narrowRolls:SetClass("collapsed", not rolls)
        end
        local view = cond(narrow, state.narrowView, nil)
        listPanel:SetClass("collapsed", rolls or view == "project")
        detailPanel:SetClass("collapsed", rolls or view == "list")
        backButton:SetClass("collapsed", rolls or view ~= "project")
        --Esc goes back to the list first, as on the Inventory tab.
        body.captureEscape = not rolls and view == "project"
        --a block hidden while the Hero changed is drawn before the frame shows it.
        HeroSheetRefresh.CatchUpShown()
    end

    --- The columns for the window's width: at Wide the list takes about a
    --- third of the room, within its bounds; at Medium one fixed width; the
    --- project the rest. At Narrow each takes the whole width.
    --- @param width number the window's width in sheet units
    local function Fit(width)
        local tier = HeroSheet.Tier()
        local narrow = tier == "narrow"
        if narrow then
            listPanel.selfStyle.width = "100%"
            detailPanel.selfStyle.width = "100%"
            detailPanel.selfStyle.lmargin = 0
            body.selfStyle.height = string.format("100%%-%d", NARROW_TABS + NARROW_TABS_GAP)
        else
            local card = CARD_COLUMN[tier]
            local room = width - 2 * CONTENT_PAD - cond(card ~= nil, (card or 0) + COLUMN_GAP, 0)
            local listWidth = math.floor(math.max(LIST_MIN_WIDTH, math.min(LIST_WIDTH, room * LIST_SHARE)))
            if tier == "medium" then
                listWidth = LIST_MEDIUM_WIDTH
            end
            listPanel.selfStyle.width = listWidth
            detailPanel.selfStyle.width = string.format("100%%-%d", listWidth + COLUMN_GAP)
            detailPanel.selfStyle.lmargin = COLUMN_GAP
            body.selfStyle.height = "100%"
        end
        if narrow ~= state.narrow then
            state.narrow = narrow
            state.narrowView = "list"
        end
        --the rows show their kind by tier; a resize changes the tier without
        --a change to the Hero, so no refresh would repaint them.
        if tier ~= state.tier then
            state.tier = tier
            if state.token ~= nil then
                PaintList()
            end
        end
        Arrange()
    end

    --- Pick a project and show it: at Narrow it opens in place of the list;
    --- otherwise its row is scrolled to and glows.
    --- @param id string
    local function ShowPicked(id)
        state.sel = id
        PaintList()
        PaintDetail()
        if state.narrow then
            state.narrowTab = "projects"
            state.narrowView = "project"
            Arrange()
        else
            ShowNew(id)
        end
    end

    --a project asked for (HeroSheetDowntime.Select) that is listed already.
    local function PickAsked()
        if mod.unloaded or not listPanel.valid or g_select == nil or state.token == nil then
            return
        end
        for _, entry in ipairs(state.entries) do
            if entry.id == g_select then
                g_select = nil
                ShowPicked(entry.id)
                return
            end
        end
    end
    g_pick = PickAsked

    --Shared projects live on other Heroes, and a roll's spend on this Hero's
    --followers. Every Downtime save touches these two documents, so watching
    --them keeps the tab live.
    local function Watcher(path)
        return gui.Panel{
            width = 0,
            height = 0,
            floating = true,
            interactable = false,
            create = function(element)
                dmhub.Schedule(0.2, function()
                    if not mod.unloaded and element.valid then
                        element.monitorGame = path()
                    end
                end)
            end,
            --a shared document changed, not the Hero: recheck the sheet without
            --reading the Hero again.
            refreshGame = function(element)
                HeroSheetRefresh.Recheck()
            end,
        }
    end

    return HeroSheetRefresh.Block({
        width = "100%",
        height = "100%",
        flow = "vertical",
        --the setting that hands players the controls changes what shows.
        multimonitor = {"permission:playersprojectrolls"},
        monitor = function(element)
            HeroSheetRefresh.Recheck()
        end,
        heroSheetLayout = function(element, width, height)
            Fit(width)
        end,
        --switching tab returns Narrow's view to the list.
        heroSheetTab = function(element, tabid)
            if state.narrowView ~= "list" then
                state.narrowView = "list"
                Arrange()
            end
        end,
        tabRow,
        body,
        Watcher(DTShares.GetDocumentPath),
        Watcher(DTSettings.GetDocumentPath),
    }, {
        name = "downtime",
        signature = function(token)
            local parts = {
                tostring(token.charid),
                tostring(HeroSheetWrite.CanWrite()),
                tostring(Manages()),
                tostring(RollsHere()),
                HeroSheet.Tier(),
            }
            local info = Info(token)
            if info ~= nil then
                parts[#parts+1] = dmhub.ToJson(info:try_get("downtimeProjects") or {})
                parts[#parts+1] = tostring(info:GetAvailableRolls())
                parts[#parts+1] = dmhub.ToJson(info:try_get("followerRolls") or {})
            end
            for _, entry in ipairs(DTBusinessRules.GetSharedProjectsForRecipient(token.charid)) do
                parts[#parts+1] = tostring(entry.ownerId) .. ":" .. dmhub.ToJson(entry.project)
            end
            --who this Hero shares with: the header's portraits follow a share or its end.
            parts[#parts+1] = dmhub.ToJson(DTShares.CreateNew():GetSharedBy(token.charid) or {})
            parts[#parts+1] = dmhub.ToJson(token.properties:try_get(DTConstants.FOLLOWERS_STORAGE_KEY) or {})
            return table.concat(parts, "|")
        end,
        refresh = function(panel, token)
            local previous = state.token
            if previous == nil or previous.charid ~= token.charid then
                state.sel = nil
                --another Hero at Narrow starts on the list.
                if state.narrowView ~= "list" then
                    state.narrowView = "list"
                    Arrange()
                end
            end
            state.token = token
            state.write = HeroSheetWrite.CanWrite()
            state.entries = Entries(token)
            local picked = Picked()
            state.sel = picked ~= nil and picked.id or nil
            PaintList()
            PaintDetail()
            --a project just started is picked once its save has landed.
            PickAsked()
        end,
    })
end

--- Pick a project on the tab, scrolled to and glowing (at Narrow, opened in
--- place): now if it is listed, else once it shows up there (New project
--- calls this with the project it started, before its save reaches the tab).
--- @param projectId string
function HeroSheetDowntime.Select(projectId)
    g_select = projectId
    if g_pick ~= nil then
        g_pick()
    end
end

--- Open a Hero's sheet on Downtime with one of their projects picked (the
--- Director panel's gear, the Respite feed's milestone link). Returns false
--- when this Hero opens in the old character sheet (the game's sheet
--- setting), so the caller opens the sheet its old way.
--- @param token CharacterToken
--- @param projectId nil|string
--- @return boolean
function HeroSheetDowntime.OpenOn(token, projectId)
    if not HeroSheet.Open(token, "Downtime") then
        return false
    end
    if projectId ~= nil then
        HeroSheetDowntime.Select(projectId)
    end
    return true
end

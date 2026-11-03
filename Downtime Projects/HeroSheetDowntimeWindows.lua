local mod = dmhub.GetModLoading()

--The Hero sheet's Downtime windows: the milestone event roll, Add adjustment,
--Share, New project / Replace project, and the Delete / Withdraw confirms.
--Each window saves the same changes as the matching window on the old
--character sheet. Every save is one undo step on the open Hero.

HeroSheetDowntimeWindows = rawget(_G, "HeroSheetDowntimeWindows") or {}

--the small window's width and the event window's.
local SMALL_WIDTH = 520
local EVENT_WIDTH = 640
--the event table's rows, scrolled when long (a d100 table runs long).
local EVENT_LIST_HEIGHT = 340
local FIELD_ROW = 22 + 34

--- Tell the other Downtime surfaces (the Respite, shared viewers) that
--- projects or roll counts changed: they repaint when these documents change.
--- @param settingsOnly nil|boolean only the roll counts changed
function HeroSheetDowntimeWindows.WakeWatchers(settingsOnly)
    dmhub.Schedule(0.1, function()
        if mod.unloaded then
            return
        end
        DTSettings.Touch()
        if not settingsOnly then
            DTShares.Touch()
        end
    end)
end

--- The Hero's Downtime record, for use inside a write: made in place when
--- the Hero has none yet. GetDowntimeInfo can only make one for a Hero on the
--- current map, and the sheet also opens Heroes that are not.
--- @param props creature
--- @return DTInfo
function HeroSheetDowntimeWindows.InfoForWrite(props)
    local info = props:try_get(DTConstants.CHARACTER_STORAGE_KEY)
    if info == nil then
        info = DTInfo.CreateNew()
        props[DTConstants.CHARACTER_STORAGE_KEY] = info
    end
    if type(info.GetAvailableRolls) ~= "function" then
        setmetatable(info, DTInfo)
    end
    return info
end

--- Save a change to one of the open Hero's projects as one undo step, then
--- wake the other Downtime surfaces.
--- @param projectId string
--- @param description string
--- @param change fun(project: DTProject, info: DTInfo)
--- @return boolean saved false when the Hero could not be written
local function SaveProject(projectId, description, change)
    local saved = HeroSheetWrite.Save{
        description = description,
        execute = function(props)
            local info = HeroSheetDowntimeWindows.InfoForWrite(props)
            if info == nil then
                return
            end
            local project = info:GetProject(projectId)
            if project ~= nil then
                change(project, info)
            end
        end,
    }
    HeroSheetDowntimeWindows.WakeWatchers()
    return saved
end
HeroSheetDowntimeWindows.SaveProject = SaveProject

--- Once the next layout has run, scroll a list so a point in its content sits
--- at the top. Used to bring a new or picked row into view.
--- @param scroll Panel the panel with vscroll
--- @param content Panel the panel inside it that holds the rows
--- @param offset fun(): nil|number how far down the content the point is, read after layout; nil to leave the scroll alone
--- @param after nil|fun() runs once the scroll is set
function HeroSheetDowntimeWindows.ScrollIntoView(scroll, content, offset, after)
    HeroSheetWindow.AfterLayout(function()
        if mod.unloaded or not scroll.valid or not content.valid then
            return
        end
        local point = offset()
        if point == nil then
            return
        end
        --the engine's scroll position runs from 1 at the top to 0 at the bottom.
        local range = content.renderedHeight - scroll.renderedHeight
        if range > 0 then
            scroll.vscrollPosition = 1 - math.max(0, math.min(range, point)) / range
        end
        if after ~= nil then
            after()
        end
    end)
end

--- A field's name over it (the sheet windows' small warm heading).
--- @param text string
--- @return Panel
local function FieldName(text)
    return gui.Label{
        classes = {"heroSheetFieldLabel"},
        text = string.upper(text),
        fontSize = 11.5,
        bold = true,
        width = "100%",
        height = 18,
        textWrap = false,
    }
end

--- A text or number field in the sheet windows' look.
--- @param args {text: string, placeholder: nil|string, numeric: nil|boolean, edit: nil|fun(text: string)}
--- @return Panel
local function Field(args)
    return gui.Input{
        classes = {"heroSheetField"},
        text = args.text,
        placeholderText = args.placeholder or "",
        width = "100%",
        height = HeroSheetWindow.TargetSize(34),
        hpad = 10,
        borderBox = true,
        border = 1,
        cornerRadius = 6,
        fontSize = 14,
        characterLimit = cond(args.numeric, 6, 200),
        selectAllOnFocus = args.numeric == true,
        editlag = 0.05,
        edit = function(element)
            if args.edit ~= nil then
                args.edit(element.text or "")
            end
        end,
    }
end

--- A footer button in the window's look, for the buttons left of Cancel.
--- @param text string
--- @param click fun()
--- @return Panel
local function FooterButton(text, click)
    local button = HeroSheetTheme.WindowButton(text, click, false)
    button.selfStyle.lmargin = 0
    button.selfStyle.rmargin = 10
    return button
end

--- Change a FooterButton's words. The theme's button has no setter, so this
--- finds its label by the class the theme gives it.
--- @param button Panel
--- @param text string
local function SetButtonText(button, text)
    for _, label in ipairs(button:GetChildrenWithClassRecursive("heroSheetButtonLabel")) do
        label.text = text
    end
end

--- The window's main button (Save, Resolve...), to dim while it cannot apply.
--- @param frame nil|Panel
--- @return nil|Panel
local function MainButton(frame)
    if frame == nil or not frame.valid then
        return nil
    end
    for _, panel in ipairs(frame:GetChildrenWithClassRecursive("heroSheetPrimary")) do
        if panel:HasClass("heroSheetButton") then
            return panel
        end
    end
    return nil
end

----------------------------------------------------------------------
--The milestone event: the event table, the next milestone, Roll
--(the Director's own dice) or Ask the player to roll, and Resolve, which
--writes the event into the history and puts the project back to work.

--- The words of one event table row: its first item that has text.
--- @param row table a RollTable row
--- @return string
local function RowText(row)
    for _, item in ipairs(row.value.items) do
        local str = item:ToString()
        if str ~= nil then
            return str
        end
    end
    return ""
end

--- Open the event window for one of the open Hero's projects.
--- @param token CharacterToken the Hero, who rolls when asked
--- @param project DTProject
function HeroSheetDowntimeWindows.Event(token, project)
    local projectId = project:GetID()
    --the old event dialog's helpers, so both offer the same tables.
    local options = DTEventRollDialog.StripEventTablePrefix(DTHelpers.GetEventTableOptions())
    local tableId = DTEventRollDialog.DefaultEventTableId(project, options)
    local function TableRef()
        return RollTableReference.CreateRef(DTConstants.EVENTS_TABLE, tableId)
    end
    if TableRef():GetTable() == nil then
        return
    end
    --what was rolled: the total, and the row it landed on.
    --- @type nil|number
    local rolled = nil
    local milestoneText = tostring(DTBusinessRules.CalcNextMilestone(project) or 0)
    --- @type nil|Panel
    local frame = nil
    --- @type fun()
    local PaintRows

    local list = gui.Panel{
        width = "100%-8",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    local empty = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "Roll to pick an event.",
        fontSize = 13,
        width = "100%",
        height = "auto",
        bmargin = 6,
    }
    local rollButton

    --A roll's total lights its row and lets Resolve apply it. The game's
    --table roller shows above this window, so the window stays open.
    --- @param total nil|number
    --- @param rolledOn string the table the roll was made on
    local function Rolled(total, rolledOn)
        if total == nil or mod.unloaded or frame == nil or not frame.valid then
            return
        end
        if rolledOn ~= tableId then
            --the Director switched tables while the dice were out.
            return
        end
        rolled = total
        if rollButton ~= nil and rollButton.valid then
            SetButtonText(rollButton, "Roll again")
        end
        PaintRows()
        local main = MainButton(frame)
        if main ~= nil then
            main:SetClassTree("heroSheetDisabled", false)
        end
    end

    --The Director's own dice, as the old event dialog rolls them: straight
    --away (no dialog), the table's properties naming the event on the chat card.
    local function DirectorRoll()
        local tableRef = TableRef()
        local eventsTable = tableRef:GetTable()
        if eventsTable == nil then
            return
        end
        local rollInfo = eventsTable:CalculateRollInfo()
        if rollInfo == nil then
            return
        end
        local rolledOn = tableId
        dmhub.Roll{
            roll = rollInfo.roll,
            description = eventsTable.name,
            tokenid = token.charid,
            creature = token.properties,
            properties = RollOnTableProperties.new{tableRef = tableRef},
            complete = function(info)
                Rolled(info ~= nil and info.total or nil, rolledOn)
            end,
        }
    end

    --The roll handed to the Hero's player, as the old dialog's Request Roll does.
    local function RequestRoll()
        local tableRef = TableRef()
        local eventsTable = tableRef:GetTable()
        if eventsTable == nil then
            return
        end
        local check = RollCheck.new{
            type = "table",
            id = "custom",
            group = "custom",
            text = eventsTable.name,
            tableRef = tableRef,
            rollProperties = RollOnTableProperties.new{tableRef = tableRef},
        }
        local tokens = {}
        tokens[token.charid] = {}
        local rolledOn = tableId
        dmhub.Coroutine(function()
            local resultTable = {}
            local actionid = dmhub.SendActionRequest(RollRequest.new{
                title = "Project Event",
                checks = {check},
                tokens = tokens,
            })
            AwaitRequestedActionCoroutine(actionid, resultTable)
            while resultTable.result == nil do
                coroutine.yield(0.1)
            end
            local action = resultTable.action
            local tokenResult = nil
            if action ~= nil and action.info ~= nil and action.info.tokens ~= nil then
                tokenResult = action.info.tokens[token.charid]
            end
            if tokenResult ~= nil and tokenResult.status == "complete" then
                Rolled(tokenResult.result or 0, rolledOn)
            end
        end)
    end

    --- @type Panel[]
    local rowPanels = {}
    --- @type nil|Panel
    local listScroll = nil
    --- Bring the rolled row into view once the list has laid out with it.
    --- @param index integer
    local function ScrollTo(index)
        if listScroll == nil then
            return
        end
        HeroSheetDowntimeWindows.ScrollIntoView(listScroll, list, function()
            local offset = 0
            for i = 1, index - 1 do
                local panel = rowPanels[i]
                if panel ~= nil and not panel:HasClass("collapsed") then
                    offset = offset + panel.renderedHeight
                end
            end
            --stop a little above the row so it does not sit flush on the edge.
            return offset - 10
        end)
    end
    --the table the rows were last written for: a roll only moves the lit row.
    local paintedTable = nil
    PaintRows = function()
        local eventsTable = TableRef():GetTable()
        local rows = eventsTable ~= nil and eventsTable.rows or {}
        local fresh = paintedTable ~= tableId
        paintedTable = tableId
        --each row's dice range ("7-8"), as the table roller shows it.
        local ranges = {}
        if eventsTable ~= nil and fresh then
            local info = eventsTable:CalculateRollInfo()
            ranges = info ~= nil and info.rollRanges or {}
        end
        local lit = nil
        if rolled ~= nil and eventsTable ~= nil then
            lit = eventsTable:RowIndexFromDiceResult(rolled)
        end
        for i, row in ipairs(rows) do
            local panel = rowPanels[i]
            if panel == nil then
                --one label a row (its range, then its text): a long table is
                --50 rows, and fewer panels open the window faster.
                panel = gui.Label{
                    classes = {"heroSheetFeatCard", "heroSheetBenefit", "heroSheetCardText"},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 6,
                    text = "",
                    fontSize = 13,
                    width = "100%",
                    height = "auto",
                    hpad = 10,
                    vpad = 6,
                    borderBox = true,
                    bmargin = 4,
                    textWrap = true,
                }
                rowPanels[i] = panel
                list:AddChild(panel)
                fresh = true
            end
            if fresh then
                panel:SetClass("collapsed", false)
                local text = RowText(row)
                local range = ranges[i] ~= nil and RollTable.FormatRange(ranges[i]) or tostring(i)
                panel.text = string.format("<b>%s</b>   %s", range, text)
            end
            --the row rolled, edged in the strong colour as a picked card.
            panel:SetClass("selected", i == lit)
        end
        for i = #rows + 1, #rowPanels do
            rowPanels[i]:SetClass("collapsed", true)
        end
        empty:SetClass("collapsed", rolled ~= nil)
        if lit ~= nil then
            ScrollTo(lit)
        end
    end

    local tableDropdown = gui.Dropdown{
        classes = {"heroSheetField"},
        width = "100%",
        height = HeroSheetWindow.TargetSize(34),
        options = options,
        idChosen = tableId,
        change = function(element)
            ---@cast element Dropdown
            tableId = tostring(element.idChosen)
            --another table: the last pick no longer means anything.
            rolled = nil
            if rollButton ~= nil and rollButton.valid then
                SetButtonText(rollButton, "Roll")
            end
            local main = MainButton(frame)
            if main ~= nil then
                main:SetClassTree("heroSheetDisabled", true)
            end
            PaintRows()
        end,
    }
    local milestoneField = Field{
        text = milestoneText,
        numeric = true,
        edit = function(text)
            milestoneText = text
        end,
    }
    local body = gui.Panel{
        width = "100%",
        height = FIELD_ROW + 12 + EVENT_LIST_HEIGHT,
        flow = "vertical",
        gui.Panel{
            width = "100%",
            height = FIELD_ROW,
            flow = "horizontal",
            gui.Panel{
                width = "62%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                FieldName("Event table"),
                tableDropdown,
            },
            gui.Panel{
                width = "34%",
                height = "auto",
                flow = "vertical",
                halign = "right",
                FieldName("Next milestone"),
                milestoneField,
            },
        },
    }
    listScroll = gui.Panel{
        width = "100%",
        height = EVENT_LIST_HEIGHT,
        flow = "vertical",
        tmargin = 12,
        vscroll = true,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            empty,
            list,
        },
    }
    body:AddChild(listScroll)
    rollButton = FooterButton("Roll", DirectorRoll)
    local footerLeft = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        --only the Director can ask the player to roll.
        dmhub.isDM and FooterButton("Ask the player to roll", RequestRoll) or nil,
        rollButton,
    }
    frame = HeroSheetWindow.ShowDialog{
        title = "Downtime event: " .. project:GetTitle(),
        width = EVENT_WIDTH,
        bodyHeight = FIELD_ROW + 12 + EVENT_LIST_HEIGHT,
        body = body,
        footerLeft = footerLeft,
        saveText = "Resolve",
        onSave = function()
            if rolled == nil then
                return false
            end
            local total = rolled
            local text = DTEventRollDialog.EventTextForTotal(TableRef(), total) or ""
            local eventsTable = TableRef():GetTable()
            local name = eventsTable ~= nil and eventsTable.name or ""
            local milestone = math.max(0, math.floor(tonumber(milestoneText) or 0))
            SaveProject(projectId, "Resolve downtime event", function(storedProject)
                storedProject:SetMilestoneThreshold(milestone)
                    :SetStatus(DTConstants.STATUS.ACTIVE.key)
                    :SetStatusReason("")
                storedProject:AddProjectEvent(DTProjectEvent.CreateNew{
                    kind = DTProjectEvent.KIND_EVENT,
                    tableName = name,
                    total = total,
                    text = text,
                })
            end)
        end,
    }
    PaintRows()
    local main = MainButton(frame)
    if main ~= nil then
        main:SetClassTree("heroSheetDisabled", rolled == nil)
    end
end

----------------------------------------------------------------------
--Add adjustment: project points (not 0) and a reason, as on the old sheet.

--- @param projectId string
--- @param title string the project's name
function HeroSheetDowntimeWindows.Adjust(projectId, title)
    local amountText = "10"
    local reasonText = ""
    --- @type nil|Panel
    local frame = nil
    local function Valid()
        local amount = tonumber(amountText)
        return amount ~= nil and math.floor(amount) ~= 0 and trim(reasonText) ~= ""
    end
    local function Sync()
        local main = MainButton(frame)
        if main ~= nil then
            main:SetClassTree("heroSheetDisabled", not Valid())
        end
    end
    local amountField = Field{
        text = amountText,
        numeric = true,
        edit = function(text)
            amountText = text
            Sync()
        end,
    }
    local reasonField = Field{
        text = "",
        placeholder = "A guide, a Director award",
        edit = function(text)
            reasonText = text
            Sync()
        end,
    }
    local body = gui.Panel{
        width = "100%",
        height = FIELD_ROW,
        flow = "horizontal",
        gui.Panel{
            width = "30%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            FieldName("Project points"),
            amountField,
        },
        gui.Panel{
            width = "66%",
            height = "auto",
            flow = "vertical",
            halign = "right",
            FieldName("Reason"),
            reasonField,
        },
    }
    frame = HeroSheetWindow.ShowDialog{
        title = "Adjust " .. title,
        width = SMALL_WIDTH,
        bodyHeight = FIELD_ROW,
        body = body,
        saveText = "Add adjustment",
        onSave = function()
            if not Valid() then
                return false
            end
            local amount = math.floor(tonumber(amountText) or 0)
            local reason = trim(reasonText)
            SaveProject(projectId, "Add downtime adjustment", function(project)
                local adjustment = DTAdjustment.CreateNew()
                adjustment:SetAmount(amount)
                adjustment:SetReason(reason)
                project:AddAdjustment(adjustment)
            end)
        end,
    }
    Sync()
    dmhub.Schedule(0.05, function()
        if not mod.unloaded and reasonField.valid then
            gui.SetFocus(reasonField)
        end
    end)
end

----------------------------------------------------------------------
--Share: the party's Heroes as portrait cards with a tick each; a tick
--shares or stops sharing at once, so the window has Done only.

--- @param token CharacterToken the owner
--- @param projectId string
--- @param title string
function HeroSheetDowntimeWindows.Share(token, projectId, title)
    local heroes = DTBusinessRules.GetAllHeroTokens(function(hero)
        return hero.charid ~= token.charid and hero.partyId == token.partyId
    end) or {}
    table.sort(heroes, function(left, right)
        return (left.name or "") < (right.name or "")
    end)
    local shares = DTShares.CreateNew()
    local chosen = {}
    for _, id in ipairs(shares:GetProjectSharedWith(token.charid, projectId)) do
        chosen[id] = true
    end
    --- @return string[]
    local function ChosenIds()
        local ids = {}
        for id, on in pairs(chosen) do
            if on then
                ids[#ids+1] = id
            end
        end
        return ids
    end

    --- @type Panel[]
    local rows = {
        gui.Label{
            classes = {"heroSheetCardSub"},
            text = cond(#heroes > 0, "Heroes you share with can roll on this project with their own rolls.", "No other Heroes to share with."),
            fontSize = 13,
            width = "100%",
            height = "auto",
            textWrap = true,
            bmargin = 8,
        },
    }
    for _, hero in ipairs(heroes) do
        local id = hero.charid
        local picture = gui.Panel{
            classes = {"heroSheetFollowerPortrait"},
            bgimage = "panels/square.png",
            cornerRadius = 4,
            width = 30,
            height = 42,
            valign = "center",
            interactable = false,
            data = {},
        }
        HeroSheetDowntime.ApplyPortrait(picture, hero, 30 / 42)
        local mark = gui.Panel{
            classes = {"heroSheetCheckMark", cond(chosen[id] == true, nil, "collapsed")},
            bgimage = "phosphor/check-bold.png",
            width = 13,
            height = 13,
            halign = "center",
            valign = "center",
            interactable = false,
        }
        rows[#rows+1] = gui.Panel{
            classes = {"heroSheetPopRow", "hoverable"},
            bgimage = "panels/square.png",
            cornerRadius = 6,
            width = "100%",
            height = 50,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            click = function(element)
                chosen[id] = not chosen[id]
                mark:SetClass("collapsed", not chosen[id])
                shares:Share(token.charid, projectId, ChosenIds())
                DTSettings.Touch()
            end,
            picture,
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = hero.name or "",
                fontSize = 14,
                bold = true,
                width = "100%-80",
                height = "auto",
                lmargin = 10,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
            gui.Panel{
                classes = {"heroSheetCheck"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 3,
                width = 16,
                height = 16,
                halign = "right",
                valign = "center",
                interactable = false,
                mark,
            },
        }
    end
    local height = 44 + #heroes * 50
    HeroSheetWindow.ShowDialog{
        title = "Share " .. title,
        width = SMALL_WIDTH,
        bodyHeight = math.min(height, 420),
        body = gui.Panel{
            width = "100%",
            height = math.min(height, 420),
            flow = "vertical",
            vscroll = height > 420,
            gui.Panel{
                width = "100%-8",
                height = "auto",
                flow = "vertical",
                children = rows,
            },
        },
        onDone = function() end,
    }
end

----------------------------------------------------------------------
--New project and Replace project: Activities, Crafting and Custom
--tabs, the list on the left, the picked source on the right. A project is
--written only on Start, through DTProjectEditor.StartProject (the Respite's
--start too); Replace applies another source to a project with no progress,
--keeping its sharing, status and approval.

local NEW_WIDTH = 860
local NEW_HEIGHT = 470
local NEW_LEFT = 380
local NEW_TABS = 36
local NEW_SEARCH = 36
local NEW_ROW = 50
local NEW_PITCH = NEW_ROW + 6
--the rows built: the list is a window onto the matches (189 craftable items).
local NEW_POOL = 14
--rows the pool starts above the first one in view, so a quick scroll up
--does not show a gap before the pool repaints.
local NEW_OVERSCAN = 3

--- Characteristic keys in the sheet's order, as "Might, Presence or Reason".
--- @param keys string[]
--- @return string
local function CharacteristicList(keys)
    local order = {}
    for i, characteristic in ipairs(DTConstants.CHARACTERISTICS) do
        order[characteristic.key] = i
    end
    local sorted = {}
    for _, key in ipairs(keys) do
        sorted[#sorted+1] = key
    end
    table.sort(sorted, function(left, right)
        return (order[left] or 99) < (order[right] or 99)
    end)
    local names = {}
    for _, key in ipairs(sorted) do
        names[#names+1] = DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, key)
    end
    return HeroSheetDowntime.JoinNames(names, "or")
end

--- A goal that is only a number, else nil ("Varies", "240 if your career...").
--- @param goal string
--- @return nil|integer
local function GoalNumber(goal)
    return tonumber(string.match(goal, "^%s*(%d+)%s*$"))
end

--- @class HeroNewSource
--- @field id string the activity's or item's id
--- @field name string
--- @field kind string "activity" or "crafting" (ApplySourceToProject's source types)
--- @field goal string the goal as stored ("450", "Varies")
--- @field sub string the row's small line
--- @field prereq string
--- @field source string
--- @field chars string[] characteristic keys
--- @field langIds nil|string[] read when the source is first picked (LangIds)

--- The activities, or the items a project can craft, sorted by name.
--- @param kind string "activity" or "crafting"
--- @return HeroNewSource[]
local function Sources(kind)
    local result = {}
    if kind == "activity" then
        for id, activity in unhidden_pairs(dmhub.GetTable(DowntimeActivity.tableName) or {}) do
            local chars = activity:GetTestCharacteristics() or {}
            result[#result+1] = {
                id = id,
                name = activity:GetName(),
                kind = kind,
                goal = trim(tostring(activity:GetProjectGoal() or "")),
                sub = CharacteristicList(chars),
                prereq = trim(activity:GetItemPrerequisite() or ""),
                source = trim(activity:GetProjectSource() or ""),
                chars = chars,
                langIds = activity:GetProjectSourceLanguages() or {},
            }
        end
    else
        for id, item in pairs(dmhub.GetTableVisible(equipment.tableName)) do
            if DTBusinessRules.IsCraftable(item) then
                local source = trim(item:try_get("projectSource") or "")
                result[#result+1] = {
                    id = id,
                    name = item.name or "",
                    kind = kind,
                    goal = trim(item:try_get("projectGoal") or ""),
                    sub = HeroSheetInventory.KindLine(item),
                    prereq = trim(item:try_get("itemPrerequisite") or ""),
                    source = source,
                    chars = DTHelpers.FlagListToList(item:try_get("projectRollCharacteristic")),
                }
            end
        end
    end
    table.sort(result, function(left, right)
        return left.name < right.name
    end)
    return result
end

--- A source's languages. An item's are found by reading its source text for
--- language names (slow over 189 items), so only for the one picked.
--- @param source HeroNewSource
--- @return string[]
local function LangIds(source)
    if source.langIds == nil then
        source.langIds = DTBusinessRules.ExtractLanguagesToIds(source.source) or {}
    end
    return source.langIds --[[@as string[] ]]
end

--- Open New project on the open Hero, or Replace project on one of their
--- projects (no Custom tab; the main button reads Replace).
--- @param token CharacterToken the Hero
--- @param opts nil|{tab: nil|string, itemid: nil|string, projectId: nil|string} tab "activity" / "crafting" / "custom"; itemid picks a craftable item (the Inventory's craft link); projectId replaces that project
function HeroSheetDowntimeWindows.NewProject(token, opts)
    opts = opts or {}
    local changing = opts.projectId ~= nil
    local heroName = token.name or ""
    local oldTitle = ""
    if changing then
        local info = DTProjectEditor._peekDowntimeInfo(token)
        local old = info ~= nil and info:GetProject(opts.projectId --[[@as string]]) or nil
        if old == nil then
            return
        end
        oldTitle = old:GetTitle()
    end
    local state = {
        tab = opts.tab or "activity",
        --- @type table<string, HeroNewSource[]>
        sources = {activity = Sources("activity"), crafting = Sources("crafting")},
        query = {activity = "", crafting = ""},
        --the source picked on each list tab, by id.
        sel = {activity = nil, crafting = opts.itemid},
        --- @type HeroNewSource[]
        matches = {},
        first = 1,
        --the Custom tab's fields as typed; chars by key.
        name = "",
        goal = "",
        prereq = "",
        source = "",
        --- @type table<string, boolean>
        chars = {},
    }
    if changing and state.tab == "custom" then
        state.tab = "activity"
    end
    --- @type nil|Panel
    local frame = nil
    --- @type fun()
    local PaintRight
    --- @type fun(top: boolean)
    local Refilter

    --- The source picked on the open list tab, if it is among the matches.
    --- @return nil|HeroNewSource
    local function Selected()
        local id = state.sel[state.tab]
        for _, source in ipairs(state.matches) do
            if source.id == id then
                return source
            end
        end
        return nil
    end

    --the Source text the languages were last read from (reading is slow).
    local customLangs = {text = nil, ids = {}}
    --- The Custom tab's fields as a source, for the preview and Start. Its
    --- languages are read from the Source text, as an item's are.
    --- @return HeroNewSource
    local function CustomSource()
        local chars = {}
        for _, characteristic in ipairs(DTConstants.CHARACTERISTICS) do
            if state.chars[characteristic.key] then
                chars[#chars+1] = characteristic.key
            end
        end
        local source = trim(state.source)
        if customLangs.text ~= source then
            customLangs.text = source
            customLangs.ids = DTBusinessRules.ExtractLanguagesToIds(source) or {}
        end
        return {
            id = "",
            name = trim(state.name),
            kind = "custom",
            goal = trim(state.goal),
            sub = "",
            prereq = trim(state.prereq),
            source = source,
            chars = chars,
            langIds = customLangs.ids,
        }
    end

    --- The Custom goal typed, or nil when there is none (it starts at 1).
    --- @return nil|integer
    local function CustomGoal()
        local typed = tonumber(trim(state.goal))
        if typed == nil or typed < 1 then
            return nil
        end
        return math.floor(typed)
    end

    --- Start (or Replace) dims until there is something to start.
    local function Sync()
        local main = MainButton(frame)
        if main == nil then
            return
        end
        local ready = false
        local tip = nil
        if state.tab == "custom" then
            ready = trim(state.name) ~= ""
            tip = cond(ready, nil, "Type a name to start.")
        else
            ready = Selected() ~= nil
        end
        main:SetClassTree("heroSheetDisabled", not ready)
        main.data.tip = tip
    end

    ------------------------------------------------------------------
    --The left: tabs, search, the list (or Custom's name).

    local TABS = {
        {id = "activity", text = "Activities"},
        {id = "crafting", text = "Crafting"},
    }
    if not changing then
        TABS[#TABS+1] = {id = "custom", text = "Custom"}
    end
    --- @type table<string, Panel>
    local chips = {}
    --- @type table<string, Panel>
    local searches = {}
    local listScroll
    local customPanel
    local nameField

    local function ShowTab()
        for id, chip in pairs(chips) do
            chip:SetClassTree("heroSklPicked", id == state.tab)
        end
        for id, search in pairs(searches) do
            search:SetClass("collapsed", id ~= state.tab)
        end
        listScroll:SetClass("collapsed", state.tab == "custom")
        customPanel:SetClass("collapsed", state.tab ~= "custom")
        Refilter(true)
        PaintRight()
        Sync()
        if state.tab == "custom" then
            dmhub.Schedule(0.05, function()
                if not mod.unloaded and nameField.valid then
                    gui.SetFocus(nameField)
                end
            end)
        end
    end

    local chipRow = gui.Panel{
        width = "100%",
        height = NEW_TABS,
        flow = "horizontal",
        valign = "top",
    }
    for _, def in ipairs(TABS) do
        local id = def.id
        local chip = gui.Panel{
            classes = {"heroSklChip", "hoverable", cond(id == state.tab, "heroSklPicked", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 14,
            width = "auto",
            height = HeroSheetWindow.TargetSize(28),
            hpad = 12,
            borderBox = true,
            rmargin = 6,
            halign = "left",
            valign = "top",
            click = function(element)
                if state.tab ~= id then
                    state.tab = id
                    ShowTab()
                end
            end,
            gui.Label{
                classes = {"heroSklChipText", cond(id == state.tab, "heroSklPicked", nil)},
                text = def.text,
                fontSize = 13,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        chips[id] = chip
        chipRow:AddChild(chip)
    end

    for _, id in ipairs({"activity", "crafting"}) do
        local tabid = id
        searches[tabid] = gui.SearchInput{
            classes = {"searchInput", cond(tabid == state.tab, nil, "collapsed")},
            placeholderText = cond(tabid == "activity", "Search activities", "Search items you can craft or imbue"),
            text = "",
            width = "100%",
            height = HeroSheetWindow.TargetSize(28),
            borderBox = true,
            valign = "top",
            bmargin = NEW_SEARCH - HeroSheetWindow.TargetSize(28),
            edit = function(element)
                state.query[tabid] = string.lower(trim(element.text or ""))
                Refilter(true)
                PaintRight()
                Sync()
            end,
        }
    end

    --- @class HeroNewRow
    --- @field panel Panel
    --- @field source nil|HeroNewSource
    --- @field paint fun(source: HeroNewSource)

    --- @return HeroNewRow
    local function NewRow()
        local row = {source = nil}
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
        local goal = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            textWrap = false,
        }
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = "auto",
            height = "auto",
            halign = "left",
        }
        sub.selfStyle.maxWidth = "100%"
        row.panel = gui.Panel{
            classes = {"heroSheetListRow", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = NEW_ROW,
            flow = "vertical",
            hpad = 10,
            vpad = 6,
            borderBox = true,
            tmargin = NEW_PITCH - NEW_ROW,
            click = function(element)
                if row.source ~= nil then
                    state.sel[state.tab] = row.source.id
                    Refilter(false)
                    PaintRight()
                    Sync()
                end
            end,
            gui.Panel{
                width = "100%",
                height = 20,
                flow = "horizontal",
                interactable = false,
                name,
                goal,
            },
            sub,
        }
        row.paint = function(source)
            row.source = source
            name.text = source.name
            local goalNumber = GoalNumber(source.goal)
            goal.text = goalNumber ~= nil and tostring(goalNumber) or "Varies"
            name.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(HeroSheetTheme.TextWidth(goal.text, 12.5) + 12))
            sub.text = source.sub
            sub:SetClass("collapsed", source.sub == "")
            row.panel:SetClass("heroSheetRowPinned", source.id == state.sel[state.tab])
        end
        return row --[[@as HeroNewRow]]
    end

    --a pool of rows painted with the matches in view, between two spacers
    --that keep the scroll length (the Inventory's add pane does the same).
    --- @type HeroNewRow[]
    local rows = {}
    local topSpacer = gui.Panel{width = "100%", height = 0, interactable = false}
    local bottomSpacer = gui.Panel{width = "100%", height = 0, interactable = false}
    local holder = gui.Panel{
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        topSpacer,
    }
    for i = 1, NEW_POOL do
        local row = NewRow()
        rows[i] = row
        row.panel:SetClass("collapsed", true)
        holder:AddChild(row.panel)
    end
    holder:AddChild(bottomSpacer)
    local empty = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "Nothing matches your search.",
        fontSize = 13,
        width = "auto",
        height = "auto",
        tmargin = 10,
    }

    --- The first match the pool shows, from how far the list is scrolled
    --- (the engine's vscrollPosition runs 1 at the top to 0 at the end).
    --- @return integer
    local function FirstIndex()
        local count = #state.matches
        if count <= NEW_POOL then
            return 1
        end
        local range = math.max(0, holder.renderedHeight - listScroll.renderedHeight)
        local offset = (1 - listScroll.vscrollPosition) * range
        local first = math.floor(offset / NEW_PITCH) + 1 - NEW_OVERSCAN
        return math.max(1, math.min(first, count - NEW_POOL + 1))
    end

    --- @param force boolean paint even when the first row in view is the same
    local function PaintWindow(force)
        local first = FirstIndex()
        if not force and first == state.first then
            return
        end
        state.first = first
        local matches = state.matches
        topSpacer.selfStyle.height = (first - 1) * NEW_PITCH
        for i = 1, NEW_POOL do
            local source = matches[first + i - 1]
            local row = rows[i]
            row.panel:SetClass("collapsed", source == nil)
            if source ~= nil then
                row.paint(source)
            else
                row.source = nil
            end
        end
        bottomSpacer.selfStyle.height = math.max(0, #matches - (first + NEW_POOL - 1)) * NEW_PITCH
        empty:SetClass("collapsed", #matches > 0 or state.tab == "custom")
    end

    listScroll = gui.Panel{
        width = "100%",
        height = NEW_HEIGHT - NEW_TABS - NEW_SEARCH,
        flow = "vertical",
        vscroll = true,
        --the pool follows the scroll.
        thinkTime = 0.05,
        think = function(element)
            PaintWindow(false)
        end,
        holder,
        empty,
    }

    --- The matches for the open tab's search; the pick moves to the first
    --- match when the search hides it. top: back to the start of the list.
    Refilter = function(top)
        local matches = {}
        if state.tab ~= "custom" then
            local query = state.query[state.tab]
            for _, source in ipairs(state.sources[state.tab]) do
                if query == "" or string.find(string.lower(source.name), query, 1, true) ~= nil then
                    matches[#matches+1] = source
                end
            end
        end
        state.matches = matches
        if state.tab ~= "custom" and Selected() == nil then
            state.sel[state.tab] = matches[1] ~= nil and matches[1].id or nil
        end
        if top then
            listScroll.vscrollPosition = 1
            state.first = 1
        end
        PaintWindow(true)
    end

    --Custom: the name and, optionally, the details
    --the project's Details hold; the preview on the right follows the typing.
    --- @param key string a state field
    --- @param placeholder string
    --- @param numeric nil|boolean
    --- @return Panel
    local function CustomField(key, placeholder, numeric)
        return Field{
            text = "",
            placeholder = placeholder,
            numeric = numeric,
            edit = function(text)
                state[key] = text
                PaintRight()
                Sync()
            end,
        }
    end
    nameField = CustomField("name", string.format("What is %s working on?", heroName))
    --the characteristics a roll may use: a chip each, picked or not.
    local charRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
    }
    for _, characteristic in ipairs(DTConstants.CHARACTERISTICS) do
        local key = characteristic.key
        local chip
        chip = gui.Panel{
            classes = {"heroSklChip", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 14,
            width = "auto",
            height = HeroSheetWindow.TargetSize(28),
            hpad = 10,
            borderBox = true,
            rmargin = 6,
            bmargin = 4,
            halign = "left",
            click = function(element)
                state.chars[key] = not state.chars[key]
                chip:SetClassTree("heroSklPicked", state.chars[key] == true)
                PaintRight()
            end,
            gui.Label{
                classes = {"heroSklChipText"},
                text = characteristic.displayText,
                fontSize = 13,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        charRow:AddChild(chip)
    end
    --- @param name string
    --- @param field Panel
    --- @return Panel
    local function CustomRow(name, field)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 8,
            FieldName(name),
            field,
        }
    end
    customPanel = gui.Panel{
        classes = {cond(state.tab == "custom", nil, "collapsed")},
        width = "100%-8",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        CustomRow("Name", nameField),
        gui.Panel{
            width = "40%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            bmargin = 8,
            FieldName("Goal"),
            CustomField("goal", "Project points", true),
        },
        CustomRow("Characteristics", charRow),
        CustomRow("Prerequisite", CustomField("prereq", "Optional")),
        CustomRow("Source", CustomField("source", "Optional")),
        gui.Label{
            classes = {"heroSheetCardSub"},
            text = "Only the name is needed. Anything else can be changed later under Details.",
            fontSize = 13,
            width = "100%",
            height = "auto",
            textWrap = true,
            tmargin = 2,
        },
    }

    --children pack from the top (Custom has no list to fill the column).
    local left = gui.Panel{
        width = NEW_LEFT,
        height = NEW_HEIGHT,
        flow = "vertical",
        halign = "left",
        valign = "top",
        chipRow,
        searches.activity,
        searches.crafting,
        listScroll,
        customPanel,
    }

    ------------------------------------------------------------------
    --The right: the picked source as the project will read it.

    local heading = gui.Label{
        classes = {"heroSheetTitle"},
        text = "",
        fontSize = 20,
        bold = true,
        width = "100%",
        height = "auto",
        textWrap = true,
        bmargin = 6,
    }
    --- @class HeroNewDetail
    --- @field panel Panel
    --- @field value Panel

    --- A detail as the project's Details show it: the heading, then the value.
    --- @param label string
    --- @return HeroNewDetail
    local function Detail(label)
        local value = gui.Label{
            classes = {"heroSheetCardText"},
            text = "",
            fontSize = 13.5,
            width = "100%-120",
            height = "auto",
            halign = "left",
            textWrap = true,
        }
        local panel = gui.Panel{
            classes = {"heroSheetCardRowLine"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vpad = 7,
            borderBox = true,
            gui.Label{
                classes = {"heroSheetCardLabel"},
                text = string.upper(label),
                fontSize = 11,
                bold = true,
                width = 120,
                height = "auto",
                halign = "left",
                valign = "top",
                tmargin = 2,
                textWrap = false,
            },
            value,
        }
        return {panel = panel, value = value}
    end
    local goalDetail = Detail("Goal")
    local prereqDetail = Detail("Prerequisite")
    local sourceDetail = Detail("Source")
    local charsDetail = Detail("Characteristics")
    local langsDetail = Detail("Languages")
    local bane = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 10,
    }
    local craftNote = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        textWrap = true,
        tmargin = 10,
    }
    local sourcePanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        heading,
        goalDetail.panel,
        prereqDetail.panel,
        sourceDetail.panel,
        charsDetail.panel,
        langsDetail.panel,
        bane,
        craftNote,
    }
    local right = gui.Panel{
        width = string.format("100%%-%d", NEW_LEFT + 24),
        height = NEW_HEIGHT,
        flow = "vertical",
        halign = "right",
        vscroll = true,
        gui.Panel{
            width = "100%-8",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            sourcePanel,
        },
    }

    PaintRight = function()
        local custom = state.tab == "custom"
        local source = Selected()
        if custom then
            source = CustomSource()
        end
        sourcePanel:SetClass("collapsed", source == nil)
        if source == nil then
            return
        end
        heading.text = source.name
        heading:SetClass("collapsed", source.name == "")
        --a goal that is only a number reads in points; one with words stays as
        --the book wrote it; none at all is the Director's to set.
        --A custom goal left empty keeps the default of 1.
        local goalNumber = GoalNumber(source.goal)
        if custom then
            local goal = CustomGoal()
            goalDetail.value.text = goal ~= nil and string.format("%d project points", goal)
                or "Not set. It starts at 1 until you change it under Details."
        elseif goalNumber ~= nil then
            goalDetail.value.text = string.format("%d project points", goalNumber)
        elseif string.match(source.goal, "^%d") ~= nil then
            goalDetail.value.text = source.goal
        else
            goalDetail.value.text = "Varies. The Director sets the goal."
        end
        prereqDetail.value.text = cond(source.prereq == "", "None", source.prereq)
        sourceDetail.value.text = source.source
        sourceDetail.panel:SetClass("collapsed", source.source == "")
        charsDetail.value.text = CharacteristicList(source.chars)
        charsDetail.panel:SetClass("collapsed", #source.chars == 0)
        local langNames = {}
        local langTable = dmhub.GetTableVisible(Language.tableName) or {}
        local langIds = LangIds(source)
        for _, id in ipairs(langIds) do
            if langTable[id] ~= nil then
                langNames[#langNames+1] = langTable[id].name
            end
        end
        langsDetail.value.text = cond(#langNames == 0, "None", table.concat(langNames, ", "))
        local line, hasBane = HeroSheetDowntime.BaneLine(langIds, token)
        bane.text = line or ""
        bane:SetClass("collapsed", line == nil)
        bane:SetClass("heroSheetCardWarning", hasBane)
        bane:SetClass("heroSheetCardSub", not hasBane)
        craftNote.text = string.format("When it is done, %s goes into %s's inventory.", source.name, heroName)
        craftNote:SetClass("collapsed", source.kind ~= "crafting")
    end

    ------------------------------------------------------------------

    local body = gui.Panel{
        width = "100%",
        height = NEW_HEIGHT,
        flow = "horizontal",
        left,
        right,
    }

    --- Start the project (one undo step), or replace the project with the source.
    --- @return nil|boolean false keeps the window open
    local function Commit()
        local source = Selected()
        if state.tab == "custom" then
            if trim(state.name) == "" then
                return false
            end
        elseif source == nil then
            return false
        end
        if changing then
            if source == nil then
                return false
            end
            local chosen = source
            local projectId = opts.projectId --[[@as string]]
            local saved = SaveProject(projectId, "Replace downtime project", function(project)
                DTBusinessRules.ApplySourceToProject(project, chosen.kind, chosen.id)
                --a new goal moves the milestones: an Active project takes the
                --book's next one for it, as Approve gives.
                if project:GetStatus() == DTConstants.STATUS.ACTIVE.key then
                    project:SetMilestoneThreshold(DTBusinessRules.CalcNextMilestone(project) or 0)
                end
            end)
            if not saved then
                return false
            end
            HeroSheetWindow.Toast(string.format("%s replaced with %s.", oldTitle, chosen.name))
            return
        end
        local projectId = dmhub.GenerateGuid()
        local waits = not DTCharSheetTab.CanManageProjects()
        local sourceType = state.tab
        local name = trim(state.name)
        --- @type nil|{goal: nil|integer, chars: string[], prereq: string, source: string, langIds: string[]}
        local custom = nil
        if sourceType == "custom" then
            local typed = CustomSource()
            custom = {
                goal = CustomGoal(),
                chars = typed.chars,
                prereq = typed.prereq,
                source = typed.source,
                langIds = typed.langIds or {},
            }
        end
        local saved = HeroSheetWrite.Save{
            description = "Start downtime project",
            execute = function(props)
                local info = HeroSheetDowntimeWindows.InfoForWrite(props)
                if info ~= nil then
                    DTProjectEditor.StartProject(info, token.charid, {
                        projectId = projectId,
                        sourceType = sourceType,
                        selectedId = source ~= nil and source.id or nil,
                        name = name,
                        custom = custom,
                    })
                end
            end,
        }
        if not saved then
            return false
        end
        HeroSheetDowntimeWindows.WakeWatchers()
        HeroSheetDowntime.Select(projectId)
        local title = cond(sourceType == "custom", name, source ~= nil and source.name or "")
        HeroSheetWindow.Toast(string.format("%s started.", title) .. cond(waits, " It waits for the Director before the first roll.", ""))
    end

    local note = nil
    if not changing and not DTCharSheetTab.CanManageProjects() then
        note = "New projects wait for the Director before the first roll."
    end
    frame = HeroSheetWindow.ShowDialog{
        title = cond(changing, "Replace " .. oldTitle, "New project"),
        subtitle = heroName,
        width = NEW_WIDTH,
        bodyHeight = NEW_HEIGHT,
        body = body,
        saveText = cond(changing, "Replace", "Start project"),
        note = note,
        onSave = Commit,
    }
    ShowTab()

    --opened on an item (the Inventory's craft link): bring its row into view
    --once the list has laid out.
    if opts.itemid ~= nil and state.tab == "crafting" then
        local index = nil
        for i, source in ipairs(state.matches) do
            if source.id == opts.itemid then
                index = i
            end
        end
        HeroSheetDowntimeWindows.ScrollIntoView(listScroll, holder, function()
            if index == nil then
                return nil
            end
            --two rows show above the item, so it does not open at the very top.
            return (index - 1) * NEW_PITCH - 2 * NEW_PITCH
        end)
    end
end

----------------------------------------------------------------------
--The confirms: Delete project and Withdraw.

--- Delete one of the open Hero's projects; its shares end with it.
--- @param token CharacterToken
--- @param projectId string
--- @param title string
function HeroSheetDowntimeWindows.ConfirmDelete(token, projectId, title)
    local charid = token.charid
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", title),
        width = SMALL_WIDTH,
        bodyHeight = 22,
        body = HeroSheetWindow.DialogText("Its history goes with it; rolls spent on it are not returned."),
        saveText = "Delete",
        onSave = function()
            local saved = HeroSheetWrite.Save{
                description = "Delete downtime project",
                charid = charid,
                --the shares go in a document Undo cannot reach, so an undone
                --delete would bring the project back unshared.
                undoable = false,
                execute = function(props)
                    local info = HeroSheetDowntimeWindows.InfoForWrite(props)
                    if info ~= nil and info:GetProject(projectId) ~= nil then
                        info:RemoveProject(projectId)
                    end
                end,
            }
            --a refused delete keeps the project, so it keeps its shares too.
            if not saved then
                return
            end
            --sharing with no one revokes every share in one change.
            DTShares.CreateNew():Share(charid, projectId, {})
            HeroSheetDowntimeWindows.WakeWatchers()
        end,
    }
end

--- Stop contributing to a project shared with the open Hero.
--- @param token CharacterToken the Hero withdrawing
--- @param ownerId string
--- @param projectId string
--- @param title string
function HeroSheetDowntimeWindows.ConfirmWithdraw(token, ownerId, projectId, title)
    local charid = token.charid
    HeroSheetWindow.ShowDialog{
        title = string.format("Withdraw from %s?", title),
        width = SMALL_WIDTH,
        bodyHeight = 22,
        body = HeroSheetWindow.DialogText("You stop contributing. Rolls you already made stay on the project."),
        saveText = "Withdraw",
        onSave = function()
            DTShares.CreateNew():Revoke(ownerId, charid, projectId)
            HeroSheetDowntimeWindows.WakeWatchers()
        end,
    }
end

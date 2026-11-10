local mod = dmhub.GetModLoading()

--The Hero sheet's card column: the Hero's card on every tab. This file is
--the card itself: the art, and on its plate the name, titles line, class
--line, Level and experience, the level line, Stamina, Recoveries, Victories
--and the heroic resource; surges sit in the art. Under the card, the kit
--card and the treasures (below).
--
--The data comes from the same reader as the EotW sheet, so both sheets read
--a Hero the same way. Every write goes through HeroSheetWrite: unlike the
--character sheet, this sheet must upload its own changes. Each part is a
--HeroSheetRefresh block, so a change to the Hero redraws only the parts
--whose data changed.

HeroSheetCard = rawget(_G, "HeroSheetCard") or {}

--The card's height in each tier; the art fills it and the plate sits at its
--foot. Narrow shows a banner instead.
local CARD_HEIGHT = {wide = 500, medium = 470}

--Narrow's banner: the art this wide at the left, the plate's content
--beside it; the banner is as tall as the plate.
local BANNER_ART_WIDTH = 210

--- The card's height in a tier, in sheet units (nil for Narrow's banner).
--- @param tier string
--- @return nil|number
function HeroSheetCard.CardHeight(tier)
    return CARD_HEIGHT[tier]
end

--The Hero as the shared reader reads it, at most once a frame for every block.
--- @param token CharacterToken
--- @return nil|table
local function Data(token)
    return HeroSheetRefresh.Read(token)
end

--A label on the card's plate.
--- @param args table gui.Label args; classes default to heroSheetCardText
--- @return Panel
local function Text(args)
    args.classes = args.classes or {"heroSheetCardText"}
    args.width = args.width or "auto"
    args.height = args.height or "auto"
    return gui.Label(args)
end

----------------------------------------------------------------------
--Resources the card sets by typing a number (heroic resource, surges,
--epic resource): the difference goes through the rules' own gain and spend
--calls, so their events fire as they do on the character sheet.

--- @param hero creature
--- @param id string resource id
--- @param current number
--- @param value number the new amount
--- @param refreshType string
--- @param note string
local function SetResource(hero, id, current, value, refreshType, note)
    local diff = value - current
    if diff > 0 then
        hero:RefreshResource(id, refreshType, diff, note)
    elseif diff < 0 then
        hero:ConsumeResource(id, refreshType, -diff, note)
    end
end

----------------------------------------------------------------------
--The art: the card's crop of the Hero's art, as the hero card cuts it.

--- @param builder nil|boolean the Builder's card: it follows the Builder's layout
--- @param block nil|fun(panelArgs: table, spec: HeroSheetBlockSpec): Panel how it repaints (the Builder's host); nil for the sheet's
--- @param heroToken nil|fun(): nil|CharacterToken the Hero it shows (the Builder's host); nil for the sheet's
--- @return Panel
local function Art(builder, block, heroToken)
    local function Apply(element, token)
        local width, height = element.renderedWidth, element.renderedHeight
        if width <= 0 or height <= 0 then
            width, height = 384, CARD_HEIGHT.wide
        end
        EotwHeroCard.ApplyPortrait(element, token, width / height)
    end
    --the crop follows the card's shape, which changes with the tier (the
    --Builder's with the screen and Font Size).
    local function Recrop(element)
        local token = (heroToken or HeroSheet.Token)()
        if token ~= nil then
            dmhub.Schedule(0.05, function()
                if not mod.unloaded and element.valid then
                    Apply(element, token)
                end
            end)
        end
    end
    return (block or HeroSheetRefresh.Block)({
        floating = true,
        interactable = false,
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        cornerRadius = 10,
        width = "100%",
        height = "100%",
        data = {},
        heroSheetLayout = cond(builder, nil, Recrop),
        heroBuilderLayout = cond(builder, Recrop, nil),
    }, {
        name = cond(builder, "builder card art", "card art"),
        builder = builder,
        signature = function(token)
            --the picture and its framings (the card's own, else the token's).
            return CardPortraitSignature(token)
        end,
        refresh = function(panel, token)
            Apply(panel, token)
        end,
    })
end

--Surges: one surge symbol in the art with the count beside it, click to
--set; shows at 0 too.
--- @return Panel
local function Surges()
    local function Get()
        local token = HeroSheet.Token()
        return token ~= nil and (token.properties:GetAvailableSurges() or 0) or 0
    end
    return HeroSheetRefresh.Block({
        classes = {"heroSheetCardPlate"},
        bgimage = "panels/square.png",
        cornerRadius = 6,
        width = "auto",
        height = 30,
        halign = "right",
        flow = "horizontal",
        hpad = 6,
        borderBox = true,
        bmargin = 6,
        rmargin = 10,
        gui.Panel{
            classes = {"heroSheetInfoIcon"},
            bgimage = "phosphor/lightning-fill.png",
            width = 18,
            height = 18,
            valign = "center",
            rmargin = 2,
            linger = function(element)
                gui.Tooltip("Surges")(element)
            end,
        },
        HeroSheetTheme.ClickNumber{
            classes = {"heroSheetCardStrong"},
            get = Get,
            set = function(value)
                HeroSheetWrite.Save{
                    description = "Set Surges",
                    execute = function(hero)
                        SetResource(hero, CharacterResource.surgeResourceId, hero:GetAvailableSurges() or 0, value, "unbounded", "Set manually")
                    end,
                }
            end,
            canEdit = HeroSheetWrite.CanWrite,
            fontSize = 17,
            tooltip = "Surges",
        },
    }, {
        name = "surges",
        signature = function(token)
            return tostring(token.properties:GetAvailableSurges())
        end,
        refresh = function(panel, token)
            panel:FireEventTree("refreshNumber")
        end,
    })
end

----------------------------------------------------------------------
--Name and privacy, and Controlled by, on the card in Edit mode.

--A name may be this long, typed or suggested.
local NAME_LIMIT = 60

--The plate's side margins (10 each) and padding (12 each), in sheet units:
--the card column less this is the room on the plate.
local PLATE_INSET = 44

--Whether the Hero's ancestry has a name table to suggest from (Revenants and
--homebrew ancestries without one do not), and the ancestry as it is said.
--- @param token CharacterToken
--- @return boolean, string
local function NameTable(token)
    local hasTable = false
    local ancestry = ""
    pcall(function()
        local hero = token.properties --[[@as character]]
        local generator = hero:GetNameGeneratorTable()
        hasTable = generator ~= nil and #generator.rows > 0
        --Race() falls back to a default ancestry; an unpicked one reads "".
        if hero:try_get("raceid") ~= nil then
            ancestry = HeroBuild.SaidName(hero:Race().name)
        end
    end)
    return hasTable, ancestry
end

--- Why Suggest a name is off: the ancestry has no names, or none is picked.
--- @param ancestry string the second value NameTable returns
--- @return string
function HeroSheetCard.NoNamesTip(ancestry)
    if ancestry == "" then
        return "Pick an ancestry to get name suggestions."
    end
    return string.format("%s has no names to suggest. Enter one yourself.", ancestry)
end
--the Appearance tab's Suggest a name follows the same rule.
HeroSheetCard.NameTable = NameTable

--Who controls the Hero, as the pill says it.
--- @param token CharacterToken
--- @return string
local function ControllerName(token)
    local ownerId = token.ownerId
    if ownerId == "PARTY" then
        local party = GetParty(token.partyId)
        return party ~= nil and party.name or "a party"
    elseif ownerId ~= nil and ownerId ~= "" then
        local name = nil
        pcall(function() name = dmhub.GetSessionInfo(ownerId).displayName end)
        return name or "a player"
    end
    return "Director"
end

--The Director's Controlled by popover: every player, every party,
--and the Director when the Hero has a token on a map (as the character sheet's dropdown),
--each with what it means beside it.
--- @param anchor Panel the pill
local function ControllerPopover(anchor)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() or not dmhub.isDM then
        return
    end
    local ownerId = token.ownerId
    local isParty = ownerId == "PARTY"
    local isDirector = ownerId == nil or ownerId == ""

    --- @type {kind: "player"|"party"|"director", id: nil|string, text: string, sub: string, selected: boolean}[]
    local options = {}
    for _, userid in ipairs(dmhub.users) do
        local info = dmhub.GetSessionInfo(userid)
        if info ~= nil and not info.dm then
            options[#options+1] = {kind = "player", id = userid, text = info.displayName or userid, sub = "Player", selected = ownerId == userid}
        end
    end
    local current = isParty and GetParty(token.partyId) or nil
    for _, partyid in ipairs(GetAllParties()) do
        local party = GetParty(partyid)
        if party ~= nil then
            options[#options+1] = {kind = "party", id = partyid, text = party.name, sub = "Anyone in the party", selected = current ~= nil and current.id == partyid}
        end
    end
    if token.hasTokenOnAnyMap or isDirector then
        options[#options+1] = {kind = "director", id = nil, text = "Director", sub = "Only on the map", selected = isDirector}
    end

    local frame
    local rows = {}
    for _, option in ipairs(options) do
        --the current controller stays lit ("selected" on the row and its text).
        local rowClasses = {"heroSheetPopRow", "hoverable"}
        local textClasses = {"heroSheetPopRowText"}
        if option.selected then
            rowClasses[#rowClasses+1] = "selected"
            textClasses[#textClasses+1] = "selected"
        end
        rows[#rows+1] = gui.Panel{
            classes = rowClasses,
            bgimage = "panels/square.png",
            cornerRadius = 6,
            width = "100%",
            height = 32,
            hpad = 8,
            borderBox = true,
            flow = "none",
            click = function(element)
                if not option.selected then
                    HeroSheetWrite.SetController(option.kind, option.id)
                    HeroSheetRefresh.Changed()
                end
                HeroSheetWindow.ClosePopup(frame)
            end,
            Text{
                classes = textClasses,
                text = option.text,
                fontSize = 14,
                width = "100%-130",
                halign = "left",
                valign = "center",
                textWrap = false,
                textOverflow = "ellipsis",
                interactable = false,
            },
            Text{
                classes = {"heroSheetCardSub"},
                text = option.sub,
                fontSize = 12,
                halign = "right",
                valign = "center",
                interactable = false,
            },
        }
    end

    frame = HeroSheetWindow.ShowPopup{
        width = 300,
        height = 12 + 14 + 6 + #rows * 32 + 12,
        anchor = anchor,
        below = true,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vpad = 12,
            hpad = 14,
            borderBox = true,
            Text{
                classes = {"heroSheetFieldLabel"},
                text = "Controlled by",
                uppercase = true,
                fontSize = 11.5,
                bold = true,
                height = 14,
                halign = "left",
                bmargin = 6,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = rows,
            },
        },
    }
end

--A boxed icon button on the name row (the privacy eye, the dice): a faint
--edge that lights on hover. A dimmed one does nothing and says why on hover.
--- @param args {icon: string, tooltip: string, enabled: nil|boolean, press: nil|fun(), click: fun()}
--- @return Panel
local function IconButton(args)
    local enabled = args.enabled ~= false
    local classes = {"heroSheetIconButton", "hoverable"}
    if not enabled then
        classes = {"heroSheetIconButton", "heroSheetDisabled"}
    end
    return gui.Panel{
        classes = classes,
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = 26,
        height = 26,
        lmargin = 8,
        valign = "center",
        linger = function(element)
            gui.Tooltip(args.tooltip)(element)
        end,
        press = function(element)
            if enabled and args.press ~= nil then
                args.press()
            end
        end,
        click = function(element)
            if enabled then
                args.click()
            end
        end,
        gui.Panel{
            classes = {"heroSheetIconButtonIcon"},
            bgimage = args.icon,
            width = 15,
            height = 15,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
end

--The privacy eye: one click hides the name from other players or shows it
--again.
--- @param token CharacterToken
--- @return Panel
local function PrivacyEye(token)
    local private = token.namePrivate == true
    return IconButton{
        icon = cond(private, "phosphor/eye-slash.png", "phosphor/eye.png"),
        tooltip = cond(private, "Hidden from other players", "Visible to other players"),
        click = function()
            HeroSheetWrite.SaveAppearance(function(target)
                target.namePrivate = not target.namePrivate
            end)
            HeroSheetRefresh.Changed()
        end,
    }
end

--The Director's Controlled by pill.
--- @param token CharacterToken
--- @return Panel
local function ControllerPill(token)
    return gui.Label{
        classes = {"heroSheetCtrlPill", "hoverable"},
        text = "Controlled by " .. ControllerName(token),
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 24,
        hpad = 8,
        borderBox = true,
        fontSize = 12,
        textWrap = false,
        halign = "right",
        valign = "center",
        click = function(element)
            ControllerPopover(element)
        end,
    }
end

--The name row. Out of Edit mode, the name alone, wrapping onto more lines
--rather than shrinking. In Edit mode the name is edited where it stands,
--as every value on the card is: it has a dashed line under
--it and turns into a field when clicked; the privacy eye and the dice
--(Suggest a name) follow it; the Director sees Controlled by at the right,
--which drops under the name before the name has to break.
--- @param token CharacterToken
--- @return Panel
local function NameRow(token)
    local state = HeroSheet.State()
    local editing = state ~= nil and state.editing == true and HeroSheetWrite.CanWrite()
    --Medium and Narrow's banner set the name smaller to fit their width.
    local size = cond(HeroSheet.Tier() ~= "wide", 24, 28)
    if not editing then
        return Text{
            classes = {"heroSheetCardStrong"},
            text = token.name or "Hero",
            width = "100%",
            fontSize = size,
            bold = true,
            textWrap = true,
        }
    end

    --the room on the plate; the name leaves room for the eye and the dice
    --after it.
    local room = (HeroSheet.CardColumnWidth(HeroSheet.Tier()) or 384) - PLATE_INSET
    local iconsRoom = 2 * (26 + 8)
    local nameMax = room - iconsRoom
    local label = Text{
        classes = {"heroSheetCardStrong"},
        text = token.name or "Hero",
        width = "auto",
        maxWidth = nameMax,
        fontSize = size,
        bold = true,
        textWrap = true,
        halign = "left",
        interactable = false,
    }

    --Enter or a click away saves; Esc restores the name. The dice fills a
    --suggestion, and the save a click away would start waits so the dice can
    --keep the field.
    local field
    local nameBox
    local open = false
    --the Hero whose name is being typed: a save landing after a switch to
    --another Hero is dropped, not given to them.
    local openFor = nil
    local focused = false
    local rolledAt = -1
    --where the Director's pill sits, from the last measure.
    local pillUnits = 0
    local pillBeside = false

    --- @param typing boolean
    local function Show(typing)
        if label.valid then
            label:SetClass("collapsed", typing)
        end
        if field.valid then
            field:SetClass("collapsed", not typing)
        end
        if nameBox.valid then
            nameBox:SetClass("heroSheetTyping", typing)
        end
    end
    local function Close()
        open = false
        focused = false
        if field.valid then
            field.captureEscape = false
        end
        Show(false)
    end
    --- @param text string
    local function Commit(text)
        if not open then
            return
        end
        Close()
        local live = HeroSheet.Token()
        if live == nil or live.charid ~= openFor then
            return
        end
        --one line (Shift+Enter could add a break), at most NAME_LIMIT long;
        --an empty field keeps the name the Hero has.
        local name = string.sub(trim(string.gsub(text or "", "%s+", " ")), 1, NAME_LIMIT)
        if name ~= "" and name ~= live.name then
            HeroSheetWrite.SaveAppearance(function(target)
                target.name = name
            end)
            HeroSheetRefresh.Changed()
        end
    end
    --- @param text string
    local function Open(text)
        if not field.valid then
            return
        end
        if not open then
            open = true
            local token = HeroSheet.Token()
            openFor = token ~= nil and token.charid or nil
            --the field takes the name's room short of a pill beside it, so
            --nothing moves while typing; the row measures again after a save.
            local width = nameMax
            if pillBeside then
                width = math.max(80, width - pillUnits - 8)
            end
            field.selfStyle.width = width
            field.captureEscape = true
            Show(true)
        end
        --set with notice: a silent set keeps the field's old height, so a
        --long suggestion would be cut off.
        field.text = text
        dmhub.Schedule(0.01, function()
            if mod.unloaded or not field.valid or not open then
                return
            end
            gui.SetFocus(field)
        end)
    end

    field = gui.Input{
        classes = {"heroSheetNameField", "collapsed"},
        width = nameMax,
        height = "auto",
        fontSize = size,
        bold = true,
        hpad = 4,
        borderBox = true,
        halign = "left",
        valign = "center",
        --wraps as the name does; Enter saves, Shift+Enter adds a line. No
        --multiline = true: the engine turns that into Enter-adds-a-line.
        lineType = "MultiLineSubmit",
        textWrap = true,
        characterLimit = NAME_LIMIT,
        selectAllOnFocus = true,
        placeholderText = "",
        text = token.name or "",
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
            local text = element.text
            dmhub.Schedule(0.05, function()
                if mod.unloaded then
                    return
                end
                if dmhub.Time() - rolledAt < 0.3 then
                    if field.valid and open then
                        gui.SetFocus(field)
                    end
                    return
                end
                Commit(text)
            end)
        end,
        --the row redrew while typing (a tier change): keep what was typed.
        destroy = function(element)
            if open and focused then
                Commit(element.text)
            end
        end,
    }

    nameBox = gui.Panel{
        classes = {"heroSheetNameEdit", "hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        --a dashed line under the name only, the sign that it can be edited.
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
        borderStyle = "dashed",
        borderDash = 4,
        borderGap = 3,
        width = "auto",
        height = "auto",
        bpad = 3,
        borderBox = true,
        halign = "left",
        valign = "center",
        click = function(element)
            if not open then
                local live = HeroSheet.Token()
                Open(live ~= nil and live.name or "")
            end
        end,
        label,
        field,
    }
    local eye = PrivacyEye(token)
    local hasTable, ancestry = NameTable(token)
    local dice = IconButton{
        icon = "phosphor/dice-five.png",
        tooltip = cond(hasTable, "Suggest a name", HeroSheetCard.NoNamesTip(ancestry)),
        enabled = hasTable,
        press = function()
            rolledAt = dmhub.Time()
        end,
        click = function()
            local live = HeroSheet.Token()
            local name = live ~= nil and HeroBuild.main.GenerateName(live.properties --[[@as character]]) or nil
            if name ~= nil then
                Open(string.sub(name, 1, NAME_LIMIT))
            end
        end,
    }
    local left = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        nameBox,
        eye,
        dice,
    }
    if not dmhub.isDM then
        return left
    end

    --the Director's pill: on the name's line when it fits, else under it.
    --The fit is a guess from the text until the row has laid out, then
    --measured (screen pixels per sheet unit from the eye's fixed size).
    local pill = ControllerPill(token)
    local pillBelow = ControllerPill(token)
    local line1 = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "none",
        left,
        pill,
    }
    local line2 = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "none",
        tmargin = 4,
        pillBelow,
    }
    --- @param nameUnits number
    --- @param measuredPill number
    local function Place(nameUnits, measuredPill)
        pillUnits = measuredPill
        pillBeside = nameUnits + iconsRoom + 8 + measuredPill <= room
        pill:SetClass("collapsed", not pillBeside)
        line2:SetClass("collapsed", pillBeside)
    end
    local pillText = "Controlled by " .. ControllerName(token)
    Place(math.min(nameMax, HeroSheetTheme.TextWidth(token.name or "", size) * 1.1),
        HeroSheetTheme.TextWidth(pillText, 12) + 18)
    local function Measure()
        dmhub.Schedule(0.05, function()
            if mod.unloaded or not eye.valid or eye.renderedHeight <= 0 then
                return
            end
            local perUnit = eye.renderedHeight / 26
            local shown = cond(pill:HasClass("collapsed"), pillBelow, pill)
            if shown.renderedWidth <= 0 then
                return
            end
            Place(nameBox.renderedWidth / perUnit, shown.renderedWidth / perUnit)
        end)
    end
    Measure()
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetLayout = function(element)
            Measure()
        end,
        line1,
        line2,
    }
end

----------------------------------------------------------------------
--Name, titles line and class line.

--- @class HeroSheetCardArgs
--- @field levelUp fun(manual: nil|boolean) opens Level up; manual: the Level up button, the next Level's page
--- @field changeKit nil|fun() opens the Builder at the Class step's Kit
--- @field openTitles nil|fun(titleid: nil|string) opens the Titles window; nil leaves the titles line unclickable
--- @field openAppearance fun() opens the Appearance tab
--- @field openInventory fun() opens the Inventory tab
--- @field columnChanged fun() the kit card changed height, so the Treasures block refits

--- @param args HeroSheetCardArgs
--- @return Panel
local function Identity(args)
    local spec
    --Edit mode and the tier are not Hero data, so they redraw the block
    --themselves rather than through its signature.
    local function Redraw(element)
        local token = HeroSheet.Token()
        if token ~= nil then
            spec.refresh(element, token)
        end
    end
    spec = {
        name = "card identity",
        signature = function(token)
            local hero = token.properties
            return table.concat({
                --the name's size follows the tier, and a tier event can miss
                --the block (a kept window reopening at another size).
                HeroSheet.Tier(),
                --the titles line writes the gold into its text, so a new
                --colour scheme redraws it.
                HeroSheetTheme.Palette().cardInfo,
                tostring(token.name),
                tostring(token.namePrivate),
                tostring(token.ownerId), tostring(token.partyId),
                dmhub.ToJson(hero:try_get("titles", {})),
                dmhub.ToJson(hero:GetLevelChoices() or {}),
                tostring(hero:CharacterLevel()),
                tostring(hero:try_get("raceid")), tostring(hero:try_get("subraceid")),
                dmhub.ToJson(hero:try_get("classes", {})),
            }, "|")
        end,
        refresh = function(panel, token)
            local read = Data(token)
            if read == nil then
                return
            end
            local children = {}
            children[#children+1] = NameRow(token)

            --held titles, or "Add a title"; a title whose benefit is not
            --chosen reads as its name, a dot and "choose a benefit", in @info.
            local parts = {}
            local unchosen = nil
            for _, title in ipairs(read.titles or {}) do
                if #title.benefits == 0 and unchosen == nil then
                    unchosen = title
                else
                    parts[#parts+1] = title.name
                end
            end
            --one wrapping line: held titles in italics, then the unchosen
            --one in @info (markup colours one label). With none held, "Add a
            --title" as a pill, so there is always a way in to edit.
            local info = HeroSheetTheme.Palette().cardInfo
            local text = table.concat(parts, ", ")
            if unchosen ~= nil then
                local extra = string.format("<color=%s>%s \u{00B7} choose a benefit</color>", info, unchosen.name)
                text = cond(text ~= "", "<i>" .. text .. "</i>, " .. extra, extra)
            elseif text ~= "" then
                text = "<i>" .. text .. "</i>"
            end
            local openTitles = args.openTitles
            local canOpen = openTitles ~= nil and HeroSheetWrite.CanWrite()
            local function Open()
                if openTitles ~= nil and HeroSheetWrite.CanWrite() then
                    openTitles(unchosen ~= nil and unchosen.id or nil)
                end
            end
            if text == "" then
                if canOpen then
                    children[#children+1] = gui.Panel{
                        classes = {"heroSheetTitleAdd", "hoverable"},
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 10,
                        width = "auto",
                        height = HeroSheetWindow.TargetSize(22),
                        hpad = 9,
                        borderBox = true,
                        tmargin = 3,
                        flow = "horizontal",
                        halign = "left",
                        click = function()
                            Open()
                        end,
                        gui.Panel{
                            classes = {"heroSheetTitleAddIcon"},
                            bgimage = "phosphor/plus-bold.png",
                            width = 10,
                            height = 10,
                            rmargin = 5,
                            valign = "center",
                            interactable = false,
                        },
                        Text{
                            classes = {"heroSheetTitleAddText"},
                            text = "Add a title",
                            fontSize = 12.5,
                            width = "auto",
                            valign = "center",
                            textWrap = false,
                            interactable = false,
                        },
                    }
                end
            else
                --in Edit mode the names end with a Manage pill.
                local manage = nil
                if canOpen and (HeroSheet.State() or {}).editing == true then
                    manage = gui.Panel{
                        classes = {"heroSheetHeadPill"},
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 12,
                        width = "auto",
                        height = HeroSheetWindow.TargetSize(22),
                        hpad = 9,
                        borderBox = true,
                        halign = "right",
                        valign = "top",
                        interactable = false,
                        gui.Label{
                            classes = {"heroSheetCardStrong"},
                            text = "Manage",
                            fontSize = 12,
                            bold = true,
                            width = "auto",
                            height = "auto",
                            valign = "center",
                            textWrap = false,
                            interactable = false,
                        },
                    }
                end
                local lineChildren = {
                    gui.Panel{
                        classes = {"heroSheetMutedIcon"},
                        bgimage = "phosphor/medal-fill.png",
                        width = 14,
                        height = 14,
                        halign = "left",
                        valign = "top",
                        tmargin = 3,
                        interactable = false,
                    },
                    Text{
                        text = text,
                        width = cond(manage ~= nil, "100%-96", "100%-20"),
                        halign = "left",
                        lmargin = 20,
                        fontSize = 14,
                        textWrap = true,
                        interactable = false,
                    },
                }
                if manage ~= nil then
                    lineChildren[#lineChildren+1] = manage
                end
                children[#children+1] = gui.Panel{
                    classes = {cond(canOpen, "hoverable", "heroSheetInert")},
                    --a panel with no image is not hit by the mouse: a clear one is.
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    width = "100%",
                    height = "auto",
                    flow = "none",
                    tmargin = 2,
                    click = function(element)
                        Open()
                    end,
                    children = lineChildren,
                }
            end

            --"Level 1 High Elf Tactician", then a dot and the subclass.
            local classLine = string.format("Level %d %s %s", read.level or 1, HeroBuild.SaidName(read.ancestry), read.className or "")
            if read.subclass ~= nil and read.subclass ~= "" then
                classLine = classLine .. " \u{00B7} " .. read.subclass
            end
            children[#children+1] = Text{
                text = classLine,
                width = "100%",
                fontSize = 15,
                tmargin = 2,
                textWrap = true,
            }
            panel.children = children
        end,
    }
    --Edit mode as last drawn: opening a tab ends Edit mode even when it was
    --off, and that must not redraw the block.
    local drawnEditing = (HeroSheet.State() or {}).editing == true
    return HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetEdit = function(element, editing)
            if editing ~= drawnEditing then
                drawnEditing = editing
                Redraw(element)
            end
        end,
        heroSheetTier = function(element, tier)
            Redraw(element)
        end,
    }, spec)
end

----------------------------------------------------------------------
--Level and experience, and the level line.

--"Choices to make" asks the build engine for every step's status, which is
--slow on a high-Level Hero, so it runs a frame after the card draws and only
--when the Hero's build data changed. By charid:
--{key = the build data it was worked out from, choices = boolean, first =
--the first page Level up would open}.
--- @type table<string, {key: string, choices: boolean, first: nil|HeroBuildPage}>
local g_choicesCache = {}

--- The build data "Choices to make" depends on.
--- @param hero creature
--- @return string
local function ChoicesKey(hero)
    return table.concat({
        dmhub.ToJson(hero:GetLevelChoices() or {}),
        dmhub.ToJson(hero:try_get("classes", {})),
        tostring(hero:try_get("raceid")), tostring(hero:try_get("backgroundid")),
        dmhub.ToJson(hero:try_get("complications", {})),
        tostring(hero:try_get("kitid")), tostring(hero:try_get("kitid2")),
        tostring(hero:try_get("culture") ~= nil and dmhub.ToJson(hero:try_get("culture")) or ""),
        dmhub.ToJson(hero:try_get("extraLevelInfo") or {}), tostring(hero:try_get("rungSeen")),
        --a treasure pick (Amnesia's) is stored outside levelChoices.
        dmhub.ToJson(hero:try_get("treasureGrants", {})),
    }, "|")
end

--- Whether any choice at or below the Hero's Level is unmade (one rule,
--- whatever raised the Level), from the cache; a stale entry is worked out
--- again a frame later and the card redraws then.
--- @param token CharacterToken
--- @return boolean
local function ChoicesToMake(token)
    local key = ChoicesKey(token.properties)
    local cached = g_choicesCache[token.charid]
    if cached ~= nil and cached.key == key then
        return cached.choices
    end
    local charid = token.charid
    dmhub.Schedule(0.02, function()
        if mod.unloaded then
            return
        end
        local live = dmhub.GetCharacterById(charid)
        if live == nil or live.properties == nil then
            return
        end
        local liveKey = ChoicesKey(live.properties)
        local current = g_choicesCache[charid]
        if current ~= nil and current.key == liveKey then
            return
        end
        local choices = false
        --- @type nil|HeroBuildPage
        local first = nil
        local ok, err = pcall(HeroBuild.main.Cached, function()
            local status = HeroBuild.main.Status(live)
            for _, step in ipairs(status.steps) do
                if step.id == "class" then
                    first = HeroBuild.main.hero.LevelsWaiting(live.properties --[[@as character]])[1]
                end
                --the name and portrait are the Appearance step's, not a choice.
                if not step.complete and step.id ~= "appearance" then
                    for _, row in ipairs(step.rows) do
                        --the inciting incident is optional story, so it never
                        --counts as a choice to make.
                        if not row.complete and row.category ~= "Incident" then
                            choices = true
                        end
                    end
                end
            end
        end)
        --cached even on a failure (no retry until the Hero changes), so the
        --log line comes once per change.
        if not ok then
            dmhub.Error(string.format("HEROSHEET:: choices to make failed: %s", tostring(err)))
        end
        g_choicesCache[charid] = {key = liveKey, choices = choices, first = first}
        --only this cache changed, not the Hero: no need to read it again.
        HeroSheetRefresh.Recheck()
    end)
    return cached ~= nil and cached.choices or false
end

--- The first page Level up would open (HeroBuildPage), from the same cache
--- as ChoicesToMake; nil while it is worked out, or with none waiting.
--- @param token CharacterToken
--- @return nil|HeroBuildPage
local function FirstPage(token)
    local cached = g_choicesCache[token.charid]
    if cached == nil or cached.key ~= ChoicesKey(token.properties) then
        return nil
    end
    return cached.first
end

--- @class HeroSheetClickTextArgs
--- @field text fun(): string what shows
--- @field get fun(): number the number the field opens with
--- @field set fun(n: number) saves a typed value
--- @field fontSize number
--- @field classes nil|string[]
--- @field width nil|any

--A label that becomes a number field on click (the experience: "14 / 16
--XP" shows, the total is what is typed). Fire "refreshNumber" on it to
--show args.text() again.
--- @param args HeroSheetClickTextArgs
--- @return Panel
local function ClickText(args)
    local label
    local input
    local focused = false
    local function Close()
        focused = false
        input.captureEscape = false
        input:SetClass("collapsed", true)
        label:SetClass("heroSheetHush", false)
        label.text = args.text()
    end
    --Enter or a click away applies what was typed and closes the field; an
    --unchanged value saves nothing. Called from change, defocus and submit,
    --whichever comes first (change does not fire when nothing was typed).
    --- @param text string
    local function Apply(text)
        if not focused then
            return
        end
        local value = tonumber(text)
        Close()
        --let go of the keyboard first (a block holding it waits to redraw),
        --unless a click away already gave it to another field. After Enter
        --the field no longer has the keyboard but is still the focus on
        --record, and a field left that way cannot be focused again.
        if input.hasInputFocus or gui.GetFocus() == input then
            gui.SetFocus(nil)
        end
        if value ~= nil and value >= 0 and math.floor(value) ~= args.get() then
            args.set(math.floor(value))
        end
        label.text = args.text()
    end
    label = Text{
        classes = args.classes,
        text = args.text(),
        fontSize = args.fontSize,
        bold = true,
        minHeight = 24,
        valign = "center",
        click = function(element)
            if not HeroSheetWrite.CanWrite() then
                return
            end
            input.text = tostring(args.get())
            label:SetClass("heroSheetHush", true)
            input:SetClass("collapsed", false)
            input.captureEscape = true
            dmhub.Schedule(0.01, function()
                if not mod.unloaded and input.valid then
                    gui.SetFocus(input)
                end
            end)
        end,
    }
    input = gui.Input{
        classes = {"heroSheetNumberInput", "collapsed"},
        floating = true,
        width = 48,
        height = args.fontSize + 6,
        halign = "left",
        fontSize = args.fontSize,
        valign = "center",
        characterLimit = 5,
        selectAllOnFocus = true,
        placeholderText = "",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            Close()
            gui.SetFocus(nil)
        end,
        focus = function(element)
            focused = true
        end,
        change = function(element)
            Apply(element.text)
        end,
        defocus = function(element)
            Apply(element.text)
        end,
        submit = function(element)
            Apply(element.text)
        end,
    }
    return gui.Panel{
        width = args.width or "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        refreshNumber = function(element)
            if not focused then
                label.text = args.text()
            end
        end,
        label,
        input,
    }
end

--The level line's button (Level up, Finish Level N): dark with a gold edge,
--filled gold when there is something to do. Its text, gold and hover are
--painted in by the level line's painter.
--- @param small boolean the Medium tier's smaller size
--- @param click fun()
--- @return Panel
local function LevelButton(small, click)
    return gui.Label{
        classes = {"heroSheetLevelButton", "hoverable"},
        text = "",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = 24,
        hpad = cond(small, 7, 10),
        borderBox = true,
        fontSize = cond(small, 11.5, 12),
        bold = true,
        textWrap = false,
        halign = "right",
        valign = "center",
        textAlignment = "center",
        data = {},
        linger = function(element)
            if element.data.tooltip ~= nil then
                gui.Tooltip(element.data.tooltip)(element)
            end
        end,
        click = function(element)
            click()
        end,
    }
end

--Banked experience on the XP bar, drawn as EotW draws its hatch:
--cream stripes at 45 degrees, clipped to the banked stretch.
local HATCH_STEP = 4

--The hatch, kept on its bar: Show sets the banked stretch, adding stripes
--when a wider stretch needs more (they are never rebuilt).
--- @param height number
--- @return {panel: Panel, show: fun(widthPct: string, units: number)}
local function Hatch(height)
    local stripes = 0
    local panel = gui.Panel{
        classes = {"heroSheetHatchGround"},
        bgimage = "panels/square.png",
        halign = "left",
        width = "0%",
        height = "100%",
        flow = "none",
        clip = true,
        interactable = false,
    }
    --- @param widthPct string the banked stretch, e.g. "12.5%"
    --- @param units number about how wide the stretch is, for the stripe count
    local function Show(widthPct, units)
        local need = math.ceil((units + height) / HATCH_STEP) + 1
        for i = stripes, need - 1 do
            panel:AddChild(gui.Panel{
                classes = {"heroSheetHatchStripe"},
                bgimage = "panels/square.png",
                floating = true,
                halign = "left",
                valign = "center",
                x = i * HATCH_STEP - height,
                width = 2,
                height = height * 3,
                rotate = 45,
                interactable = false,
            })
        end
        stripes = math.max(stripes, need)
        panel.selfStyle.width = widthPct
    end
    return {panel = panel, show = Show}
end

--- @param args HeroSheetCardArgs
--- @return Panel
local function Progress(args)
    local function Prog(token)
        local read = Data(token)
        return read ~= nil and read.progress or nil
    end
    local function SetXp(value)
        HeroSheetWrite.Save{
            description = "Set experience",
            execute = function(hero)
                hero.xp = value
            end,
        }
    end
    local function Xp()
        local live = HeroSheet.Token()
        return live ~= nil and (tonumber(live.properties:try_get("xp", 0)) or 0) or 0
    end
    --Edit mode as last painted: opening a tab ends Edit mode even when it
    --was off, and that must not repaint the level line.
    local drawnEditing = false

    --Builds the block for its shape: Level 10's experience and epic
    --resource, or the experience bar below it, at the tier's size. Returns
    --the painter that shows a Hero's values in what was built.
    --- @param panel Panel
    --- @param token CharacterToken
    --- @return nil|fun(token: CharacterToken)
    local function Build(panel, token)
        local prog = Prog(token)
        if prog == nil then
            panel.children = {}
            return nil
        end
        --Medium's card and Narrow's banner use smaller text to fit their width.
        local small = HeroSheet.Tier() ~= "wide"
        --what the painter last read, for the handlers.
        local last = {prog = prog, epic = {name = "Epic", value = 0}, choices = false, newLevel = false, nextRung = nil}
        local children = {}
        --- @type fun()
        local paintTop
        if prog.maxLevel then
            --Level 10: the experience as text, click to set, then a
            --hairline and the epic resource with its icon; at Medium only
            --the icon and the number.
            local levelText = Text{
                classes = {"heroSheetCardStrong"},
                text = "",
                fontSize = 13,
                bold = true,
                valign = "center",
                rmargin = 3,
            }
            local epicIcon = gui.Panel{
                bgimage = "panels/square.png",
                bgcolor = "white",
                width = 18,
                height = 18,
                valign = "center",
                rmargin = 5,
                linger = function(element)
                    gui.Tooltip(last.epic.name or "Epic resource")(element)
                end,
            }
            local epicName = Text{
                classes = {"heroSheetCardStrong"},
                text = "",
                fontSize = 12.5,
                bold = true,
                valign = "center",
                rmargin = 5,
            }
            --the narrow card column has no room for it; the banner does.
            epicName:SetClass("collapsed", HeroSheet.Tier() == "medium")
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                --only the experience is typed into: it
                --alone is underlined, and its field opens in its place.
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    levelText,
                    HeroSheetTheme.ClickNumber{
                        classes = {"heroSheetCardStrong"},
                        get = Xp,
                        set = SetXp,
                        canEdit = HeroSheetWrite.CanWrite,
                        fontSize = 13,
                        snug = true,
                    },
                    Text{
                        classes = {"heroSheetCardStrong"},
                        text = "XP",
                        fontSize = 13,
                        bold = true,
                        valign = "center",
                        lmargin = 3,
                    },
                },
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "right",
                    valign = "center",
                    gui.Panel{
                        classes = {"heroSheetDivider"},
                        bgimage = "panels/square.png",
                        width = 1,
                        height = 18,
                        valign = "center",
                        rmargin = 8,
                    },
                    epicIcon,
                    epicName,
                    HeroSheetTheme.ClickNumber{
                        classes = {"heroSheetCardStrong"},
                        get = function()
                            local live = HeroSheet.Token()
                            return live ~= nil and (live.properties:GetEpicResources() or 0) or 0
                        end,
                        set = function(value)
                            HeroSheetWrite.Save{
                                description = "Set " .. (last.epic.name or "epic resource"),
                                execute = function(hero)
                                    local diff = value - (hero:GetEpicResources() or 0)
                                    if diff ~= 0 then
                                        hero:AddUnboundedResource(CharacterResource.epicResourceId, diff, "Manually Set")
                                    end
                                end,
                            }
                        end,
                        canEdit = HeroSheetWrite.CanWrite,
                        fontSize = 16,
                        tooltip = function()
                            return last.epic.name
                        end,
                    },
                },
            }
            paintTop = function()
                last.epic = last.prog.epic or {name = "Epic", value = 0}
                levelText.text = string.format("Level %d \u{00B7}", last.prog.level)
                local hasIcon = last.epic.iconid ~= nil and last.epic.iconid ~= ""
                epicIcon:SetClass("collapsed", not hasIcon)
                if hasIcon then
                    epicIcon.bgimage = last.epic.iconid
                end
                epicName.text = last.epic.name or "Epic"
            end
        else
            --the experience bar fills by progress within this Level, with
            --banked Victories (next respite's XP) hatched after it.
            --The next Level's number is dimmer than this one.
            local fill = gui.Panel{
                classes = {"heroSheetXpFill"},
                bgimage = "panels/square.png",
                cornerRadius = 4,
                halign = "left",
                width = "0%",
                height = "100%",
                interactable = false,
            }
            local hatch = Hatch(10)
            local track = gui.Panel{
                classes = {"heroSheetXpTrack"},
                bgimage = "panels/square.png",
                cornerRadius = 5,
                width = "100%-80",
                height = 10,
                valign = "center",
                flow = "horizontal",
                fill,
                --a dark notch where the earned experience ends.
                gui.Panel{
                    classes = {"heroSheetXpNotch"},
                    bgimage = "panels/square.png",
                    halign = "left",
                    width = 2,
                    height = "100%",
                    interactable = false,
                },
                hatch.panel,
            }
            local levelNow = Text{
                classes = {"heroSheetCardStrong"},
                text = "",
                fontSize = 14,
                bold = true,
                valign = "center",
                rmargin = 8,
            }
            local levelNext = Text{
                classes = {"heroSheetCardSub"},
                text = "",
                fontSize = 14,
                bold = true,
                valign = "center",
                hmargin = 8,
            }
            local function XpText()
                return string.format("%d / %d XP", Xp(), last.prog.level * math.max(1, last.prog.xpPerLevel))
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",
                levelNow,
                track,
                levelNext,
                ClickText{
                    classes = {"heroSheetCardStrong"},
                    text = XpText,
                    get = Xp,
                    set = SetXp,
                    fontSize = 12,
                },
            }
            paintTop = function()
                local progress = last.prog
                local per = math.max(1, progress.xpPerLevel)
                local into = math.max(0, math.min(per, progress.xpIntoLevel))
                local banked = math.max(0, math.min(per - into, progress.victories))
                fill.selfStyle.width = string.format("%.1f%%", into / per * 100)
                hatch.panel:SetClass("collapsed", banked <= 0)
                if banked > 0 then
                    --the bar is about 240 units wide at Wide.
                    hatch.show(string.format("%.1f%%", banked / per * 100), banked / per * 240)
                end
                levelNow.text = tostring(progress.level)
                levelNext.text = tostring(progress.level + 1)
                --the bar takes what the numbers leave, worked out from their
                --texts: a part sized "100% available" beside text is restyled
                --by the engine every frame.
                local numbers = HeroSheetTheme.TextWidth(tostring(progress.level), 14) + 8
                    + HeroSheetTheme.TextWidth(tostring(progress.level + 1), 14) + 16
                    + HeroSheetTheme.TextWidth(XpText(), 12) + 4
                track.selfStyle.width = string.format("100%%-%d", math.ceil(numbers))
            end
        end

        --the level line: "Choices to make" by one rule, whatever raised the
        --Level. The button reads "Finish Level N" while choices are unmade and
        --is gold when there is work to do. Manual Level up is Edit mode only:
        --players read it as a call to action, and in Narrow it costs a row.
        local lineLabel = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            width = "100%",
            halign = "left",
            valign = "center",
            fontSize = cond(small, 11.5, 13.5),
            bold = true,
            textWrap = true,
            click = function(element)
                if (last.choices or last.newLevel) and HeroSheetWrite.CanWrite() then
                    args.levelUp()
                end
            end,
        }
        --the Level up button is the manual path; Finish is not. On a
        --slow-start rung the Director's button moves this Hero up one rung.
        local button = LevelButton(small, function()
            if last.nextRung ~= nil then
                HeroSheetWrite.Save{
                    description = last.nextRung,
                    execute = function(hero)
                        HeroBuild.main.hero.NextRung(hero --[[@as character]])
                    end,
                }
                return
            end
            args.levelUp(not (last.choices or last.newLevel))
        end)
        local line = gui.Panel{
            width = "100%",
            height = "auto",
            minHeight = 28,
            flow = "none",
            tmargin = 4,
            lineLabel,
            button,
        }
        children[#children+1] = line
        panel.children = children

        return function(liveToken)
            local progress = Prog(liveToken)
            if progress == nil then
                return
            end
            last.prog = progress
            paintTop()
            local choices = ChoicesToMake(liveToken)
            last.choices = choices
            local hero = liveToken.properties --[[@as character]]
            --a Level a respite raised that Level up has not shown yet, though
            --nothing is left to choose; or the slow-start page the Director
            --moved the Hero onto (its key, 2-5; a rung that brings nothing has none).
            local seen = hero:try_get("levelUpSeen")
            local first = FirstPage(liveToken)
            local newRung = nil
            if not choices and first ~= nil and first.level == 1 then
                newRung = first.key
            end
            local newLevel = not choices and ((seen ~= nil and seen < progress.level) or newRung ~= nil)
            last.newLevel = newLevel
            --Finish names the page Level up opens first.
            local finish = string.format("Finish Level %d", progress.level)
            local firstKey = newRung
            if choices and first ~= nil and first.level == 1 then
                firstKey = first.key
            end
            if firstKey ~= nil then
                finish = cond(firstKey <= 4, "Finish " .. tostring(HeroBuild.main.RUNGS[firstKey]), "Finish Level 1")
            end
            local lineText = nil
            local ready = false
            --- @type nil|string
            local tooltip = "Level up manually, for example when the Director awards a level"
            if choices then
                lineText, ready, tooltip = "Choices to make.", true, nil
            elseif newRung ~= nil then
                lineText = cond(newRung <= 4, string.format("See what changed for the %s.", tostring(HeroBuild.main.RUNGS[newRung])), "See what changed at Level 1.")
                ready, tooltip = true, nil
            elseif newLevel then
                lineText, ready, tooltip = string.format("See what changed at Level %d.", progress.level), true, nil
            elseif progress.maxLevel then
                if progress.victories > 0 and progress.epic ~= nil then
                    lineText = string.format("Your next respite adds %d XP and %d %s.", progress.victories, progress.victories, progress.epic.name or "Epic")
                end
            elseif progress.readyToLevel then
                lineText, ready, tooltip = "Ready to level up.", true, "Level up now"
            elseif progress.respiteWouldLevel then
                lineText = "A respite would Level this Hero."
            end
            --a Hero on a slow-start rung has no Level up: the Director moves
            --the slow start, with this card's Move to button once no page waits.
            local rung = HeroBuild.main.hero.Rung(hero)
            local onRung = rung ~= nil
            last.nextRung = nil
            if rung ~= nil and dmhub.isDM and not (choices or newLevel) then
                if rung < 4 then
                    last.nextRung = "Move to " .. tostring(HeroBuild.main.RUNGS[rung + 1])
                    tooltip = "Director only. Moves this Hero to the next encounter of the slow start."
                else
                    last.nextRung = "End slow start"
                    tooltip = "Director only. Moves this Hero off of Slow Start and to Level 1."
                end
            end
            drawnEditing = HeroSheet.Editing()
            local manualLevelUp = not progress.maxLevel and not onRung and (progress.readyToLevel or drawnEditing)
            local showButton = HeroSheetWrite.CanWrite() and (choices or newLevel or last.nextRung ~= nil or manualLevelUp)
            local buttonText = cond(choices or newLevel, finish, last.nextRung or "Level up")
            --the text takes what the button leaves, so a short line stays on
            --one line.
            local buttonRoom = 0
            if showButton then
                buttonRoom = math.ceil(HeroSheetTheme.TextWidth(buttonText, cond(small, 11.5, 12)) + 2 * cond(small, 7, 10) + 10)
            end
            lineLabel.text = lineText or ""
            lineLabel:SetClass("collapsed", lineText == nil)
            lineLabel.selfStyle.width = cond(showButton, string.format("100%%-%d", buttonRoom), "100%")
            button:SetClass("collapsed", not showButton)
            button.text = buttonText
            button:SetClass("heroSheetLevelReady", ready)
            button.data.tooltip = tooltip
            line:SetClass("collapsed", lineText == nil and not showButton)
            panel:FireEventTree("refreshNumber")
        end
    end

    return HeroSheetRefresh.KeptBlock({
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 8,
        --Medium sets the level line and the epic resource smaller.
        heroSheetTier = function(element, tier)
            element:FireEvent("heroSheetRepaint")
        end,
        --Edit mode shows or hides the manual Level up button.
        heroSheetEdit = function(element, editing)
            if HeroSheet.Editing() ~= drawnEditing then
                element:FireEvent("heroSheetRepaint")
            end
        end,
    }, {
        name = "card progress",
        signature = function(token)
            local prog = Prog(token)
            if prog == nil then
                return "none"
            end
            local epic = prog.epic ~= nil and prog.epic.value or ""
            --the slow start's place and Level up's first page name the line
            --and its button too.
            local hero = token.properties --[[@as character]]
            local first = FirstPage(token)
            local slow = string.format("%s|%s|%s", tostring(hero:try_get("rungSeen")), tostring(HeroBuild.main.hero.Rung(hero)), tostring(first ~= nil and first.key or nil))
            return string.format("%d|%d|%d|%d|%s|%s|%s|%s|%s|%s", prog.level, prog.xp, prog.xpPerLevel, prog.victories, tostring(epic), tostring(ChoicesToMake(token)), tostring(HeroSheetWrite.CanWrite()), tostring(hero:try_get("levelUpSeen")), slow, tostring(HeroSheet.Editing()))
        end,
        shape = function(token)
            local prog = Prog(token)
            return string.format("%s|%s", tostring(prog ~= nil and prog.maxLevel), HeroSheet.Tier())
        end,
        build = Build,
    })
end

----------------------------------------------------------------------
--Stamina: the bar with hover zones Damage / Set / Heal / Temp. Picking one
--turns the bar into a field for that value: Enter or the tick applies, Esc
--or the cross cancels. It writes Stamina the same way the Character panel's
--bar does.

local STAMINA_MODES = {
    dmg = {label = "Damage", description = "Apply Damage"},
    set = {label = "Stamina", description = "Set Stamina"},
    heal = {label = "Heal", description = "Apply Healing"},
    temp = {label = "Temp", description = "Apply Temp Stamina"},
}

--- Apply a typed value to the open Hero's Stamina.
--- @param mode string dmg, set, heal or temp
--- @param text string what was typed
local function ApplyStamina(mode, text)
    local value = tonumber(text)
    if value == nil then
        return
    end
    --Stamina is whole numbers: a typed 2.5 would break every label that
    --shows it.
    value = math.floor(value)
    text = tostring(value)
    local info = STAMINA_MODES[mode]
    if info == nil then
        return
    end
    if (mode == "dmg" or mode == "heal") and value <= 0 then
        return
    end
    local token = HeroSheet.Token()
    if mode == "temp" and token ~= nil and value == (token.properties:TemporaryHitpoints() or 0) then
        --unchanged: no "gained temporary Stamina" event, no empty undo step.
        return
    end
    HeroSheetWrite.Save{
        description = info.description,
        execute = function(hero)
            if mode == "dmg" then
                --a string: TakeDamage takes a formula.
                hero:TakeDamage(text)
            elseif mode == "heal" then
                hero:Heal(value)
            elseif mode == "temp" then
                hero:SetTemporaryHitpoints(text)
                hero:DispatchEvent("gaintempstamina", {})
            else
                hero:SetCurrentHitpoints(value)
            end
        end,
    }
end

--- @return Panel
local function Stamina()
    local bar
    local fill
    local tempFill
    local number
    local zones
    local field
    local fieldLabel
    local fieldInput
    local line
    local mode = nil
    local focused = false
    --When the tick or cross was pressed: pressing one takes focus from the
    --field, which must not close the field before the click lands.
    local buttonPressedAt = -1

    local function Values(token)
        local hero = token.properties
        local max = math.max(1, hero:MaxHitpoints())
        local cur = hero:CurrentHitpoints()
        local temp = hero:TemporaryHitpoints() or 0
        local winded = math.floor(max / 2)
        local state = "healthy"
        local dead = false
        pcall(function() dead = hero:IsDead() end)
        if dead then
            state = "dead"
        elseif cur <= 0 then
            state = "dying"
        elseif cur <= winded then
            state = "winded"
        end
        return cur, max, temp, winded, state
    end

    local function CloseField()
        mode = nil
        focused = false
        fieldInput.captureEscape = false
        field:SetClass("collapsed", true)
        line:SetClass("heroSheetHush", false)
    end

    --- @param newMode string
    local function OpenField(newMode)
        local token = HeroSheet.Token()
        if token == nil or not HeroSheetWrite.CanWrite() then
            return
        end
        local cur, _, temp = Values(token)
        mode = newMode
        fieldLabel.text = STAMINA_MODES[newMode].label
        if newMode == "set" then
            fieldInput.text = tostring(cur)
        elseif newMode == "temp" then
            fieldInput.text = tostring(temp)
        else
            fieldInput.text = ""
        end
        field:SetClass("collapsed", false)
        fieldInput.captureEscape = true
        --the line under the bar keeps its height but hides while editing.
        line:SetClass("heroSheetHush", true)
        dmhub.Schedule(0.01, function()
            if not mod.unloaded and fieldInput.valid then
                gui.SetFocus(fieldInput)
            end
        end)
    end

    local function Commit()
        local openMode = mode
        local text = fieldInput.text
        CloseField()
        gui.SetFocus(nil)
        if openMode ~= nil then
            ApplyStamina(openMode, text)
        end
    end

    local function Zone(zoneMode, text, cls, width)
        return gui.Label{
            classes = {"heroSheetHpZone", cls},
            text = text,
            bgimage = "panels/square.png",
            width = width,
            height = "100%",
            fontSize = 12,
            bold = true,
            textAlignment = "center",
            click = function(element)
                OpenField(zoneMode)
            end,
        }
    end

    fill = gui.Panel{
        classes = {"heroSheetHpFill"},
        bgimage = "panels/square.png",
        width = "0%",
        height = "100%",
        halign = "left",
        interactable = false,
        --a light top half, for a soft sheen.
        gui.Panel{
            classes = {"heroSheetHpSheen"},
            bgimage = "panels/square.png",
            width = "100%",
            height = "50%",
            valign = "top",
            interactable = false,
        },
    }
    tempFill = gui.Panel{
        classes = {"heroSheetHpTemp"},
        bgimage = "panels/square.png",
        width = "0%",
        height = "100%",
        halign = "left",
        interactable = false,
    }
    number = Text{
        classes = {"heroSheetHpNumber"},
        floating = true,
        text = "",
        fontSize = 15,
        bold = true,
        halign = "center",
        valign = "center",
        interactable = false,
    }

    --the four zones, in the bar's own proportions (1 : 1.15 : 1 : 0.8),
    --shown while the bar is hovered (the heroSheetHpZones rules).
    local setZone = Zone("set", "", "heroSheetHpSet", "29.1%")
    zones = gui.Panel{
        classes = {"heroSheetHpZones"},
        floating = true,
        width = "100%",
        height = "100%",
        flow = "horizontal",
        Zone("dmg", "\u{2212} Dmg", "heroSheetHpDmg", "25.3%"),
        setZone,
        Zone("heal", "Heal +", "heroSheetHpHeal", "25.3%"),
        Zone("temp", "Temp", "heroSheetHpTempZone", "20.3%"),
    }

    fieldLabel = Text{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        bold = true,
        valign = "center",
        lmargin = 8,
        rmargin = 8,
    }
    fieldInput = gui.Input{
        classes = {"heroSheetNumberInput"},
        width = 56,
        height = 20,
        fontSize = 13,
        valign = "center",
        characterLimit = 8,
        selectAllOnFocus = true,
        placeholderText = "0",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            CloseField()
            gui.SetFocus(nil)
        end,
        focus = function(element)
            focused = true
        end,
        --Enter applies (change fires on Enter and on focus loss; clicking
        --away cancels, so only Enter and the tick commit).
        submit = function(element)
            Commit()
        end,
        defocus = function(element)
            if not focused then
                return
            end
            dmhub.Schedule(0.05, function()
                if mod.unloaded or not fieldInput.valid then
                    return
                end
                if dmhub.Time() - buttonPressedAt < 0.5 then
                    return
                end
                if mode ~= nil and not fieldInput.hasFocus then
                    CloseField()
                end
            end)
        end,
    }
    local function FieldButton(icon, onClick)
        return gui.Panel{
            classes = {"hoverable"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = 24,
            height = 24,
            valign = "center",
            hmargin = 2,
            press = function(element)
                buttonPressedAt = dmhub.Time()
            end,
            click = function(element)
                onClick()
            end,
            gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = icon,
                width = 14,
                height = 14,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end
    field = gui.Panel{
        classes = {"heroSheetHpField", "collapsed"},
        bgimage = "panels/square.png",
        floating = true,
        width = "100%",
        height = "100%",
        flow = "horizontal",
        fieldLabel,
        fieldInput,
        FieldButton("phosphor/check-bold.png", Commit),
        FieldButton("phosphor/x-bold.png", function()
            CloseField()
            gui.SetFocus(nil)
        end),
    }

    bar = gui.Panel{
        classes = {"heroSheetHpBar"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 4,
        width = "100%",
        height = 24,
        tmargin = 8,
        gui.Panel{
            classes = {"heroSheetHpClip"},
            bgimage = "panels/square.png",
            clip = true,
            clipHidden = true,
            width = "100%-4",
            height = "100%-4",
            halign = "center",
            valign = "center",
            flow = "horizontal",
            fill,
            tempFill,
        },
        number,
        zones,
        field,
    }

    --the line's labels: 13 at Wide, 11.5 at Medium and Narrow, so the
    --"Dead at" and "Winded at" values never run together.
    local lineLabels = {}
    local function LineFont()
        return cond(HeroSheet.Tier() ~= "wide", 11.5, 13)
    end
    local function LineText(args)
        args.fontSize = LineFont()
        local label = Text(args)
        lineLabels[#lineLabels+1] = label
        return label
    end
    --the four parts spread across the line, first at the left and the
    --state word at the right.
    local function LinePart(label, value, align)
        return gui.Panel{
            width = "25%",
            height = "auto",
            flow = "none",
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = align,
                LineText{classes = {"heroSheetCardSub"}, text = label, rmargin = 4},
                value,
            },
        }
    end
    local deadAt = LineText{classes = {"heroSheetCardStrong"}, text = "", bold = true}
    local windedAt = LineText{classes = {"heroSheetCardStrong"}, text = "", bold = true}
    local tempValue = LineText{
        classes = {"heroSheetCardText", "hoverable"},
        text = "",
        bold = true,
        click = function(element)
            OpenField("temp")
        end,
    }
    --Temp is typed into, so it wears the click-to-type dotted underline.
    local tempDots = HeroSheetTheme.DottedUnderline(HeroSheetTheme.TextWidth("0", 13), {
        floating = true,
        halign = "center",
        valign = "bottom",
        --the label is only as tall as its text: the dots go just below it.
        y = 3,
    })
    local tempHolder = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        tempValue,
        tempDots,
    }
    local stateWord = LineText{text = "", bold = true, halign = "right"}
    line = gui.Panel{
        width = "100%",
        height = 22,
        flow = "horizontal",
        tmargin = 2,
        LinePart("Dead at", deadAt, "left"),
        LinePart("Winded at", windedAt, "center"),
        LinePart("Temp", tempHolder, "center"),
        gui.Panel{
            width = "25%",
            height = "auto",
            flow = "none",
            stateWord,
        },
    }

    return HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetTier = function(element, tier)
            for _, label in ipairs(lineLabels) do
                label.selfStyle.fontSize = LineFont()
            end
        end,
        heroSheetRedrawStamina = function(element, token)
            local cur, max, temp, winded, state = Values(token)
            local pct = math.max(0, math.min(1, cur / max))
            local tempPct = math.min(1 - pct, temp / max)
            fill.selfStyle.width = string.format("%.2f%%", pct * 100)
            tempFill.selfStyle.width = string.format("%.2f%%", tempPct * 100)
            fill:SetClass("winded", state == "winded")
            fill:SetClass("dying", state == "dying" or state == "dead")
            bar:SetClass("winded", state == "winded")
            bar:SetClass("dying", state == "dying" or state == "dead")
            local text = string.format("%d/%d", cur, max)
            if temp > 0 then
                text = text .. string.format(" +%d", temp)
            end
            number.text = text
            setZone.text = string.format("%d/%d", cur, max)
            deadAt.text = tostring(-winded)
            windedAt.text = tostring(winded)
            tempValue.text = tostring(temp)
            HeroSheetTheme.SetDots(tempDots, HeroSheetTheme.TextWidth(tempValue.text, LineFont()))
            tempDots:SetClass("collapsed", not HeroSheetWrite.CanWrite())
            local word = string.upper(string.sub(state, 1, 1)) .. string.sub(state, 2)
            stateWord.text = word
            stateWord:SetClass("heroSheetCardSuccess", state == "healthy")
            stateWord:SetClass("heroSheetCardWarning", state == "winded")
            stateWord:SetClass("heroSheetCardDanger", state == "dying" or state == "dead")
            --the zones only for those who may change the Hero.
            zones:SetClass("collapsed", not HeroSheetWrite.CanWrite())
        end,
        bar,
        line,
    }, {
        name = "card stamina",
        signature = function(token)
            local cur, max, temp, winded, state = Values(token)
            return string.format("%d|%d|%d|%s", cur, max, temp, state)
        end,
        refresh = function(panel, token)
            panel:FireEvent("heroSheetRedrawStamina", token)
        end,
    })
end

----------------------------------------------------------------------
--Recoveries, Victories and the heroic resource.

--The Recovery popup: spend one, or set how many are left. Nothing is
--spent by clicking the ring itself.
--- @param anchor Panel
local function RecoveryPopup(anchor)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local read = Data(token)
    if read == nil then
        return
    end
    local rec = read.recoveries
    local frame
    local canSpend = EotwHeroSheet.CanSpendRecovery(token)
    local id = CharacterResource.recoveryResourceId
    local function Limit()
        local info = (dmhub.GetTable(CharacterResource.tableName) or {})[id]
        return info and info.usageLimit or "long"
    end
    local input
    local function SetCount()
        local value = tonumber(input.text)
        if value == nil or value < 0 then
            return
        end
        value = math.min(math.floor(value), rec.max)
        HeroSheetWrite.Save{
            description = "Set Recoveries",
            execute = function(hero)
                local left = (hero:GetResources()[id] or 0) - (hero:GetResourceUsage(id, Limit()) or 0)
                SetResource(hero, id, left, value, Limit(), "Set manually")
            end,
        }
        HeroSheetWindow.ClosePopup(frame)
    end
    input = gui.Input{
        classes = {"heroSheetNumberInput"},
        width = 42,
        height = 24,
        fontSize = 15,
        halign = "right",
        valign = "center",
        characterLimit = 3,
        selectAllOnFocus = true,
        text = tostring(rec.current),
        submit = function(element)
            SetCount()
        end,
    }
    local spend = gui.Label{
        classes = {"heroSheetPlateButton", cond(canSpend, "hoverable", "heroSheetDisabled")},
        text = string.format("Spend a Recovery (+%d Stamina)", rec.value),
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "100%",
        height = HeroSheetWindow.TargetSize(32),
        fontSize = 15,
        bold = true,
        textAlignment = "center",
        --a greyed Spend says why.
        linger = function(element)
            if not canSpend then
                gui.Tooltip(cond(rec.current <= 0, "None left", "Stamina is full"))(element)
            end
        end,
        click = function(element)
            if not canSpend then
                return
            end
            HeroSheetWrite.Save{
                description = "Use Recovery",
                execute = function(hero)
                    hero:Heal(hero:RecoveryAmount(), "Use Recovery")
                    hero:ConsumeResource(id, Limit(), 1, "Used Recovery")
                end,
            }
            HeroSheetWindow.ClosePopup(frame)
        end,
    }
    --as tall as its content: the padding, Spend, the gap and the Set row.
    frame = HeroSheetWindow.ShowPopup{
        width = 300,
        height = 12 + HeroSheetWindow.TargetSize(32) + 10 + 28 + 12,
        anchor = anchor,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            spend,
            gui.Panel{
                width = "100%",
                height = 28,
                flow = "none",
                tmargin = 10,
                Text{text = "Set Recoveries", fontSize = 15, halign = "left", valign = "center"},
                input,
            },
        },
    }
end

--- @return Panel
local function Counters()
    --Builds the row for the tier: Recoveries, then Victories and the heroic
    --resource side by side, or stacked at Medium so neither is cut off. The
    --painter it returns shows a Hero's values in it, so another Hero only
    --changes text.
    --- @param panel Panel
    --- @param token CharacterToken
    --- @return nil|fun(token: CharacterToken)
    local function Build(panel, token)
        if Data(token) == nil then
            panel.children = {}
            return nil
        end
        --what the painter last read, for the handlers below.
        local last = {rec = {current = 0, max = 0, value = 0}, resource = {}, minimum = 0}
        local count = Text{
            text = "",
            fontSize = 20,
            bold = true,
            halign = "center",
            valign = "center",
            interactable = false,
        }
        --Narrow's banner has a smaller ring, to fit its height.
        local ringSize = cond(HeroSheet.Tier() == "narrow", 34, 40)
        local ring
        ring = gui.Panel{
            classes = {"heroSheetRing2", "hoverable"},
            bgimage = "panels/square.png",
            border = 2,
            cornerRadius = ringSize / 2,
            width = ringSize,
            height = ringSize,
            halign = "left",
            valign = "center",
            linger = function(element)
                gui.Tooltip(string.format("Click the ring to spend one (+%d Stamina) or set the number of available recoveries.", last.rec.value))(element)
            end,
            click = function(element)
                RecoveryPopup(ring)
            end,
            count,
        }
        local victories = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            --the Victory icon the character panel uses, sized as the
            --heroic resource's.
            gui.Panel{
                bgimage = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png",
                bgcolor = "white",
                width = 24,
                height = 24,
                valign = "center",
                rmargin = 4,
                linger = gui.Tooltip("Victories"),
            },
            HeroSheetTheme.ClickNumber{
                classes = {"heroSheetCardStrong"},
                get = function()
                    local live = HeroSheet.Token()
                    return live ~= nil and live.properties:GetVictories() or 0
                end,
                set = function(value)
                    --undoable, as on the character sheet.
                    HeroSheetWrite.Save{
                        description = "Set Victories",
                        execute = function(hero)
                            hero:SetVictories(value)
                        end,
                    }
                end,
                canEdit = HeroSheetWrite.CanWrite,
                fontSize = 22,
                tooltip = "Victories",
            },
        }
        --the heroic resource with the class's own icon; below 0 where the
        --class allows it.
        local icon = gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = 24,
            height = 24,
            valign = "center",
            rmargin = 4,
            linger = function(element)
                gui.Tooltip(last.resource.name or "Heroic resource")(element)
            end,
        }
        local resourceGroup = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            icon,
            HeroSheetTheme.ClickNumber{
                classes = {"heroSheetCardStrong"},
                get = function()
                    local live = HeroSheet.Token()
                    return live ~= nil and (live.properties:GetHeroicOrMaliceResources() or 0) or 0
                end,
                set = function(value)
                    HeroSheetWrite.Save{
                        description = "Set " .. (last.resource.name or "heroic resource"),
                        execute = function(hero)
                            SetResource(hero, CharacterResource.heroicResourceId, hero:GetHeroicOrMaliceResources() or 0, value, "unbounded", "Set manually")
                        end,
                    }
                end,
                canEdit = HeroSheetWrite.CanWrite,
                min = function()
                    return last.minimum
                end,
                fontSize = 22,
                tooltip = function()
                    return last.resource.name
                end,
            },
        }
        local recoveryLine = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 13,
        }
        --what follows Recoveries sits at the row's right end (halign right),
        --never pushed there by a "100% available" spacer: the engine restyles
        --such a panel every frame.
        local function Divider(height)
            return gui.Panel{
                classes = {"heroSheetDivider"},
                bgimage = "panels/square.png",
                width = 1,
                height = height,
                hmargin = 10,
                halign = "right",
                valign = "center",
            }
        end
        local children = {
            ring,
            --at the ring's side: the banner's wide row would centre it.
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                lmargin = 8,
                Text{text = "Recoveries", fontSize = 15, bold = true},
                recoveryLine,
            },
        }
        if HeroSheet.Tier() == "medium" then
            --Medium: one divider, Victories over the heroic resource, so
            --neither is cut off.
            victories.selfStyle.halign = "left"
            resourceGroup.selfStyle.halign = "left"
            children[#children+1] = Divider(44)
            children[#children+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                halign = "right",
                valign = "center",
                victories,
                resourceGroup,
            }
        else
            victories.selfStyle.halign = "right"
            resourceGroup.selfStyle.halign = "right"
            children[#children+1] = Divider(28)
            children[#children+1] = victories
            children[#children+1] = Divider(28)
            children[#children+1] = resourceGroup
        end
        panel.children = children

        return function(liveToken)
            local read = Data(liveToken)
            if read == nil then
                return
            end
            last.rec = read.recoveries
            last.resource = read.resource or {}
            last.minimum = 0
            pcall(function() last.minimum = -liveToken.properties:AllowNegativeResources() end)
            local write = HeroSheetWrite.CanWrite()
            ring:SetClass("hoverable", write)
            ring:SetClass("heroSheetInert", not write)
            count.text = tostring(last.rec.current)
            recoveryLine.text = string.format("of %d \u{00B7} +%d each", last.rec.max, last.rec.value)
            local hasIcon = last.resource.iconid ~= nil and last.resource.iconid ~= ""
            icon.bgimage = cond(hasIcon, last.resource.iconid, "panels/square.png")
            icon.selfStyle.bgcolor = cond(hasIcon, "white", "clear")
            panel:FireEventTree("refreshNumber")
        end
    end
    return HeroSheetRefresh.KeptBlock({
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 9,
        heroSheetTier = function(element, tier)
            element:FireEvent("heroSheetRepaint")
        end,
    }, {
        name = "card counters",
        signature = function(token)
            local read = Data(token)
            if read == nil then
                return "none"
            end
            return string.format("%d|%d|%d|%d|%s|%s|%s", read.recoveries.current, read.recoveries.max, read.recoveries.value,
                token.properties:GetVictories(), tostring(read.resource.value), tostring(read.resource.iconid), tostring(HeroSheetWrite.CanWrite()))
        end,
        shape = function(token)
            return HeroSheet.Tier()
        end,
        build = Build,
    })
end

----------------------------------------------------------------------
--The kit card: the combined kits as one (each bonus at the better value),
--the gear they use, and, when both kits give the same damage type, a two-way
--switch for which kit's damage bonus applies. A class without kits shows its
--kit equivalents (a Conduit's Prayer and Ward...).

--A kit equivalent's text longer than this is cut short on the kit card, the
--whole text on hover (EotW's limit).
local KIT_TEXT_FOLD_CHARS = 150

--Short bonus labels, so a label and its value fit on one row.
local KIT_LABELS = {
    ["Melee distance"] = "Melee dist.",
    ["Ranged distance"] = "Ranged dist.",
    ["Melee damage"] = "Melee dmg",
    ["Ranged damage"] = "Ranged dmg",
}

--The kits a Hero has, by id, or nil.
--- @param hero creature
--- @return nil|Kit kit1
--- @return nil|Kit kit2
local function Kits(hero)
    local kitTable = dmhub.GetTable(Kit.tableName) or {}
    local kit1 = kitTable[hero:try_get("kitid") or ""]
    local kit2 = nil
    local count = 1
    pcall(function() count = hero:GetNumberOfKits() end)
    if count > 1 then
        kit2 = kitTable[hero:try_get("kitid2") or ""]
    end
    return kit1, kit2
end

--The damage types both kits give, for the switch: {dtype, label, kit1, kit2,
--value1, value2, first (kit1's applies)}.
--- @param hero creature
--- @return table[]
local function DamagePicks(hero)
    local kit1, kit2 = Kits(hero)
    local result = {}
    if kit1 == nil or kit2 == nil then
        return result
    end
    for _, dtype in ipairs({"melee", "ranged"}) do
        local bonus1 = kit1:FormatDamageBonus(dtype)
        local bonus2 = kit2:FormatDamageBonus(dtype)
        --nothing to choose when both kits give the same bonus.
        if bonus1 ~= nil and bonus2 ~= nil and bonus1 ~= bonus2 then
            result[#result+1] = {
                dtype = dtype,
                label = cond(dtype == "melee", "Melee damage", "Ranged damage"),
                kit1 = kit1,
                kit2 = kit2,
                value1 = bonus1,
                value2 = bonus2,
                first = Kit.DamageBonusSelected(hero, dtype, kit1, kit2),
            }
        end
    end
    return result
end

--One damage switch row: the label, then a button per kit ("+2/+2/+2" and
--the kit's name, cut off with its full name on hover). Built once and
--painted with a pick (paint), so another Hero changes its text only.
--- @return {panel: Panel, paint: fun(pick: table)}
local function DamageSwitch()
    --the pick shown, for the click handlers.
    local shown = nil
    local function Option(which)
        local value = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 13,
            bold = true,
            valign = "center",
            rmargin = 6,
            interactable = false,
        }
        local name = HeroSheetTheme.EllipsisLabel{
            classes = {"heroSheetCardSub"},
            text = "",
            width = "100%-70",
            height = "auto",
            fontSize = 12,
            valign = "center",
        }
        local option = gui.Panel{
            classes = {"heroSheetKitPick", "unselected", "heroSheetInert"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 4,
            width = "50%",
            height = 28,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            click = function(element)
                local pick = shown
                if pick == nil or not HeroSheetWrite.CanWrite() then
                    return
                end
                local selected = (which == 1) == pick.first
                if selected then
                    return
                end
                --a switch that writes something else (the Builder's
                --Companion melee) brings its own write.
                if pick.write ~= nil then
                    HeroSheetWrite.Save{
                        description = pick.description or "Choose kit damage bonus",
                        execute = function(hero)
                            pick.write(hero, which)
                        end,
                    }
                    return
                end
                local kit = cond(which == 1, pick.kit1, pick.kit2)
                HeroSheetWrite.Save{
                    description = "Choose kit damage bonus",
                    execute = function(hero)
                        local levelChoices = hero:GetLevelChoices()
                        local choices = levelChoices.kitBonusChoices or {}
                        choices[pick.dtype] = kit.id
                        levelChoices.kitBonusChoices = choices
                    end,
                }
            end,
            value,
            name,
        }
        --- @param pick table
        local function Paint(pick)
            local selected = (which == 1) == pick.first
            local kit = cond(which == 1, pick.kit1, pick.kit2)
            option:SetClass("selected", selected)
            option:SetClass("unselected", not selected)
            option:SetClass("hoverable", HeroSheetWrite.CanWrite())
            option:SetClass("heroSheetInert", not HeroSheetWrite.CanWrite())
            --view only: the kit in use, not a switch that cannot switch.
            option:SetClass("collapsed", not selected and not HeroSheetWrite.CanWrite())
            value.text = cond(which == 1, pick.value1, pick.value2)
            value:SetClass("heroSheetKitPickText", selected)
            value:SetClass("heroSheetCardStrong", not selected)
            local own = cond(which == 1, pick.name1, pick.name2)
            name.text = own or (kit ~= nil and kit.name or "")
            name:SetClass("heroSheetKitPickText", selected)
            name:SetClass("heroSheetCardSub", not selected)
        end
        return option, Paint
    end
    local label = Text{
        classes = {"heroSheetCardLabel"},
        text = "",
        fontSize = 11,
        bold = true,
        halign = "left",
        valign = "center",
    }
    local first, paintFirst = Option(1)
    local second, paintSecond = Option(2)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 8,
        gui.Panel{
            classes = {"heroSheetDivider"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            bmargin = 6,
        },
        label,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            first,
            second,
        },
    }
    return {
        panel = panel,
        paint = function(pick)
            shown = pick
            label.text = string.upper(pick.label)
            paintFirst(pick)
            paintSecond(pick)
        end,
    }
end

--- The damage types both of a Hero's kits give, each a pick for DamageSwitch.
HeroSheetCard.DamagePicks = DamagePicks

--- A two-way switch row (the kit card's, and the Builder's under Kits):
--- paint it with a pick {label, value1, value2, first, kit1/kit2 or
--- name1/name2, and write(hero, which) + description for anything but a kit
--- damage bonus}.
HeroSheetCard.DamageSwitch = DamageSwitch

--One bonus on the kit card: its label at the left, its value at the right;
--two to a row at Wide, one at Medium.
--- @param two boolean two to a row
--- @return {panel: Panel, paint: fun(bonus: table)}
local function KitBonus(two)
    local label = Text{
        classes = {"heroSheetCardLabel"},
        text = "",
        fontSize = 11,
        bold = true,
        halign = "left",
        valign = "center",
    }
    local value = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 13.5,
        bold = true,
        halign = "right",
        valign = "center",
    }
    local panel = gui.Panel{
        width = cond(two, "50%", "100%"),
        height = 20,
        halign = "left",
        flow = "none",
        rpad = cond(two, 12, 0),
        borderBox = true,
        heroSheetKitColumns = function(element, twoNow)
            element.selfStyle.width = cond(twoNow, "50%", "100%")
            --the gap between the two columns.
            element.selfStyle.rpad = cond(twoNow, 12, 0)
        end,
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            label,
        },
        value,
    }
    return {
        panel = panel,
        paint = function(bonus)
            label.text = string.upper(KIT_LABELS[bonus.label] or bonus.label)
            value.text = bonus.value
        end,
    }
end

--- A kit's armor and weapons as one line: "Heavy armor, medium weapon,
--- shield". Used by the kit card and the Builder's kit options.
--- @param gear nil|{armor: nil|string[], weapons: nil|string[]} as EotwHeroSheet.KitGear gives it
--- @return string "" when the kit has neither
function HeroSheetCard.KitGearText(gear)
    gear = gear or {}
    local parts = {}
    for _, armor in ipairs(gear.armor or {}) do
        parts[#parts+1] = string.lower(armor) .. " armor"
    end
    --a size is a weapon of that size; anything else (shield, bow, polearm)
    --is named as it is.
    local sizes = {light = true, medium = true, heavy = true}
    for _, weapon in ipairs(gear.weapons or {}) do
        local lower = string.lower(weapon)
        parts[#parts+1] = cond(sizes[lower], lower .. " weapon", lower)
    end
    local line = table.concat(parts, ", ")
    return string.upper(string.sub(line, 1, 1)) .. string.sub(line, 2)
end

--- The whole kit for the summary's hover card: its name, gear and every
--- bonus, and for two kits the damage each gives with the one in use.
--- @param token CharacterToken
--- @return Panel
local function KitHoverCard(token)
    local read = Data(token)
    local first = read ~= nil and read.kit ~= nil and read.kit.entries[1] or nil
    local children = {}
    if first ~= nil then
        children[#children+1] = Text{
            classes = {"heroSheetCardStrong"},
            text = first.name or "",
            fontSize = 15,
            bold = true,
            width = "100%",
            textWrap = true,
        }
        local line = HeroSheetCard.KitGearText(first.gear)
        if line ~= "" then
            children[#children+1] = Text{
                classes = {"heroSheetCardSub"},
                text = line,
                fontSize = 12.5,
                width = "100%",
                textWrap = true,
                tmargin = 4,
            }
        end
        local cells = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 6,
        }
        local picks = DamagePicks(token.properties)
        local picked = {}
        for _, pick in ipairs(picks) do
            picked[pick.label] = true
        end
        for _, bonus in ipairs(first.bonuses or {}) do
            if not picked[bonus.label] then
                local cell = KitBonus(true)
                cell.paint(bonus)
                cells:AddChild(cell.panel)
            end
        end
        --a damage both kits give: the one in use, and which kit it is from.
        for _, pick in ipairs(picks) do
            local kit = cond(pick.first, pick.kit1, pick.kit2)
            --the whole width: the value and the kit's name do not fit half of it.
            local cell = KitBonus(false)
            cell.paint({label = pick.label, value = string.format("%s (%s)", cond(pick.first, pick.value1, pick.value2), kit.name)})
            cells:AddChild(cell.panel)
        end
        children[#children+1] = cells
    end
    return gui.Panel{
        width = HeroSheetTheme.CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

--- The kit card for the card column.
--- @param args HeroSheetCardArgs
--- @return Panel
function HeroSheetCard.Kit(args)
    --whether the card was last painted as the Inventory tab's summary.
    local kitSummary = false
    --Builds the card for its shape (no kit, a kit, or N kit equivalents)
    --and returns the painter that shows a Hero's kit in it. Bonuses and
    --damage switches are kept in pools that only grow; unused ones collapse.
    --- @param panel Panel
    --- @param token CharacterToken
    --- @return nil|fun(token: CharacterToken)
    local function Build(panel, token)
        local read = Data(token)
        if read == nil or read.kit == nil then
            panel.children = {}
            return nil
        end
        local kind = read.kit.kind
        --the header, with Change in Builder while editing. Kit equivalents
        --head their own sections instead.
        local headerText = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 16,
            bold = true,
            halign = "left",
            valign = "center",
        }
        local changeButton = gui.Label{
            classes = {"heroSheetPlateButton", "hoverable", "collapsed"},
            text = "Change in Builder",
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 12,
            width = "auto",
            height = 24,
            hpad = 10,
            borderBox = true,
            fontSize = 12,
            bold = true,
            halign = "right",
            valign = "center",
            click = function()
                if args.changeKit ~= nil then
                    args.changeKit()
                else
                    args.levelUp()
                end
            end,
        }
        local headerRow = gui.Panel{
            width = "100%",
            height = 26,
            flow = "none",
            headerText,
            changeButton,
        }
        local children = {headerRow}
        --- @type fun(kit: table, token: CharacterToken)
        local paintBody

        if kind == "none" then
            children[#children+1] = Text{classes = {"heroSheetCardSub"}, text = "No kit.", fontSize = 13, halign = "left"}
            paintBody = function(kit, liveToken) end
        elseif kind == "equivalent" then
            --each kit equivalent in its own section: the slot as its header,
            --the pick, and its text cut short with the whole text on hover
            --(EotW's KIT_TEXT_FOLD_CHARS).
            local count = #read.kit.entries
            --at most two to a row, so a Summoner's kit and three wards still
            --have room for their names.
            local perRow = math.min(count, 2)
            local rows = {}
            local sections = {}
            local parts = {}
            for i = 1, count do
                local part = {full = nil, shown = nil}
                part.head = Text{
                    classes = {"heroSheetCardStrong"},
                    text = "",
                    fontSize = 16,
                    bold = true,
                    halign = "left",
                }
                part.name = Text{
                    classes = {"heroSheetCardStrong"},
                    text = "",
                    fontSize = 15,
                    bold = true,
                    width = "100%",
                    textWrap = true,
                    tmargin = 6,
                }
                part.body = Text{
                    classes = {"heroSheetCardSub"},
                    text = "",
                    fontSize = 12.5,
                    width = "100%",
                    textWrap = true,
                    tmargin = 3,
                    linger = function(element)
                        if part.shown ~= part.full and part.full ~= nil then
                            gui.Tooltip(part.full)(element)
                        end
                    end,
                }
                parts[i] = part
                --a divider between a row's sections, centred in its gap; its
                --height is set to the row's tallest section once laid out.
                if (i - 1) % perRow ~= 0 then
                    sections[#sections+1] = gui.Panel{
                        classes = {"heroSheetDivider", "heroSheetKitDivider"},
                        bgimage = "panels/square.png",
                        width = 1,
                        height = 20,
                        hmargin = 11,
                        valign = "top",
                        interactable = false,
                    }
                end
                sections[#sections+1] = gui.Panel{
                    classes = {"heroSheetKitSection"},
                    width = string.format("%.2f%%-%d", 100 / perRow, cond(perRow > 1, 12, 0)),
                    height = "auto",
                    flow = "vertical",
                    valign = "top",
                    halign = "left",
                    part.head,
                    part.name,
                    part.body,
                }
                --a row is full, or this is the last section.
                if i % perRow == 0 or i == count then
                    rows[#rows+1] = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        tmargin = cond(#rows > 0, 12, 0),
                        children = sections,
                    }
                    sections = {}
                end
            end
            --pixels to units from a fixed-size probe: a divider this code resized
            --may not be redrawn yet, so it cannot be measured.
            local unitProbe = gui.Panel{
                floating = true,
                interactable = false,
                width = 1,
                height = 100,
            }
            rows[#rows+1] = unitProbe
            local holder = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = rows,
            }
            --each row's dividers take its tallest section's height once a
            --paint is laid out; only the newest pass applies.
            local fitGen = 0
            local function FitDividers()
                fitGen = fitGen + 1
                local gen = fitGen
                HeroSheetWindow.AfterLayout(function()
                    if mod.unloaded or gen ~= fitGen or not holder.valid then
                        return
                    end
                    --hidden (a minimized sheet): the next paint fits them.
                    local perUnit = unitProbe.renderedHeight / 100
                    if perUnit <= 0 then
                        return
                    end
                    for _, row in ipairs(holder.children) do
                        local tallest = 0
                        local dividers = {}
                        for _, child in ipairs(row.children) do
                            if child:HasClass("heroSheetKitSection") then
                                tallest = math.max(tallest, child.renderedHeight)
                            elseif child:HasClass("heroSheetKitDivider") then
                                dividers[#dividers+1] = child
                            end
                        end
                        if tallest > 0 then
                            for _, divider in ipairs(dividers) do
                                divider.selfStyle.height = math.floor(tallest / perUnit)
                            end
                        end
                    end
                end)
            end
            children[#children+1] = holder
            paintBody = function(kit, liveToken)
                for i, entry in ipairs(kit.entries) do
                    local part = parts[i]
                    if part ~= nil then
                        part.head.text = string.upper(entry.header or "")
                        part.name.text = entry.name or "None chosen"
                        part.name:SetClass("heroSheetCardStrong", entry.name ~= nil)
                        part.name:SetClass("heroSheetCardSub", entry.name == nil)
                        part.name.selfStyle.bold = entry.name ~= nil
                        local full = entry.text
                        local shown = full
                        if shown ~= nil and #shown > KIT_TEXT_FOLD_CHARS then
                            shown = (string.match(string.sub(shown, 1, KIT_TEXT_FOLD_CHARS), "^(.*)%s") or string.sub(shown, 1, KIT_TEXT_FOLD_CHARS)) .. "..."
                        end
                        part.full, part.shown = full, shown
                        part.body.text = shown or ""
                        part.body:SetClass("collapsed", full == nil or full == "")
                    end
                end
                FitDividers()
            end
        else
            --while the card is a summary (the Inventory tab at Medium), its
            --name shows the whole kit on hover.
            local summary = false
            local name = Text(HeroSheetTheme.HoverCard({
                classes = {"heroSheetCardStrong"},
                text = "",
                fontSize = 16.5,
                bold = true,
                width = "100%",
                textWrap = true,
                bgimage = "panels/square.png",
                bgcolor = "clear",
            }, function(pinned, close)
                if not summary then
                    return nil
                end
                local tok = HeroSheet.Token()
                if tok == nil then
                    return nil
                end
                return HeroSheetTheme.CardFrame(KitHoverCard(tok), pinned, close)
            end, false))
            local gearLine = Text{
                classes = {"heroSheetCardSub"},
                text = "",
                fontSize = 12.5,
                width = "100%",
                textWrap = true,
                --a small gap under the kit's name.
                tmargin = 4,
            }
            local cellRow = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                tmargin = 4,
            }
            local switchHolder = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
            }
            --- @type {panel: Panel, paint: fun(bonus: table)}[]
            local cells = {}
            --- @type {panel: Panel, paint: fun(pick: table)}[]
            local switches = {}
            children[#children+1] = name
            children[#children+1] = gearLine
            children[#children+1] = cellRow
            children[#children+1] = switchHolder
            paintBody = function(kit, liveToken)
                local first = kit.entries[1]
                name.text = first.name or ""
                local state = HeroSheet.State()
                summary = state ~= nil and state.tab == "Inventory" and HeroSheet.Tier() == "medium"
                kitSummary = summary
                cellRow:SetClass("collapsed", summary)
                switchHolder:SetClass("collapsed", summary)
                local line = HeroSheetCard.KitGearText(first.gear)
                gearLine.text = line
                gearLine:SetClass("collapsed", line == "" or summary)
                --the bonuses, two to a row (one at Medium); damage both
                --kits give goes to the switch below instead.
                local picks = DamagePicks(liveToken.properties)
                local picked = {}
                for _, pick in ipairs(picks) do
                    picked[pick.label] = true
                end
                local shown = 0
                for _, bonus in ipairs(first.bonuses or {}) do
                    if not picked[bonus.label] then
                        shown = shown + 1
                        local cell = cells[shown]
                        if cell == nil then
                            cell = KitBonus(HeroSheet.Tier() == "wide")
                            cells[shown] = cell
                            cellRow:AddChild(cell.panel)
                        end
                        cell.panel:SetClass("collapsed", false)
                        cell.paint(bonus)
                    end
                end
                for i = shown + 1, #cells do
                    cells[i].panel:SetClass("collapsed", true)
                end
                for i, pick in ipairs(picks) do
                    local switch = switches[i]
                    if switch == nil then
                        switch = DamageSwitch()
                        switches[i] = switch
                        switchHolder:AddChild(switch.panel)
                    end
                    switch.panel:SetClass("collapsed", false)
                    switch.paint(pick)
                end
                for i = #picks + 1, #switches do
                    switches[i].panel:SetClass("collapsed", true)
                end
            end
        end
        panel.children = children

        return function(liveToken)
            local liveRead = Data(liveToken)
            if liveRead == nil or liveRead.kit == nil then
                return
            end
            local kit = liveRead.kit
            local first = kit.entries[1]
            local equivalent = kit.kind == "equivalent"
            local state = HeroSheet.State()
            local editing = state ~= nil and state.editing == true and HeroSheetWrite.CanWrite()
            headerText.text = cond(equivalent, "", string.upper(first ~= nil and first.header or "Kit"))
            changeButton:SetClass("collapsed", not editing)
            headerRow:SetClass("collapsed", equivalent and not editing)
            paintBody(kit, liveToken)
            --the Treasures block below fills what the kit card leaves.
            if args.columnChanged ~= nil then
                args.columnChanged()
            end
        end
    end

    --Edit mode as last painted (opening a tab ends it even when it was off).
    local kitEditing = (HeroSheet.State() or {}).editing == true
    return HeroSheetRefresh.KeptBlock({
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 12,
        hpad = 16,
        borderBox = true,
        tmargin = 12,
        valign = "top",
        heroSheetTier = function(element, newTier)
            element:FireEventTree("heroSheetKitColumns", newTier == "wide")
            element:FireEvent("heroSheetRepaint")
        end,
        --the Inventory tab at Medium shows the kit as a summary: repaint
        --only when that flips, since every other tab shows the same card.
        heroSheetTab = function(element, tabid)
            local wantSummary = tabid == "Inventory" and HeroSheet.Tier() == "medium"
            if wantSummary ~= kitSummary then
                element:FireEvent("heroSheetRepaint")
            end
        end,
        heroSheetEdit = function(element, editing)
            if editing ~= kitEditing then
                kitEditing = editing
                element:FireEvent("heroSheetRepaint")
            end
        end,
    }, {
        name = "kit card",
        signature = function(token)
            local hero = token.properties
            local levelChoices = hero:GetLevelChoices() or {}
            local state = HeroSheet.State()
            return table.concat({
                tostring(hero:try_get("kitid")), tostring(hero:try_get("kitid2")),
                tostring(hero:CharacterLevel()),
                tostring(state ~= nil and state.editing == true),
                --kit equivalents are choices, so any choice can change them.
                dmhub.ToJson(levelChoices),
            }, "|")
        end,
        shape = function(token)
            local read = Data(token)
            local kit = read ~= nil and read.kit or nil
            if kit == nil then
                return "none read"
            end
            return string.format("%s|%d", tostring(kit.kind), cond(kit.kind == "equivalent", #kit.entries, 0))
        end,
        build = Build,
    })
end

----------------------------------------------------------------------
--Treasures: what the Hero carries, grouped Leveled treasures / Trinkets /
--Consumables, each row with its state and Equip or Unequip. Items that are
--not treasures (ancestry items, mundane gear) stay on the Inventory tab. A
--consumable's Use goes through the Inventory tab's cast.

--The Treasures block is never shorter than this (blocks keep their height;
--the column scrolls instead).
HeroSheetCard.TREASURES_MIN_HEIGHT = 240

--The kind line under an item's name on its hover card.
local ITEM_KIND_NAMES = {
    leveled = "Leveled treasure",
    trinket = "Trinket",
    consumable = "Consumable",
}

--A leveled treasure's Level texts, in the book's order, and the item field
--each is stored in.
local ITEM_TIERS = {
    {level = 1, name = "1st Level", field = "description"},
    {level = 5, name = "5th Level", field = "level5"},
    {level = 9, name = "9th Level", field = "level9"},
}

--The item image's size on its hover card, in sheet units.
local ITEM_CARD_ICON = 44

--What a row and its hover card say about an item's state.
--- @param it table one of the reader's treasures
--- @return string
local function ItemState(it)
    if it.kind == "consumable" then
        return string.format("%d carried", it.quantity or 1)
    elseif not it.equippable then
        return "Carried"
    end
    return cond(it.equipped, "Equipped", "Not equipped")
end

--An item's hover card: its image, the name and its state,
--the kind and keywords, then each Level text the Hero has reached (a leveled
--treasure) or the item's text, and why it gives no benefit, if it does not.
--- @param it table one of the reader's treasures
--- @param level number the Hero's Level
--- @param noBenefit nil|string the No benefit reason's text
--- @param pinned boolean pinned cards carry an x at the top right
--- @return Panel
local function ItemCard(it, level, noBenefit, pinned)
    local item = it.item
    local keywords = table.mapped_keys(item:try_get("keywords", {}), ActivatedAbility.CanonicalKeyword)
    table.sort(keywords)
    local kind = ITEM_KIND_NAMES[it.kind] or "Item"
    if #keywords > 0 then
        kind = kind .. " \u{00B7} " .. table.concat(keywords, ", ")
    end
    local stateClass = cond(it.equipped or it.kind == "consumable", "heroSheetCardSuccess", "heroSheetCardSub")
    --the item's image beside its name, as the Inventory's rows draw it.
    --the Inventory tab is another mod: looked up when used.
    local icon = rawget(_G, "HeroSheetInventory").Icon(ITEM_CARD_ICON)
    icon.paint(it)
    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            icon.panel,
            gui.Panel{
                width = string.format("100%%-%d", ITEM_CARD_ICON + 10),
                height = "auto",
                flow = "vertical",
                lmargin = 10,
                valign = "center",
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    Text{
                        classes = {"heroSheetCardStrong"},
                        text = it.name,
                        width = "100%-100",
                        fontSize = 15,
                        bold = true,
                        textWrap = true,
                        halign = "left",
                    },
                    Text{
                        classes = {stateClass},
                        --Equipped / Carried: a card says whether it is worn; a party
                        --stash item belongs to no one, so says neither.
                        text = cond(it.stash == true, "", cond(it.kind ~= "consumable" and it.equippable and not it.equipped, "Carried", ItemState(it))),
                        fontSize = 11.5,
                        halign = "right",
                        valign = "top",
                        tmargin = 2,
                        --clear of a pinned card's x.
                        rmargin = cond(pinned, 30, 0),
                    },
                },
                Text{
                    classes = {"heroSheetCardLabel"},
                    text = kind,
                    width = "100%",
                    fontSize = 12,
                    textWrap = true,
                    tmargin = 1,
                },
            },
        },
    }
    local function Body(text)
        children[#children+1] = Text{
            classes = {"heroSheetCardText"},
            text = text,
            markdown = true,
            width = "100%",
            fontSize = 13,
            textWrap = true,
            tmargin = 4,
        }
    end
    if it.kind == "leveled" then
        for _, tier in ipairs(ITEM_TIERS) do
            local text = item:try_get(tier.field)
            if level >= tier.level and type(text) == "string" and text ~= "" then
                children[#children+1] = Text{
                    classes = {"heroSheetCardLabel"},
                    text = string.upper(tier.name),
                    fontSize = 10.5,
                    bold = true,
                    tmargin = 8,
                }
                Body(text)
            end
        end
    else
        local text = item:try_get("description")
        if type(text) == "string" and text ~= "" then
            Body(text)
        end
    end
    if noBenefit ~= nil then
        children[#children+1] = Text{
            classes = {"heroSheetCardWarning"},
            text = noBenefit,
            width = "100%",
            fontSize = 13,
            textWrap = true,
            tmargin = 8,
        }
    end
    return gui.Panel{
        width = HeroSheetTheme.CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

--- An item's hover card, for the Inventory tab's rows too.
HeroSheetCard.ItemCard = ItemCard

--About one character's width at the pill's 12-point bold, in sheet units.
local PILL_CHAR_WIDTH = 5.6

--A small rounded count beside a heading ("2 of 3 carried", "6 carried").
--Its text, warning colour and hover are painted in by its ItemGroup.
--- @return Panel
local function Pill()
    return gui.Label{
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
        textAlignment = "center",
        data = {},
        linger = function(element)
            if element.data.tooltip ~= nil then
                gui.Tooltip(element.data.tooltip)(element)
            end
        end,
    }
end

--One item row, kept: the name (its hover card, pinned on click), then the
--state, the No benefit warning or the count, and Equip / Unequip. Built
--once; paint shows an item in it and hide clears it away.
--- @return {panel: Panel, paint: fun(it: table, context: table), hide: fun()}
local function ItemRow()
    --the item shown and what was worked out for it, for the handlers.
    local cur = {it = nil, context = nil, noBenefit = nil, busy = false}
    local qty = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 13,
        bold = true,
        valign = "center",
        rmargin = 8,
    }
    local state = Text{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 12,
        valign = "center",
        rmargin = 6,
    }
    --the kit cannot use this gear: the warning takes the state's place,
    --the reason on hover.
    local warning = Text{
        classes = {"heroSheetCardWarning"},
        text = "No benefit",
        fontSize = 12,
        valign = "center",
        rmargin = 6,
        linger = function(element)
            if cur.noBenefit ~= nil then
                gui.Tooltip(cur.noBenefit)(element)
            end
        end,
    }
    --Equip / Unequip, or Use on a consumable: equipping has no
    --cap, and Use goes through the cast.
    local button = gui.Label{
        classes = {"heroSheetSmallButton", "hoverable", "heroSheetOn"},
        text = "Equip",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 26,
        hpad = 9,
        borderBox = true,
        fontSize = 12.5,
        textWrap = false,
        valign = "center",
        textAlignment = "center",
        click = function(element)
            local it = cur.it
            --one action per button until the Hero's change paints the row.
            if it == nil or cur.busy then
                return
            end
            cur.busy = true
            if it.kind == "consumable" then
                cur.busy = false
                if not rawget(_G, "HeroSheetInventory").Use(it.itemid) then
                    audio.FireSoundEvent("UI.Error_Generic")
                end
            elseif it.equipped then
                --a refused save (view only) plays its own error sound.
                if HeroSheetWrite.Unequip(it.slot) then
                    audio.FireSoundEvent("UI.Inv_Grab")
                else
                    cur.busy = false
                end
            elseif HeroSheetWrite.Equip(it.itemid) then
                audio.FireSoundEvent("UI.Inv_Place")
            else
                cur.busy = false
                audio.FireSoundEvent("UI.Error_Generic")
            end
        end,
    }
    local name = Text(HeroSheetTheme.HoverCard({
        classes = {"heroSheetCardText"},
        text = "",
        width = "auto",
        maxWidth = "100%-16",
        height = "100%",
        halign = "left",
        fontSize = 13.5,
        textWrap = false,
        textOverflow = "ellipsis",
        valign = "center",
    }, function(pinned, close)
        return HeroSheetTheme.CardFrame(ItemCard(cur.it, cur.context.level, cur.noBenefit, pinned), pinned, close)
    end))
    local panel = gui.Panel{
        classes = {"heroSheetItemRow"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "100%",
        height = 31,
        flow = "horizontal",
        lpad = 10,
        rpad = 3,
        borderBox = true,
        tmargin = 4,
        name,
        gui.Panel{
            width = "auto",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            qty,
            state,
            warning,
            button,
        },
    }

    --- @param it table one of the reader's treasures
    --- @param context {token: CharacterToken, level: number, kit: {read: boolean, gear: nil|table}, write: boolean}
    local function Paint(it, context)
        local previous = cur.it
        cur.it, cur.context, cur.busy = it, context, false
        local noBenefit = nil
        if context.kit.read then
            pcall(function()
                local reason = EotwHeroSheet.NoBenefitReason(it.item:try_get("keywords", {}), context.kit.gear)
                if reason ~= nil then
                    noBenefit = EotwHeroSheet.NoBenefitText(reason, context.kit.gear)
                end
            end)
        end
        cur.noBenefit = noBenefit
        local consumable = it.kind == "consumable"
        local many = (it.quantity or 1) > 1
        --about how wide the right side is, from its texts: the name takes the
        --rest (never "100% available", which the engine restyles every frame).
        local rightWidth = 0
        qty:SetClass("collapsed", not many)
        if many then
            qty.text = string.format("x%d", it.quantity)
            qty.selfStyle.rmargin = cond(consumable, 4, 8)
            rightWidth = rightWidth + HeroSheetTheme.TextWidth(qty.text, 13) + 8
        end
        state:SetClass("collapsed", consumable or noBenefit ~= nil)
        warning:SetClass("collapsed", consumable or noBenefit == nil)
        if not consumable then
            rightWidth = rightWidth + HeroSheetTheme.TextWidth(cond(noBenefit ~= nil, "No benefit", ItemState(it)), 12) + 6
            state.text = ItemState(it)
            state:SetClass("heroSheetCardSuccess", it.equipped == true)
            state:SetClass("heroSheetCardSub", it.equipped ~= true)
        end
        local usable = consumable and type(it.item:try_get("consumable")) == "table"
        local showButton = context.write and (usable or (not consumable and it.equippable == true))
        button:SetClass("collapsed", not showButton)
        if showButton then
            button.text = cond(consumable, "Use", cond(it.equipped, "Unequip", "Equip"))
            button:SetClass("heroSheetOff", false)
            button:SetClass("heroSheetOn", true)
            rightWidth = rightWidth + HeroSheetTheme.TextWidth(button.text, 12.5) + 20
        end
        name.text = it.name
        name.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(rightWidth) + 16)
        --a card for another item closes; one pinned for this item opens
        --again, so it shows the item's new state.
        local same = previous ~= nil and previous.itemid == it.itemid
        if not same then
            name.tooltip = nil
        end
        if name.popup ~= nil then
            name.popup = nil
            if same then
                name:FireEvent("click")
            end
        end
        panel:SetClass("collapsed", false)
    end

    local function Hide()
        cur.it = nil
        name.tooltip = nil
        if name.popup ~= nil then
            name.popup = nil
        end
        panel:SetClass("collapsed", true)
    end

    return {panel = panel, paint = Paint, hide = Hide}
end

--One group of items under its heading, kept with a pool of rows that only
--grows (unused rows collapse). The Leveled group's heading has the carried
--count at its right.
--- @param title string
--- @param withPill boolean
--- @return {panel: Panel, paint: fun(items: table[], context: table, top: boolean, pill: nil|{text: string, warn: boolean, tooltip: nil|string})}
local function ItemGroup(title, withPill)
    --- @type nil|Panel
    local pill = nil
    local label
    if withPill then
        pill = Pill()
        label = Text{
            classes = {"heroSheetCardLabel"},
            text = string.upper(title),
            fontSize = 11,
            bold = true,
            width = "100%-60",
            textWrap = true,
            halign = "left",
            valign = "center",
        }
    else
        --a small upper-case label, as on the kit card.
        label = Text{
            classes = {"heroSheetCardLabel"},
            text = string.upper(title),
            fontSize = 11,
            bold = true,
            halign = "left",
            valign = "center",
        }
    end
    local heading
    --A long pill leaves the heading what is left of the row, and the heading
    --wraps (a two-line "Leveled / treasures"). The room is a
    --guess from the pill's text until the row has laid out, then measured,
    --and again whenever the window re-flows (a resize or a tier change).
    local function Measure()
        if pill == nil or pill:HasClass("collapsed") then
            return
        end
        dmhub.Schedule(0.05, function()
            if mod.unloaded or not heading.valid or not pill.valid or pill.renderedHeight <= 0 then
                return
            end
            --screen pixels per sheet unit, from the pill's fixed height.
            local perUnit = pill.renderedHeight / 18
            local room = math.floor((heading.renderedWidth - pill.renderedWidth) / perUnit) - 8
            label.selfStyle.width = math.max(40, room)
        end)
    end
    heading = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 9,
        heroSheetLayout = function(element)
            Measure()
        end,
        label,
        pill,
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
        heading,
        holder,
    }
    --- @type {panel: Panel, paint: fun(it: table, context: table), hide: fun()}[]
    local rows = {}
    return {
        panel = panel,
        paint = function(items, context, top, pillInfo)
            panel:SetClass("collapsed", #items == 0)
            heading.selfStyle.tmargin = cond(top, 4, 9)
            if pill ~= nil then
                pill:SetClass("collapsed", pillInfo == nil)
                if pillInfo ~= nil then
                    pill.text = pillInfo.text
                    --in @warning past three carried.
                    pill:SetClass("heroSheetPillWarn", pillInfo.warn)
                    pill.data.tooltip = pillInfo.tooltip
                    --a guess at the pill's width plus its padding and gap, until
                    --Measure reads it.
                    label.selfStyle.width = string.format("100%%-%d", math.ceil(#pillInfo.text * PILL_CHAR_WIDTH) + 24)
                    Measure()
                else
                    label.selfStyle.width = "100%"
                end
            end
            for i, it in ipairs(items) do
                local row = rows[i]
                if row == nil then
                    row = ItemRow()
                    rows[i] = row
                    holder:AddChild(row.panel)
                end
                row.paint(it, context)
            end
            for i = #items + 1, #rows do
                rows[i].hide()
            end
        end,
    }
end

--- The Treasures block for the card column. Its height is set by the
--- column (HeroSheet.lua): what the card and kit leave, never under
--- HeroSheetCard.TREASURES_MIN_HEIGHT; the list scrolls inside it.
--- @param args HeroSheetCardArgs
--- @return Panel
function HeroSheetCard.Treasures(args)
    --the item count and Open Inventory sit on the header row, so a long list
    --cannot scroll them out of view.
    local countLabel = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "",
        fontSize = 12.5,
        lmargin = 8,
        valign = "center",
        textWrap = false,
    }
    local openInventory = gui.Label{
        classes = {"heroSheetPlateButton", "hoverable"},
        text = "Open Inventory",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = 24,
        hpad = 10,
        borderBox = true,
        fontSize = 12,
        bold = true,
        textWrap = false,
        halign = "right",
        valign = "center",
        click = function(element)
            args.openInventory()
        end,
    }
    local header = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        Text{
            classes = {"heroSheetCardStrong"},
            text = "TREASURES",
            fontSize = 16,
            bold = true,
            halign = "left",
            valign = "center",
        },
        countLabel,
        openInventory,
    }
    --the groups, kept for every Hero (an empty one collapses).
    local leveled = ItemGroup("Leveled treasures", true)
    local trinketGroup = ItemGroup("Trinkets", false)
    local consumables = ItemGroup("Consumables", false)
    local empty = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "Nothing carried yet.",
        fontSize = 13,
        halign = "left",
        tmargin = 6,
    }
    --narrower than the list by the scrollbar's width, so nothing sits under it.
    local content = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        leveled.panel,
        trinketGroup.panel,
        consumables.panel,
        empty,
    }
    --what the 26-unit header leaves (never "100% available", which the
    --engine restyles every frame).
    local list = gui.Panel{
        width = "100%",
        height = "100%-28",
        flow = "vertical",
        vscroll = true,
        tmargin = 2,
        content,
    }

    return HeroSheetRefresh.Block({
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = HeroSheetCard.TREASURES_MIN_HEIGHT,
        flow = "vertical",
        vpad = 12,
        hpad = 16,
        borderBox = true,
        tmargin = 12,
        valign = "top",
        header,
        list,
    }, {
        name = "treasures",
        signature = function(token)
            local hero = token.properties
            return table.concat({
                dmhub.ToJson(hero:Equipment()),
                dmhub.ToJson(hero:try_get("inventory", {})),
                tostring(hero:CharacterLevel()),
                --the kit decides No benefit.
                tostring(hero:try_get("kitid")), tostring(hero:try_get("kitid2")),
                dmhub.ToJson(hero:GetLevelChoices() or {}),
                tostring(HeroSheetWrite.CanWrite()),
            }, "|")
        end,
        refresh = function(panel, token)
            local read = Data(token)
            local treasures = read ~= nil and read.treasures or nil
            local write = HeroSheetWrite.CanWrite()
            openInventory:SetClass("collapsed", not write)
            local level = 1
            pcall(function() level = token.properties:CharacterLevel() end)
            --nothing is claimed when the kit could not be read.
            local kit = {read = read ~= nil and read.kit ~= nil, gear = read ~= nil and read.kitGear or nil}
            local context = {token = token, level = level, kit = kit, write = write}

            --trinkets as the reader lists them, less the items that are not
            --treasures (it puts those with the trinkets).
            local trinkets = {}
            local leveledItems = {}
            local consumableItems = {}
            if treasures ~= nil then
                leveledItems = treasures.leveled
                consumableItems = treasures.consumables
                for _, it in ipairs(treasures.trinkets) do
                    if it.kind ~= "other" then
                        trinkets[#trinkets+1] = it
                    end
                end
            end
            local listed = #leveledItems + #trinkets + #consumableItems
            --carry three counts treasures, so a stack counts each one.
            local carried = 0
            for _, it in ipairs(leveledItems) do
                carried = carried + (it.quantity or 1)
            end

            countLabel.text = string.format("%d %s", listed, cond(listed == 1, "item", "items"))
            countLabel:SetClass("collapsed", listed == 0)

            --past three, the count alone in @warning; the hover says why.
            local pillInfo = nil
            if carried > 3 then
                pillInfo = {text = string.format("%d carried", carried), warn = true,
                    tooltip = "Carrying more than three leveled treasures means a Presence test each respite."}
            elseif carried > 0 then
                pillInfo = {text = string.format("%d of 3 carried", carried), warn = false}
            end
            --the first group shown sits closer to the header.
            leveled.paint(leveledItems, context, true, pillInfo)
            trinketGroup.paint(trinkets, context, #leveledItems == 0, nil)
            consumables.paint(consumableItems, context, #leveledItems + #trinkets == 0, nil)
            empty:SetClass("collapsed", treasures == nil or listed > 0)
        end,
    })
end

----------------------------------------------------------------------
--The card.

--- The Hero's card for the card column.
--- @param args HeroSheetCardArgs
--- @return Panel
function HeroSheetCard.Create(args)
    --"Change appearance" on the card's hover, for those who may edit.
    local appearance = gui.Label{
        classes = {"heroSheetCardAppear", "hoverable"},
        text = "Change appearance",
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "100%-20",
        height = 30,
        halign = "center",
        valign = "top",
        tmargin = 10,
        --over the art in every tier, never in the banner's row.
        floating = true,
        fontSize = 14,
        bold = true,
        textAlignment = "center",
        click = function(element)
            args.openAppearance()
        end,
    }

    local plate = gui.Panel{
        classes = {"heroSheetCardPlate"},
        bgimage = "panels/square.png",
        cornerRadius = 8,
        width = "100%-20",
        height = "auto",
        halign = "center",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        Identity(args),
        Progress(args),
        Stamina(),
        --a faint rule above Recoveries, Victories and the resource.
        gui.Panel{
            classes = {"heroSheetCardRule"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            tmargin = 8,
        },
        Counters(),
    }

    local art = Art()
    --the surges over the art's foot, with the plate under them at Wide and
    --Medium; at Narrow the plate moves to the banner's right.
    local foot = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "bottom",
        bmargin = 10,
        Surges(),
        plate,
    }
    local side = gui.Panel{
        classes = {"collapsed"},
        width = string.format("100%%-%d", BANNER_ART_WIDTH),
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        vpad = 8,
        borderBox = true,
    }

    --The banner is as tall as the plate beside the art. The art is a floating
    --layer, so the frame's height is set from the plate's, measured after
    --layout (sheet units: the art is a known width).
    local bannerHeight = nil
    --- @param element Panel the card's frame
    local function FitBanner(element)
        if art.renderedWidth <= 0 or side.renderedHeight <= 0 then
            return
        end
        local perUnit = art.renderedWidth / BANNER_ART_WIDTH
        local height = math.ceil(side.renderedHeight / perUnit)
        if height ~= bannerHeight then
            bannerHeight = height
            element.selfStyle.height = height
        end
    end

    --Arranges the card for a tier: the same parts, moved.
    --- @param element Panel the card's frame
    --- @param tier string
    local function Arrange(element, tier)
        local narrow = tier == "narrow"
        element.selfStyle.flow = cond(narrow, "horizontal", "none")
        if narrow then
            element.selfStyle.height = bannerHeight or 240
        else
            bannerHeight = nil
            element.selfStyle.height = CARD_HEIGHT[tier] or CARD_HEIGHT.wide
        end
        --the plate's height can change at any refresh (a title, the level
        --line): a cheap check a few times a second, at Narrow only.
        element.thinkTime = cond(narrow, 0.25, nil)
        art.selfStyle.width = cond(narrow, BANNER_ART_WIDTH, "100%")
        art.selfStyle.halign = "left"
        appearance.selfStyle.width = cond(narrow, BANNER_ART_WIDTH - 20, "100%-20")
        appearance.selfStyle.halign = cond(narrow, "left", "center")
        appearance.selfStyle.lmargin = cond(narrow, 10, 0)
        foot.selfStyle.width = cond(narrow, BANNER_ART_WIDTH, "100%")
        foot.selfStyle.halign = "left"
        side:SetClass("collapsed", not narrow)
        local into = cond(narrow, side, foot)
        if plate.parent ~= into then
            --leave first: a panel added elsewhere stays listed in both.
            plate:Unparent()
            into:AddChild(plate)
        end
        plate.selfStyle.width = cond(narrow, "100%-10", "100%-20")
        plate.selfStyle.halign = cond(narrow, "left", "center")
    end

    return gui.Panel{
        classes = {"heroSheetCardFrame"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = CARD_HEIGHT.wide,
        valign = "top",
        flow = "none",
        heroSheetTier = function(element, tier)
            Arrange(element, tier)
        end,
        create = function(element)
            appearance:SetClass("collapsed", not HeroSheetWrite.CanWrite())
            Arrange(element, HeroSheet.Tier())
        end,
        think = function(element)
            FitBanner(element)
        end,
        art,
        appearance,
        foot,
        side,
    }
end

----------------------------------------------------------------------
--The Builder's live card: the Hero as the build makes them, alone in the
--Builder's left column and as tall as it. Read only, and without Victories
--or the heroic resource (session values, 0 while building); the kit numbers
--sit two across.

--The kit numbers in pairs, left then right.
local BUILDER_KIT_ROWS = {
    {"Speed", "Disengage"},
    {"Stability", "Distance"},
    {"Melee", "Ranged"},
}

--- The Builder card's numbers for a Hero, by label ("-" when a kit gives none).
--- @param read table the shared read
--- @return table<string, string>
local function BuilderKitNumbers(read)
    local byLabel = {}
    for _, entry in ipairs((read.kit or {}).entries or {}) do
        for _, bonus in ipairs(entry.bonuses or {}) do
            byLabel[bonus.label] = bonus.value
        end
    end
    local stats = read.stats or {}
    local function Stat(id)
        local stat = stats[id]
        return stat ~= nil and tostring(stat.value) or "-"
    end
    return {
        Speed = Stat("speed"),
        Disengage = Stat("disengage"),
        Stability = Stat("stability"),
        --a kit's reach: its ranged distance, else its melee distance.
        Distance = byLabel["Ranged distance"] or byLabel["Melee distance"] or "-",
        Melee = byLabel["Melee damage"] or "-",
        Ranged = byLabel["Ranged damage"] or "-",
    }
end

--- @class HeroSheetCardNumbers
--- @field kit table<string, string> the kit numbers by label, as BuilderKitNumbers gives them
--- @field stamina number the Stamina maximum
--- @field renown number
--- @field wealth number
--- @field resist table<string, number> immunities and weaknesses by name ("Cold immunity"), their value

--- A kit's distance and damage numbers, worked out as the shared read's kit
--- section does: one kit's, or for two kits the selected damage and the
--- higher distance.
--- @param hero creature
--- @return table<string, string> by bonus label ("Melee damage")
local function KitBonusValues(hero)
    local result = {}
    local eotw = rawget(_G, "EotwHeroSheet")
    local can = false
    pcall(function() can = hero:CanHaveKits() end)
    if eotw == nil or eotw.KitBonuses == nil or not can then
        return result
    end
    local kits = dmhub.GetTable(Kit.tableName) or {}
    local echelon = hero:Echelon()
    local kit1 = kits[hero:try_get("kitid") or ""]
    local kit2 = nil
    if hero:GetNumberOfKits() > 1 then
        kit2 = kits[hero:try_get("kitid2") or ""]
    end
    --- @param kit nil|Kit
    --- @return table<string, string>
    local function Bonuses(kit)
        local map = {}
        if kit ~= nil then
            for _, bonus in ipairs(eotw.KitBonuses(kit, echelon)) do
                map[bonus.label] = bonus.value
            end
        end
        return map
    end
    local bonuses1, bonuses2 = Bonuses(kit1), Bonuses(kit2)
    for _, label in ipairs({"Melee distance", "Ranged distance", "Melee damage", "Ranged damage"}) do
        local value1, value2 = bonuses1[label], bonuses2[label]
        local first = value2 == nil
        if not first and value1 ~= nil and kit1 ~= nil and kit2 ~= nil then
            if label == "Melee damage" or label == "Ranged damage" then
                first = Kit.DamageBonusSelected(hero, cond(label == "Melee damage", "melee", "ranged"), kit1, kit2)
            else
                first = (tonumber(value1) or 0) >= (tonumber(value2) or 0)
            end
        end
        if first then
            result[label] = value1
        else
            result[label] = value2
        end
    end
    return result
end

--- The Builder card's numbers read straight from a Hero's properties, not
--- from the shared read: a preview reads them from a copy of the Hero
--- with the hovered pick made, and compares them with the live Hero's.
--- @param hero creature
--- @return HeroSheetCardNumbers
function HeroSheetCard.BuilderNumbers(hero)
    local function Read(fn, fallback)
        local ok, value = pcall(fn)
        if ok and value ~= nil then
            return value
        end
        return fallback
    end
    local bonus = Read(function() return KitBonusValues(hero) end, {})
    local disengage = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
    local numbers = {
        kit = {
            Speed = tostring(Read(function() return hero:WalkingSpeed() end, "-")),
            Disengage = tostring(Read(function() return disengage ~= nil and hero:GetCustomAttribute(disengage) or nil end, "-")),
            Stability = tostring(Read(function() return hero:Stability() end, "-")),
            Distance = bonus["Ranged distance"] or bonus["Melee distance"] or "-",
            Melee = bonus["Melee damage"] or "-",
            Ranged = bonus["Ranged damage"] or "-",
        },
        stamina = tonumber(Read(function() return hero:MaxHitpoints() end, 0)) or 0,
        renown = tonumber(Read(function() return hero:CalculateNamedCustomAttribute("Renown") end, 0)) or 0,
        wealth = tonumber(Read(function() return hero:CalculateNamedCustomAttribute("Wealth") end, 0)) or 0,
        resist = {},
    }
    --immunity and weakness by damage type; the strongest of each counts.
    pcall(function()
        for _, resistance in ipairs(hero:ResistanceEntries()) do
            local dr = resistance.entry:try_get("dr", 0)
            local name = TacPanel.CleanResistanceText(resistance.text)
            name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
            local key = string.format("%s %s", name, cond(dr < 0, "weakness", "immunity"))
            numbers.resist[key] = math.max(numbers.resist[key] or 0, math.abs(dr))
        end
    end)
    return numbers
end

--- @class HeroSheetCardPreview
--- @field kit table<string, {value: string, better: boolean}> the kit numbers a pick changes, by label
--- @field stamina nil|{max: number, better: boolean} the Stamina maximum, when it changes
--- @field also {text: string, better: boolean}[] the "Also changes" line's items
--- @field level nil|integer the Level the class line names (a manual Level up's)

--- The total of the numbers in a value ("+0/+0/+4" is 4; "-" is 0), to say
--- whether a change is better.
--- @param value string
--- @return number
local function NumberSum(value)
    local sum = 0
    for number in string.gmatch(value or "", "[-+]?%d+") do
        sum = sum + (tonumber(number) or 0)
    end
    return sum
end

--- What a pick would change on the Builder's card: the numbers that differ,
--- and the "Also changes" items, each a signed change with a mark saying
--- whether it is better for the Hero. nil when the pick changes nothing the
--- card shows.
--- @param before HeroSheetCardNumbers
--- @param after HeroSheetCardNumbers
--- @return nil|HeroSheetCardPreview
function HeroSheetCard.BuilderPreview(before, after)
    local preview = {kit = {}, stamina = nil, also = {}}
    local any = false
    for label, value in pairs(after.kit) do
        if value ~= before.kit[label] then
            preview.kit[label] = {value = value, better = NumberSum(value) >= NumberSum(before.kit[label] or "-")}
            any = true
        end
    end
    if after.stamina ~= before.stamina then
        preview.stamina = {max = after.stamina, better = after.stamina > before.stamina}
        any = true
    end
    --- @param name string
    --- @param change number
    --- @param better boolean
    local function Also(name, change, better)
        if change ~= 0 then
            preview.also[#preview.also+1] = {text = string.format("%s %s%d", name, cond(change > 0, "+", "-"), math.abs(change)), better = better}
            any = true
        end
    end
    Also("Renown", after.renown - before.renown, after.renown > before.renown)
    Also("Wealth", after.wealth - before.wealth, after.wealth > before.wealth)
    local names = {}
    for name in pairs(before.resist) do
        names[#names+1] = name
    end
    for name in pairs(after.resist) do
        if before.resist[name] == nil then
            names[#names+1] = name
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local change = (after.resist[name] or 0) - (before.resist[name] or 0)
        --more immunity is better; more weakness is worse.
        local weakness = string.find(name, " weakness$") ~= nil
        Also(name, change, cond(weakness, change < 0, change > 0))
    end
    if not any then
        return nil
    end
    return preview
end

--- A mark a preview puts beside a changed number: a caret up for
--- better in @success, down for worse in @danger, 12 units (the card's font
--- has no triangles). Collapsed until SetMark shows it.
--- @return Panel
local function Mark()
    return gui.Panel{
        classes = {"collapsed"},
        bgimage = "phosphor/caret-down-fill.png",
        width = 12,
        height = 12,
        valign = "center",
        lmargin = 2,
        interactable = false,
    }
end

--- @param mark Panel from Mark
--- @param better boolean
local function SetMark(mark, better)
    local palette = HeroSheetTheme.Palette()
    mark.selfStyle.bgcolor = cond(better, palette.success, palette.danger)
    mark.selfStyle.rotate = cond(better, 180, 0)
    mark:SetClass("collapsed", false)
end

--the Inventory pane's equip chips use the same marks.
HeroSheetCard.Mark = Mark
HeroSheetCard.SetMark = SetMark

--- The Builder's card. Built once; every change paints values into it.
--- Its panel's data.preview(spec) shows what a hovered option would change
--- and data.preview(nil) shows the Hero as they are again.
--- @param block nil|fun(panelArgs: table, spec: HeroSheetBlockSpec): Panel how it repaints with the Hero (the Builder's host); nil for the Hero sheet's
--- @param heroToken nil|fun(): nil|CharacterToken the Hero it shows (the Builder's host); nil for the Hero sheet's
--- @return Panel
function HeroSheetCard.BuilderCard(block, heroToken)
    --the characteristics strip in the art's corner: "M +2" ...
    local charLetters = {}
    local charValues = {}
    local charRows = {}
    for i = 1, 5 do
        charLetters[i] = Text{classes = {"heroSheetCardSub"}, text = "", fontSize = 12.5, width = 14}
        charValues[i] = Text{classes = {"heroSheetCardStrong"}, text = "", fontSize = 12.5, bold = true, halign = "right"}
        charRows[i] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            charLetters[i],
            charValues[i],
        }
    end
    local strip = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#000000b8",
        cornerRadius = 6,
        floating = true,
        width = 48,
        height = "auto",
        halign = "right",
        valign = "top",
        tmargin = 10,
        rmargin = 10,
        hpad = 6,
        vpad = 4,
        borderBox = true,
        flow = "vertical",
        interactable = false,
        children = charRows,
    }

    local name = HeroSheetTheme.EllipsisLabel{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 28,
        bold = true,
        width = "100%",
        height = "auto",
    }
    local classLine = Text{text = "", width = "100%", fontSize = 14, tmargin = 2, textWrap = true}

    --Stamina, read only: the bar, then Dead at and Winded at.
    local fill = gui.Panel{
        classes = {"heroSheetHpFill"},
        bgimage = "panels/square.png",
        width = "100%",
        height = "100%",
        halign = "left",
        interactable = false,
        gui.Panel{
            classes = {"heroSheetHpSheen"},
            bgimage = "panels/square.png",
            width = "100%",
            height = "50%",
            valign = "top",
            interactable = false,
        },
    }
    local number = Text{classes = {"heroSheetHpNumber"}, text = "", fontSize = 13, bold = true, valign = "center"}
    local staminaMark = Mark()
    local bar = gui.Panel{
        classes = {"heroSheetHpBar"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 4,
        width = "100%",
        height = 22,
        tmargin = 10,
        interactable = false,
        gui.Panel{
            classes = {"heroSheetHpClip"},
            bgimage = "panels/square.png",
            clip = true,
            clipHidden = true,
            width = "100%-4",
            height = "100%-4",
            halign = "center",
            valign = "center",
            flow = "horizontal",
            fill,
        },
        --the number, with a preview's mark after it.
        gui.Panel{
            floating = true,
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "center",
            interactable = false,
            number,
            staminaMark,
        },
    }
    local deadAt = Text{classes = {"heroSheetCardStrong"}, text = "", fontSize = 13, bold = true}
    local windedAt = Text{classes = {"heroSheetCardStrong"}, text = "", fontSize = 13, bold = true}
    local staminaLine = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 4,
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            Text{classes = {"heroSheetCardSub"}, text = "Dead at", fontSize = 13, rmargin = 4},
            deadAt,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            Text{classes = {"heroSheetCardSub"}, text = "Winded at", fontSize = 13, rmargin = 4},
            windedAt,
        },
    }

    --the kit numbers, two across. Each value sits on a plate that lights for
    --a moment when a preview changes it, then its mark.
    --- @type table<string, Panel>
    local kitValues = {}
    --- @type table<string, Panel>
    local kitMarks = {}
    local kitRows = {}
    for _, pair in ipairs(BUILDER_KIT_ROWS) do
        local cells = {}
        for i, label in ipairs(pair) do
            kitValues[label] = Text{
                classes = {"heroSheetCardStrong"},
                bgimage = "panels/square.png",
                bgcolor = "clear",
                cornerRadius = 3,
                text = "",
                fontSize = 12.5,
                bold = true,
                hpad = 3,
                borderBox = true,
                halign = "right",
            }
            kitMarks[label] = Mark()
            cells[i] = gui.Panel{
                width = "50%-6",
                height = "auto",
                flow = "horizontal",
                halign = cond(i == 1, "left", "right"),
                Text{classes = {"heroSheetCardSub"}, text = label, fontSize = 12.5, halign = "left"},
                gui.Panel{width = "auto", height = "auto", flow = "horizontal", halign = "right", kitValues[label], kitMarks[label]},
            }
        end
        kitRows[#kitRows+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 1,
            children = cells,
        }
    end
    local kitGrid = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 8,
        children = kitRows,
    }

    --The "Also changes" line, under the kit numbers, only while a hovered
    --option changes Renown, Wealth, an immunity or a weakness. The label
    --leads the items on one line.
    local alsoItems = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        Text{classes = {"heroSheetCardLabel"}, text = "ALSO CHANGES", fontSize = 10.5, bold = true, halign = "left", valign = "center", rmargin = 10},
    }
    --- @type {panel: Panel, label: Label, mark: Panel}[]
    local alsoLabels = {}
    local alsoLine = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 6,
        gui.Panel{classes = {"heroSheetCardRule"}, bgimage = "panels/square.png", width = "100%", height = 1, bmargin = 4},
        alsoItems,
    }

    --Recoveries: the count in a ring, then how many and how much each.
    local recoveryCount = Text{classes = {"heroSheetCardStrong"}, text = "", fontSize = 18, bold = true, halign = "center", valign = "center"}
    local recoveryLine = Text{classes = {"heroSheetCardSub"}, text = "", fontSize = 12.5, halign = "left"}
    local recoveries = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 9,
        gui.Panel{
            classes = {"heroSheetRing2"},
            bgimage = "panels/square.png",
            border = 2,
            cornerRadius = 21,
            width = 42,
            height = 42,
            halign = "left",
            valign = "center",
            interactable = false,
            recoveryCount,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            lmargin = 10,
            Text{classes = {"heroSheetCardStrong"}, text = "Recoveries", fontSize = 14, bold = true, halign = "left"},
            recoveryLine,
        },
    }

    local plate = gui.Panel{
        classes = {"heroSheetCardPlate"},
        bgimage = "panels/square.png",
        cornerRadius = 8,
        width = "100%-20",
        height = "auto",
        halign = "center",
        valign = "bottom",
        bmargin = 10,
        flow = "vertical",
        hpad = 14,
        vpad = 12,
        borderBox = true,
        name,
        classLine,
        bar,
        staminaLine,
        gui.Panel{classes = {"heroSheetCardRule"}, bgimage = "panels/square.png", width = "100%", height = 1, tmargin = 8},
        kitGrid,
        alsoLine,
        gui.Panel{classes = {"heroSheetCardRule"}, bgimage = "panels/square.png", width = "100%", height = 1, tmargin = 8},
        recoveries,
    }

    --- @param token CharacterToken
    --- @return nil|table
    local function Values(token)
        local read = Data(token)
        if read == nil then
            return nil
        end
        local hero = token.properties
        local max = math.max(1, hero:MaxHitpoints())
        local line = string.format("Level %d %s %s", read.level or 1, HeroBuild.SaidName(read.ancestry), read.className or "")
        if read.subclass ~= nil and read.subclass ~= "" then
            line = line .. " \u{00B7} " .. read.subclass
        end
        local chars = {}
        for i, characteristic in ipairs(read.characteristics or {}) do
            local value = characteristic.value or 0
            chars[i] = {letter = string.sub(characteristic.name or "", 1, 1), value = cond(value >= 0, "+" .. tostring(value), tostring(value))}
        end
        return {
            name = token.name or "",
            classLine = trim((string.gsub(line, "%s+", " "))),
            cur = hero:CurrentHitpoints(),
            max = max,
            winded = math.floor(max / 2),
            chars = chars,
            kit = BuilderKitNumbers(read),
            recoveries = read.recoveries or {current = 0, max = 0, value = 0},
        }
    end

    --the Hero as they are, painted on every refresh; a preview paints over
    --it and putting it back repaints these.
    local live = nil

    --- @param values table from Values
    local function PaintLive(values)
        live = values
        name.text = values.name
        name:SetClass("collapsed", values.name == "")
        classLine.text = values.classLine
        for i = 1, 5 do
            local char = values.chars[i]
            charLetters[i].text = char ~= nil and char.letter or ""
            charValues[i].text = char ~= nil and char.value or ""
        end
        fill.selfStyle.width = string.format("%.2f%%", math.max(0, math.min(1, values.cur / values.max)) * 100)
        number.text = string.format("%d/%d", values.cur, values.max)
        deadAt.text = tostring(-values.winded)
        windedAt.text = tostring(values.winded)
        for label, value in pairs(values.kit) do
            kitValues[label].text = value
            kitMarks[label]:SetClass("collapsed", true)
        end
        alsoLine:SetClass("collapsed", true)
        staminaMark:SetClass("collapsed", true)
        recoveryCount.text = tostring(values.recoveries.current)
        recoveryLine.text = string.format("of %d \u{00B7} +%d each", values.recoveries.max, values.recoveries.value)
    end

    --A changed value's plate lights in the info colour and fades over about
    --a second.
    --- @param panel Panel
    local function Ping(panel)
        local gen = (panel.data.pingGen or 0) + 1
        panel.data.pingGen = gen
        local color = HeroSheetTheme.WithAlpha(HeroSheetTheme.Palette().rawInfo, 1)
        local steps = 9
        for i = 0, steps do
            dmhub.Schedule(i * 0.1, function()
                if mod.unloaded or not panel.valid or panel.data.pingGen ~= gen then
                    return
                end
                panel.selfStyle.bgcolor = HeroSheetTheme.ToHex(color, 0.35 * (1 - i / steps))
            end)
        end
    end

    --a manual Level up's standing preview: the next Level, shown in
    --place of the Hero as they are until it is cleared.
    --- @type nil|HeroSheetCardPreview
    local standing = nil

    --- Shows what a hovered option would change, or the Hero as they
    --- are again (nil: the standing preview, when there is one). Nothing
    --- here touches the Hero. quiet: the values do not ping.
    --- @param spec nil|HeroSheetCardPreview
    --- @param quiet nil|boolean
    local function Preview(spec, quiet)
        if live == nil then
            return
        end
        PaintLive(live)
        if spec == nil then
            spec = standing
            quiet = true
        end
        if spec == nil then
            return
        end
        if spec.level ~= nil then
            classLine.text = (string.gsub(live.classLine, "^Level %d+", "Level " .. tostring(spec.level)))
        end
        local palette = HeroSheetTheme.Palette()
        for label, change in pairs(spec.kit) do
            local value, mark = kitValues[label], kitMarks[label]
            if value ~= nil and mark ~= nil then
                value.text = change.value
                SetMark(mark, change.better)
                if not quiet then
                    Ping(value)
                end
            end
        end
        if spec.stamina ~= nil then
            local max = math.max(1, spec.stamina.max)
            local winded = math.floor(max / 2)
            fill.selfStyle.width = string.format("%.2f%%", math.max(0, math.min(1, live.cur / max)) * 100)
            number.text = string.format("%d/%d", live.cur, max)
            SetMark(staminaMark, spec.stamina.better)
            deadAt.text = tostring(-winded)
            windedAt.text = tostring(winded)
        end
        --each item a signed change, its mark after.
        for i, item in ipairs(spec.also) do
            local entry = alsoLabels[i]
            if entry == nil then
                local label = Text{classes = {"heroSheetCardSub"}, text = "", fontSize = 12.5}
                --Text builds a gui.Label; its annotation only says Panel.
                ---@cast label Label
                local mark = Mark()
                entry = {
                    panel = gui.Panel{width = "auto", height = "auto", flow = "horizontal", halign = "left", valign = "center", rmargin = 12, label, mark},
                    label = label,
                    mark = mark,
                }
                alsoLabels[i] = entry
                alsoItems:AddChild(entry.panel)
            end
            --the change in the strong colour after the muted name.
            local what, change = string.match(item.text, "^(.-) ([-+]%d+)$")
            entry.label.text = string.format("%s <b><color=%s>%s</color></b>", what or item.text, palette.cardStrong, change or "")
            SetMark(entry.mark, item.better)
            entry.panel:SetClass("collapsed", false)
        end
        for i = #spec.also + 1, #alsoLabels do
            alsoLabels[i].panel:SetClass("collapsed", true)
        end
        alsoLine:SetClass("collapsed", #spec.also == 0)
    end

    local panel = (block or HeroSheetRefresh.Block)({
        classes = {"heroSheetCardFrame"},
        bgimage = "panels/square.png",
        bgcolor = "#151515ff",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "100%",
        flow = "none",
        Art(true, block, heroToken),
        strip,
        plate,
    }, {
        name = "builder card",
        builder = true,
        signature = function(token)
            local values = Values(token)
            return values ~= nil and dmhub.ToJson(values) or "none"
        end,
        refresh = function(panel, token)
            local values = Values(token)
            if values ~= nil then
                PaintLive(values)
                if standing ~= nil then
                    Preview(standing, true)
                end
            end
        end,
    })
    panel.data.preview = Preview
    --- Set (or clear, nil) the standing preview and show it; it pings only
    --- when it changes.
    --- @param spec nil|HeroSheetCardPreview
    panel.data.stand = function(spec)
        local same = dmhub.ToJson(spec or {}) == dmhub.ToJson(standing or {})
        standing = spec
        Preview(spec, same)
    end
    return panel
end

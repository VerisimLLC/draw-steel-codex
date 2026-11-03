local mod = dmhub.GetModLoading()

--The Followers window: the Hero's followers on the left, each with Open
--sheet, Find on map (a retainer on the map) and a menu (Use another token...,
--Dismiss), beside the form that adds one on the right: a Retainer from the
--bestiary, an Artisan or a Sage built from an ancestry, or an Existing
--follower already in the party. A new follower joins the party beside the
--Hero and appears in the switcher; its sheet does not open. Opened from the
--switcher's "+".
--
--The follower link is the one the old character sheet uses: the Hero's
--followers table (charid -> true), written through the follower rules calls
--(CreateFollowerMonster, RemoveFollowerFromMentor), which save their own
--undo step.

HeroSheetWindows = rawget(_G, "HeroSheetWindows") or {}

local DOT = " \u{00B7} "

--The Followers window's design size: as wide as Titles, the same columns.
local WINDOW_WIDTH = 1040
local WINDOW_BODY = 600
--A window narrower than this (sheet units) stacks its columns.
local STACK_BELOW = 760

--The add form's types, shown as tiles two to a row.
local TYPES = {
    {id = "retainer", name = "Retainer", text = "Fights beside you. A creature with a stat block and its own token."},
    {id = "artisan", name = "Artisan", text = "Helps with crafting projects in downtime."},
    {id = "sage", name = "Sage", text = "Helps with research projects in downtime."},
    {id = "existing", name = "Existing", text = "A follower already in the party."},
}

--A change landed on the Hero (through the follower rules calls, which upload
--it themselves): the write layer counts it as sent, and the sheet redraws.
local function Saved()
    HeroSheetWrite.Rebaseline()
    HeroSheet.Saved()
end

--- @param text string
--- @param classes string[]
--- @param size number
--- @param args nil|table more label args
--- @return Panel
local function Line(text, classes, size, args)
    local fields = {
        classes = classes,
        text = text,
        fontSize = size,
        width = "100%",
        height = "auto",
        textWrap = true,
        interactable = false,
    }
    for field, value in pairs(args or {}) do
        fields[field] = value
    end
    return gui.Label(fields)
end

--A small caps heading, with an optional count at its right.
--- @param text string
--- @param count nil|string
--- @return Panel
local function Caps(text, count)
    local children = {
        gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(text),
            fontSize = 11.5,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
    }
    if count ~= nil then
        children[#children+1] = gui.Label{
            classes = {"heroSheetCardSub"},
            text = count,
            fontSize = 11.5,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            textWrap = false,
        }
    end
    return gui.Panel{
        width = "100%",
        height = 18,
        flow = "horizontal",
        bmargin = 8,
        children = children,
    }
end

--- @param text string
--- @param click fun(element: Panel)
--- @param args nil|table more panel args (classes are added to)
--- @return Panel
local function Button(text, click, args)
    local fields = {
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 10,
        borderBox = true,
        rmargin = 6,
        halign = "left",
        valign = "center",
        click = function(element)
            click(element)
        end,
        gui.Label{
            classes = {"heroSheetButtonLabel"},
            text = text,
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    for field, value in pairs(args or {}) do
        fields[field] = value
    end
    return gui.Panel(fields)
end

----------------------------------------------------------------------
--Reading followers.

--- @param tok CharacterToken
--- @return string "Retainer", "Artisan", "Sage" or ""
local function TypeName(tok)
    local followerType = tok.properties:try_get("followerType")
    if type(followerType) == "string" and followerType ~= "" then
        return string.upper_first(followerType)
    end
    return ""
end

--- True when the follower has a token on the map being looked at.
--- @param charid string
--- @return boolean
local function OnMap(charid)
    return dmhub.GetTokenById(charid) ~= nil
end

--A follower made from an ancestry has that ancestry as its first keyword.
--- @param props creature
--- @return nil|string
local function Ancestry(props)
    local keywords = props:try_get("keywords")
    if type(keywords) == "table" then
        for keyword, _ in pairs(keywords) do
            return keyword
        end
    end
    return nil
end

--What the follower is ("Kobold Shieldbearer retainer", "Human artisan") and
--what it does (an artisan's characteristics and skills).
--- @param tok CharacterToken
--- @return string what
--- @return string line
local function Describe(tok)
    local props = tok.properties
    local kind = string.lower(TypeName(tok))
    if kind == "retainer" then
        local what = props:try_get("monster_type") or tok.name or ""
        local line = ""
        if OnMap(tok.charid) then
            line = "On the map. Moves on your turn."
        end
        return string.format("%s retainer", what), line
    end
    local what = string.format("%s %s", Ancestry(props) or "", kind)
    local parts = {}
    local chars = {}
    pcall(function()
        for _, id in ipairs(creature.attributeIds) do
            local attribute = props:GetBaseAttribute(id)
            if attribute ~= nil and (attribute.baseValue or 0) > 0 then
                chars[#chars+1] = creature.attributesInfo[id].description
            end
        end
    end)
    if #chars > 0 then
        parts[#parts+1] = table.concat(chars, ", ") .. "."
    end
    local skills = {}
    for id, _ in pairs(props:try_get("skillRatings") or {}) do
        local skill = Skill.SkillsById[id]
        if skill ~= nil then
            skills[#skills+1] = skill.name
        end
    end
    table.sort(skills)
    if #skills > 0 then
        parts[#parts+1] = table.concat(skills, ", ") .. "."
    end
    if kind == "artisan" then
        parts[#parts+1] = "Helps with crafting projects."
    elseif kind == "sage" then
        parts[#parts+1] = "Helps with research projects."
    end
    return trim(what), table.concat(parts, " ")
end

--- The Hero's followers, by name.
--- @param mentor CharacterToken
--- @return CharacterToken[]
local function Followers(mentor)
    local result = {}
    pcall(function()
        for charid, _ in pairs(mentor.properties:try_get("followers") or {}) do
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.properties ~= nil then
                result[#result+1] = tok
            end
        end
    end)
    table.sort(result, function(left, right) return (left.name or "") < (right.name or "") end)
    return result
end

--- Followers in the party or an allied one (the old sheet's Token list) that
--- this Hero does not have yet, with where they are.
--- @param mentor CharacterToken
--- @return {token: CharacterToken, where: string}[]
local function Linkable(mentor)
    local mine = {}
    pcall(function() mine = mentor.properties:try_get("followers") or {} end)
    local result = {}
    local options = {}
    pcall(function() options = FollowerTokenDropdownOptions(mentor.partyId, true) end)
    for _, option in ipairs(options) do
        if option.id ~= "none" and not mine[option.id] then
            local tok = dmhub.GetCharacterById(option.id)
            if tok ~= nil then
                local where = cond(tok.partyId == mentor.partyId, "in the party", "in an allied party")
                result[#result+1] = {token = tok, where = where}
            end
        end
    end
    table.sort(result, function(left, right) return (left.token.name or "") < (right.token.name or "") end)
    return result
end

----------------------------------------------------------------------
--The window.

--- Open the Followers window for the open Hero.
function HeroSheetWindows.OpenFollowers()
    local mentor = HeroSheet.Token()
    if mentor == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local hero = mentor.name or "this Hero"
    local stacked = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < STACK_BELOW
    --the add form: its type and what is picked so far.
    local form = {
        type = "retainer",
        name = "",
        pregenid = nil,
        ancestry = Race.DefaultRace(),
        characteristic = "mgt",
        link = nil,
    }

    --- @type Panel
    local list
    --- @type Panel
    local listCaps
    --- @type Panel
    local formPanel
    --- @type fun()
    local FillList
    --- @type fun()
    local FillForm
    --what the list shows, so a follower made a moment later redraws it.
    local listSignature = nil

    local function Live()
        return HeroSheet.Token()
    end

    --- @param tok CharacterToken
    local function Dismiss(tok)
        local name = tok.name or "This follower"
        local charid = tok.charid
        HeroSheetWindow.ShowDialog{
            title = string.format("Dismiss %s?", name),
            width = 520,
            bodyHeight = 44,
            body = HeroSheetWindow.DialogText(string.format("%s stops being %s's follower. Their character and token stay in the party; delete them separately if you want them gone.", name, hero)),
            saveText = "Dismiss",
            onSave = function()
                local live = Live()
                if live == nil or not HeroSheetWrite.CanWrite() then
                    return
                end
                local props = live.properties --[[@as character]]
                props:RemoveFollowerFromMentor(charid)
                Saved()
                FillList()
                FillForm()
            end,
        }
    end

    --The follower's link moves to another token (as the old sheet's Token
    --dropdown does).
    --- @param fromid string
    --- @param toid string
    local function Reassign(fromid, toid)
        HeroSheetWrite.Save{
            charid = mentor.charid,
            description = "Reassign follower",
            execute = function(props)
                local followers = (props --[[@as character]]):EnsureFollowers()
                followers[fromid] = nil
                followers[toid] = true
            end,
        }
        Saved()
        FillList()
        FillForm()
    end

    --- @param anchor Panel
    --- @param tok CharacterToken
    local function TokenMenu(anchor, tok)
        local live = Live()
        if live == nil then
            return
        end
        local entries = {{text = string.format("%s (current token)", tok.name or ""), reason = "This follower uses it now."}}
        for _, link in ipairs(Linkable(live)) do
            local other = link.token
            local otherid = other.charid
            entries[#entries+1] = {
                text = cond(OnMap(otherid), string.format("%s (on the map)", other.name or ""), other.name or ""),
                click = function()
                    Reassign(tok.charid, otherid)
                end,
            }
        end
        HeroSheetLists.ShowMenu(anchor, entries)
    end

    --- @param tok CharacterToken
    --- @return Panel
    local function Row(tok)
        local charid = tok.charid
        local typeName = TypeName(tok)
        local what, line = Describe(tok)
        local portrait = nil
        pcall(function() portrait = tok.offTokenPortrait end)
        local more
        more = Button("", function(element)
            HeroSheetLists.ShowMenu(more, {
                {text = "Use another token...", click = function()
                    dmhub.Schedule(0.05, function()
                        if mod.unloaded or not more.valid then
                            return
                        end
                        TokenMenu(more, tok)
                    end)
                end},
                "-",
                {text = "Dismiss", danger = true, click = function()
                    Dismiss(tok)
                end},
            })
        end, {halign = "right", rmargin = 0})
        --the lists' row menu glyph, not words.
        more.children = {
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
        local buttons = {
            Button("Open sheet", function()
                local live = dmhub.GetCharacterById(charid)
                if live ~= nil then
                    live:ShowSheet()
                end
            end),
        }
        if typeName == "Retainer" and OnMap(charid) then
            buttons[#buttons+1] = Button("Find on map", function()
                dmhub.CenterOnToken(charid, function()
                    dmhub.SelectToken(charid)
                end)
            end)
        end
        buttons[#buttons+1] = more
        local info = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    classes = {"heroSheetCardStrong"},
                    text = tok.name or "",
                    fontSize = 17,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                },
                gui.Panel{
                    classes = {"heroSheetFeatTag", cond(typeName == "", "collapsed", nil)},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 9,
                    width = "auto",
                    height = 18,
                    hpad = 7,
                    borderBox = true,
                    lmargin = 8,
                    halign = "left",
                    valign = "center",
                    gui.Label{
                        classes = {"heroSheetCardSub"},
                        text = typeName,
                        fontSize = 11.5,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        textWrap = false,
                    },
                },
            },
            Line(what, {"heroSheetCardStrong"}, 13.5, {bold = true, tmargin = 2}),
        }
        if line ~= "" then
            info[#info+1] = Line(line, {"heroSheetCardText"}, 13.5, {tmargin = 1})
        end
        info[#info+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 8,
            children = buttons,
        }
        return gui.Panel{
            classes = {"heroSheetFeatCard"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 12,
            vpad = 10,
            borderBox = true,
            bmargin = 10,
            gui.Panel{
                classes = {"heroSheetFollowerPortrait"},
                bgimage = portrait or "panels/square.png",
                bgcolor = cond(portrait ~= nil, "#ffffffff", nil),
                cornerRadius = 6,
                width = 56,
                height = 56,
                halign = "left",
                valign = "top",
                rmargin = 12,
                interactable = false,
            },
            gui.Panel{
                width = "100%-68",
                height = "auto",
                flow = "vertical",
                halign = "left",
                children = info,
            },
        }
    end

    --- @param mentorTok CharacterToken
    --- @return string
    local function ListSignature(mentorTok)
        local parts = {}
        for _, tok in ipairs(Followers(mentorTok)) do
            parts[#parts+1] = tok.charid .. ":" .. tostring(tok.name) .. ":" .. tostring(OnMap(tok.charid))
        end
        return table.concat(parts, "|")
    end

    FillList = function()
        local live = Live()
        if live == nil or list == nil or not list.valid then
            return
        end
        listSignature = ListSignature(live)
        local followers = Followers(live)
        local children = {}
        for _, tok in ipairs(followers) do
            children[#children+1] = Row(tok)
        end
        if #children == 0 then
            children[#children+1] = Line("No followers yet.", {"heroSheetCardSub"}, 14, {tmargin = 4})
        end
        list.children = children
        listCaps.children[2].text = tostring(#followers)
    end

    --The form's fields: a caps name over the control.
    --- @param name string
    --- @param control Panel
    --- @param note nil|string muted under the control
    --- @return Panel
    local function Field(name, control, note)
        local children = {Caps(name), control}
        if note ~= nil then
            children[#children+1] = Line(note, {"heroSheetCardSub"}, 12, {tmargin = 4})
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 12,
            children = children,
        }
    end

    --- @param placeholder string
    --- @return Panel
    local function NameField(placeholder)
        return gui.Input{
            classes = {"heroSheetField"},
            text = form.name,
            placeholderText = placeholder,
            width = "100%",
            height = HeroSheetWindow.TargetSize(32),
            hpad = 10,
            borderBox = true,
            border = 1,
            cornerRadius = 5,
            fontSize = 14,
            characterLimit = 60,
            editlag = 0.1,
            edit = function(element)
                local was = trim(form.name) == ""
                form.name = element.text or ""
                --only the Add button's state can change: no rebuild while typing.
                if was ~= (trim(form.name) == "") then
                    formPanel:FireEventTree("followerFormValid")
                end
            end,
        }
    end

    --- @param options table[] dropdown options
    --- @param chosen string
    --- @param change fun(id: string)
    --- @return Panel
    local function Choose(options, chosen, change)
        return gui.Dropdown{
            classes = {"heroSheetField"},
            width = "100%",
            height = HeroSheetWindow.TargetSize(32),
            options = options,
            idChosen = chosen,
            hasSearch = #options > 12,
            change = function(element)
                ---@cast element Dropdown
                change(tostring(element.idChosen))
            end,
        }
    end

    --- @return boolean
    local function Valid()
        if form.type == "retainer" then
            return form.pregenid ~= nil
        elseif form.type == "existing" then
            return form.link ~= nil
        end
        return trim(form.name) ~= "" and form.ancestry ~= nil
    end

    local function Add()
        local live = Live()
        if live == nil or not HeroSheetWrite.CanWrite() or not Valid() then
            return
        end
        local info = {
            name = trim(form.name),
            type = form.type,
            ancestry = form.ancestry,
            characteristic = form.characteristic,
        }
        local kind = form.type
        local options = {open = false}
        if kind == "retainer" then
            kind = "premaderetainer"
            options.pregenid = form.pregenid
            if info.name == "" then
                local _, lookup = buildRetainerList()
                info.name = lookup[form.pregenid] or "Retainer"
            end
        elseif kind == "existing" then
            options.followerToken = form.link
        end
        CreateFollowerMonster(info, kind, live, options)
        HeroSheetWindow.Toast("Added. It now appears in the switcher.")
        form.name = ""
        form.link = nil
        form.pregenid = nil
        --the new follower is made over a few frames; the list catches up.
        dmhub.Schedule(0.2, function()
            if mod.unloaded then
                return
            end
            Saved()
        end)
        FillForm()
    end

    FillForm = function()
        if formPanel == nil or not formPanel.valid then
            return
        end
        local live = Live()
        if live == nil then
            return
        end
        --the type tiles, two to a row.
        local tiles = {}
        for i, followerType in ipairs(TYPES) do
            local id = followerType.id
            tiles[#tiles+1] = gui.Panel{
                classes = {"heroSheetFeatCard", "heroSheetBenefit", "hoverable", cond(form.type == id, "selected", nil)},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 7,
                width = "50%-4",
                height = HeroSheetWindow.TargetSize(76),
                flow = "vertical",
                hpad = 12,
                vpad = 8,
                borderBox = true,
                bmargin = 8,
                rmargin = cond(i % 2 == 1, 8, 0),
                halign = "left",
                click = function()
                    if form.type ~= id then
                        form.type = id
                        FillForm()
                    end
                end,
                Line(followerType.name, {"heroSheetCardStrong"}, 14.5, {bold = true}),
                Line(followerType.text, {"heroSheetCardSub"}, 12.5, {tmargin = 2}),
            }
        end
        local children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                children = tiles,
            },
        }

        if form.type == "retainer" then
            local options, lookup = buildRetainerList()
            local rows = {}
            for _, option in ipairs(options) do
                if option.id ~= "none" then
                    local id = option.id
                    rows[#rows+1] = gui.Panel{
                        classes = {"heroSheetListRow", "hoverable", cond(form.pregenid == id, "heroSheetRowPinned", nil)},
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 5,
                        width = "100%-8",
                        height = HeroSheetWindow.TargetSize(30),
                        hpad = 10,
                        borderBox = true,
                        bmargin = 3,
                        click = function()
                            form.pregenid = id
                            FillForm()
                        end,
                        gui.Label{
                            classes = {"heroSheetCardStrong"},
                            text = option.text,
                            fontSize = 13.5,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            valign = "center",
                            textWrap = false,
                            interactable = false,
                        },
                    }
                end
            end
            children[#children+1] = Field("Retainer", gui.Panel{
                width = "100%",
                height = 200,
                flow = "vertical",
                vscroll = true,
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    valign = "top",
                    children = rows,
                },
            })
            children[#children+1] = Field("Name", NameField(form.pregenid ~= nil and lookup[form.pregenid] or "Name"))
        elseif form.type == "artisan" or form.type == "sage" then
            children[#children+1] = Field("Name", NameField("Name"))
            children[#children+1] = Field("Ancestry", Choose(Race.GetDropdownList(), form.ancestry, function(id)
                form.ancestry = id
            end))
            if form.type == "artisan" then
                children[#children+1] = Field("Characteristic", Choose({
                    {id = "mgt", text = "Might"},
                    {id = "agl", text = "Agility"},
                }, form.characteristic, function(id)
                    form.characteristic = id
                end), "Reason 1, plus Might 1 or Agility 1.")
            else
                children[#children+1] = Field("Characteristics", Line("Reason 1, Intuition 1.", {"heroSheetCardSub"}, 12.5))
            end
        else
            local rows = {}
            for _, link in ipairs(Linkable(live)) do
                local id = link.token.charid
                local typeName = TypeName(link.token)
                rows[#rows+1] = gui.Panel{
                    classes = {"heroSheetListRow", "hoverable", cond(form.link == id, "heroSheetRowPinned", nil)},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 7,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    hpad = 10,
                    vpad = 7,
                    borderBox = true,
                    bmargin = 4,
                    click = function()
                        form.link = id
                        FillForm()
                    end,
                    Line(link.token.name or "", {"heroSheetCardStrong"}, 13.5),
                    Line(cond(typeName ~= "", typeName .. DOT, "") .. link.where, {"heroSheetCardSub"}, 11.5),
                }
            end
            if #rows == 0 then
                rows[#rows+1] = Line("No followers in the party.", {"heroSheetCardSub"}, 13.5)
            end
            children[#children+1] = Field("Link an existing follower", gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = rows,
            })
        end

        local addButton = Button(cond(form.type == "existing", "Link follower", "Add follower"), function()
            Add()
        end, {
            classes = {"heroSheetButton", "heroSheetSolid", "heroSheetPrimary", "hoverable", cond(Valid(), nil, "heroSheetDisabled")},
            height = HeroSheetWindow.TargetSize(32),
            hpad = 14,
            followerFormValid = function(element)
                element:SetClassTree("heroSheetDisabled", not Valid())
            end,
        })
        addButton.children[1]:SetClass("heroSheetPrimary", true)
        --opacity is not inherited: the words dim with the frame.
        addButton:SetClassTree("heroSheetDisabled", not Valid())
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 14,
            addButton,
        }
        formPanel.children = children
    end

    list = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        --a follower made a moment ago (or changed elsewhere) redraws the list.
        thinkTime = 0.5,
        think = function(element)
            local live = Live()
            if live ~= nil and ListSignature(live) ~= listSignature then
                FillList()
            end
        end,
    }
    formPanel = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    listCaps = Caps(string.format("%s's followers", hero), "0")
    local left = gui.Panel{
        width = cond(stacked, "100%", "50%-14"),
        height = cond(stacked, "auto", "100%"),
        flow = "vertical",
        halign = "left",
        listCaps,
        gui.Panel{
            width = "100%",
            height = cond(stacked, "auto", "100%-26"),
            flow = "vertical",
            vscroll = not stacked,
            list,
        },
    }
    local right = gui.Panel{
        width = cond(stacked, "100%", "50%-14"),
        height = cond(stacked, "auto", "100%"),
        flow = "vertical",
        halign = "right",
        tmargin = cond(stacked, 18, 0),
        Caps("Add a follower"),
        gui.Panel{
            width = "100%",
            height = cond(stacked, "auto", "100%-26"),
            flow = "vertical",
            vscroll = not stacked,
            formPanel,
        },
    }
    local columns
    if stacked then
        columns = gui.Panel{
            width = "100%",
            height = WINDOW_BODY,
            flow = "vertical",
            vscroll = true,
            gui.Panel{
                width = "100%-10",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                left,
                right,
            },
        }
    else
        columns = gui.Panel{
            width = "100%",
            height = WINDOW_BODY,
            flow = "horizontal",
            left,
            gui.Panel{
                classes = {"heroSheetDialogRule"},
                bgimage = "panels/square.png",
                width = 1,
                height = "100%",
                halign = "center",
            },
            right,
        }
    end

    HeroSheetWindow.ShowDialog{
        title = "Followers",
        subtitle = hero,
        width = WINDOW_WIDTH,
        bodyHeight = WINDOW_BODY,
        body = columns,
        footerLeft = gui.Label{
            classes = {"heroSheetCardSub"},
            text = "Followers appear after the party in the sheet's switcher.",
            fontSize = 12,
            italics = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        onDone = function() end,
    }
    FillList()
    FillForm()
end

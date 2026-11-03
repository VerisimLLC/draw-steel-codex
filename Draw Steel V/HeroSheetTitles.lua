local mod = dmhub.GetModLoading()

--The Titles window: the titles the Hero holds, each with its benefit choice
--in place and an Earned note, beside the list to grant from. The list opens
--on the Hero's echelon with the lower echelons under it ("Lower echelons");
--the other echelons are a chip away, so a Director can award any title.
--Removing a title keeps its benefit pick (in levelChoices, with the Hero's
--other saved choices) and its note (titleEarned), so granting it again brings
--them back. Everything saves as it is made.

HeroSheetWindows = rawget(_G, "HeroSheetWindows") or {}

local ORDINAL = {"1st", "2nd", "3rd", "4th"}
local DOT = " \u{00B7} "

--The Titles window's design size; its two columns are 600 tall.
local WINDOW_WIDTH = 1040
local WINDOW_BODY = 600
--A window narrower than this (sheet units) stacks its columns.
local STACK_BELOW = 760

--- @param title Title
--- @return integer
local function Echelon(title)
    local echelon = tonumber(title.echelon) or 1
    return math.max(1, math.min(4, math.floor(echelon)))
end

--Compendium text keeps vertical tabs for line breaks.
--- @param text nil|string
--- @return string
local function Text(text)
    return (string.gsub(text or "", "\v", "\n"))
end

--- The title's benefit choices ("Choose one of the following"), in order: empty
--- for a title with one fixed benefit. Some 4th echelon titles have two (a
--- characteristic increase and the title's own benefit).
--- @param title Title
--- @return CharacterFeatureChoice[]
local function BenefitChoices(title)
    local choices = {}
    local info = title:try_get("modifierInfo")
    if info == nil then
        return choices
    end
    for _, feature in ipairs(info.features or {}) do
        if feature.typeName == "CharacterFeatureChoice" then
            choices[#choices+1] = feature --[[@as CharacterFeatureChoice]]
        end
    end
    return choices
end

--- @param choice CharacterFeatureChoice
--- @return CharacterFeature[]
local function Options(choice)
    local options = {}
    pcall(function()
        options = choice.options or {}
    end)
    return options
end

--- The picked option's guid, or nil.
--- @param choice CharacterFeatureChoice
--- @param levelChoices table
--- @return nil|string
local function Picked(choice, levelChoices)
    local picks = levelChoices[choice.guid]
    if type(picks) == "table" then
        return picks[1]
    end
    return nil
end

--- @param creature creature
--- @return Title[] the held titles, by name
local function Held(creature)
    local held = {}
    pcall(function()
        held = creature:Titles()
    end)
    table.sort(held, function(left, right) return (left.name or "") < (right.name or "") end)
    return held
end

----------------------------------------------------------------------
--The title card: a grant row shows the whole title on a deliberate
--hover and pins it on a click.

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

--- @param title Title
--- @param pinned boolean
--- @param close fun()
--- @return Panel
local function TitleCard(title, pinned, close)
    local children = {
        Line(title.name or "", {"heroSheetCardStrong"}, 17, {bold = true, width = "100%-30"}),
        Line(string.format("Title%s%s echelon", DOT, ORDINAL[Echelon(title)]), {"heroSheetCardSub"}, 12.5, {tmargin = 1}),
    }
    local flavor = Text(title.description)
    if trim(flavor) ~= "" then
        children[#children+1] = Line(flavor, {"heroSheetCardSub"}, 13.5, {italics = true, tmargin = 6})
    end
    local prerequisite = Text(title.prerequisite)
    if trim(prerequisite) ~= "" then
        children[#children+1] = Line("<b>Prerequisite.</b> " .. prerequisite, {"heroSheetCardText"}, 13.5, {tmargin = 8})
    end
    local choices = BenefitChoices(title)
    if #choices > 0 then
        for _, choice in ipairs(choices) do
            local heading = "Benefit: choose one"
            if #choices > 1 then
                heading = string.format("%s: choose one", choice.name or "Benefit")
            end
            children[#children+1] = Line(heading, {"heroSheetCardLabel"}, 12, {bold = true, tmargin = 10})
            for _, option in ipairs(Options(choice)) do
                local name = option.name or ""
                if not string.find(name, "[%.!?]$") then
                    name = name .. "."
                end
                children[#children+1] = Line(string.format("<b>%s</b> %s", name, Text(option.description)), {"heroSheetCardText"}, 13.5, {tmargin = 4})
            end
        end
    else
        local effect = Text(title:try_get("effect"))
        if trim(effect) ~= "" then
            children[#children+1] = Line("<b>Effect.</b> " .. effect, {"heroSheetCardText"}, 13.5, {tmargin = 8})
        end
    end
    return HeroSheetTheme.CardFrame(gui.Panel{
        width = 380,
        height = "auto",
        flow = "vertical",
        children = children,
    }, pinned, close)
end

----------------------------------------------------------------------
--The window.

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
--- @param click nil|fun()
--- @param disabled nil|boolean
--- @return Panel
local function SmallButton(text, click, disabled)
    return gui.Panel{
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable", cond(disabled, "heroSheetDisabled", nil)},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 10,
        borderBox = true,
        halign = "right",
        valign = "center",
        click = function()
            if click ~= nil and not disabled then
                click()
            end
        end,
        gui.Label{
            classes = {"heroSheetButtonLabel", cond(disabled, "heroSheetDisabled", nil)},
            text = text,
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
end

--- Open the Titles window for the open Hero. With a title id, that title's
--- card is marked and brought into view (the card's "choose a benefit").
--- @param focusid nil|string
function HeroSheetWindows.OpenTitles(focusid)
    local token = HeroSheet.Token()
    if token == nil or not HeroSheetWrite.CanWrite() then
        return
    end
    local hero = token.name or "this Hero"
    local echelon = 1
    pcall(function() echelon = token.properties:Echelon() end)
    local state = {chip = echelon, query = ""}
    local stacked = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < STACK_BELOW

    --- @type Panel
    local heldList
    --- @type Panel
    local grantList
    --- @type Panel
    local heldScroll
    --- @type Panel
    local heldCaps
    --- @type fun()
    local FillHeld
    --- @type fun()
    local FillGrants

    local function Live()
        local live = HeroSheet.Token()
        if live == nil then
            return nil
        end
        return live.properties
    end

    local function Grant(title)
        local id = title.id
        HeroSheetWrite.Save{
            charid = token.charid,
            description = "Grant title",
            execute = function(props)
                props:AddTitle(id)
            end,
        }
        HeroSheet.Saved()
        FillHeld()
        FillGrants()
    end
    local function Remove(title)
        local id = title.id
        HeroSheetWrite.Save{
            charid = token.charid,
            description = "Remove title",
            execute = function(props)
                local titles = props:GetTitles()
                titles[id] = nil
            end,
        }
        HeroSheet.Saved()
        HeroSheetWindow.Toast(string.format("Removed %s. Granting it again restores its benefit and note.", title.name or "the title"))
        FillHeld()
        FillGrants()
    end
    local function Pick(choice, optionGuid)
        local guid = choice.guid
        HeroSheetWrite.Save{
            charid = token.charid,
            description = "Choose a title benefit",
            execute = function(props)
                local levelChoices = props:GetLevelChoices()
                levelChoices[guid] = {optionGuid}
            end,
        }
        HeroSheet.Saved()
        FillHeld()
    end

    --A held title: its name and echelon, Remove, its flavour, Earned, then
    --its benefit: the options to choose from, or its one fixed benefit.
    --- @param title Title
    --- @param creature creature
    --- @return Panel
    local function HeldCard(title, creature)
        local id = title.id
        local choices = BenefitChoices(title)
        local levelChoices = creature:GetLevelChoices() or {}
        local todo = false
        for _, choice in ipairs(choices) do
            if Picked(choice, levelChoices) == nil then
                todo = true
            end
        end
        local earned = (creature:try_get("titleEarned") or {})[id] or ""
        local children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    classes = {"heroSheetCardStrong"},
                    text = title.name or "",
                    fontSize = 18,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                },
                gui.Label{
                    classes = {"heroSheetCardLabel"},
                    text = string.format("Title%s%s echelon", DOT, ORDINAL[Echelon(title)]),
                    fontSize = 12.5,
                    width = "auto",
                    height = "auto",
                    lmargin = 8,
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                },
                gui.Panel{
                    classes = {"heroSheetIconButton", "hoverable"},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 6,
                    width = 26,
                    height = 26,
                    halign = "right",
                    valign = "center",
                    linger = function(element)
                        gui.Tooltip("Remove title")(element)
                    end,
                    click = function()
                        Remove(title)
                    end,
                    gui.Panel{
                        classes = {"heroSheetIconButtonIcon"},
                        bgimage = "window-chrome/chrome-close.png",
                        width = 11,
                        height = 11,
                        halign = "center",
                        valign = "center",
                        interactable = false,
                    },
                },
            },
        }
        local flavor = Text(title.description)
        if trim(flavor) ~= "" then
            children[#children+1] = Line(flavor, {"heroSheetCardSub"}, 13.5, {italics = true, tmargin = 4})
        end
        --how the Hero earned it, saved as it is typed.
        children[#children+1] = gui.Panel{
            width = "100%",
            height = HeroSheetWindow.TargetSize(30),
            flow = "horizontal",
            tmargin = 8,
            gui.Label{
                classes = {"heroSheetCardSub"},
                text = "Earned",
                fontSize = 13,
                width = "auto",
                height = "auto",
                rmargin = 8,
                halign = "left",
                valign = "center",
                textWrap = false,
            },
            gui.Input{
                classes = {"heroSheetField"},
                text = earned,
                placeholderText = "What the Hero did",
                width = "100%-60",
                height = "100%",
                hpad = 8,
                borderBox = true,
                border = 1,
                cornerRadius = 5,
                fontSize = 13,
                characterLimit = 200,
                halign = "right",
                valign = "center",
                editlag = 0.1,
                edit = function(element)
                    local text = element.text or ""
                    if text == earned then
                        return
                    end
                    earned = text
                    HeroSheetWrite.SaveSoon("titleEarned:" .. id, {
                        charid = token.charid,
                        description = "Title earned note",
                        execute = function(props)
                            local notes = props:get_or_add("titleEarned", {})
                            notes[id] = text
                        end,
                    })
                end,
                defocus = function(element)
                    HeroSheetWrite.Flush("titleEarned:" .. id)
                end,
            },
        }
        --the benefit, with a prompt to choose while one is still unpicked.
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 10,
            bmargin = 4,
            gui.Label{
                classes = {"heroSheetCardLabel"},
                text = "BENEFIT",
                fontSize = 11.5,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                textWrap = false,
            },
            gui.Label{
                classes = {cond(todo, "heroSheetCardInfo", "heroSheetCardSub")},
                text = cond(todo, cond(#choices > 1, "Choose one of each", "Choose one"), "Shows on the sheet as a Title feature"),
                fontSize = 12,
                bold = todo,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                textWrap = false,
            },
        }
        for _, choice in ipairs(choices) do
            local picked = Picked(choice, levelChoices)
            --with more than one choice, each group is headed by its own name
            --and description (Characteristic Increase, Forsaken Benefit).
            if #choices > 1 then
                children[#children+1] = Line(choice.name or "", {"heroSheetCardStrong"}, 13.5, {bold = true, tmargin = 10})
                local description = Text(choice.description)
                if trim(description) ~= "" then
                    children[#children+1] = Line(description, {"heroSheetCardSub"}, 13, {tmargin = 1})
                end
            end
            for _, option in ipairs(Options(choice)) do
                local on = option.guid == picked
                local optionGuid = option.guid
                children[#children+1] = gui.Panel{
                    classes = {"heroSheetFeatCard", "heroSheetBenefit", "hoverable", cond(on, "selected", nil)},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 7,
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    hpad = 12,
                    vpad = 8,
                    borderBox = true,
                    tmargin = 6,
                    click = function()
                        if not on then
                            Pick(choice, optionGuid)
                        end
                    end,
                    gui.Panel{
                        classes = {"heroSheetRadio", cond(on, "selected", nil)},
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 7,
                        width = 14,
                        height = 14,
                        valign = "top",
                        tmargin = 3,
                        interactable = false,
                        gui.Panel{
                            classes = {"heroSheetRadioDot", cond(on, nil, "collapsed")},
                            bgimage = "panels/square.png",
                            cornerRadius = 3,
                            width = 6,
                            height = 6,
                            halign = "center",
                            valign = "center",
                            interactable = false,
                        },
                    },
                    gui.Panel{
                        width = "100%-26",
                        height = "auto",
                        flow = "vertical",
                        halign = "right",
                        interactable = false,
                        Line(option.name or "", {"heroSheetCardStrong"}, 14, {bold = true}),
                        Line(Text(option.description), {"heroSheetCardText"}, 13.5, {tmargin = 2}),
                    },
                }
            end
        end
        if #choices == 0 then
            local effect = Text(title:try_get("effect"))
            if trim(effect) ~= "" then
                children[#children+1] = Line(effect, {"heroSheetCardText"}, 13.5, {tmargin = 2})
            end
        end
        return gui.Panel{
            classes = {"heroSheetFeatCard", cond(todo, "heroSheetTitleTodo", nil), cond(id == focusid, "heroSheetTitleFocus", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 14,
            vpad = 12,
            borderBox = true,
            bmargin = 10,
            data = {id = id},
            children = children,
        }
    end

    --A title to grant: its name and the deed, Grant (Held once held). The
    --whole title shows on a deliberate hover and pins on a click.
    --- @param title Title
    --- @param held boolean
    --- @return Panel
    local function GrantRow(title, held)
        local args = {
            classes = {"heroSheetListRow", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 10,
            vpad = 7,
            borderBox = true,
            bmargin = 4,
            gui.Panel{
                width = "100%-80",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                interactable = false,
                Line(title.name or "", {"heroSheetCardStrong"}, 14.5, {bold = true}),
                Line(Text(title.prerequisite), {"heroSheetCardSub"}, 13, {tmargin = 1}),
            },
            SmallButton(cond(held, "Held", "Grant"), function()
                Grant(title)
            end, held),
        }
        return gui.Panel(HeroSheetTheme.HoverCard(args, function(pinned, close, element)
            return TitleCard(title, pinned, close)
        end, true, {halign = "left", valign = "center"}))
    end

    FillHeld = function()
        local creature = Live()
        if creature == nil or heldList == nil or not heldList.valid then
            return
        end
        local held = Held(creature)
        local children = {}
        for _, title in ipairs(held) do
            children[#children+1] = HeldCard(title, creature)
        end
        if #children == 0 then
            children[#children+1] = Line("No titles yet.", {"heroSheetCardSub"}, 14, {tmargin = 4})
        end
        heldList.children = children
        heldCaps.children[2].text = tostring(#held)
    end

    FillGrants = function()
        local creature = Live()
        if creature == nil or grantList == nil or not grantList.valid then
            return
        end
        local heldIds = creature:try_get("titles") or {}
        local all = {}
        for id, title in unhidden_pairs(dmhub.GetTable(Title.tableName) or {}) do
            all[#all+1] = title
        end
        table.sort(all, function(left, right) return (left.name or "") < (right.name or "") end)
        local query = string.lower(trim(state.query or ""))
        local children = {}
        if query ~= "" then
            --a search looks through every echelon.
            for _, title in ipairs(all) do
                local hay = string.lower((title.name or "") .. " " .. Text(title.prerequisite))
                if string.find(hay, query, 1, true) ~= nil then
                    children[#children+1] = GrantRow(title, heldIds[title.id] == true)
                end
            end
        else
            for _, title in ipairs(all) do
                if Echelon(title) == state.chip then
                    children[#children+1] = GrantRow(title, heldIds[title.id] == true)
                end
            end
            --on the Hero's own echelon, the lower ones follow (the rules allow them).
            if state.chip == echelon and echelon > 1 then
                children[#children+1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    tmargin = 10,
                    Caps("Lower echelons"),
                }
                for _, title in ipairs(all) do
                    if Echelon(title) < echelon then
                        children[#children+1] = GrantRow(title, heldIds[title.id] == true)
                    end
                end
            end
        end
        grantList.children = children
    end

    --- @type table<integer, Panel>
    local chips = {}
    local chipChildren = {}
    for chipEchelon = 1, 4 do
        local chip = gui.Panel{
            classes = {"heroSklChip", "hoverable", cond(chipEchelon == state.chip, "heroSklPicked", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 14,
            width = "auto",
            height = HeroSheetWindow.TargetSize(28),
            hpad = 11,
            borderBox = true,
            rmargin = 6,
            valign = "center",
            click = function()
                state.chip = chipEchelon
                for otherEchelon, otherChip in pairs(chips) do
                    otherChip:SetClassTree("heroSklPicked", otherEchelon == chipEchelon)
                end
                FillGrants()
            end,
            gui.Label{
                classes = {"heroSklChipText", cond(chipEchelon == state.chip, "heroSklPicked", nil)},
                text = ORDINAL[chipEchelon],
                fontSize = 12.5,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        chips[chipEchelon] = chip
        chipChildren[#chipChildren+1] = chip
    end
    chipChildren[#chipChildren+1] = gui.SearchInput{
        placeholderText = "Search titles",
        text = "",
        width = 220,
        height = HeroSheetWindow.TargetSize(28),
        borderBox = true,
        valign = "center",
        editlag = 0.15,
        edit = function(element)
            state.query = element.text or ""
            FillGrants()
        end,
    }

    heldList = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    grantList = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }
    heldCaps = Caps("Held", "0")
    heldScroll = gui.Panel{
        width = "100%",
        height = cond(stacked, "auto", "100%-26"),
        flow = "vertical",
        vscroll = not stacked,
        heldList,
    }
    local grantScroll = gui.Panel{
        width = "100%",
        height = cond(stacked, "auto", string.format("100%%-%d", 26 + HeroSheetWindow.TargetSize(28) + 10)),
        flow = "vertical",
        vscroll = not stacked,
        grantList,
    }
    local left = gui.Panel{
        width = cond(stacked, "100%", "50%-14"),
        height = cond(stacked, "auto", "100%"),
        flow = "vertical",
        halign = "left",
        heldCaps,
        heldScroll,
    }
    local right = gui.Panel{
        width = cond(stacked, "100%", "50%-14"),
        height = cond(stacked, "auto", "100%"),
        flow = "vertical",
        halign = "right",
        tmargin = cond(stacked, 18, 0),
        Caps("Grant a title"),
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 10,
            children = chipChildren,
        },
        grantScroll,
    }
    local columns
    if stacked then
        --narrow: one column that scrolls as a whole.
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
        title = "Titles",
        subtitle = hero,
        width = WINDOW_WIDTH,
        bodyHeight = WINDOW_BODY,
        body = columns,
        footerLeft = gui.Label{
            classes = {"heroSheetCardSub"},
            text = cond(dmhub.isDM, "Grant a title when a Hero meets its prerequisite.", "The Director usually grants titles. Players can add one here too."),
            fontSize = 12,
            italics = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        onDone = function()
            HeroSheetWrite.Flush()
        end,
        onCancel = function()
            HeroSheetWrite.Flush()
        end,
    }
    FillHeld()
    FillGrants()

    --the card's "choose a benefit": bring that title's card into view.
    if focusid ~= nil and not stacked then
        dmhub.Schedule(0.1, function()
            if mod.unloaded or not heldScroll.valid or not heldScroll.vscroll then
                return
            end
            local above = 0
            local total = heldList.renderedHeight
            for _, card in ipairs(heldList.children) do
                if card.data ~= nil and card.data.id == focusid then
                    break
                end
                above = above + card.renderedHeight
            end
            local room = total - heldScroll.renderedHeight
            if room > 0 then
                heldScroll.vscrollPosition = 1 - math.min(1, above / room)
            end
        end)
    end
end

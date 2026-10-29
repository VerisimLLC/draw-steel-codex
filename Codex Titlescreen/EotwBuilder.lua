local mod = dmhub.GetModLoading()

--Encounter of the Week hero builder: the screen. A guided, full-screen
--builder that walks the player through Ancestry, Culture, Career, Class,
--Complication and Appearance, over a lobby-game character.
--
--All the rules live in EotwBuild (EotwBuild.lua); this file only draws the
--steps and calls it. After every write the whole screen is refreshed from
--EotwBuild.Status, so what is shown is always what the character holds.
--
--Layout, left to right under a stepper: the hero so far (the town's hero
--card plus a few lines), the current step's page (main pick cards, then
--one block per choice), and a picks pane listing what the player has chosen
--on this step so far. Every card and pick has an (i) whose hover popup
--shows the item in full. A footer holds Back, Fill in the rest, and
--Next / Finish.
--
--Entry point: EotwBuilder.Open{host, token, onFinish, onClose}.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The hero builder and hero sheet".

local T = UIText.T
local TP = UIText.Plural

EotwBuilder = {}

--The builder's palette: the old character builder's cream on near-black
--(Draw Steel Character Builder/Styles.lua, CBStyles.COLORS).
local C = {
    SCREEN = "#0b0c0bff",
    COLUMN = "#121311ff",
    CARD = "#1a1b18ff",
    CARD_HOVER = "#262722ff",
    BORDER = "#3a3833ff",
    CREAM = "#DFCFC0ff",
    CREAM_LIGHT = "#F3EDE7ff",
    TAN = "#BC9B7Bff",
    MUTED = "#9a9188ff",
    INK = "#10110Fff",
    DONE = "#8fd18fff",
    TODO = "#e9b86fff",
    STALE = "#e07a5fff",
}

local SUMMARY_WIDTH = 360
local PICKS_WIDTH = 440
--the width of an (i) popup's contents
local POPUP_WIDTH = 480
local HEADER_HEIGHT = 132
local FOOTER_HEIGHT = 86

--The id the Complication page uses for its "No Complication" card.
local NO_COMPLICATION = "__none"

local RULES = {
    {
        selectors = { "eotwbText" },
        color = C.CREAM,
        fontSize = 17,
        width = "100%",
        height = "auto",
    },
    {
        selectors = { "eotwbText", "muted" },
        color = C.MUTED,
    },
    {
        selectors = { "eotwbHeading" },
        color = C.CREAM_LIGHT,
        fontSize = 30,
        bold = true,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "eotwbSection" },
        color = C.TAN,
        fontSize = 20,
        bold = true,
        width = "100%",
        height = "auto",
        tmargin = 18,
        bmargin = 6,
    },
    {
        selectors = { "eotwbColumn" },
        bgcolor = C.COLUMN,
        borderColor = C.BORDER,
        borderWidth = 1,
        cornerRadius = 8,
    },
    --main-pick cards and option chips
    {
        selectors = { "eotwbCard" },
        bgcolor = C.CARD,
        borderColor = C.BORDER,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbCard", "hover" },
        bgcolor = C.CARD_HOVER,
        borderColor = C.TAN,
    },
    {
        selectors = { "eotwbCard", "selected" },
        bgcolor = C.CREAM,
        borderColor = C.CREAM_LIGHT,
        borderWidth = 2,
    },
    {
        selectors = { "eotwbCard", "unavailable" },
        opacity = 0.35,
    },
    --an unavailable card can't be picked, so hovering doesn't highlight it
    {
        selectors = { "eotwbCard", "unavailable", "hover" },
        bgcolor = C.CARD,
        borderColor = C.BORDER,
    },
    {
        selectors = { "eotwbCardText" },
        color = C.CREAM,
        fontSize = 17,
        width = "100%",
        height = "auto",
        valign = "center",
        textAlignment = "center",
    },
    {
        selectors = { "eotwbCardText", "parent:selected" },
        color = C.INK,
        bold = true,
    },
    --Skills & Languages cards: known from elsewhere, and the native language
    {
        selectors = { "eotwbCard", "known" },
        bgcolor = "#2a2418ff",
        borderColor = C.TAN,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbCardText", "parent:known" },
        color = C.TAN,
    },
    {
        selectors = { "eotwbCard", "native" },
        bgcolor = "#173c3cff",
        borderColor = "#6fd3d3ff",
        borderWidth = 2,
    },
    {
        selectors = { "eotwbCardText", "parent:native" },
        color = "#bff2f2ff",
        bold = true,
    },
    --a dead language: read, not spoken
    {
        selectors = { "eotwbCard", "dead" },
        borderColor = "#6b6b8aff",
    },
    {
        selectors = { "eotwbCard", "unavailable", "dead", "hover" },
        borderColor = "#6b6b8aff",
    },
    {
        selectors = { "eotwbCardText", "parent:dead" },
        italics = true,
        color = "#b4b4d0ff",
    },
    --the info box listing what a step grants in skills and languages
    {
        selectors = { "eotwbInfo" },
        bgcolor = "#1b2226ff",
        borderColor = "#4f6a78ff",
        borderWidth = 1,
    },
    --the stepper
    {
        selectors = { "eotwbPill" },
        bgcolor = C.CARD,
        borderColor = C.BORDER,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbPill", "hover" },
        borderColor = C.TAN,
        bgcolor = C.CARD_HOVER,
    },
    {
        selectors = { "eotwbPill", "current" },
        borderColor = C.CREAM_LIGHT,
        borderWidth = 2,
        bgcolor = "#2c2a25ff",
    },
    {
        selectors = { "eotwbPillTitle" },
        color = C.CREAM,
        fontSize = 18,
        minFontSize = 12,
        bold = true,
        width = "100%",
        height = "auto",
        textWrap = false,
    },
    {
        selectors = { "eotwbPillSub" },
        color = C.TODO,
        fontSize = 14,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "eotwbPillSub", "done" },
        color = C.DONE,
    },
    --a choice block on the page
    {
        selectors = { "eotwbRow" },
        bgcolor = "#161714ff",
        borderColor = C.BORDER,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbRow", "todo" },
        borderColor = "#e9b86f88",
    },
    {
        selectors = { "eotwbRow", "stale" },
        borderColor = C.STALE,
    },
    {
        selectors = { "eotwbStatus" },
        fontSize = 15,
        width = "auto",
        height = "auto",
        color = C.TODO,
    },
    {
        selectors = { "eotwbStatus", "done" },
        color = C.DONE,
    },
    {
        selectors = { "eotwbStatus", "stale" },
        color = C.STALE,
    },
    --the (i) on a card or pick that pops up the item's details
    {
        selectors = { "eotwbInfoIcon" },
        bgcolor = C.MUTED,
    },
    {
        selectors = { "eotwbInfoIcon", "hover" },
        bgcolor = C.CREAM_LIGHT,
    },
    {
        selectors = { "eotwbInfoIcon", "parent:selected" },
        bgcolor = C.INK,
    },
    --a block in the picks pane: the main pick, or one choice's picks
    {
        selectors = { "eotwbPickBlock" },
        bgcolor = C.CARD,
        borderColor = C.BORDER,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbPickBlock", "todo" },
        borderColor = "#e9b86f88",
    },
    {
        selectors = { "eotwbPickBlock", "stale" },
        borderColor = C.STALE,
    },
    --characteristic boxes on the Class page
    {
        selectors = { "eotwbAttr" },
        bgcolor = C.CARD,
        borderColor = C.BORDER,
        borderWidth = 1,
    },
    {
        selectors = { "eotwbAttr", "hover" },
        borderColor = C.TAN,
    },
    {
        selectors = { "eotwbAttr", "picked" },
        borderColor = C.CREAM_LIGHT,
        borderWidth = 2,
    },
    {
        selectors = { "eotwbAttr", "locked" },
        bgcolor = "#0f100eff",
    },
}

--The full cascade: the theme, the old builder's classes (ability cards in
--the (i) popups use them), the hero card's rules, then ours.
local function BuilderStyles()
    local rules = {}
    for _,list in ipairs({ CBStyles.GetStyles(), EotwHeroCard.rules, RULES }) do
        for _,rule in ipairs(list) do
            rules[#rules+1] = rule
        end
    end
    return ThemeEngine.MergeStyles(rules)
end

--The intro text for a step, from the old builder's strings.
local function StepIntro(stepid)
    local strings = CharacterBuilder.STRINGS
    local key = string.upper(stepid)
    if stepid == "appearance" then
        return T("builder.appearance.intro")
    end
    if stepid == "skills" then
        return T("builder.skills.intro")
    end
    local entry = strings[key]
    return entry and entry.INTRO or ""
end

--The current main pick of a step, as the id its cards use.
---@param token CharacterToken
---@param stepid string
---@return string|nil
local function CurrentBaseId(token, stepid)
    local hero = token.properties --[[@as character]]
    if stepid == "ancestry" then
        return hero:try_get("raceid")
    elseif stepid == "career" then
        return hero:try_get("backgroundid")
    elseif stepid == "class" then
        local classItem = hero:GetClass()
        return classItem and classItem.id or nil
    elseif stepid == "culture" then
        local culture = hero:try_get("culture")
        local aggregate = culture and culture:try_get("aggregate") or nil
        if aggregate == "" then
            return nil
        end
        return aggregate
    elseif stepid == "complication" then
        local ids = EotwBuild.hero.ComplicationIds(hero)
        if #ids > 0 then
            return ids[1]
        end
        --no complication is the default
        return NO_COMPLICATION
    end
    return nil
end

--Make a step's main pick.
---@param token CharacterToken
---@param stepid string
---@param id string
local function SetBase(token, stepid, id)
    if stepid == "ancestry" then
        EotwBuild.SetAncestry(token, id)
    elseif stepid == "career" then
        EotwBuild.SetCareer(token, id)
    elseif stepid == "class" then
        EotwBuild.SetClass(token, id)
    elseif stepid == "culture" then
        EotwBuild.SetCultureAggregate(token, id)
    elseif stepid == "complication" then
        if id == NO_COMPLICATION then
            EotwBuild.SetComplication(token, nil)
        else
            EotwBuild.SetComplication(token, id)
        end
    end
end

--The table row behind a main-pick id, for its (i) and the picks pane.
local function BaseItem(stepid, id)
    local tableName = nil
    if stepid == "ancestry" then
        tableName = Race.tableName
    elseif stepid == "career" then
        tableName = Background.tableName
    elseif stepid == "class" then
        tableName = Class.tableName
    elseif stepid == "culture" then
        tableName = Culture.tableName
    elseif stepid == "complication" then
        tableName = CharacterComplication.tableName
    end
    if tableName == nil or id == nil then
        return nil
    end
    return (dmhub.GetTableVisible(tableName) or {})[id]
end

--The description text of a main-pick item.
local function BaseItemText(stepid, item)
    local text = nil
    if stepid == "ancestry" or stepid == "class" then
        text = item:try_get("details")
        if text == nil or text == "" then
            text = item:try_get("lore")
        end
    else
        text = item:try_get("description")
    end
    if type(text) ~= "string" then
        return ""
    end
    return text
end

--A class list from a base class plus optional flags: Classes("a", {b = true,
--c = false}) -> {"a", "b"}. Avoids nil holes, which cut an array short.
local function Classes(base, flags)
    local result = { base }
    for name,on in pairs(flags or {}) do
        if on then
            result[#result+1] = name
        end
    end
    return result
end

local function Text(text, classes, extra)
    local args = {
        classes = classes or { "eotwbText" },
        text = text or "",
        markdown = true,
        textAlignment = "topleft",
    }
    for k,v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Label(args)
end

--Set a scroll position now and again once layout has run: set while the
--new children are still unmeasured, it can land at the wrong end.
---@param panel Panel
---@param position number 1 = top, 0 = bottom
local function SetScroll(panel, position)
    panel.vscrollPosition = position
    dmhub.Schedule(0.05, function()
        if not mod.unloaded and panel.valid then
            panel.vscrollPosition = position
        end
    end)
end

--Read a field from a game-typed object or a plain table, or nil.
local function Field(obj, key)
    local value = nil
    pcall(function()
        if type(obj) == "table" and rawget(obj, "try_get") == nil and getmetatable(obj) == nil then
            value = obj[key]
        else
            value = obj:try_get(key)
        end
    end)
    return value
end

--The ability an option stands for (a signature or heroic ability pick),
--found the way the old builder's CBOptionWrapper:Panel finds it.
local function OptionAbility(option)
    local function FromModifiers(modifiers)
        for _,modifier in ipairs(modifiers or {}) do
            local behavior = Field(modifier, "behavior")
            if behavior == "activated" or behavior == "triggerdisplay" or behavior == "routine" then
                local ability = Field(modifier, cond(behavior == "activated", "activatedAbility", "ability"))
                if ability ~= nil then
                    return ability
                end
            end
        end
        return nil
    end
    local ability = FromModifiers(Field(option, "modifiers"))
    if ability ~= nil then
        return ability
    end
    local modifierInfo = Field(option, "modifierInfo")
    if modifierInfo ~= nil then
        for _,feature in ipairs(Field(modifierInfo, "features") or {}) do
            ability = FromModifiers(Field(feature, "modifiers"))
            if ability ~= nil then
                return ability
            end
        end
    end
    for _,feature in ipairs(Field(option, "features") or {}) do
        ability = FromModifiers(Field(feature, "modifiers"))
        if ability ~= nil then
            return ability
        end
    end
    return nil
end

--Crop an image to fill its panel without stretching (like CSS "cover"),
--keeping the top of a tall image (faces are near the top of portraits).
--Call from the panel's imageLoaded; aspect = width/height of the panel.
---@param element Panel
---@param aspect number
local function CoverCrop(element, aspect)
    local sprite = element.bgsprite
    if sprite == nil then
        return
    end
    local w = sprite.dimensions.x
    local h = sprite.dimensions.y
    if w <= 0 or h <= 0 or aspect <= 0 then
        return
    end
    local imageAspect = w / h
    if imageAspect > aspect then
        local frac = aspect / imageAspect
        element.selfStyle.imageRect = { x1 = (1 - frac) / 2, y1 = 0, x2 = 1 - (1 - frac) / 2, y2 = 1 }
    else
        local frac = imageAspect / aspect
        element.selfStyle.imageRect = { x1 = 0, y1 = 1 - frac, x2 = 1, y2 = 1 }
    end
end

--A panel showing `image` cropped to fill it (CoverCrop). extra: more panel
--fields (width, height, margins, children, ...).
---@param image string
---@param extra table
---@return Panel
local function ArtPanel(image, extra)
    local panelArgs = {
        bgimage = image,
        bgcolor = "white",
        cornerRadius = 8,
        interactable = false,
        --Crop only once both the image and the panel's size are known:
        --imageLoaded can come before layout, or never (an image already
        --cached), so a short think retries it.
        data = { cropped = false },
        imageLoaded = function(element)
            element:FireEvent("crop")
        end,
        crop = function(element)
            local w = element.renderedWidth
            local h = element.renderedHeight
            if element.bgsprite == nil or w == nil or h == nil or w <= 1 or h <= 1 then
                return
            end
            CoverCrop(element, w / h)
            element.data.cropped = true
        end,
        thinkTime = 0.05,
        think = function(element)
            element:FireEvent("crop")
            if element.data.cropped then
                element.thinkTime = nil
            end
        end,
    }
    for k,v in pairs(extra) do
        panelArgs[k] = v
    end
    return gui.Panel(panelArgs)
end

--The builder's styles for (i) popups, made on first use. A popup is not
--inside the builder's root, so it does not inherit the root's styles.
local g_popupStyles = nil
local function PopupStyles()
    if g_popupStyles == nil then
        g_popupStyles = BuilderStyles()
    end
    return g_popupStyles
end

--The contents of an (i) popup for a detail table:
--  { title, text, panelFn, art, image }
--art (a class's or ancestry's) is a banner across the top; image (another
--item's portrait) sits centered above the title.
local function DetailBody(d)
    ---@type Panel[]
    local children = {}
    if d.art ~= nil and d.art ~= "" then
        children[#children+1] = ArtPanel(d.art, { width = "100%", height = 220, bmargin = 12 })
    elseif d.image ~= nil and d.image ~= "" then
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            maxWidth = 240,
            maxHeight = 240,
            halign = "center",
            bgimage = d.image,
            bgcolor = "white",
            cornerRadius = 8,
            bmargin = 12,
            autosizeimage = true,
            interactable = false,
        }
    end
    if d.title ~= nil then
        children[#children+1] = gui.Label{ classes = { "eotwbHeading" }, text = d.title, fontSize = 26, width = "100%", bmargin = 8 }
    end
    if d.panelFn ~= nil then
        local ok, panel = pcall(d.panelFn)
        if ok and panel ~= nil then
            children[#children+1] = panel
        end
    end
    if d.text ~= nil and d.text ~= "" then
        children[#children+1] = Text(d.text, { "eotwbText" }, { fontSize = 16 })
    end
    return gui.Panel{
        styles = PopupStyles(),
        width = POPUP_WIDTH,
        height = "auto",
        flow = "vertical",
        interactable = false,
        children = children,
    }
end

--The (i) on a card or pick: hovering it pops up the item in full.
--detailFn returns a detail table (see DetailBody), or nil for none.
--side: where the popup opens, "right" (default) or "left" (the picks pane
--is at the screen's right edge). extra: more panel fields.
---@param detailFn fun(): table|nil
---@param side? string
---@param extra? table
---@return Panel
local function InfoIcon(detailFn, side, extra)
    local panelArgs = {
        classes = { "eotwbInfoIcon" },
        bgimage = "phosphor/info.png",
        width = 20,
        height = 20,
        popupPositioning = "panel",
        hover = function(element)
            local ok, d = pcall(detailFn)
            if not ok or d == nil then
                return
            end
            local built, body = pcall(DetailBody, d)
            if built and body ~= nil then
                element.tooltip = gui.TooltipFrame(body, { halign = side or "right", valign = "center" })
            end
        end,
        --the (i) is for reading: a click on it must not pick its card.
        press = function() end,
        click = function() end,
    }
    for k,v in pairs(extra or {}) do
        panelArgs[k] = v
    end
    return gui.Panel(panelArgs)
end

--A clickable card (a main pick) or chip (a choice's option).
--args: text, selected, unavailable, width, height, fontSize, press, info,
--blockedTip
--info: a function returning the card's detail table for its (i), or nil
--for a card without one.
--blockedTip: a tooltip shown when an unavailable card is clicked, saying
--why it can't be picked.
local function Card(args)
    ---@type Panel[]
    local children = {
        gui.Label{
            classes = { "eotwbCardText" },
            text = args.text,
            fontSize = args.fontSize,
            minFontSize = 11,
            --leave room for the (i) on the right, evenly on both sides so
            --the name stays centered.
            width = cond(args.info ~= nil, "100%-44", "100%"),
            halign = "center",
            interactable = false,
        },
    }
    if args.info ~= nil then
        children[#children+1] = InfoIcon(args.info, "right", { floating = true, halign = "right", valign = "center" })
    end
    return gui.Panel{
        classes = Classes("eotwbCard", { selected = args.selected == true, unavailable = args.unavailable == true }),
        bgimage = "panels/square.png",
        cornerRadius = 6,
        width = args.width or 230,
        height = args.height or 56,
        hmargin = 4,
        vmargin = 4,
        hpad = 8,
        borderBox = true,
        press = function(element)
            if args.unavailable and args.blockedTip ~= nil then
                gui.Tooltip(args.blockedTip)(element)
                return
            end
            if args.unavailable or args.press == nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            args.press()
        end,
        children = children,
    }
end

--The opening of an item's text for the picks pane: its first line that is
--not a heading, cut at a sentence (or a word) near `limit` characters.
---@param text string|nil
---@param limit integer
---@return string
local function Blurb(text, limit)
    if type(text) ~= "string" then
        return ""
    end
    for line in string.gmatch(text, "[^\n]+") do
        line = trim(line)
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            if #line <= limit then
                return line
            end
            local cut = string.sub(line, 1, limit)
            local stop = string.match(cut, "^.*()[%.!?] ")
            if stop ~= nil and stop > limit / 2 then
                return string.sub(cut, 1, stop)
            end
            local space = string.match(cut, "^.*() ") or (limit + 1)
            return string.sub(cut, 1, space - 1) .. "..."
        end
    end
    return ""
end

--A choice row's status words and their class (nil, "done" or "stale"),
--e.g. "Choose 2", as both the page and the picks pane show it.
---@param row table a row from EotwBuild.Status
---@param info table the row's info from EotwBuild.RowOptions
---@return string, string|nil
local function RowStatusText(row, info)
    if #row.stale > 0 then
        return T("builder.choice.status.stale"), "stale"
    elseif row.complete then
        return cond(row.exhausted, T("builder.choice.status.exhausted"), T("builder.choice.status.done")), "done"
    elseif info.costsPoints then
        return T("builder.choice.status.points_to_spend", { count = row.remaining, points = info.pointsName }), nil
    elseif row.remaining == info.numChoices then
        return TP("builder.choice.status.choose", info.numChoices), nil
    end
    return T("builder.choice.status.choose_more", { count = row.remaining }), nil
end

--An ability card for an (i) popup, top-aligned.
local function AbilityCard(ability)
    return ability:Render({ width = "100%", halign = "left", valign = "top", vmargin = 4 }, {})
end

--A subclass (or a Conduit's domain) in full: its description and what it
--grants at 1st level, with ability cards for the abilities.
local function SubclassDetail(subclass)
    local features = {}
    pcall(function() subclass:FillFeatureDetailsForLevel({}, 1, {}, true, features) end)
    return {
        title = subclass.name,
        panelFn = function()
            local children = {}
            local details = subclass:try_get("details")
            if type(details) == "string" and details ~= "" then
                children[#children+1] = gui.Label{ classes = { "eotwbText" }, text = details, markdown = true, fontSize = 16, textAlignment = "topleft", bmargin = 10 }
            end
            if #features > 0 then
                children[#children+1] = gui.Label{ classes = { "eotwbSection" }, text = T("builder.detail.subclass_first_level") }
            end
            for _,entry in ipairs(features) do
                local feature = entry.feature
                local name = Field(feature, "name") or T("builder.detail.feature_fallback")
                local ability = OptionAbility(feature)
                if ability ~= nil then
                    children[#children+1] = AbilityCard(ability)
                else
                    local text = nil
                    pcall(function() text = feature:GetDescription() end)
                    children[#children+1] = gui.Label{ classes = { "eotwbText" }, text = string.format("**%s**", name), markdown = true, fontSize = 16, tmargin = 6 }
                    if type(text) == "string" and text ~= "" then
                        children[#children+1] = gui.Label{ classes = { "eotwbText", "muted" }, text = text, markdown = true, fontSize = 15, textAlignment = "topleft" }
                    end
                end
            end
            return gui.Panel{ width = "100%", height = "auto", flow = "vertical", children = children }
        end,
    }
end

--What the (i) popup shows for one option of a choice row. A kit shows
--the whole kit; an ability pick shows its ability card (top-aligned, with
--no repeat of its flavor text underneath).
local function OptionDetail(entry, info)
    if info.typeName == "CharacterSubclassChoice" then
        local subclass = (dmhub.GetTableVisible("subclasses") or {})[entry.id]
        if subclass ~= nil then
            return SubclassDetail(subclass)
        end
    end
    if info.typeName == "CharacterKitChoice" then
        local kit = (dmhub.GetTableVisible(Kit.tableName) or {})[entry.id]
        if kit ~= nil then
            return {
                title = kit.name,
                panelFn = function()
                    return kit:Render({ width = POPUP_WIDTH }, {})
                end,
            }
        end
    end
    local optionWrapper = entry.option
    local ability = OptionAbility(optionWrapper:GetOption())
    if ability ~= nil then
        return {
            title = entry.name,
            panelFn = function()
                return AbilityCard(ability)
            end,
        }
    end
    local description = nil
    pcall(function() description = optionWrapper:GetDescription() end)
    local panelFn = nil
    pcall(function() panelFn = optionWrapper:Panel() end)
    return { title = entry.name, text = description, panelFn = panelFn }
end

--What a typical culture fills in: its three aspects (and what each one
--lets the hero choose) and its language.
local function CultureDetail(item)
    local aspectsTable = dmhub.GetTableVisible(CultureAspect.tableName) or {}
    local lines = {}
    local description = item:try_get("description")
    if type(description) == "string" and description ~= "" then
        lines[#lines+1] = description
        lines[#lines+1] = ""
    end
    lines[#lines+1] = T("builder.culture.detail.sets")
    lines[#lines+1] = ""
    for _,cat in ipairs(CultureAspect.categories) do
        local aspect = aspectsTable[(item.aspects or {})[cat.id] or ""]
        if aspect ~= nil then
            lines[#lines+1] = string.format("**%s: %s**", cat.text, aspect.name)
            local text = aspect:try_get("description")
            if type(text) == "string" and text ~= "" then
                lines[#lines+1] = text
            end
            local details = {}
            pcall(function() aspect:FillFeatureDetails({}, details) end)
            for _,detailEntry in ipairs(details) do
                local feature = detailEntry.feature
                local name = Field(feature, "name")
                local featureText = nil
                pcall(function() featureText = feature:GetDescription() end)
                if name ~= nil then
                    if type(featureText) == "string" and featureText ~= "" and featureText ~= name then
                        lines[#lines+1] = string.format("- *%s:* %s", name, featureText)
                    else
                        lines[#lines+1] = string.format("- *%s*", name)
                    end
                end
            end
            lines[#lines+1] = ""
        end
    end
    local languageid = item:try_get("languageid")
    local language = type(languageid) == "string" and (dmhub.GetTableVisible(Language.tableName) or {})[languageid] or nil
    if language ~= nil then
        lines[#lines+1] = T("builder.culture.detail.language", { language = language.name })
    end
    return { title = item.name, text = table.concat(lines, "\n") }
end

--- the screen ---------------------------------------------------------------

--Open the builder over `host`.
--args:
--  host      the panel to mount on (the town screen)
--  token     the lobby character being built
--  title     optional heading (default "Create Your Hero")
--  step      optional step to open on (default: the first incomplete one)
--  only      optional step id: show only that step (no stepper choice, no
--            Back / Fill / Next), e.g. "appearance" for Change Appearance
--  lockedSteps optional set of step ids ({ancestry = true}) whose main pick
--            is fixed once made: the page shows only the chosen card. A
--            rebuild locks Ancestry and Class; Create locks nothing.
--  onFinish  function(token) when the player finishes a complete hero
--  onClose   function(token) when the player closes without finishing
---@param args table
---@return Panel
function EotwBuilder.Open(args)
    local charid = args.token.charid
    local root
    local stepper
    local summary
    local summaryLines
    local page
    local pageContent = nil
    --above the scrolling page: blocks that stay in view (see BuildPage)
    local pageHeader
    --the picks pane on the right: its heading and its scrolling body
    local picks
    local picksHeading
    local picksBody
    local footer
    local messageLabel
    local themeHandler = nil

    local state = {
        step = nil,
        --a characteristic picked as the first half of a swap
        swapAttr = nil,
        message = "",
        --true after Fill in the Rest filled this page: the button then offers
        --to fill every other tab too. Any other action disarms it.
        fillAllArmed = false,
        --the page's blocks by key: {signature, panel} (see BuildPage)
        blocks = {},
        stepperSignature = nil,
        summarySignature = nil,
        --the picks pane's two blocks, each rebuilt only when its signature
        --changes: { step, baseSignature, basePanel, rowsSignature, rowsPanel }
        picks = {},
    }

    local function Tok()
        return dmhub.GetCharacterById(charid)
    end

    local Refresh
    local RefreshChrome
    local GoTo

    --Run a write, then redraw. Errors land in the footer, not the console.
    local function Act(fn)
        local tok = Tok()
        if tok == nil then
            return
        end
        state.fillAllArmed = false
        local ok, err = pcall(fn, tok)
        if not ok then
            state.message = T("builder.footer.error", { error = tostring(err) })
            printf("EotW builder: %s", tostring(err))
        end
        Refresh(false)
    end

    --- the stepper ---

    local function BuildStepper(status)
        local parts = { state.step }
        for _,stepStatus in ipairs(status.steps) do
            parts[#parts+1] = string.format("%s:%d/%d:%s:%s:%s", stepStatus.id, stepStatus.filled, stepStatus.total, tostring(stepStatus.complete), tostring(stepStatus.stale), tostring(stepStatus.optional))
        end
        local signature = table.concat(parts, "|")
        if signature == state.stepperSignature and stepper.valid and #stepper.children > 0 then
            return
        end
        state.stepperSignature = signature
        local pills = {}
        for i,stepStatus in ipairs(status.steps) do
            local stepid = stepStatus.id
            --args.only shows a single step (the hero sheet's Change Appearance)
            if args.only ~= nil and stepid ~= args.only then
                goto continue
            end
            local left = stepStatus.total - stepStatus.filled
            local sub
            --done = complete and not optional: an optional step the player
            --has not used reads "Optional", though it does not block Finish.
            local done = stepStatus.complete and not stepStatus.stale and not stepStatus.optional
            if stepStatus.stale then
                sub = T("builder.stepper.needs_attention")
            elseif stepStatus.optional then
                sub = T("builder.stepper.optional")
            elseif stepStatus.complete then
                sub = T("builder.stepper.done")
            elseif stepStatus.filled == 0 then
                sub = T("builder.stepper.not_started")
            else
                sub = T("builder.stepper.left", { count = left })
            end
            pills[#pills+1] = gui.Panel{
                classes = Classes("eotwbPill", { current = state.step == stepid }),
                bgimage = "panels/square.png",
                cornerRadius = 8,
                width = 176,
                height = 64,
                hmargin = 4,
                flow = "horizontal",
                hpad = 10,
                borderBox = true,
                press = function()
                    audio.FireSoundEvent("Mouse.Click")
                    state.step = stepid
                    state.swapAttr = nil
                    state.message = ""
                    Refresh(true)
                end,
                children = {
                    --the step's number, or a tick once it is done
                    gui.Panel{
                        width = 30,
                        height = 30,
                        valign = "center",
                        bgimage = cond(done, "phosphor/check-circle-fill.png", "panels/square.png"),
                        bgcolor = cond(done, C.DONE, "#00000000"),
                        borderColor = cond(done, "#00000000", C.TAN),
                        borderWidth = 2,
                        cornerRadius = 15,
                        interactable = false,
                        children = {
                            gui.Label{
                                text = cond(done, "", tostring(i)),
                                fontSize = 16,
                                bold = true,
                                color = C.TAN,
                                width = "100%",
                                height = "100%",
                                textAlignment = "center",
                                interactable = false,
                            },
                        },
                    },
                    gui.Panel{
                        width = "100%-40",
                        height = "auto",
                        valign = "center",
                        lmargin = 10,
                        flow = "vertical",
                        interactable = false,
                        children = {
                            gui.Label{ classes = { "eotwbPillTitle" }, text = stepStatus.title, interactable = false },
                            gui.Label{ classes = Classes("eotwbPillSub", { done = done }), text = sub, interactable = false },
                        },
                    },
                },
            }
            ::continue::
        end
        stepper.children = pills
    end

    --- the summary rail ---

    local function BuildSummary(tok)
        local hero = tok.properties --[[@as character]]
        local lines = {}
        local function Line(label, value)
            if value == nil or value == "" then
                value = "-"
            end
            lines[#lines+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 3,
                children = {
                    gui.Label{ classes = { "eotwbText", "muted" }, text = label, width = 120, fontSize = 15 },
                    gui.Label{ classes = { "eotwbText" }, text = value, width = "100%-120", fontSize = 15 },
                },
            }
        end

        local culture = hero:try_get("culture")
        local cultureName = nil
        if culture ~= nil then
            local aggregate = culture:try_get("aggregate")
            local item = aggregate ~= nil and aggregate ~= "" and (dmhub.GetTableVisible(Culture.tableName) or {})[aggregate] or nil
            if item ~= nil then
                cultureName = item.name
            else
                local names = {}
                local aspects = dmhub.GetTableVisible(CultureAspect.tableName) or {}
                for _,cat in ipairs(CultureAspect.categories) do
                    local aspect = aspects[culture.aspects[cat.id] or ""]
                    if aspect ~= nil then
                        names[#names+1] = aspect.name
                    end
                end
                cultureName = table.concat(names, ", ")
            end
        end

        local career = EotwBuild.hero.Career(hero)
        local kitNames = {}
        for _,kitid in ipairs({ hero:try_get("kitid"), hero:try_get("kitid2") }) do
            local kit = (dmhub.GetTableVisible(Kit.tableName) or {})[kitid]
            if kit ~= nil then
                kitNames[#kitNames+1] = kit.name
            end
        end
        local complication = "-"
        local ids = EotwBuild.hero.ComplicationIds(hero)
        if #ids > 0 then
            local item = (dmhub.GetTableVisible(CharacterComplication.tableName) or {})[ids[1]]
            complication = item and item.name or "-"
        elseif EotwBuild.hero.ChoseNoComplication(hero) then
            complication = T("builder.summary.no_complication")
        end


        --only the lines are rebuilt: the hero card is made once and repaints
        --itself (rebuilding it made it flicker on every pick).
        local signature = string.format("%s|%s|%s|%s", tostring(cultureName), career and career.name or "", table.concat(kitNames, ","), complication)
        if signature == state.summarySignature and #summaryLines.children > 0 then
            return
        end
        state.summarySignature = signature
        Line(T("builder.summary.culture"), cultureName)
        Line(T("builder.summary.career"), career and career.name or nil)
        Line(T("builder.summary.kit"), table.concat(kitNames, ", "))
        Line(T("builder.summary.complication"), complication)
        summaryLines.children = lines
    end

    --- the page ---

    --Whether this step's main pick is fixed (args.lockedSteps) and already made.
    --An unmade pick is never locked, so a hero missing one can still choose.
    local function BaseLocked(tok, stepid)
        return args.lockedSteps ~= nil and args.lockedSteps[stepid] == true and CurrentBaseId(tok, stepid) ~= nil
    end

    --The cards for a step's main pick. A locked pick shows only its own card.
    local function BaseCards(tok, stepid, options, width)
        local current = CurrentBaseId(tok, stepid)
        local locked = BaseLocked(tok, stepid)
        local cards = {}
        for _,entry in ipairs(options) do
            local id = entry.id
            if locked and id ~= current then
                goto continue
            end
            cards[#cards+1] = Card{
                text = entry.name,
                selected = current == id,
                width = width,
                info = function()
                    if id == NO_COMPLICATION then
                        return { title = T("builder.complication.none.title"), text = T("builder.complication.none.preview") }
                    end
                    return EotwBuilder.ItemDetail(stepid, entry.item)
                end,
                press = function()
                    if current == id then
                        return
                    end
                    local t = Tok()
                    if t == nil then
                        return
                    end
                    local step = EotwBuild.STEP_BY_ID[stepid]
                    local Apply = function()
                        state.message = ""
                        Act(function(t2) SetBase(t2, stepid, id) end)
                    end
                    if current ~= nil and EotwBuild.HasDependentPicks(t, stepid) then
                        EotwBuilder.Confirm(root, {
                            title = T("builder.change_confirm.title", { step = step.title }),
                            message = T("builder.change_confirm.message", { step = string.lower(step.title) }),
                            confirm = T("builder.change_confirm.button"),
                            onConfirm = Apply,
                        })
                    else
                        Apply()
                    end
                end,
            }
            ::continue::
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            children = cards,
        }
    end

    --The characteristic boxes under the array choice: the current values,
    --locked ones marked. Swap two unlocked ones by dragging one onto the
    --other, or by clicking one and then the other.
    local function CharacteristicsPanel(tok)
        local hero = tok.properties --[[@as character]]
        local classItem = hero:GetClass()
        if classItem == nil then
            return nil
        end
        local baseChars = classItem.baseCharacteristics
        local build = hero:try_get("attributeBuild") or {}
        if build.array == nil then
            return nil
        end
        local function Swap(first, second)
            state.swapAttr = nil
            if first == second then
                Refresh(false)
                return
            end
            local newBuild = {}
            for _,id in ipairs(creature.attributeIds) do
                if baseChars[id] == nil then
                    newBuild[id] = build[id]
                end
            end
            newBuild[first], newBuild[second] = newBuild[second], newBuild[first]
            Act(function(t) EotwBuild.SetCharacteristics(t, build.array, newBuild) end)
        end

        local boxes = {}
        for _,attrid in ipairs(creature.attributeIds) do
            local locked = baseChars[attrid] ~= nil
            local info = creature.attributesInfo[attrid] or {}
            local value = 0
            pcall(function() value = hero:GetBaseAttribute(attrid).baseValue or 0 end)
            boxes[#boxes+1] = gui.Panel{
                classes = Classes("eotwbAttr", { locked = locked, picked = state.swapAttr == attrid }),
                bgimage = "panels/square.png",
                cornerRadius = 6,
                width = 120,
                height = 92,
                hmargin = 5,
                flow = "vertical",
                data = { attrid = attrid },
                draggable = not locked,
                dragTarget = not locked,
                canDragOnto = function(element, target)
                    return target ~= nil and target ~= element and target:HasClass("eotwbAttr") and not target:HasClass("locked")
                end,
                drag = function(element, target)
                    if target == nil then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    Swap(attrid, target.data.attrid)
                end,
                --click, not press: press also fires when a drag ends.
                click = function()
                    if locked then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    if state.swapAttr == nil then
                        state.swapAttr = attrid
                        Refresh(false)
                        return
                    end
                    Swap(state.swapAttr --[[@as string]], attrid)
                end,
                children = {
                    gui.Label{
                        text = string.format("%+d", value),
                        fontSize = 34,
                        bold = true,
                        color = C.CREAM_LIGHT,
                        width = "100%",
                        height = 50,
                        textAlignment = "center",
                        interactable = false,
                    },
                    gui.Label{
                        text = cond(locked, T("builder.class.characteristic_fixed", { name = info.description or attrid }), info.description or attrid),
                        fontSize = 14,
                        color = C.MUTED,
                        width = "100%",
                        height = "auto",
                        textAlignment = "center",
                        interactable = false,
                    },
                },
            }
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 8,
            children = {
                gui.Panel{ width = "100%", height = "auto", flow = "horizontal", children = boxes },
                Text(T("builder.class.characteristics_hint"), { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
            },
        }
    end

    --One choice block: header, description, and the option chips.
    --options/info come from EotwBuild.RowOptions.
    local function RowBlock(tok, stepid, row, options, info)

        local statusText, statusClass = RowStatusText(row, info)

        local isCharacteristics = row.guid == "characteristics"
        --a full multi-kit row (a Tactician's two kits) greys out the other
        --kits; clicking one says to free a slot rather than doing nothing.
        local kitsFull = info.typeName == "CharacterKitChoice" and info.numChoices > 1 and info.remaining == 0
        local chips = {}
        for _,entry in ipairs(options) do
            local text = entry.name
            if info.costsPoints then
                text = string.format("%s (%d)", text, entry.cost)
            end
            local optionWrapper = entry.option
            chips[#chips+1] = Card{
                text = text,
                selected = entry.selected,
                unavailable = not entry.available,
                blockedTip = (kitsFull and not entry.available) and T("builder.choice.kits_full") or nil,
                width = cond(isCharacteristics, 150, 220),
                height = 44,
                fontSize = 15,
                --an array of numbers needs no popup: the boxes below show it.
                info = (not isCharacteristics) and function() return OptionDetail(entry, info) end or nil,
                press = function()
                    state.message = ""
                    if isCharacteristics then
                        local arrayIndex = optionWrapper:GetOption().arrayIndex
                        state.swapAttr = nil
                        Act(function(t) EotwBuild.SetCharacteristics(t, arrayIndex, nil) end)
                    elseif entry.selected then
                        Act(function(t) EotwBuild.Unchoose(t, stepid, row.guid, entry.id) end)
                    else
                        Act(function(t) EotwBuild.Choose(t, stepid, row.guid, entry.id) end)
                    end
                end,
            }
        end

        ---@type Panel[]
        local children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                children = {
                    gui.Label{
                        text = row.name,
                        fontSize = 20,
                        bold = true,
                        color = C.CREAM_LIGHT,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                    },
                    gui.Label{
                        classes = Classes("eotwbStatus", { [statusClass or "none"] = statusClass ~= nil }),
                        text = statusText,
                        valign = "center",
                        lmargin = 14,
                    },
                },
            },
        }
        if info.description ~= nil and info.description ~= "" and not isCharacteristics then
            children[#children+1] = Text(info.description, { "eotwbText", "muted" }, { fontSize = 15, vmargin = 4 })
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 4,
            children = chips,
        }
        if isCharacteristics then
            local panel = CharacteristicsPanel(tok)
            if panel ~= nil then
                children[#children+1] = panel
            end
        end

        return gui.Panel{
            classes = Classes("eotwbRow", { todo = not row.complete, stale = #row.stale > 0 }),
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            vmargin = 6,
            children = children,
        }
    end

    --The Appearance page: name, portrait (art, frame, placement), anthem.
    --The Appearance page in three parts, each its own block so that one
    --changing does not redraw the others: "name", "portrait" (preview, art
    --buttons, zoom) and "extras" (frame and anthem).
    local function AppearanceBlocks(tok, part)
        ---@type Panel[]
        local blocks = {}
        if part == "name" then

        local function SetNameFrom(element)
            local t = Tok()
            if t == nil then
                return
            end
            local text = trim(element.text or "")
            if text ~= (t.name or "") then
                EotwBuild.SetName(t, text)
                --not a full Refresh: rebuilding the page would take the
                --focus away from this input mid-typing.
                RefreshChrome()
            end
        end

        blocks[#blocks+1] = gui.Label{ classes = { "eotwbSection" }, text = T("builder.appearance.name_heading") }
        blocks[#blocks+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            children = {
                gui.Input{
                    classes = { "input", "bordered" },
                    text = tok.name or "",
                    create = function(element)
                        state.nameInput = element
                    end,
                    placeholderText = T("builder.appearance.name_placeholder"),
                    characterLimit = 60,
                    fontSize = 22,
                    width = 460,
                    height = 44,
                    editlag = 0.5,
                    edit = SetNameFrom,
                    change = SetNameFrom,
                },
                gui.Button{
                    text = T("builder.appearance.suggest_name_button"),
                    fontSize = 18,
                    width = 200,
                    height = 44,
                    lmargin = 12,
                    click = function()
                        local t = Tok()
                        if t == nil then
                            return
                        end
                        local generated = EotwBuild.GenerateName(t.properties --[[@as character]])
                        if generated == nil then
                            state.message = T("builder.appearance.no_name_list")
                            Refresh(false)
                            return
                        end
                        EotwBuild.SetName(t, generated)
                        --only the input and the chrome change; a page redraw
                        --made the portrait blocks flicker.
                        local input = state.nameInput
                        if input ~= nil and input.valid then
                            input.text = generated
                        end
                        RefreshChrome()
                    end,
                },
            },
        }

        end
        if part == "portrait" then
        --The framed preview: the portrait inside the chosen frame, at the
        --chosen zoom and offset. Drag it to move the portrait in the frame.
        local previewFrame = gui.Panel{
            width = "100%",
            height = "100%",
            bgcolor = "white",
            interactable = false,
        }
        local preview
        local zoomSlider
        preview = gui.Panel{
            width = 240,
            height = 240,
            valign = "top",
            bgimage = "panels/square.png",
            bgcolor = "white",
            data = { dragging = false, anchor = nil, start = nil, wheelSerial = 0 },
            linger = function(element)
                gui.Tooltip(T("builder.appearance.preview_tooltip"))(element)
            end,
            --The wheel drives the Zoom slider: each notch moves it 0.5%, and a
            --whole spin settles into one upload rather than one per notch.
            wheel = function(element, delta)
                local t = Tok()
                if t == nil or zoomSlider == nil or not zoomSlider.valid then
                    return true
                end
                local current = zoomSlider.value or 1
                local newZoom = current + 0.005 * delta
                --clamp to the slider's range, but never snap a typed-in value
                --that already lies outside it back inside.
                if delta > 0 then
                    newZoom = math.min(newZoom, math.max(current, 2))
                else
                    newZoom = math.max(newZoom, math.min(current, 0.25))
                end
                zoomSlider.value = newZoom
                t.portraitZoom = newZoom
                element:FireEvent("refreshPreview")

                element.data.wheelSerial = element.data.wheelSerial + 1
                local serial = element.data.wheelSerial
                dmhub.Schedule(0.4, function()
                    if not element.valid or element.data.wheelSerial ~= serial then
                        return
                    end
                    local tt = Tok()
                    if tt ~= nil then
                        tt:UploadAppearance()
                        RefreshChrome()
                    end
                end)
                return true
            end,
            refreshPreview = function(element)
                local t = Tok()
                if t == nil then
                    return
                end
                local portrait = t.portrait
                if not EotwBuild.PortraitIsSet(portrait) then
                    element.bgimage = "panels/square.png"
                    element.bgimageTokenMask = nil
                    element.selfStyle.imageRect = nil
                    element.selfStyle.bgcolor = "#ffffff11"
                    previewFrame:SetClass("hidden", true)
                    return
                end
                element.bgimage = portrait
                element.selfStyle.bgcolor = "white"
                element.selfStyle.imageRect = t.portraitRect
                local frame = t.portraitFrame
                if frame ~= nil and frame ~= "" then
                    element.bgimageTokenMask = frame
                    previewFrame.bgimage = frame
                    previewFrame.selfStyle.hueshift = t.portraitFrameHueShift
                    previewFrame:SetClass("hidden", false)
                else
                    element.bgimageTokenMask = nil
                    previewFrame:SetClass("hidden", true)
                end
            end,
            create = function(element)
                state.preview = element
                element:FireEvent("refreshPreview")
            end,
            press = function(element)
                local t = Tok()
                if t == nil then
                    return
                end
                element.data.dragging = true
                element.data.anchor = { x = element.mousePoint.x, y = element.mousePoint.y }
                element.data.start = { x = t.portraitOffset.x, y = t.portraitOffset.y }
                element.thinkTime = 0.02
            end,
            unpress = function(element)
                element.thinkTime = nil
                if element.data.dragging then
                    element.data.dragging = false
                    local t = Tok()
                    if t ~= nil then
                        t:UploadAppearance()
                    end
                    RefreshChrome()
                end
            end,
            think = function(element)
                local t = Tok()
                if not element.data.dragging or t == nil then
                    return
                end
                local point = element.mousePoint
                --(0,0) means the pointer left the panel: hold still.
                if point.x == 0 and point.y == 0 then
                    return
                end
                local anchor = element.data.anchor
                local start = element.data.start
                t.portraitOffset = core.Vector2(start.x + point.x - anchor.x, start.y + point.y - anchor.y)
                element:FireEvent("refreshPreview")
            end,
            children = { previewFrame },
        }

        --auto: back to the default, so the portrait follows later class changes.
        local function SetPortraitTo(art, missingMessage, auto)
            local t = Tok()
            if t == nil or art == nil or art == "" then
                state.message = missingMessage
                Refresh(false)
                return
            end
            EotwBuild.SetPortrait(t, art, auto)
            Refresh(false)
        end

        local zoom = 1
        pcall(function() zoom = tok.portraitZoom or 1 end)

        blocks[#blocks+1] = gui.Label{ classes = { "eotwbSection" }, text = T("builder.appearance.portrait_heading") }
        blocks[#blocks+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            children = {
                preview,
                gui.Panel{
                    width = "100%-260",
                    height = "auto",
                    lmargin = 20,
                    flow = "vertical",
                    children = {
                        Text(T("builder.appearance.portrait_hint"), { "eotwbText", "muted" }, { fontSize = 15, bmargin = 10 }),
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            children = {
                                gui.Button{
                                    text = T("builder.appearance.class_art_button"),
                                    fontSize = 18,
                                    width = 190,
                                    height = 44,
                                    rmargin = 10,
                                    click = function()
                                        local t = Tok()
                                        local classItem = t and (t.properties --[[@as character]]):GetClass() or nil
                                        SetPortraitTo(classItem and classItem:try_get("portraitid", "") or nil, T("builder.appearance.class_art_missing"), true)
                                    end,
                                },
                                gui.Button{
                                    text = T("builder.appearance.ancestry_art_button"),
                                    fontSize = 18,
                                    width = 190,
                                    height = 44,
                                    rmargin = 10,
                                    click = function()
                                        local t = Tok()
                                        local race = t and EotwBuild.hero.Ancestry(t.properties --[[@as character]]) or nil
                                        SetPortraitTo(race and race:try_get("portraitid", "") or nil, T("builder.appearance.ancestry_art_missing"))
                                    end,
                                },
                                gui.IconEditor{
                                    --Always open on plain Avatars: players kept uploading ordinary
                                    --portraits into Popout Avatars by accident. It stays pickable.
                                    library = "Avatar",
                                    restrictImageType = "Avatar",
                                    allowPaste = true,
                                    borderColor = C.TAN,
                                    borderWidth = 2,
                                    cornerRadius = 6,
                                    width = 96,
                                    height = 96,
                                    bgcolor = "white",
                                    linger = function(element)
                                        gui.Tooltip(T("builder.appearance.portrait_picker_tooltip"))(element)
                                    end,
                                    --IconEditor swaps its image itself, and
                                    --imageLoaded does not reliably reach us, so a
                                    --light think crops each new image once.
                                    data = { croppedFor = nil },
                                    thinkTime = 0.1,
                                    think = function(element)
                                        local image = element.bgimage
                                        if element.bgsprite ~= nil and element.data.croppedFor ~= image then
                                            local w = element.renderedWidth
                                            local h = element.renderedHeight
                                            if w ~= nil and h ~= nil and w > 1 and h > 1 then
                                                CoverCrop(element, w / h)
                                                element.data.croppedFor = image
                                            end
                                        end
                                    end,
                                    create = function(element)
                                        local t = Tok()
                                        if t ~= nil and EotwBuild.PortraitIsSet(t.portrait) then
                                            element:SetValue(t.portrait, false)
                                        end
                                    end,
                                    change = function(element)
                                        SetPortraitTo(element.value, nil)
                                    end,
                                },
                            },
                        },
                        gui.Label{ classes = { "eotwbText", "muted" }, text = T("builder.appearance.zoom_label"), fontSize = 15, tmargin = 14 },
                        gui.Slider{
                            width = 420,
                            height = 30,
                            sliderWidth = 340,
                            labelWidth = 60,
                            minValue = 0.25,
                            maxValue = 2,
                            unclamped = true,
                            labelFormat = "rawpercent",
                            value = zoom,
                            create = function(element)
                                zoomSlider = element
                            end,
                            change = function(element)
                                local t = Tok()
                                if t ~= nil then
                                    t.portraitZoom = element.value
                                    preview:FireEvent("refreshPreview")
                                end
                            end,
                            confirm = function(element)
                                local t = Tok()
                                if t ~= nil then
                                    t.portraitZoom = element.value
                                    t:UploadAppearance()
                                    preview:FireEvent("refreshPreview")
                                    RefreshChrome()
                                end
                            end,
                        },
                        gui.Button{
                            text = T("builder.appearance.reset_placement_button"),
                            fontSize = 16,
                            width = 180,
                            height = 38,
                            tmargin = 8,
                            click = function()
                                local t = Tok()
                                if t == nil then
                                    return
                                end
                                t.portraitZoom = 1
                                t.portraitOffset = core.Vector2(0, 0)
                                t:UploadAppearance()
                                Refresh(false)
                            end,
                        },
                    },
                },
            },
        }

        end
        if part == "extras" then
        local anthem = nil
        local anthemVolume = 1
        local frame = nil
        pcall(function()
            anthem = tok.anthem
            anthemVolume = tok.anthemVolume or 1
            frame = tok.portraitFrame
        end)

        local anthemEditor
        anthemEditor = gui.AudioEditor{
            width = 140,
            height = 140,
            autoplay = true,
            autoplayvolume = anthemVolume,
            --previews through the anthem bus, like real anthem playback.
            autoplaymixgroup = "anthem",
            value = anthem,
            change = function(element)
                local t = Tok()
                if t ~= nil then
                    t.anthem = element.value
                    t:UploadAppearance()
                end
            end,
        }

        blocks[#blocks+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,
            children = {
                gui.Panel{
                    width = 300,
                    height = "auto",
                    flow = "vertical",
                    children = {
                        gui.Label{ classes = { "eotwbSection" }, text = T("builder.appearance.frame_heading") },
                        gui.IconEditor{
                            library = "AvatarFrame",
                            width = 140,
                            height = 140,
                            bgcolor = "white",
                            allowNone = true,
                            create = function(element)
                                element:SetValue(frame, false)
                            end,
                            change = function(element)
                                local t = Tok()
                                if t ~= nil then
                                    t.portraitFrame = element.value
                                    t:UploadAppearance()
                                    local preview = state.preview
                                    if preview ~= nil and preview.valid then
                                        preview:FireEvent("refreshPreview")
                                    end
                                end
                            end,
                        },
                        Text(T("builder.appearance.frame_hint"), { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
                    },
                },
                gui.Panel{
                    width = 360,
                    height = "auto",
                    flow = "vertical",
                    children = {
                        gui.Label{ classes = { "eotwbSection" }, text = T("builder.appearance.anthem_heading") },
                        anthemEditor,
                        gui.Label{ classes = { "eotwbText", "muted" }, text = T("builder.appearance.volume_label"), fontSize = 14, tmargin = 6 },
                        gui.Slider{
                            width = 220,
                            height = 24,
                            sliderWidth = 160,
                            labelWidth = 50,
                            minValue = 0,
                            maxValue = 1,
                            labelFormat = "percent",
                            value = anthemVolume,
                            change = function(element)
                                anthemEditor:FireEvent("volume", element.value)
                            end,
                            confirm = function(element)
                                anthemEditor:FireEvent("volume", element.value)
                                local t = Tok()
                                if t ~= nil then
                                    t.anthemVolume = element.value
                                    t:UploadAppearance()
                                end
                            end,
                        },
                        Text(T("builder.appearance.anthem_hint"), { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
                    },
                },
            },
        }

        end
        return blocks
    end

    --How far the page is scrolled from its top, in pixels (0 when it does
    --not scroll). A fraction would not survive the page growing, e.g. when
    --picking a class adds its choice blocks.
    local function ScrollOffset()
        if pageContent == nil or not pageContent.valid then
            return 0
        end
        local overflow = pageContent.renderedHeight - page.renderedHeight
        if overflow <= 1 then
            return 0
        end
        return (1 - page.vscrollPosition) * overflow
    end

    --Scroll the page back to `offset` pixels from its top once the new
    --content has been laid out (and again a little later, to be safe).
    local function RestoreScrollOffset(offset, afterLayoutOnly)
        local function Apply()
            if mod.unloaded or not page.valid or pageContent == nil or not pageContent.valid then
                return
            end
            local overflow = pageContent.renderedHeight - page.renderedHeight
            if overflow <= 1 or offset <= 0 then
                page.vscrollPosition = 1
            else
                page.vscrollPosition = math.max(0, math.min(1, 1 - offset / overflow))
            end
        end
        if not afterLayoutOnly then
            Apply()
        end
        dmhub.Schedule(0.05, Apply)
        dmhub.Schedule(0.2, Apply)
    end

    --The detail for one skill or language card.
    local function PoolEntryDetail(kind, entry)
        local lines = {}
        local category = entry.category and Skill.categoriesById[entry.category] or nil
        if kind == "skill" and category ~= nil then
            lines[#lines+1] = T("builder.skills.detail.category", { category = category.text })
        end
        if entry.dead then
            lines[#lines+1] = T("builder.skills.detail.dead")
        end
        if entry.speakers ~= nil then
            lines[#lines+1] = cond(entry.dead, T("builder.skills.detail.once_spoken_by", { speakers = entry.speakers }), T("builder.skills.detail.spoken_by", { speakers = entry.speakers }))
        end
        if type(entry.description) == "string" and entry.description ~= "" then
            lines[#lines+1] = entry.description
        end
        lines[#lines+1] = ""
        if entry.state == "native" then
            lines[#lines+1] = T("builder.skills.detail.native")
        elseif entry.state == "fixed" then
            local source = entry.source or T("builder.skills.detail.source_fallback")
            lines[#lines+1] = cond(kind == "skill", T("builder.skills.detail.known_skill", { source = source }), T("builder.skills.detail.known_language", { source = source }))
        elseif entry.state == "selected" then
            lines[#lines+1] = T("builder.skills.detail.picked")
        elseif entry.state == "selectable" then
            lines[#lines+1] = T("builder.skills.detail.available")
        else
            lines[#lines+1] = T("builder.skills.detail.unavailable")
        end
        if #entry.pools > 0 and entry.state ~= "native" and entry.state ~= "fixed" then
            lines[#lines+1] = T("builder.skills.detail.pools", { choices = table.concat(entry.pools, ", ") })
        end
        if entry.special ~= nil then
            lines[#lines+1] = ""
            lines[#lines+1] = T("builder.skills.detail.special", { features = table.concat(entry.special, ", ") })
        end
        return { title = entry.name, text = table.concat(lines, "\n") }
    end

    --A card's label: the name, plus who speaks a language and whether it is dead,
    --e.g. "Szetch (Goblins, Radenwights)" or "Low Rhyvian (Sky elf; dead)".
    local function PoolCardText(entry)
        local notes = {}
        if entry.speakers ~= nil then
            notes[#notes+1] = entry.speakers
        end
        if entry.dead then
            notes[#notes+1] = T("builder.skills.card.dead")
        end
        if #notes == 0 then
            return entry.name
        end
        return string.format("%s (%s)", entry.name, table.concat(notes, "; "))
    end

    --One skill or language card on the Skills & Languages page.
    local function PoolCard(kind, entry)
        local entryState = entry.state
        local clickable = entryState == "selectable" or entryState == "selected"
        ---@type Panel[]
        local children = {
            gui.Label{
                classes = { "eotwbCardText" },
                text = PoolCardText(entry),
                fontSize = 15,
                minFontSize = 11,
                --room for the star on the left and the (i) on the right
                width = "100%-44",
                halign = "center",
                interactable = false,
            },
            InfoIcon(function() return PoolEntryDetail(kind, entry) end, "right", { floating = true, halign = "right", valign = "center" }),
        }
        if entry.special ~= nil then
            children[#children+1] = gui.Panel{
                floating = true,
                width = 16,
                height = 16,
                halign = "left",
                valign = "top",
                y = 4,
                bgimage = "phosphor/star-fill.png",
                bgcolor = "#ffd66bff",
                interactable = false,
            }
        end
        return gui.Panel{
            classes = Classes("eotwbCard", {
                selected = entryState == "selected",
                known = entryState == "fixed",
                native = entryState == "native",
                dead = entry.dead == true,
                unavailable = entryState == "unavailable",
            }),
            bgimage = "panels/square.png",
            cornerRadius = 6,
            width = 200,
            height = 42,
            hmargin = 4,
            vmargin = 4,
            hpad = 8,
            borderBox = true,
            press = function()
                if not clickable then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                state.message = ""
                Act(function(t) EotwBuild.TogglePoolPick(t, kind, entry.id) end)
            end,
            children = children,
        }
    end

    --The list of choices at the top of the Skills & Languages page.
    local function PoolSummary(skillView, languageView)
        local rows = {}
        local function Add(pool, kindName)
            local step = EotwBuild.STEP_BY_ID[pool.source or ""]
            local status = cond(pool.remaining == 0, T("builder.skills.summary.done"), T("builder.skills.summary.left", { count = pool.remaining }))
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 3,
                children = {
                    gui.Label{ classes = { "eotwbText", "muted" }, text = cond(kindName == "skill", T("builder.skills.summary.source_skill", { step = step and step.title or "" }), T("builder.skills.summary.source_language", { step = step and step.title or "" })), width = 220, fontSize = 15 },
                    gui.Label{ classes = { "eotwbText" }, text = pool.description or pool.name, markdown = true, width = "100%-330", fontSize = 15 },
                    gui.Label{ classes = Classes("eotwbStatus", { done = pool.remaining == 0 }), text = status, width = 100, textAlignment = "right" },
                },
            }
        end
        for _,pool in ipairs(skillView.pools) do
            Add(pool, "skill")
        end
        for _,pool in ipairs(languageView.pools) do
            Add(pool, "language")
        end
        if #rows == 0 then
            rows[1] = Text(T("builder.skills.summary.none"), { "eotwbText", "muted" }, { fontSize = 15 })
        end
        return gui.Panel{
            classes = { "eotwbRow" },
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            vmargin = 6,
            children = rows,
        }
    end

    --The cards of one kind, grouped (skills by skill group).
    local function PoolCards(kind, view)
        local blocks = {}
        if kind == "skill" then
            for _,category in ipairs(Skill.categories) do
                local cards = {}
                for _,entry in ipairs(view.entries) do
                    if entry.category == category.id then
                        cards[#cards+1] = PoolCard(kind, entry)
                    end
                end
                if #cards > 0 then
                    blocks[#blocks+1] = gui.Label{ classes = { "eotwbText", "muted" }, text = category.text, fontSize = 16, bold = true, tmargin = 8 }
                    blocks[#blocks+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", wrap = true, children = cards }
                end
            end
        else
            local cards = {}
            for _,entry in ipairs(view.entries) do
                cards[#cards+1] = PoolCard(kind, entry)
            end
            blocks[#blocks+1] = gui.Panel{ width = "100%", height = "auto", flow = "horizontal", wrap = true, children = cards }
        end
        return gui.Panel{ width = "100%", height = "auto", flow = "vertical", children = blocks }
    end

    local function PoolViewSignature(view)
        local parts = {}
        for _,pool in ipairs(view.pools) do
            parts[#parts+1] = string.format("%s:%d", pool.guid, pool.remaining)
        end
        for _,entry in ipairs(view.entries) do
            parts[#parts+1] = string.format("%s:%s:%s:%s", entry.id, entry.state, tostring(entry.special ~= nil), tostring(entry.source))
        end
        return table.concat(parts, "|")
    end

    --The small box on a step's page saying what it gives in skills and
    --languages; the choices themselves are made on Skills & Languages.
    local function GrantsBox(grants)
        local lines = {}
        if #grants.fixed > 0 then
            lines[#lines+1] = T("builder.grants.you_gain", { list = table.concat(grants.fixed, ", ") })
        end
        for _,pool in ipairs(grants.pools) do
            lines[#lines+1] = string.format("**%s:** %s", pool.name, pool.description or "")
        end
        local children = {
            gui.Label{ classes = { "eotwbText" }, text = T("builder.grants.heading"), fontSize = 18, bold = true, color = "#bfe0f0ff" },
            Text(table.concat(lines, "\n"), { "eotwbText" }, { fontSize = 15, vmargin = 4 }),
        }
        return gui.Panel{
            classes = { "eotwbInfo" },
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            vmargin = 6,
            children = children,
        }
    end

    --A signature for a choice row: everything its block shows. The block is
    --rebuilt only when this changes.
    local function RowSignature(tok, row, options)
        local parts = { row.guid, tostring(row.complete), tostring(row.remaining), tostring(#row.stale), tostring(row.exhausted) }
        for _,entry in ipairs(options) do
            parts[#parts+1] = string.format("%s:%s:%s", entry.id, tostring(entry.selected), tostring(entry.available))
        end
        if row.guid == "characteristics" then
            local hero = tok.properties --[[@as character]]
            for _,attrid in ipairs(creature.attributeIds) do
                local value = 0
                pcall(function() value = hero:GetBaseAttribute(attrid).baseValue or 0 end)
                parts[#parts+1] = string.format("%s=%d", attrid, value)
            end
            parts[#parts+1] = tostring(state.swapAttr)
        end
        return table.concat(parts, "|")
    end

    --Draw the page. It is a list of keyed blocks: a block whose signature
    --is unchanged keeps its existing panel, so a pick only redraws the
    --blocks it changed (rebuilding the whole page made it flicker).
    --keepScroll false (a new step) starts a fresh page at the top.
    --A pinned block sits in pageHeader, above the scrolling area, and stays
    --in view; pinned blocks must come before every unpinned one.
    local function BuildPage(tok, stepStatus, keepScroll)
        local stepid = stepStatus.id
        local step = EotwBuild.STEP_BY_ID[stepid]
        local hero = tok.properties --[[@as character]]

        --the Skills & Languages page keeps its list of choices in view while
        --the cards scroll, so the title and intro above it stay too.
        local pinHeader = stepid == "skills"

        local specs = {}
        local function Add(key, signature, build, pinned)
            specs[#specs+1] = { key = key, signature = signature, build = build, pinned = pinned or false }
        end

        Add("title", stepid, function()
            return gui.Label{ classes = { "eotwbHeading" }, text = step.title, fontSize = 34 }
        end, pinHeader)
        Add("intro", stepid, function()
            return Text(StepIntro(stepid), { "eotwbText", "muted" }, { fontSize = 16, tmargin = 4 })
        end, pinHeader)

        if stepid == "skills" then
            local skillView = EotwBuild.PoolTable(tok, "skill")
            local languageView = EotwBuild.PoolTable(tok, "language")
            Add("poolsummary", PoolViewSignature(skillView) .. "#" .. PoolViewSignature(languageView), function()
                return PoolSummary(skillView, languageView)
            end, true)
            Add("skillsheader", "", function()
                return gui.Label{ classes = { "eotwbSection" }, text = T("builder.skills.skills_heading") }
            end)
            Add("skills", PoolViewSignature(skillView), function()
                return PoolCards("skill", skillView)
            end)
            Add("languagesheader", tostring(languageView.native), function()
                local nativeItem = languageView.native and (dmhub.GetTableVisible(Language.tableName) or {})[languageView.native] or nil
                return gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    children = {
                        gui.Label{ classes = { "eotwbSection" }, text = T("builder.skills.languages_heading") },
                        Text(nativeItem and T("builder.skills.native_language", { language = nativeItem.name }) or T("builder.skills.native_language_missing"), { "eotwbText", "muted" }, { fontSize = 15, bmargin = 4 }),
                    },
                }
            end)
            Add("languages", PoolViewSignature(languageView), function()
                return PoolCards("language", languageView)
            end)
        elseif stepid == "appearance" then
            local portraitSignature = ""
            pcall(function()
                local offset = tok.portraitOffset
                portraitSignature = string.format("%s|%s|%s,%s", tostring(tok.portrait), tostring(tok.portraitZoom), tostring(offset and offset.x), tostring(offset and offset.y))
            end)
            for _,part in ipairs({ "name", "portrait", "extras" }) do
                Add("appearance:" .. part, cond(part == "portrait", portraitSignature, ""), function()
                    return gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "vertical",
                        children = AppearanceBlocks(tok, part),
                    }
                end)
            end
        else
            local current = CurrentBaseId(tok, stepid) or ""
            --the main pick
            if stepid == "culture" then
                local groups = {}
                local order = {}
                for _,entry in ipairs(EotwBuild.CultureAggregates()) do
                    if groups[entry.group] == nil then
                        groups[entry.group] = {}
                        order[#order+1] = entry.group
                    end
                    local list = groups[entry.group]
                    list[#list+1] = entry
                end
                for _,group in ipairs(order) do
                    Add("grouplabel:" .. group, "", function()
                        return gui.Label{ classes = { "eotwbSection" }, text = group }
                    end)
                    Add("group:" .. group, current, function()
                        return BaseCards(tok, stepid, groups[group])
                    end)
                end
                Add("ownculture", "", function()
                    return gui.Label{ classes = { "eotwbSection" }, text = T("builder.culture.own_culture_heading") }
                end)
            elseif step.base ~= nil then
                local baseRow = stepStatus.rows[1]
                local optional = baseRow ~= nil and baseRow.optional == true
                local done = baseRow ~= nil and baseRow.complete and not optional
                local statusText = cond(optional, T("builder.base.status.optional"), cond(done, T("builder.base.status.done"), T("builder.base.status.choose_one")))
                local locked = BaseLocked(tok, stepid)
                Add("baseheader", statusText .. tostring(locked), function()
                    local heading = cond(locked, T("builder.base.heading_locked", { pick = string.lower(step.base) }), T("builder.base.heading", { pick = string.lower(step.base) }))
                    return gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "vertical",
                        children = {
                            gui.Panel{
                                width = "100%",
                                height = "auto",
                                flow = "horizontal",
                                children = {
                                    gui.Label{ classes = { "eotwbSection" }, text = heading, width = "auto" },
                                    gui.Label{ classes = Classes("eotwbStatus", { done = done }), text = statusText, valign = "center", lmargin = 14, tmargin = 12 },
                                },
                            },
                            locked and Text(T("builder.base.locked_note", { pick = string.lower(step.base) }), { "eotwbText", "muted" }, { bmargin = 6 }) or nil,
                        },
                    }
                end)
                Add("basecards", current, function()
                    local options = EotwBuild.BaseOptions(hero, stepid)
                    if stepid == "complication" then
                        table.insert(options, 1, { id = NO_COMPLICATION, name = T("builder.complication.none.card") })
                    end
                    return BaseCards(tok, stepid, options)
                end)
            end

            --what this step gives in skills and languages
            local grants = EotwBuild.StepGrants(tok, stepid)
            if #grants.fixed > 0 or #grants.pools > 0 then
                local parts = {}
                for _,text in ipairs(grants.fixed) do
                    parts[#parts+1] = text
                end
                for _,pool in ipairs(grants.pools) do
                    parts[#parts+1] = pool.name
                end
                Add("grants", table.concat(parts, "|"), function()
                    return GrantsBox(grants)
                end)
            end

            --the choice blocks
            local headed = false
            for _,row in ipairs(stepStatus.rows) do
                if not row.base then
                    local options, info = EotwBuild.RowOptions(tok, stepid, row.guid)
                    if options ~= nil and info ~= nil then
                        if not headed and stepid ~= "culture" then
                            Add("choicesheader", "", function()
                                return gui.Label{ classes = { "eotwbSection" }, text = T("builder.choice.heading") }
                            end)
                            headed = true
                        end
                        Add("row:" .. row.guid, RowSignature(tok, row, options), function()
                            return RowBlock(tok, stepid, row, options, info)
                        end)
                    end
                end
            end
        end

        if not keepScroll then
            state.blocks = {}
        end
        local offset = keepScroll and ScrollOffset() or 0
        local panels = {}
        local pinnedPanels = {}
        local cache = {}
        for _,spec in ipairs(specs) do
            local cached = state.blocks[spec.key]
            local panel
            if cached ~= nil and cached.signature == spec.signature and cached.panel.valid then
                panel = cached.panel
            else
                panel = spec.build()
            end
            if panel ~= nil then
                if spec.pinned then
                    pinnedPanels[#pinnedPanels+1] = panel
                else
                    panels[#panels+1] = panel
                end
                cache[spec.key] = { signature = spec.signature, panel = panel }
            end
        end
        state.blocks = cache
        pageHeader.children = pinnedPanels
        pageHeader:SetClass("collapsed", #pinnedPanels == 0)

        if keepScroll and pageContent ~= nil and pageContent.valid then
            --same step: swap the changed blocks in place; the kept ones are
            --the same panels, so nothing visibly redraws.
            pageContent.children = panels
            RestoreScrollOffset(offset, true)
        else
            --a fresh content panel: the page's children list is reassigned,
            --which lays the new child out reliably.
            pageContent = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = panels,
            }
            page.children = { pageContent }
            RestoreScrollOffset(0)
        end
    end

    --- the picks pane ---

    --One block in the picks pane: a bordered box around `children`.
    --todo/stale color the border as the page's choice blocks do.
    local function PickBlock(children, todo, stale)
        return gui.Panel{
            classes = Classes("eotwbPickBlock", { todo = todo == true, stale = stale == true }),
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            vmargin = 5,
            children = children,
        }
    end

    --A block's small heading, such as "Signature Ability".
    local function PickLabel(text)
        return gui.Label{ classes = { "eotwbText" }, text = text, fontSize = 15, bold = true, color = C.TAN, bmargin = 4 }
    end

    --One pick: its name and, when it has details, an (i) opening to the left.
    --color: optional, e.g. for a stale pick or one the hero has from elsewhere.
    local function PickLine(name, detailFn, color)
        ---@type Panel[]
        local children = {
            gui.Label{
                classes = { "eotwbText" },
                text = name,
                fontSize = 17,
                color = color or C.CREAM_LIGHT,
                width = "auto",
                maxWidth = PICKS_WIDTH - 90,
                valign = "center",
            },
        }
        if detailFn ~= nil then
            children[#children+1] = InfoIcon(detailFn, "left", { valign = "center", lmargin = 8 })
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 2,
            children = children,
        }
    end

    --A row status line ("Choose 2"), colored like the page's.
    local function PickStatus(text, statusClass)
        return gui.Label{
            classes = Classes("eotwbStatus", { [statusClass or "none"] = statusClass ~= nil }),
            text = text,
            tmargin = 2,
        }
    end

    --The main pick's block: its art, its name with an (i), and the opening of
    --its text; or a note that it is still to choose. nil when the step has
    --no main pick to show (Culture without a typical culture: its aspects
    --are listed as choices below).
    local function PicksBase(tok, stepid)
        local step = EotwBuild.STEP_BY_ID[stepid]
        local id = CurrentBaseId(tok, stepid)
        if stepid == "complication" and id == NO_COMPLICATION then
            return PickBlock({
                PickLine(T("builder.complication.none.title"), nil),
                Text(T("builder.complication.none.detail"), { "eotwbText", "muted" }, { fontSize = 15, tmargin = 4 }),
            })
        end
        local item = BaseItem(stepid, id)
        if item == nil then
            if step.base == nil then
                return nil
            end
            return PickBlock({
                PickLabel(step.base),
                PickStatus(T("builder.picks.not_chosen"), nil),
            }, true)
        end
        local d = EotwBuilder.ItemDetail(stepid, item)
        local banner = d.art or d.image
        ---@type Panel[]
        local children = {}
        if banner ~= nil and banner ~= "" then
            children[#children+1] = ArtPanel(banner, { width = "100%", height = 170, bmargin = 10 })
        end
        if step.base ~= nil then
            children[#children+1] = PickLabel(step.base)
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            children = {
                gui.Label{ classes = { "eotwbHeading" }, text = item.name, fontSize = 24, maxWidth = PICKS_WIDTH - 90, valign = "center" },
                InfoIcon(function() return EotwBuilder.ItemDetail(stepid, item) end, "left", { valign = "center", lmargin = 10 }),
            },
        }
        local blurb = Blurb(d.text, 220)
        if blurb ~= "" then
            children[#children+1] = Text(blurb, { "eotwbText", "muted" }, { fontSize = 15, tmargin = 6 })
        end
        return PickBlock(children)
    end

    --The five characteristics as small boxes, once an array is chosen.
    local function PicksCharacteristics(tok)
        local hero = tok.properties --[[@as character]]
        local build = hero:try_get("attributeBuild") or {}
        if build.array == nil then
            return nil
        end
        local boxes = {}
        for _,attrid in ipairs(creature.attributeIds) do
            local info = creature.attributesInfo[attrid] or {}
            local value = 0
            pcall(function() value = hero:GetBaseAttribute(attrid).baseValue or 0 end)
            boxes[#boxes+1] = gui.Panel{
                classes = { "eotwbAttr" },
                bgimage = "panels/square.png",
                cornerRadius = 6,
                width = 68,
                height = 58,
                hmargin = 3,
                flow = "vertical",
                children = {
                    gui.Label{ text = string.format("%+d", value), fontSize = 22, bold = true, color = C.CREAM_LIGHT, width = "100%", height = 32, textAlignment = "center" },
                    gui.Label{ text = info.description or attrid, fontSize = 11, minFontSize = 8, color = C.MUTED, width = "100%", height = "auto", textAlignment = "center", textWrap = false },
                },
            }
        end
        return gui.Panel{ width = "auto", height = "auto", flow = "horizontal", halign = "left", tmargin = 2, children = boxes }
    end

    --One choice row's block: its name, each pick with an (i), and what is
    --still to choose.
    local function PicksRow(tok, stepid, row, options, info)
        local statusText, statusClass = RowStatusText(row, info)
        local stale = {}
        for _,id in ipairs(row.stale) do
            stale[id] = true
        end
        ---@type Panel[]
        local children = { PickLabel(row.name) }
        if row.guid == "characteristics" then
            local boxes = PicksCharacteristics(tok)
            if boxes ~= nil then
                children[#children+1] = boxes
            end
        else
            for _,entry in ipairs(options) do
                if entry.selected then
                    children[#children+1] = PickLine(entry.name, function() return OptionDetail(entry, info) end, stale[entry.id] and C.STALE or nil)
                end
            end
        end
        --"Done" goes without saying once the picks are listed.
        if statusClass ~= "done" then
            children[#children+1] = PickStatus(statusText, statusClass)
        end
        return PickBlock(children, not row.complete, #row.stale > 0)
    end

    --Skills & Languages in the picks pane: per kind, what the player picked
    --here, what is still to pick, and what the hero has from elsewhere.
    local function PicksPools(views)
        local blocks = {}
        for _,kind in ipairs({ "skill", "language" }) do
            local view = views[kind]
            local remaining = 0
            for _,pool in ipairs(view.pools) do
                remaining = remaining + pool.remaining
            end
            local chosen = {}
            local known = {}
            for _,entry in ipairs(view.entries) do
                local DetailFn = function() return PoolEntryDetail(kind, entry) end
                if entry.state == "selected" then
                    chosen[#chosen+1] = PickLine(entry.name, DetailFn)
                elseif entry.state == "native" then
                    known[#known+1] = PickLine(T("builder.picks.native", { language = entry.name }), DetailFn, C.CREAM)
                elseif entry.state == "fixed" then
                    known[#known+1] = PickLine(entry.name, DetailFn, C.CREAM)
                end
            end
            if #chosen > 0 or remaining > 0 then
                local children = { PickLabel(cond(kind == "skill", T("builder.picks.skills_chosen"), T("builder.picks.languages_chosen"))) }
                for _,line in ipairs(chosen) do
                    children[#children+1] = line
                end
                if remaining > 0 then
                    children[#children+1] = PickStatus(T("builder.picks.left_to_choose", { count = remaining }), nil)
                end
                blocks[#blocks+1] = PickBlock(children, remaining > 0)
            end
            if #known > 0 then
                local children = { PickLabel(cond(kind == "skill", T("builder.picks.skills_known"), T("builder.picks.languages_known"))) }
                for _,line in ipairs(known) do
                    children[#children+1] = line
                end
                blocks[#blocks+1] = PickBlock(children)
            end
        end
        return blocks
    end

    --Appearance in the picks pane: the name, whether a portrait and an
    --anthem are set.
    local function PicksAppearance(tok)
        local name = trim(tok.name or "")
        local hasPortrait = EotwBuild.PortraitIsSet(tok.portrait)
        local hasAnthem = false
        pcall(function() hasAnthem = tok.anthem ~= nil and tok.anthem ~= "" end)
        local function Block(label, value, todo)
            if value == nil then
                return PickBlock({ PickLabel(label), PickStatus(T("builder.picks.not_chosen"), nil) }, todo)
            end
            return PickBlock({ PickLabel(label), PickLine(value, nil) })
        end
        return {
            Block(T("builder.picks.name"), cond(name ~= "", name, nil), true),
            Block(T("builder.picks.portrait"), cond(hasPortrait, T("builder.picks.chosen"), nil), true),
            Block(T("builder.picks.anthem"), cond(hasAnthem, T("builder.picks.chosen"), T("builder.picks.none")), false),
        }
    end

    --Draw the picks pane for the current step. The main pick and the rest
    --are separate blocks, each rebuilt only when what it shows changed, so a
    --pick lower down does not reload the class art.
    local function BuildPicks(tok, stepStatus)
        local stepid = stepStatus.id
        if state.picks.step ~= stepid then
            state.picks = { step = stepid }
        end
        local cache = state.picks
        picksHeading.text = T("builder.picks.heading", { step = stepStatus.title })

        local baseSignature = tostring(CurrentBaseId(tok, stepid))
        local rowsSignature
        local BuildRows
        if stepid == "skills" then
            local views = { skill = EotwBuild.PoolTable(tok, "skill"), language = EotwBuild.PoolTable(tok, "language") }
            rowsSignature = PoolViewSignature(views.skill) .. "#" .. PoolViewSignature(views.language)
            BuildRows = function() return PicksPools(views) end
        elseif stepid == "appearance" then
            local anthem = nil
            pcall(function() anthem = tok.anthem end)
            rowsSignature = string.format("%s|%s|%s", tostring(tok.name), tostring(EotwBuild.PortraitIsSet(tok.portrait)), tostring(anthem))
            BuildRows = function() return PicksAppearance(tok) end
        else
            local rows = {}
            local parts = {}
            for _,row in ipairs(stepStatus.rows) do
                if not row.base then
                    local options, info = EotwBuild.RowOptions(tok, stepid, row.guid)
                    if options ~= nil and info ~= nil then
                        rows[#rows+1] = { row = row, options = options, info = info }
                        parts[#parts+1] = RowSignature(tok, row, options)
                    end
                end
            end
            rowsSignature = table.concat(parts, "#")
            BuildRows = function()
                local blocks = {}
                for _,r in ipairs(rows) do
                    blocks[#blocks+1] = PicksRow(tok, stepid, r.row, r.options, r.info)
                end
                return blocks
            end
        end

        local changed = false
        if cache.baseSignature ~= baseSignature or (cache.basePanel ~= nil and not cache.basePanel.valid) then
            cache.baseSignature = baseSignature
            cache.basePanel = (stepid ~= "skills" and stepid ~= "appearance") and PicksBase(tok, stepid) or nil
            changed = true
        end
        if cache.rowsSignature ~= rowsSignature or cache.rowsPanel == nil or not cache.rowsPanel.valid then
            cache.rowsSignature = rowsSignature
            cache.rowsPanel = gui.Panel{ width = "100%", height = "auto", flow = "vertical", children = BuildRows() }
            changed = true
        end
        if changed then
            local children = {}
            if cache.basePanel ~= nil then
                children[#children+1] = cache.basePanel
            end
            children[#children+1] = cache.rowsPanel
            picksBody.children = children
        end
    end

    --- the footer ---

    local backButton
    local fillButton
    local nextButton
    local closeButton = nil

    local function StepIndex(stepid)
        for i,step in ipairs(EotwBuild.STEPS) do
            if step.id == stepid then
                return i
            end
        end
        return 1
    end

    local function UpdateFooter(status)
        local index = StepIndex(state.step)
        local stepStatus = status.steps[index]
        backButton:SetClass("hidden", index == 1 or args.only ~= nil)
        --a single-step builder (args.only) has nowhere to go and nothing to fill
        fillButton:SetClass("hidden", args.only ~= nil)
        nextButton:SetClass("hidden", args.only ~= nil)
        if status.complete then
            state.fillAllArmed = false
        end
        fillButton.text = cond(state.fillAllArmed, T("builder.footer.fill_all_button"), T("builder.footer.fill_button"))
        fillButton:SetClass("disabled", not state.fillAllArmed and stepStatus.complete and not stepStatus.stale)
        if index == #EotwBuild.STEPS then
            nextButton.text = T("builder.footer.finish_button")
        elseif stepStatus.complete then
            nextButton.text = T("builder.footer.next_button")
        else
            nextButton.text = T("builder.footer.skip_button")
        end
        messageLabel.text = state.message or ""
        state.allComplete = status.complete
        if closeButton ~= nil and closeButton.valid then
            closeButton.text = cond(status.complete, T("builder.header.finish_button"), T("builder.header.save_close_button"))
        end
    end

    --- refresh ---

    --Redraw everything from the character. newStep: the page is a different
    --step than before (scroll the page and the picks pane to the top).
    Refresh = function(newStep)
        if root == nil or not root.valid then
            return
        end
        local tok = Tok()
        if tok == nil then
            return
        end
        EotwBuild.SyncDefaultPortrait(tok)
        local status = EotwBuild.Status(tok)
        if state.step == nil then
            state.step = status.incomplete[1] or "ancestry"
        end
        BuildStepper(status)
        BuildSummary(tok)
        local stepStatus = status.steps[StepIndex(state.step)]
        BuildPage(tok, stepStatus, not newStep)
        BuildPicks(tok, stepStatus)
        if newStep then
            SetScroll(picksBody, 1)
        end
        UpdateFooter(status)
    end

    --Redraw the stepper, the hero summary, the picks pane and the footer,
    --but not the page.
    RefreshChrome = function()
        if root == nil or not root.valid then
            return
        end
        local tok = Tok()
        if tok == nil then
            return
        end
        local status = EotwBuild.Status(tok)
        BuildStepper(status)
        BuildSummary(tok)
        BuildPicks(tok, status.steps[StepIndex(state.step)])
        UpdateFooter(status)
    end

    GoTo = function(stepid)
        state.step = stepid
        state.swapAttr = nil
        state.fillAllArmed = false
        Refresh(true)
    end

    local function Close(finished)
        local tok = Tok()
        if themeHandler ~= nil then
            themeHandler:Deregister()
            themeHandler = nil
        end
        if root ~= nil and root.valid then
            root:DestroySelf()
        end
        if finished then
            if args.onFinish ~= nil and tok ~= nil then
                args.onFinish(tok)
            end
        elseif args.onClose ~= nil and tok ~= nil then
            args.onClose(tok)
        end
    end

    --- assembly ---

    stepper = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "horizontal",
    }

    summaryLines = gui.Panel{
        width = "100%-32",
        height = "auto",
        halign = "center",
        flow = "vertical",
    }

    summary = gui.Panel{
        classes = { "eotwbColumn" },
        bgimage = "panels/square.png",
        width = SUMMARY_WIDTH,
        height = "100%",
        flow = "vertical",
        --the hero card repaints (name, portrait, stats) on refreshCard,
        --which its host has to fire, as the town's strip does.
        thinkTime = 0.25,
        think = function(element)
            element:FireEventTree("refreshCard")
        end,
        create = function(element)
            element:FireEventTree("refreshCard")
        end,
        children = {
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 16,
                bmargin = 14,
                children = {
                    EotwHeroCard.CreateHeroCard({
                        charid = charid,
                        mine = true,
                        name = args.token.name or "",
                    }, {
                        halign = "center",
                        --centred in its wrapper: the stats card's uiscale grows
                        --it about its centre, so top-aligned it pokes out above.
                        valign = "center",
                        showStats = true,
                        showSkills = false,
                        showResources = false,
                        click = function() end,
                        subtitle = function(t)
                            local className, ancestry, level = EotwRoster.HeroDetails(t)
                            return EotwRoster.FormatDetails(level, ancestry, className)
                        end,
                    }),
                },
            },
            summaryLines,
        },
    }

    pageHeader = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        rpad = 16,
        bmargin = 4,
        borderBox = true,
    }

    page = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        vscroll = true,
        rpad = 16,
        borderBox = true,
    }

    --the page's column: the pinned header over the scrolling page.
    local pageColumn = gui.Panel{
        width = string.format("100%%-%d", SUMMARY_WIDTH + PICKS_WIDTH + 40),
        height = "100%",
        hmargin = 20,
        flow = "vertical",
        children = { pageHeader, page },
    }

    picksHeading = gui.Label{
        classes = { "eotwbSection" },
        text = "",
        fontSize = 22,
        tmargin = 0,
        bmargin = 4,
    }

    picksBody = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        vscroll = true,
    }

    --what the player has chosen on this step so far (BuildPicks)
    picks = gui.Panel{
        classes = { "eotwbColumn" },
        bgimage = "panels/square.png",
        width = PICKS_WIDTH,
        height = "100%",
        flow = "vertical",
        pad = 16,
        rpad = 10,
        borderBox = true,
        children = { picksHeading, picksBody },
    }

    messageLabel = gui.Label{
        text = "",
        fontSize = 16,
        color = C.TODO,
        width = 600,
        height = "auto",
        valign = "center",
        textAlignment = "left",
    }

    backButton = gui.Button{
        text = T("builder.footer.back_button"),
        fontSize = 20,
        width = 180,
        height = 48,
        hmargin = 8,
        click = function()
            local index = StepIndex(state.step)
            if index > 1 then
                state.message = ""
                GoTo(EotwBuild.STEPS[index - 1].id)
            end
        end,
    }

    fillButton = gui.Button{
        text = T("builder.footer.fill_button"),
        fontSize = 20,
        width = 220,
        height = 48,
        hmargin = 8,
        linger = function(element)
            if state.fillAllArmed then
                gui.Tooltip(T("builder.footer.fill_all_tooltip"))(element)
            else
                gui.Tooltip(T("builder.footer.fill_tooltip"))(element)
            end
        end,
        --First click fills this page and arms the button as "For All Tabs?";
        --a second click fills every remaining tab.
        click = function(element)
            local tok = Tok()
            if tok == nil or element:HasClass("disabled") then
                return
            end
            local allTabs = state.fillAllArmed
            local ok, picks
            if allTabs then
                ok, picks = pcall(EotwBuild.FillAll, tok)
            else
                ok, picks = pcall(EotwBuild.Fill, tok, state.step)
            end
            if not ok then
                state.message = T("builder.footer.error", { error = tostring(picks) })
                printf("EotW builder: %s", tostring(picks))
            elseif picks == nil or #picks == 0 then
                state.message = cond(allTabs, T("builder.footer.nothing_to_fill_all"), T("builder.footer.nothing_to_fill"))
            else
                state.message = cond(allTabs, TP("builder.footer.filled_all", #picks), TP("builder.footer.filled", #picks))
            end
            --UpdateFooter disarms it again once the whole hero is complete.
            state.fillAllArmed = ok and not allTabs
            state.swapAttr = nil
            --the Appearance page's inputs show the filled name, so rebuild it.
            Refresh(state.step == "appearance")
        end,
    }

    nextButton = gui.Button{
        text = T("builder.footer.next_button"),
        fontSize = 20,
        width = 220,
        height = 48,
        hmargin = 8,
        click = function()
            local index = StepIndex(state.step)
            state.message = ""
            if index < #EotwBuild.STEPS then
                GoTo(EotwBuild.STEPS[index + 1].id)
                return
            end
            local tok = Tok()
            if tok == nil then
                return
            end
            local status = EotwBuild.Status(tok)
            if status.complete then
                Close(true)
                return
            end
            local names = {}
            for _,stepid in ipairs(status.incomplete) do
                names[#names+1] = EotwBuild.STEP_BY_ID[stepid].title
            end
            state.message = T("builder.footer.still_to_do", { steps = table.concat(names, ", ") })
            GoTo(status.incomplete[1])
        end,
    }

    footer = gui.Panel{
        width = "100%",
        height = FOOTER_HEIGHT,
        flow = "horizontal",
        children = {
            gui.Panel{
                width = "100%-720",
                height = "100%",
                lpad = 24,
                borderBox = true,
                children = { messageLabel },
            },
            gui.Panel{
                width = 700,
                height = "100%",
                flow = "horizontal",
                halign = "right",
                children = {
                    gui.Panel{ width = "auto", height = "auto", halign = "right", valign = "center", flow = "horizontal", rmargin = 24,
                        children = { backButton, fillButton, nextButton },
                    },
                },
            },
        },
    }

    root = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = C.SCREEN,
        flow = "vertical",
        styles = BuilderStyles(),
        captureEscape = true,
        --above the Guild dialog and the town under it.
        escapePriority = 5,
        escape = function()
            Close(false)
        end,
        destroy = function()
            if themeHandler ~= nil then
                themeHandler:Deregister()
                themeHandler = nil
            end
        end,
        children = {
            --header: title, the stepper, and Save & Close
            gui.Panel{
                width = "100%",
                height = HEADER_HEIGHT,
                flow = "horizontal",
                children = {
                    gui.Panel{
                        width = 320,
                        height = "100%",
                        lpad = 24,
                        borderBox = true,
                        flow = "vertical",
                        children = {
                            gui.Label{ classes = { "eotwbHeading" }, text = args.title or T("builder.header.title"), fontSize = 30, valign = "center", tmargin = 30 },
                            gui.Label{ classes = { "eotwbText", "muted" }, text = T("builder.header.subtitle"), fontSize = 15, width = "auto" },
                        },
                    },
                    gui.Panel{
                        width = "100%-560",
                        height = "100%",
                        children = { stepper },
                    },
                    gui.Panel{
                        width = 240,
                        height = "100%",
                        children = {
                            --"Save and Close" until every step is complete,
                            --then "Finish" (UpdateFooter switches it).
                            gui.Button{
                                text = T("builder.header.save_close_button"),
                                fontSize = 18,
                                width = 200,
                                height = 44,
                                halign = "right",
                                valign = "center",
                                rmargin = 24,
                                create = function(element)
                                    closeButton = element
                                end,
                                linger = function(element)
                                    --the draft / finish wording does not fit a single-step edit
                                    if args.only ~= nil then
                                        return
                                    end
                                    if state.allComplete then
                                        gui.Tooltip(T("builder.header.finish_tooltip"))(element)
                                    else
                                        gui.Tooltip(T("builder.header.save_close_tooltip"))(element)
                                    end
                                end,
                                click = function()
                                    Close(state.allComplete == true)
                                end,
                            },
                        },
                    },
                },
            },
            --body: summary | page | picks
            gui.Panel{
                width = "100%-32",
                height = string.format("100%%-%d", HEADER_HEIGHT + FOOTER_HEIGHT),
                halign = "center",
                flow = "horizontal",
                children = { summary, pageColumn, picks },
            },
            footer,
        },
    }

    args.host:AddChild(root)

    themeHandler = ThemeEngine.OnThemeChanged(mod, function()
        g_popupStyles = nil
        if root ~= nil and root.valid then
            root.styles = BuilderStyles()
        end
    end)

    state.step = args.step
    Refresh(true)
    return root
end

--What the (i) popup shows for a main-pick item: its art, name and text
--(a complication shows its benefit and drawback).
---@param stepid string
---@param item table
---@return table
function EotwBuilder.ItemDetail(stepid, item)
    if stepid == "culture" then
        return CultureDetail(item)
    end
    local result = {
        title = item.name,
        text = BaseItemText(stepid, item),
    }
    local portrait = item:try_get("portraitid")
    if type(portrait) == "string" and portrait ~= "" then
        --a class's or ancestry's art fills the pane (user direction);
        --others sit on top.
        if stepid == "class" or stepid == "ancestry" then
            result.art = portrait
        else
            result.image = portrait
        end
    end
    if stepid == "complication" then
        result.panelFn = function()
            return item:Render{ width = "100%" }
        end
    end
    return result
end

--A small confirm dialog over `host`.
--args: title, message, confirm (button text), onConfirm
---@param host Panel
---@param args table
function EotwBuilder.Confirm(host, args)
    local dlg
    dlg = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#000000aa",
        captureEscape = true,
        escapePriority = 10,
        escape = function()
            dlg:DestroySelf()
        end,
        children = {
            gui.Panel{
                width = 560,
                height = "auto",
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                bgcolor = C.COLUMN,
                borderColor = C.TAN,
                borderWidth = 2,
                cornerRadius = 10,
                flow = "vertical",
                pad = 24,
                borderBox = true,
                children = {
                    gui.Label{ classes = { "eotwbHeading" }, text = args.title, fontSize = 26, halign = "center" },
                    gui.Label{ classes = { "eotwbText" }, text = args.message, textAlignment = "center", vmargin = 16 },
                    gui.Panel{
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        flow = "horizontal",
                        children = {
                            gui.Button{
                                text = args.confirm or T("builder.confirm.confirm_button"),
                                fontSize = 18,
                                width = 180,
                                height = 44,
                                hmargin = 8,
                                click = function()
                                    dlg:DestroySelf()
                                    args.onConfirm()
                                end,
                            },
                            gui.Button{
                                text = T("builder.confirm.cancel_button"),
                                fontSize = 18,
                                width = 180,
                                height = 44,
                                hmargin = 8,
                                click = function()
                                    dlg:DestroySelf()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    host:AddChild(dlg)
end

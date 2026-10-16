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
--one block per choice), and a detail pane describing whatever the player
--last hovered. A footer holds Back, Fill in the rest, and Next / Finish.
--
--Entry point: EotwBuilder.Open{host, token, onFinish, onClose}.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The hero builder and hero sheet".

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
local DETAIL_WIDTH = 500
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
--the detail pane use them), the hero card's rules, then ours.
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
        return "Give your hero a name and a face, and if you like a frame for their token and an anthem."
    end
    if stepid == "skills" then
        return "Your ancestry, culture, career and class each let you pick skills and languages. Pick them all here: click a skill to take it, click it again to drop it. Each pick goes to whichever of your choices can take it, so you only see a skill as available if it still fits."
    end
    local entry = strings[key]
    return entry and entry.INTRO or ""
end

--The step's overview text for the detail pane when nothing is focused.
local function StepOverview(stepid)
    local entry = CharacterBuilder.STRINGS[string.upper(stepid)]
    if entry ~= nil and entry.OVERVIEW ~= nil then
        return entry.OVERVIEW
    end
    return StepIntro(stepid)
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

--The table row behind a main-pick id, for the detail pane.
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

--A clickable card (a main pick) or chip (a choice's option).
--args: text, selected, unavailable, width, height, fontSize, press, hover
local function Card(args)
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
        hover = function()
            if args.hover ~= nil then
                args.hover()
            end
        end,
        dehover = function()
            if args.dehover ~= nil then
                args.dehover()
            end
        end,
        press = function()
            if args.unavailable or args.press == nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            args.press()
        end,
        children = {
            gui.Label{
                classes = { "eotwbCardText" },
                text = args.text,
                fontSize = args.fontSize,
                minFontSize = 11,
                interactable = false,
            },
        },
    }
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

--An ability card for the detail pane, top-aligned.
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
                children[#children+1] = gui.Label{ classes = { "eotwbSection" }, text = "At 1st level" }
            end
            for _,entry in ipairs(features) do
                local feature = entry.feature
                local name = Field(feature, "name") or "Feature"
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

--What the detail pane shows for one option of a choice row. A kit shows
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
                    return kit:Render({ width = DETAIL_WIDTH - 60 }, {})
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
    lines[#lines+1] = "Taking this culture sets:"
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
        lines[#lines+1] = string.format("**Language:** %s", language.name)
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
    local detail
    local footer
    local messageLabel
    local themeHandler = nil

    local state = {
        step = nil,
        --a characteristic picked as the first half of a swap
        swapAttr = nil,
        --what the detail pane shows; nil = the step's own overview
        detail = nil,
        message = "",
        --true after Fill in the Rest filled this page: the button then offers
        --to fill every other tab too. Any other action disarms it.
        fillAllArmed = false,
        --the page's blocks by key: {signature, panel} (see BuildPage)
        blocks = {},
        stepperSignature = nil,
        summarySignature = nil,
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
            state.message = "Something went wrong: " .. tostring(err)
            printf("EotW builder: %s", tostring(err))
        end
        Refresh(false)
    end

    --- detail pane ---

    local function ShowDetail(d)
        state.detail = d
        if detail == nil or not detail.valid then
            return
        end
        d = d or {}

        --Art mode (a class): the art fills the pane and the text sits on a
        --darkened band over its lower part, as the old builder showed it.
        if d.art ~= nil and d.art ~= "" then
            ---@type Panel[]
            local overlay = {}
            if d.title ~= nil then
                overlay[#overlay+1] = gui.Label{ classes = { "eotwbHeading" }, text = d.title, fontSize = 30, width = "100%", bmargin = 8 }
            end
            if d.text ~= nil and d.text ~= "" then
                overlay[#overlay+1] = Text(d.text, { "eotwbText" }, { fontSize = 16 })
            end
            detail.children = {
                gui.Panel{
                    width = "100%",
                    height = "100%",
                    bgimage = d.art,
                    bgcolor = "white",
                    cornerRadius = 8,
                    --Crop only once both the image and the panel's size are
                    --known: imageLoaded can come before layout, or never (an
                    --image already cached), so a short think retries it.
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
                    children = {
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            maxHeight = 560,
                            valign = "bottom",
                            flow = "vertical",
                            vscroll = true,
                            bgimage = "panels/square.png",
                            bgcolor = "#10110Fe6",
                            pad = 18,
                            rpad = 26,
                            borderBox = true,
                            children = overlay,
                        },
                    },
                },
            }
            return
        end

        ---@type Panel[]
        local children = {}
        if d.image ~= nil and d.image ~= "" then
            children[#children+1] = gui.Panel{
                width = "auto",
                height = "auto",
                maxWidth = 320,
                maxHeight = 360,
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
            children[#children+1] = gui.Label{
                classes = { "eotwbHeading" },
                text = d.title,
                fontSize = 26,
                width = "100%",
                bmargin = 8,
            }
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
        local body = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vscroll = true,
            pad = 18,
            rpad = 26,
            borderBox = true,
            children = children,
        }
        detail.children = { body }
        SetScroll(body, 1)
    end

    --The detail for a step when nothing is hovered: the chosen main pick,
    --or the step's overview.
    local function DefaultDetail(tok, stepid)
        local id = CurrentBaseId(tok, stepid)
        if stepid == "complication" and id == NO_COMPLICATION then
            return { title = "No Complication", text = "Your hero takes no complication. You can come back and choose one at any time before you finish." }
        end
        local item = BaseItem(stepid, id)
        if item ~= nil then
            return EotwBuilder.ItemDetail(stepid, item)
        end
        local step = EotwBuild.STEP_BY_ID[stepid]
        return { title = step.title, text = StepOverview(stepid) }
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
                sub = "Needs attention"
            elseif stepStatus.optional then
                sub = "Optional"
            elseif stepStatus.complete then
                sub = "Done"
            elseif stepStatus.filled == 0 then
                sub = "Not started"
            else
                sub = string.format("%d left", left)
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
                    state.detail = nil
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
            complication = "None"
        end


        --only the lines are rebuilt: the hero card is made once and repaints
        --itself (rebuilding it made it flicker on every pick).
        local signature = string.format("%s|%s|%s|%s", tostring(cultureName), career and career.name or "", table.concat(kitNames, ","), complication)
        if signature == state.summarySignature and #summaryLines.children > 0 then
            return
        end
        state.summarySignature = signature
        Line("Culture", cultureName)
        Line("Career", career and career.name or nil)
        Line("Kit", table.concat(kitNames, ", "))
        Line("Complication", complication)
        summaryLines.children = lines
    end

    --- the page ---

    --The cards for a step's main pick.
    local function BaseCards(tok, stepid, options, width)
        local current = CurrentBaseId(tok, stepid)
        local cards = {}
        for _,entry in ipairs(options) do
            local id = entry.id
            cards[#cards+1] = Card{
                text = entry.name,
                selected = current == id,
                width = width,
                --Previews only while nothing is chosen, and the preview stays
                --after the pointer leaves. Once something is chosen the pane
                --stays on it. (No Complication is a default, not a choice, so
                --complications can still be previewed over it.)
                hover = function()
                    if current ~= nil and current ~= NO_COMPLICATION then
                        return
                    end
                    if id == NO_COMPLICATION then
                        ShowDetail({ title = "No Complication", text = "Take no complication. Complications are optional: each gives a benefit and a drawback." })
                    else
                        ShowDetail(EotwBuilder.ItemDetail(stepid, entry.item))
                    end
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
                        state.detail = nil
                        state.message = ""
                        Act(function(t2) SetBase(t2, stepid, id) end)
                    end
                    if current ~= nil and EotwBuild.HasDependentPicks(t, stepid) then
                        EotwBuilder.Confirm(root, {
                            title = string.format("Change %s?", step.title),
                            message = string.format("This clears the choices you made for your current %s.", string.lower(step.title)),
                            confirm = "Change",
                            onConfirm = Apply,
                        })
                    else
                        Apply()
                    end
                end,
            }
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
                        text = (info.description or attrid) .. cond(locked, " (fixed)", ""),
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
                Text("Drag one characteristic onto another (or click both) to swap their values. Characteristics marked fixed are set by your class.", { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
            },
        }
    end

    --One choice block: header, description, and the option chips.
    --options/info come from EotwBuild.RowOptions.
    local function RowBlock(tok, stepid, row, options, info)

        local statusText
        local statusClass = nil
        if #row.stale > 0 then
            statusText = "A pick here is no longer valid. Choose again, or use Fill in the rest."
            statusClass = "stale"
        elseif row.complete then
            statusText = cond(row.exhausted, "Nothing left to choose", "Done")
            statusClass = "done"
        elseif info.costsPoints then
            statusText = string.format("%d %s to spend", row.remaining, info.pointsName)
        elseif row.remaining == info.numChoices then
            statusText = cond(info.numChoices == 1, "Choose one", string.format("Choose %d", info.numChoices))
        else
            statusText = string.format("Choose %d more", row.remaining)
        end

        local isCharacteristics = row.guid == "characteristics"
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
                width = cond(isCharacteristics, 150, 220),
                height = 44,
                fontSize = 15,
                hover = function()
                    ShowDetail(OptionDetail(entry, info))
                end,
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

        blocks[#blocks+1] = gui.Label{ classes = { "eotwbSection" }, text = "Name" }
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
                    placeholderText = "Your hero's name",
                    characterLimit = 60,
                    fontSize = 22,
                    width = 460,
                    height = 44,
                    editlag = 0.5,
                    edit = SetNameFrom,
                    change = SetNameFrom,
                },
                gui.Button{
                    text = "Suggest a Name",
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
                            state.message = "This ancestry has no name list. Type a name instead."
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
                gui.Tooltip("Drag to move the portrait within its frame. Scroll to zoom.")(element)
            end,
            --The wheel drives the Zoom slider: each notch moves it 5%, and a
            --whole spin settles into one upload rather than one per notch.
            wheel = function(element, delta)
                local t = Tok()
                if t == nil or zoomSlider == nil or not zoomSlider.valid then
                    return true
                end
                local current = zoomSlider.value or 1
                local newZoom = current + 0.05 * delta
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

        blocks[#blocks+1] = gui.Label{ classes = { "eotwbSection" }, text = "Portrait" }
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
                        Text("Your class's art is your portrait until you choose another. Click the image to the right to pick or upload your own.", { "eotwbText", "muted" }, { fontSize = 15, bmargin = 10 }),
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            children = {
                                gui.Button{
                                    text = "Use Class Art",
                                    fontSize = 18,
                                    width = 190,
                                    height = 44,
                                    rmargin = 10,
                                    click = function()
                                        local t = Tok()
                                        local classItem = t and (t.properties --[[@as character]]):GetClass() or nil
                                        SetPortraitTo(classItem and classItem:try_get("portraitid", "") or nil, "Choose a class first: its art is the default portrait.", true)
                                    end,
                                },
                                gui.Button{
                                    text = "Use Ancestry Art",
                                    fontSize = 18,
                                    width = 190,
                                    height = 44,
                                    rmargin = 10,
                                    click = function()
                                        local t = Tok()
                                        local race = t and EotwBuild.hero.Ancestry(t.properties --[[@as character]]) or nil
                                        SetPortraitTo(race and race:try_get("portraitid", "") or nil, "Choose an ancestry with art first.")
                                    end,
                                },
                                gui.IconEditor{
                                    library = cond(dmhub.GetSettingValue("popoutavatars"), "popoutavatars", "Avatar"),
                                    restrictImageType = "Avatar",
                                    allowPaste = true,
                                    borderColor = C.TAN,
                                    borderWidth = 2,
                                    cornerRadius = 6,
                                    width = 96,
                                    height = 96,
                                    bgcolor = "white",
                                    linger = function(element)
                                        gui.Tooltip("Choose a portrait from the library, or upload your own.")(element)
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
                        gui.Label{ classes = { "eotwbText", "muted" }, text = "Zoom", fontSize = 15, tmargin = 14 },
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
                            text = "Reset Placement",
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
                        gui.Label{ classes = { "eotwbSection" }, text = "Frame" },
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
                        Text("The frame around your hero's token.", { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
                    },
                },
                gui.Panel{
                    width = 360,
                    height = "auto",
                    flow = "vertical",
                    children = {
                        gui.Label{ classes = { "eotwbSection" }, text = "Anthem" },
                        anthemEditor,
                        gui.Label{ classes = { "eotwbText", "muted" }, text = "Volume", fontSize = 14, tmargin = 6 },
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
                        Text("Music that plays when your hero takes their turn. Optional.", { "eotwbText", "muted" }, { fontSize = 14, tmargin = 6 }),
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
            lines[#lines+1] = string.format("*%s skill*", category.text)
        end
        if entry.dead then
            lines[#lines+1] = "*A dead language: no one speaks it any more, but its writing can still be read.*"
        end
        if entry.speakers ~= nil then
            lines[#lines+1] = string.format("**%s:** %s", cond(entry.dead, "Once spoken by", "Spoken by"), entry.speakers)
        end
        if type(entry.description) == "string" and entry.description ~= "" then
            lines[#lines+1] = entry.description
        end
        lines[#lines+1] = ""
        if entry.state == "native" then
            lines[#lines+1] = "**Your native language** (chosen with your culture)."
        elseif entry.state == "fixed" then
            lines[#lines+1] = string.format("**You know this %s already** from %s.", kind, entry.source or "another of your features")
        elseif entry.state == "selected" then
            lines[#lines+1] = "**Picked.** Click to drop it."
        elseif entry.state == "selectable" then
            lines[#lines+1] = "**Available.** Click to pick it."
        else
            lines[#lines+1] = "**Not available:** none of your remaining choices can take it."
        end
        if #entry.pools > 0 and entry.state ~= "native" and entry.state ~= "fixed" then
            lines[#lines+1] = "Can be picked for: " .. table.concat(entry.pools, ", ")
        end
        if entry.special ~= nil then
            lines[#lines+1] = ""
            lines[#lines+1] = "**Special:** your " .. table.concat(entry.special, ", ") .. " gives you a benefit with this skill."
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
            notes[#notes+1] = "dead"
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
                interactable = false,
            },
        }
        if entry.special ~= nil then
            children[#children+1] = gui.Panel{
                floating = true,
                width = 16,
                height = 16,
                halign = "right",
                valign = "top",
                x = -4,
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
            hover = function()
                ShowDetail(PoolEntryDetail(kind, entry))
            end,
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
            local status = cond(pool.remaining == 0, "Done", string.format("%d left", pool.remaining))
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 3,
                children = {
                    gui.Label{ classes = { "eotwbText", "muted" }, text = string.format("%s (%s)", step and step.title or "", kindName), width = 220, fontSize = 15 },
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
            rows[1] = Text("You have no skills or languages to pick yet. They come from your ancestry, culture, career and class.", { "eotwbText", "muted" }, { fontSize = 15 })
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
            lines[#lines+1] = "**You gain:** " .. table.concat(grants.fixed, ", ")
        end
        for _,pool in ipairs(grants.pools) do
            lines[#lines+1] = string.format("**%s:** %s", pool.name, pool.description or "")
        end
        local children = {
            gui.Label{ classes = { "eotwbText" }, text = "Skills & Languages", fontSize = 18, bold = true, color = "#bfe0f0ff" },
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
                return gui.Label{ classes = { "eotwbSection" }, text = "Skills" }
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
                        gui.Label{ classes = { "eotwbSection" }, text = "Languages" },
                        Text(nativeItem and string.format("Your native language is **%s**, from your culture.", nativeItem.name) or "Choose your native language on the Culture step.", { "eotwbText", "muted" }, { fontSize = 15, bmargin = 4 }),
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
                    return gui.Label{ classes = { "eotwbSection" }, text = "Or build your own culture from three aspects" }
                end)
            elseif step.base ~= nil then
                local baseRow = stepStatus.rows[1]
                local optional = baseRow ~= nil and baseRow.optional == true
                local done = baseRow ~= nil and baseRow.complete and not optional
                local statusText = cond(optional, "Optional", cond(done, "Done", "Choose one"))
                Add("baseheader", statusText, function()
                    return gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        children = {
                            gui.Label{ classes = { "eotwbSection" }, text = string.format("Choose your %s", string.lower(step.base)), width = "auto" },
                            gui.Label{ classes = Classes("eotwbStatus", { done = done }), text = statusText, valign = "center", lmargin = 14, tmargin = 12 },
                        },
                    }
                end)
                Add("basecards", current, function()
                    local options = EotwBuild.BaseOptions(hero, stepid)
                    if stepid == "complication" then
                        table.insert(options, 1, { id = NO_COMPLICATION, name = "No Complication" })
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
                                return gui.Label{ classes = { "eotwbSection" }, text = "Your choices" }
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
        fillButton.text = cond(state.fillAllArmed, "For All Tabs?", "Fill in the Rest")
        fillButton:SetClass("disabled", not state.fillAllArmed and stepStatus.complete and not stepStatus.stale)
        if index == #EotwBuild.STEPS then
            nextButton.text = "Finish"
        elseif stepStatus.complete then
            nextButton.text = "Next"
        else
            nextButton.text = "Skip for Now"
        end
        messageLabel.text = state.message or ""
        state.allComplete = status.complete
        if closeButton ~= nil and closeButton.valid then
            closeButton.text = cond(status.complete, "Finish", "Save and Close")
        end
    end

    --- refresh ---

    --Redraw everything from the character. newStep: the page is a different
    --step than before (scroll to the top, show the step's own detail).
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
        BuildPage(tok, status.steps[StepIndex(state.step)], not newStep)
        if newStep or state.detail == nil then
            ShowDetail(DefaultDetail(tok, state.step))
        end
        UpdateFooter(status)
    end

    --Redraw the stepper, the hero summary and the footer, but not the page.
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
        UpdateFooter(status)
    end

    GoTo = function(stepid)
        state.step = stepid
        state.detail = nil
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
        width = string.format("100%%-%d", SUMMARY_WIDTH + DETAIL_WIDTH + 40),
        height = "100%",
        hmargin = 20,
        flow = "vertical",
        children = { pageHeader, page },
    }

    --holds either a scrolling body or the full-bleed art view (ShowDetail).
    detail = gui.Panel{
        classes = { "eotwbColumn" },
        bgimage = "panels/square.png",
        width = DETAIL_WIDTH,
        height = "100%",
        flow = "vertical",
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
        text = "Back",
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
        text = "Fill in the Rest",
        fontSize = 20,
        width = 220,
        height = 48,
        hmargin = 8,
        linger = function(element)
            if state.fillAllArmed then
                gui.Tooltip("Fill every choice you have not made yet on all the other tabs too, completing the hero. Your own choices are kept.")(element)
            else
                gui.Tooltip("Fill every choice on this page you have not made yet with a sensible default or a random pick. Your own choices are kept.")(element)
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
                state.message = "Something went wrong: " .. tostring(picks)
                printf("EotW builder: %s", tostring(picks))
            elseif picks == nil or #picks == 0 then
                state.message = cond(allTabs, "Nothing left to fill.", "Nothing left to fill on this page.")
            else
                state.message = string.format("Filled %d choice%s%s.", #picks, cond(#picks == 1, "", "s"), cond(allTabs, " across all tabs", ""))
            end
            --UpdateFooter disarms it again once the whole hero is complete.
            state.fillAllArmed = ok and not allTabs
            state.detail = nil
            state.swapAttr = nil
            --the Appearance page's inputs show the filled name, so rebuild it.
            Refresh(state.step == "appearance")
        end,
    }

    nextButton = gui.Button{
        text = "Next",
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
            state.message = "Still to do: " .. table.concat(names, ", ") .. "."
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
                            gui.Label{ classes = { "eotwbHeading" }, text = args.title or "Create Your Hero", fontSize = 30, valign = "center", tmargin = 30 },
                            gui.Label{ classes = { "eotwbText", "muted" }, text = "Level 1 hero for Blackbottom", fontSize = 15, width = "auto" },
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
                                text = "Save and Close",
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
                                        gui.Tooltip("Your hero is complete. Finish and add them to your roster.")(element)
                                    else
                                        gui.Tooltip("Keep this hero as a draft and come back to it later from the Hero's Guild.")(element)
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
            --body: summary | page | detail
            gui.Panel{
                width = "100%-32",
                height = string.format("100%%-%d", HEADER_HEIGHT + FOOTER_HEIGHT),
                halign = "center",
                flow = "horizontal",
                children = { summary, pageColumn, detail },
            },
            footer,
        },
    }

    args.host:AddChild(root)

    themeHandler = ThemeEngine.OnThemeChanged(mod, function()
        if root ~= nil and root.valid then
            root.styles = BuilderStyles()
        end
    end)

    state.step = args.step
    Refresh(true)
    return root
end

--What the detail pane shows for a main-pick item: its art, name and text
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
                                text = args.confirm or "Confirm",
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
                                text = "Cancel",
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

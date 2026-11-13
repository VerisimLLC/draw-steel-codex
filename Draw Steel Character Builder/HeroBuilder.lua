local mod = dmhub.GetModLoading()

--The Hero Builder: the main game's Builder for Heroes, shown in the Hero
--sheet window at full size in place of the sheet (HeroSheet.lua opens it
--from the Builder button). It lays out at the screen size divided by Font
--Size, so it keeps one arrangement on every common screen:
--  * the title row: Create / Edit Your Hero, the Hero's name with Build at
--    Level (and Slow start at Level 1), then Undo and Back to the sheet;
--  * the stepper: one pill per step, saying what is done or left;
--  * the body: the live card alone on the left (HeroSheetCard.BuilderCard),
--    the step's page, and the picks pane, "Your <step>"; every option
--    and pick has an (i) that shows it in full;
--  * the footer: Back, a message line, Fill in the rest (it shows what
--    it would choose first), and Next (Skip for now while the step has
--    picks left; Finish on Review, which returns to the sheet).
--The rules behind every step are the shared build engine's
--(HeroBuild.main, Draw Steel V/HeroBuildPools.lua). Every write goes through
--the host (HeroSheetWrite in the sheet), so picks save as you go, one
--undo step each. Where it shows comes from its host (HeroBuilderHost).
--The older Builder tab (CharacterBuilder) stays for everyone but Heroes.

local T = UIText.T
local TP = UIText.Plural

HeroBuilder = rawget(_G, "HeroBuilder") or {}

--Spacing, in Builder units.
local PAD_X = 24
local PAD_TOP = 18
local PAD_BOTTOM = 18
--the title row sits on a plate (text on the frosted glass is unreadable
--over a light table), so it is a little taller than a bare row.
local HEAD_ROW_HEIGHT = 64
local STEPPER_GAP = 10
local STEPPER_HEIGHT = 45
local PILL_GAP = 6
--between the stepper and the body, and the body and the footer.
local BODY_GAP = 14
local COLUMN_GAP = 20
local FOOTER_HEIGHT = 64
--The footer's message line; FitLinks keeps its lists within two lines of it.
local MESSAGE_WIDTH = 600
local FOOTER_BUTTON_WIDTH = 150
--A slow-start page's Finish is wider, to fit its longer words ("Finish
--Second Encounter").
local FINISH_RUNG_WIDTH = 206
--Review: the banner under the stepper, and the gaps around it.
local REVIEW_GAP = 10
local BANNER_HEIGHT = 44

--The Review step closes the stepper; it is the Builder's, not the engine's.
local REVIEW = "review"

--Each step's lead under its title.
local LEADS = {
    ancestry = T("herobuilder.lead.ancestry"),
    culture = T("herobuilder.lead.culture"),
    career = T("herobuilder.lead.career"),
    class = T("herobuilder.lead.class"),
    skills = T("herobuilder.lead.skills"),
    complication = T("herobuilder.lead.complication"),
    other = T("herobuilder.lead.other"),
}

--The Class step's lead once a class is chosen: the hover is
--then the live card's, and the (i) compares.
local CLASS_LEAD_PICKED = T("herobuilder.lead.class_picked")

--Slow start's rungs: the four encounters of a slow start (as
--HeroBuild.main.RUNGS: this file loads before the build engine).
local RUNGS = {T("herobuilder.rung.first"), T("herobuilder.rung.second"), T("herobuilder.rung.third"), T("herobuilder.rung.fourth")}

--- What the Builder needs from where it is shown: the Hero, the writes,
--- the repaint, the Appearance surface and the build engine. The Hero sheet
--- window is the default host (HeroBuilder.SheetHost); the EotW town passes
--- its own.
--- @class HeroBuilderHost
--- @field token fun(): nil|CharacterToken the Hero the Builder shows
--- @field canWrite fun(): boolean whether this player may change that Hero
--- @field save fun(args: HeroSheetSaveArgs): boolean one change to the Hero, as one undo step; false when nothing was written
--- @field saveAppearance fun(mutate: fun(token: CharacterToken)): boolean a change to the token's appearance (name, portrait)
--- @field changed fun() after a write: what follows the Hero repaints
--- @field block fun(panelArgs: table, spec: HeroSheetBlockSpec): Panel a panel that repaints when the Hero's build changes
--- @field drawn fun(panel: Panel) the block was just painted by hand: it is up to date
--- @field lendAppearance fun(): nil|HeroAppearanceView the Appearance surface for the Appearance step
--- @field returnAppearance fun() the step is done with the surface
--- @field engine nil|HeroBuildEngine the build rules; nil for the main game's (HeroBuild.main)

--- The Hero sheet window as the Builder's host.
--- @type HeroBuilderHost
HeroBuilder.SheetHost = {
    token = function() return HeroSheet.Token() end,
    canWrite = function() return HeroSheetWrite.CanWrite() end,
    save = function(args) return HeroSheetWrite.Save(args) end,
    saveAppearance = function(mutate) return HeroSheetWrite.SaveAppearance(mutate) end,
    changed = function() HeroSheetRefresh.Changed() end,
    block = function(panelArgs, spec) return HeroSheetRefresh.Block(panelArgs, spec) end,
    drawn = function(panel) HeroSheetRefresh.Drawn(panel) end,
    lendAppearance = function() return HeroSheet.LendAppearance() end,
    returnAppearance = function() HeroSheet.ReturnAppearance() end,
}

--The host of the Builder on screen. One Builder shows at a time (the main
--game's Builder or Level up, or EotW's in its town), so the one that opens
--sets it; the file's helpers read it through Host() and Engine().
--- @type nil|HeroBuilderHost
local g_host = nil

--- @return HeroBuilderHost
local function Host()
    return g_host or HeroBuilder.SheetHost
end

--- The build engine of the Builder on screen.
--- @return HeroBuildEngine
local function Engine()
    return Host().engine or HeroBuild.main
end

--- 2 as "2nd", for the Level headings ("2nd-Level Features").
--- @param number integer
--- @return string
local function Ordinal(number)
    local tens = number % 100
    if tens >= 11 and tens <= 13 then
        return T("herobuilder.ordinal.th", {number = number})
    end
    local last = number % 10
    if last == 1 then
        return T("herobuilder.ordinal.st", {number = number})
    elseif last == 2 then
        return T("herobuilder.ordinal.nd", {number = number})
    elseif last == 3 then
        return T("herobuilder.ordinal.rd", {number = number})
    end
    return T("herobuilder.ordinal.th", {number = number})
end

--- Level up's step for a Level: one page per Level waiting.
--- @param level integer
--- @return string
local function LevelStepId(level)
    return "level" .. tostring(level)
end

--- The card column's and picks pane's widths for a body this wide: 300 and
--- 340 at 1371 units, 380 and 440 at 1920; the page takes the rest.
--- @param bodyW number
--- @return number card
--- @return number detail
local function ColumnWidths(bodyW)
    local card = math.max(300, math.min(400, math.floor(bodyW * 0.203)))
    local detail = math.max(340, math.min(460, math.floor(bodyW * 0.235)))
    return card, detail
end

--Other choices: choices an item or another feature asks for; a step
--of its own before Review, shown only while there is one.
local OTHER = "other"

--- Level up's step for a slow-start rung's page.
--- @param rung integer 2-4
--- @return string
local function RungStepId(rung)
    return "rung" .. tostring(rung)
end

--- Level up's step for one of its pages (HeroBuildPage).
--- @param page {level: integer, rung: nil|integer}
--- @return string
local function PageStepId(page)
    if page.rung ~= nil then
        return RungStepId(page.rung)
    end
    return LevelStepId(page.level)
end

--- @class HeroBuilderStep
--- @field id string
--- @field title string the pill's name
--- @field level nil|integer Level up: the page's Level (1 for the slow start's)
--- @field rung nil|integer Level up: the slow-start rung (2-4)
--- @field key nil|integer Level up: the page's place (Engine().PageKey)

--- The steps in the stepper: the engine's, Other choices, then Review.
--- Level up's are its pages: the slow start's 2nd to 4th rungs and the rest
--- of the 1st Level, then the 2nd to the 10th Level, "2nd Level"; only
--- the pages waiting show.
--- @param levelUp boolean
--- @return HeroBuilderStep[]
local function Steps(levelUp)
    local steps = {}
    if levelUp then
        for rung = 2, 4 do
            steps[#steps+1] = {id = RungStepId(rung), title = RUNGS[rung], level = 1, rung = rung, key = Engine().PageKey(1, rung)}
        end
        for level = 1, 10 do
            steps[#steps+1] = {id = LevelStepId(level), title = T("herobuilder.levelup.step_title", {ordinal = Ordinal(level)}), level = level, key = Engine().PageKey(level, nil)}
        end
        return steps
    end
    for _, step in ipairs(Engine().STEPS) do
        steps[#steps+1] = {id = step.id, title = step.title}
    end
    steps[#steps+1] = {id = OTHER, title = T("herobuilder.steps.other")}
    steps[#steps+1] = {id = REVIEW, title = T("herobuilder.steps.review")}
    return steps
end

--- The build data the engine's status reads: when it is unchanged, the last
--- status still holds (working it out is slow for a high-Level Hero).
--- @param token CharacterToken
--- @return string
local function BuildKey(token)
    local props = token.properties
    return table.concat({
        dmhub.ToJson(props:GetLevelChoices() or {}),
        dmhub.ToJson(props:try_get("classes", {})),
        tostring(props:try_get("raceid")), tostring(props:try_get("subraceid")), tostring(props:try_get("backgroundid")),
        dmhub.ToJson(props:try_get("complications", {})),
        tostring(props:try_get(Engine().NO_COMPLICATION_FIELD)),
        tostring(props:try_get("kitid")), tostring(props:try_get("kitid2")),
        dmhub.ToJson(props:try_get("culture") or {}),
        dmhub.ToJson(props:try_get("attributeBuild") or {}),
        tostring(props:CharacterLevel()), dmhub.ToJson(props:try_get("extraLevelInfo") or {}),
        tostring(token.name), tostring(token.portrait),
        --not built here, but they offer choices (Titles and Other choices)
        --and make skills and languages known: a change must show here too.
        dmhub.ToJson(props:try_get("titles", {})), dmhub.ToJson(props:try_get("characterFeatures", {})),
        dmhub.ToJson(props:try_get("creatureFeats", {})), dmhub.ToJson(props:try_get("creatureTemplates", {})),
        tostring(props:try_get("chartypeid")), dmhub.ToJson(props:try_get("innateLanguages", {})),
        --a treasure pick (Amnesia's, Secret Twin's) is stored here, not in levelChoices.
        dmhub.ToJson(props:try_get("treasureGrants", {})),
        --a compendium edit can change what a step offers.
        tostring(dmhub.tablesUpdateId),
    }, "|")
end

--The status of the open Hero's build, kept while its build data stays the same.
--- @type {charid: nil|string, key: nil|string, status: nil|table}
local g_status = {charid = nil, key = nil, status = nil}

--- @param token CharacterToken
--- @return table status as Engine().Status gives it, with .other: the Other choices step's status, or nil when nothing asks
local function Status(token)
    local key = BuildKey(token)
    if g_status.charid ~= token.charid or g_status.key ~= key or g_status.status == nil then
        local status = Engine().Status(token)
        local other = Engine().StepStatus(token, OTHER)
        if other ~= nil and #other.rows > 0 then
            other.title = T("herobuilder.steps.other")
            status.other = other
        end
        --picks held above the Hero's Level, for the Class page.
        status.kept = Engine().hero.KeptPicks(token.properties --[[@as character]])
        g_status = {charid = token.charid, key = key, status = status}
    end
    return g_status.status --[[@as table]]
end

--- What a done step's pill names: the pick, or "N picked" for skills.
--- @param token CharacterToken
--- @param stepStatus table
--- @return string
local function PickText(token, stepStatus)
    local hero = token.properties --[[@as character]]
    local id = stepStatus.id
    if id == "culture" then
        local culture = hero:try_get("culture")
        local names = {}
        if culture ~= nil then
            local aspects = dmhub.GetTableVisible(CultureAspect.tableName) or {}
            for _, cat in ipairs(CultureAspect.categories) do
                local aspect = aspects[(culture.aspects or {})[cat.id] or ""]
                if aspect ~= nil then
                    names[#names+1] = aspect.name
                end
            end
        end
        return table.concat(names, ", ")
    elseif id == "class" then
        local classItem = hero:GetClass()
        local names = {classItem ~= nil and classItem.name or nil}
        for _, sub in ipairs(hero:GetSubclasses() or {}) do
            names[#names+1] = sub.name
        end
        return table.concat(names, ", ")
    elseif id == "skills" then
        local picked = 0
        for _, row in ipairs(stepStatus.rows) do
            picked = picked + #(row.selectedNames or {})
        end
        return T("herobuilder.pill.picked", {count = string.format("%d", picked)})
    elseif id == "appearance" then
        return token.name or ""
    end
    --the main pick's names: the ancestry, the career, the complications.
    local base = stepStatus.rows[1]
    if base ~= nil and base.base then
        local names = {}
        for _, name in ipairs(base.selectedNames or {}) do
            names[#names+1] = HeroBuild.SaidName(name)
        end
        return table.concat(names, ", ")
    end
    return ""
end

--- Picks still to make on a step. The inciting incident is optional:
--- story only, it never counts.
--- @param stepStatus table
--- @return integer
local function PicksLeft(stepStatus)
    local left = 0
    for _, row in ipairs(stepStatus.rows) do
        if not row.complete and row.category ~= "Incident" then
            left = left + math.max(1, row.remaining or 1)
        end
    end
    return left
end

--- The step the Builder opens on: the first with picks left or a
--- stale pick, else the first step.
--- @param status table
--- @return string
local function FirstOpenStep(status)
    for _, stepStatus in ipairs(status.steps) do
        if stepStatus.stale or PicksLeft(stepStatus) > 0 then
            return stepStatus.id
        end
    end
    return status.steps[1].id
end

--- How a step's pill reads: its state ("done", "todo", "optional",
--- "stale" or "plain") and the line under its name.
--- @param token CharacterToken
--- @param stepStatus nil|table nil for Review
--- @return string state
--- @return string sub
local function PillState(token, stepStatus)
    if stepStatus == nil then
        return "plain", T("herobuilder.pill.before_finish")
    end
    if stepStatus.stale then
        return "stale", T("herobuilder.pill.needs_attention")
    end
    local left = PicksLeft(stepStatus)
    if left > 0 then
        return "todo", T("herobuilder.status.left", {count = string.format("%d", left)})
    end
    --Skills & Languages before any step has given a choice (a new Hero).
    if stepStatus.id == "skills" and #stepStatus.rows == 0 then
        return "todo", T("herobuilder.status.to_choose")
    end
    if stepStatus.id == "complication" and stepStatus.optional then
        return "optional", T("herobuilder.status.optional")
    end
    return "done", PickText(token, stepStatus)
end

----------------------------------------------------------------------
--The Builder's look: the sheet's palette (HeroSheetTheme) on its own parts.

--- @return table[]
local function BuilderRules()
    local palette = HeroSheetTheme.Palette()
    local see = HeroSheetTheme.SeeThrough()
    local plate = HeroSheetTheme.WithAlpha(palette.plate, 1)
    local function Alpha(hex, alpha)
        return HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(hex, 1), alpha)
    end
    --the plate mixed toward the card's foreground: solid, since see-through
    --fills blend lighter than intended.
    local fgColor = HeroSheetTheme.ParseHex(palette.cardFg) or plate
    local function Tint(amount, alpha)
        return HeroSheetTheme.ToHex(HeroSheetTheme.Mix(plate, fgColor, amount), alpha)
    end
    return {
        --step pills: near-black plates; the open step lighter, cream-edged.
        {selectors = {"heroBuilderPill"}, bgcolor = HeroSheetTheme.ToHex(plate, cond(see, 0.88, 1)), borderColor = "#ffffff1f"},
        {selectors = {"heroBuilderPill", "hover"}, borderColor = Alpha(palette.strong, 0.5)},
        {selectors = {"heroBuilderPill", "selected"}, bgcolor = HeroSheetTheme.ToHex(HeroSheetTheme.Mix(plate, HeroSheetTheme.ParseHex("#ffffff") or plate, 0.12), cond(see, 0.95, 1)), borderColor = palette.strong},
        --the step's mark: a tick when done, its number otherwise.
        {selectors = {"heroBuilderMark"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroBuilderMark", "done"}, bgcolor = Alpha(palette.rawSuccess, 0.18), borderColor = Alpha(palette.rawSuccess, 0.6)},
        {selectors = {"heroBuilderMark", "todo"}, bgcolor = palette.rawInfo, borderColor = palette.rawInfo},
        {selectors = {"heroBuilderMark", "stale"}, bgcolor = Alpha(palette.rawDanger, 0.18), borderColor = palette.rawDanger},
        {selectors = {"heroBuilderMarkText"}, color = palette.muted},
        {selectors = {"heroBuilderMarkText", "todo"}, color = palette.bg},
        {selectors = {"heroBuilderMarkText", "stale"}, color = palette.danger},
        {selectors = {"heroBuilderTick"}, bgcolor = palette.success},
        {selectors = {"heroBuilderPillSub"}, color = palette.muted},
        {selectors = {"heroBuilderPillSub", "done"}, color = palette.success},
        {selectors = {"heroBuilderPillSub", "todo"}, color = palette.info},
        {selectors = {"heroBuilderPillSub", "stale"}, color = palette.danger},

        --a page section's heading: tan capitals over a faint tan rule, with
        --its state on a small plate: done in @success, to choose in @info.
        {selectors = {"heroBuilderCaps"}, color = palette.cardLabel},
        {selectors = {"heroBuilderRule"}, bgcolor = Alpha(palette.cardLabel, 0.35)},
        {selectors = {"heroBuilderStatus"}, bgcolor = "#ffffff0d", borderColor = palette.border, color = palette.muted},
        {selectors = {"heroBuilderStatus", "ok"}, bgcolor = Alpha(palette.rawSuccess, 0.1), borderColor = Alpha(palette.rawSuccess, 0.45), color = palette.success},
        {selectors = {"heroBuilderStatus", "go"}, bgcolor = Alpha(palette.rawInfo, 0.1), borderColor = Alpha(palette.rawInfo, 0.45), color = palette.info},
        {selectors = {"heroBuilderTileArt"}, bgcolor = "#2a2620ff", borderColor = "#000000ff", color = palette.cardLabel},
        --the tile whose art fills the pane before a pick is outlined.
        {selectors = {"heroBuilderTileArt", "heroBuilderShown"}, borderColor = palette.cardStrong},
        --option cards: open ones raised (a faint fill and edge of
        --the card's foreground); a picked one filled with it, every word in
        --the background colour; one that cannot be picked flat, no fill or
        --edge, its words muted (still 4.5:1).
        {selectors = {"heroBuilderCard"}, bgcolor = Tint(0.075, cond(see, 0.9, 1)), borderColor = Tint(0.42)},
        {selectors = {"heroBuilderCard", "hover"}, bgcolor = Tint(0.13, cond(see, 0.9, 1)), borderColor = palette.cardStrong},
        {selectors = {"heroBuilderCard", "selected"}, bgcolor = palette.cardFg, borderColor = palette.cardFg},
        {selectors = {"heroBuilderCard", "selected", "hover"}, bgcolor = palette.cardStrong, borderColor = palette.cardStrong},
        --flat: no fill or edge (the solid plate is for the characteristic
        --tiles only, not cards such as kits).
        {selectors = {"heroBuilderCard", "unavailable"}, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroBuilderCard", "unavailable", "hover"}, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroBuilderCardName"}, color = palette.cardStrong},
        {selectors = {"heroBuilderCardName", "selected"}, color = palette.bg},
        {selectors = {"heroBuilderCardName", "unavailable"}, color = palette.muted},
        {selectors = {"heroBuilderCardLine"}, color = palette.muted},
        {selectors = {"heroBuilderCardLine", "selected"}, color = palette.bg},
        --a picked tile: a cream frame on the art and
        --its name on a cream plate in dark words, as a picked card fills.
        {selectors = {"heroBuilderTileArt", "selected"}, borderColor = palette.cardFg},
        {selectors = {"heroBuilderTileName"}, bgcolor = "clear", color = palette.muted},
        {selectors = {"heroBuilderTileName", "selected"}, bgcolor = palette.cardFg, color = palette.bg, bold = true},
        {selectors = {"heroBuilderTileName", "heroBuilderShown"}, color = palette.strong},
        --the (i): muted, lit on hover; dark on a picked card; on art,
        --a dark disc behind it.
        {selectors = {"heroBuilderInfo"}, bgcolor = "clear"},
        {selectors = {"heroBuilderInfo", "hover"}, bgcolor = Alpha(palette.cardFg, 0.16)},
        {selectors = {"heroBuilderInfo", "selected", "hover"}, bgcolor = Alpha(palette.bg, 0.14)},
        {selectors = {"heroBuilderInfo", "heroBuilderOnArt"}, bgcolor = "#000000c7"},
        {selectors = {"heroBuilderInfo", "heroBuilderOnArt", "hover"}, bgcolor = "#000000ff"},
        {selectors = {"heroBuilderInfoIcon"}, bgcolor = palette.muted},
        {selectors = {"heroBuilderInfoIcon", "parent:hover"}, bgcolor = palette.cardStrong},
        {selectors = {"heroBuilderInfoIcon", "selected"}, bgcolor = palette.bg},
        {selectors = {"heroBuilderInfoIcon", "heroBuilderOnArt"}, bgcolor = palette.cardFg},
        --the picks pane: one block per choice, a lighter step of the
        --plate; an open choice has a gold bar down its left edge; a choice
        --that waits on the main pick is dashed and bare.
        {selectors = {"heroBuilderBlock"}, bgcolor = Tint(0.05), borderColor = palette.border},
        {selectors = {"heroBuilderBlock", "hover"}, borderColor = palette.cardSub},
        {selectors = {"heroBuilderBlock", "heroBuilderBlockWaits"}, bgcolor = "clear", borderColor = palette.border, borderStyle = "dashed"},
        {selectors = {"heroBuilderBlockBar"}, bgcolor = palette.rawInfo},
        {selectors = {"heroBuilderBlockHead"}, color = palette.cardLab},
        {selectors = {"heroBuilderBlockStatus"}, color = palette.muted},
        {selectors = {"heroBuilderBlockStatus", "ok"}, color = palette.success},
        {selectors = {"heroBuilderBlockStatus", "go"}, color = palette.info},
        {selectors = {"heroBuilderBox"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroBuilderCaret"}, bgcolor = palette.muted},
        --characteristic tiles: a free score raised like an open card,
        --a class-fixed one flat; the first of a click-swap ringed in gold.
        {selectors = {"heroBuilderCharTile"}, bgcolor = Tint(0), borderColor = palette.border},
        {selectors = {"heroBuilderCharTile", "heroBuilderCharFree"}, bgcolor = Tint(0.075, cond(see, 0.9, 1)), borderColor = Tint(0.42)},
        {selectors = {"heroBuilderCharTile", "heroBuilderCharFree", "hover"}, bgcolor = Tint(0.13, cond(see, 0.9, 1)), borderColor = palette.cardStrong},
        {selectors = {"heroBuilderCharTile", "selected"}, borderColor = palette.rawInfo, border = 2},
        --a drag: the tile it left dims, the one under the chip is edged.
        {selectors = {"heroBuilderCharTile", "heroBuilderCharDragging"}, opacity = 0.5},
        {selectors = {"heroBuilderCharTile", "heroBuilderCharOver"}, borderColor = palette.info, border = 2},
        --a stale pick's row: a faint danger plate, the old pick as a
        --danger-edged chip.
        {selectors = {"heroBuilderStaleRow"}, bgcolor = Alpha(palette.rawDanger, 0.08), borderColor = Alpha(palette.rawDanger, 0.7)},
        {selectors = {"heroBuilderStaleChip"}, bgcolor = "clear", borderColor = palette.danger, color = palette.danger},
        --picks kept for a higher Level: one dashed box per Level.
        {selectors = {"heroBuilderKeptBox"}, bgcolor = "clear", borderColor = palette.border, borderStyle = "dashed"},
    }
end

----------------------------------------------------------------------
--Parts.

--A button in the sheet's look: the title row's (38 tall, sized to its words)
--or the footer's (150 x 44).
--- @class HeroBuilderButtonArgs
--- @field text string
--- @field click fun()
--- @field footer nil|boolean the footer's size (150 x 44)
--- @field small nil|boolean a row's size (30 tall: Remove on a stale or kept pick)
--- @field tooltip nil|fun(): nil|string its tooltip, read on hover
--- @field hover nil|fun() runs when the pointer comes onto it
--- @field think nil|fun() runs twice a second while it shows

--- @param args HeroBuilderButtonArgs
--- @return Panel
local function Button(args)
    local footer = args.footer == true
    local small = args.small == true
    local label = gui.Label{
        classes = {"heroSheetButtonLabel"},
        text = args.text,
        width = "auto",
        height = "auto",
        fontSize = cond(footer, 15, cond(small, 13, 14)),
        halign = "center",
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local button = gui.Panel{
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = cond(footer, FOOTER_BUTTON_WIDTH, "auto"),
        height = cond(footer, 44, cond(small, 30, 38)),
        hpad = cond(small, 10, 14),
        borderBox = true,
        valign = "center",
        hover = function(element)
            if args.hover ~= nil then
                args.hover()
            end
        end,
        linger = function(element)
            local text = args.tooltip ~= nil and args.tooltip() or nil
            if text ~= nil then
                gui.Tooltip(text)(element)
            end
        end,
        click = function(element)
            if not element:HasClass("heroSheetDisabled") then
                args.click()
            end
        end,
        thinkTime = cond(args.think ~= nil, 0.5, nil),
        think = args.think ~= nil and function(element)
            args.think()
        end or nil,
        label,
    }
    button.data.label = label
    return button
end

--Turn History takes every undo during a combat turn and rewinds the whole
--board, not the last pick, so the Builder's Undo is off then; the Builder is
--not meant for use mid-combat.
--- @return boolean
local function TurnHistoryTakesUndo()
    local rewind = rawget(_G, "TurnRewind")
    return rewind ~= nil and rewind.UndoAvailable(dmhub.initiativeQueue) == true
end

--- A small button with the dice before its words, for a pick made at random
--- (Roll an inciting incident, Roll a complication).
--- @param text string
--- @param click fun()
--- @return Panel
local function RollButton(text, click)
    return gui.Panel{
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = 30,
        hpad = 12,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        click = function(element)
            if not element:HasClass("heroSheetDisabled") then
                click()
            end
        end,
        gui.Panel{
            classes = {"heroSheetButtonIcon"},
            bgimage = "phosphor/dice-five.png",
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 7,
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetButtonLabel"},
            text = text,
            fontSize = 13.5,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
end

--- Whether an option's name passes a list's search, in the older Builder's
--- syntax: ! or - leaves a word out, > matches the start and < the end.
--- @param name string
--- @param query string
--- @return boolean
local function SearchMatch(name, query)
    --the sign is handled here: CharacterBuilder._matchesFilter keeps a name
    --that has the word even when told to leave it out (HeroSkillsLanguages
    --works round it the same way).
    local negative = string.find(query, "^[!%-]") ~= nil
    if negative then
        query = string.sub(query, 2)
    end
    if query == "" then
        return true
    end
    local hit = nil
    local builder = rawget(_G, "CharacterBuilder")
    if builder ~= nil and builder._matchesFilter ~= nil then
        local ok, result = pcall(builder._matchesFilter, query, name)
        if ok then
            hit = result == true
        end
    end
    if hit == nil then
        hit = string.find(string.lower(name), string.lower(query), 1, true) ~= nil
    end
    return hit ~= negative
end

--- A Level dropdown in the title row's sub line.
--- @param args table gui.Dropdown args
--- @return Dropdown
local function Picker(args)
    local fields = {
        classes = {"heroSheetField"},
        height = 24,
        fontSize = 14,
        valign = "center",
        lmargin = 6,
    }
    for field, value in pairs(args) do
        fields[field] = value
    end
    return gui.Dropdown(fields)
end

--- The host's save for the Builder, raising a failure to the caller so
--- the footer can say so. The engine catches an error inside a save
--- (it logs it and drops the change), so the caller would never hear of it.
--- @param description string the undo list's words
--- @param fn fun(hero: character)
local function SaveOrRaise(description, fn)
    local failure = nil
    Host().save{
        description = description,
        execute = function(hero)
            local trace = nil
            local ok, err = xpcall(fn, function(thrown)
                trace = debug.traceback(tostring(thrown), 2)
                return thrown
            end, hero --[[@as character]])
            if not ok then
                failure = tostring(err)
                --raised again with where it happened, so the engine still
                --drops the change and its log keeps the trace.
                error(trace or failure, 0)
            end
        end,
    }
    if failure ~= nil then
        error(failure, 0)
    end
end

--- Write the Hero's Level, or a slow-start rung at Level 1, as
--- CharacterBuilder does: the Level override, and each class at that Level.
--- @param level integer
--- @param rung nil|integer 1-4 for First to Fourth Encounter
local function SetLevel(level, rung)
    SaveOrRaise(cond(rung ~= nil, T("herobuilder.undo.slow_start"), T("herobuilder.undo.build_at_level")), function(hero)
        local extra = hero:ExtraLevelInfo()
        extra.encounter = rung
        hero.extraLevelInfo = extra
        Engine().hero.SetLevel(hero, level)
        Engine().hero.MarkLevelsSeen(hero, level)
        Engine().hero.MarkRungsSeen(hero)
    end)
    Host().changed()
end

----------------------------------------------------------------------
--Step pages. A page is a list of sections, each a heading with its
--state over a grid of option cards. A page is built once for its
--shape (which sections, which options) and kept: a pick only repaints which
--cards are chosen and what the plates say; a new shape (a subclass that
--brings a choice) builds that page again.

--The older Builder's analytics (MainPanel.lua, FeatureSelector.lua): the
--same events, fields and limits, sent only while telemetry is on.
--- @param eventType string
--- @param fields table
local function Track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

--Card grids by kind: each card at least this wide, this far apart (art
--tiles; text cards; option cards 2-up on a small screen and 4-up on a
--large one; wide cards 2-up and 3-up).
local GRIDS = {
    tiles = {min = 62, gap = 5},
    text = {min = 150, gap = 6},
    cards = {min = 230, gap = 8},
    kits = {min = 230, gap = 8},
    wide = {min = 270, gap = 8},
}

--A card's second line is cut to this many characters (its detail has the
--rest): three lines on the narrowest wide card.
local LINE_CHARS = 120

--Each kind of card's one height, so cards in a grid match:
--text cards fit a two-line name, option cards a name, wide and kit cards a
--name and three lines. Art tiles are sized by their art.
local CARD_HEIGHTS = {text = 46, cards = 38, kits = 88, wide = 88}

--- @class HeroBuilderOption
--- @field id string
--- @field name string
--- @field line nil|string the card's second line
--- @field art nil|string an image id (art tiles)
--- @field selected boolean
--- @field available boolean
--- @field detail fun(): nil|HeroBuilderDetail what its (i) card shows
--- @field view nil|table the builder_ability_view fields, sent the first time its (i) card shows
--- @field arrayIndex nil|integer a characteristic array's place in the class's arrays (its pick goes by this)
--- @field impl nil|number its automation status, for options that track one
--- @field quickBuild nil|boolean the book's Quick Build pick: a star after the diamond
--- @field hoverText nil|string what a deliberate hover on the card says ("Picked. Click to drop it.")

--- @class HeroBuilderSection
--- @field key string
--- @field title string
--- @field grid string a GRIDS kind
--- @field options HeroBuilderOption[]
--- @field note nil|string muted words after the title
--- @field status nil|string the state plate's words
--- @field statusKind nil|string "ok" (done) or "go" (to choose)
--- @field chosen nil|{name: string, text: string, art: nil|string} the main pick, for the pane's top card
--- @field hint nil|string a rules note between the heading and the cards
--- @field shape nil|string its key and option ids: a section with the same shape is repainted, not built again
--- @field level nil|integer the Level its choice comes at (the page groups by it); 1 for anything without one
--- @field levelGain nil|HeroBuilderPaneLine[] Level up's You gain: what the Level brings without a choice
--- @field remaining nil|integer picks still to make (0 when done or optional)
--- @field chars nil|HeroBuilderChars the characteristics row's arrays and values
--- @field switches nil|table[] the two-way switches under Kits: HeroSheetCard.DamageSwitch picks
--- @field search nil|string a long list's search field: its placeholder
--- @field roll nil|{text: string, kind: string} a button that picks at random: kind "incident" or "complication"
--- @field result nil|string a muted line under the cards ("Saved to your notes.")
--- @field gain nil|HeroBuilderGainRow[] the page's You gain rows; such a section has no cards
--- @field link nil|boolean You gain has choices to make: the link to Skills & Languages shows
--- @field stale nil|HeroBuilderStale picks no longer offered
--- @field kept nil|HeroBuilderKept[] picks kept for one higher Level; such a section has no cards

--- @class HeroBuilderStale
--- @field ids string[] the picked ids no longer offered
--- @field names string[] the names still found for them (none for a removed option)

--- @class HeroBuilderKept
--- @field guid string the choice the pick is for
--- @field id string the picked option
--- @field name string what the row shows

--- @class HeroBuilderGainRow
--- @field label string what the step grants ("Skill", "Farmer: two exploration skills")
--- @field value nil|string what fills it ("Navigate, Nature"); nil when nothing does yet
--- @field open boolean a choice with picks still to make: "Not chosen" follows the value

--Lists this long get a search field on their heading, as in CharacterBuilder.
local SEARCH_AT = 20

--Crops a panel's image to fill it without stretching (the CSS "cover"),
--keeping the top of a tall picture, where faces are. True once it could
--(the image and the panel's size both known).
--- @param element Panel
--- @return boolean
local function CoverCrop(element)
    local sprite = element.bgsprite
    local panelW, panelH = element.renderedWidth, element.renderedHeight
    if sprite == nil or panelW <= 1 or panelH <= 1 then
        return false
    end
    local imageW, imageH = sprite.dimensions.x, sprite.dimensions.y
    if imageW <= 0 or imageH <= 0 then
        return false
    end
    local aspect = panelW / panelH
    local imageAspect = imageW / imageH
    if imageAspect > aspect then
        local frac = aspect / imageAspect
        element.selfStyle.imageRect = {x1 = (1 - frac) / 2, y1 = 0, x2 = 1 - (1 - frac) / 2, y2 = 1}
    else
        local frac = imageAspect / aspect
        element.selfStyle.imageRect = {x1 = 0, y1 = 1 - frac, x2 = 1, y2 = 1}
    end
    return true
end

--- A box for a piece of art (an ancestry's or class's), cropped to fill it;
--- without art it is a dark tile (SetArt changes the art).
--- @param image nil|string
--- @param width number|string
--- @param height number|string
--- @param opts nil|{radius: nil|number, border: nil|number}
--- @return Panel
local function ArtPanel(image, width, height, opts)
    opts = opts or {}
    return gui.Panel{
        classes = {"heroBuilderTileArt"},
        bgimage = image or "panels/square.png",
        bgcolor = cond(image ~= nil, "white", "#2a2620ff"),
        border = opts.border or 1,
        cornerRadius = opts.radius or 6,
        width = width,
        height = height,
        interactable = false,
        data = {image = image},
        --the crop needs the image and the layout: imageLoaded can come first,
        --or never (an image already cached), so a short think retries it.
        imageLoaded = function(element)
            CoverCrop(element)
        end,
        thinkTime = cond(image ~= nil, 0.1, nil),
        think = function(element)
            if element.data.image == nil or CoverCrop(element) then
                element.thinkTime = nil
            end
        end,
    }
end

--- @param panel Panel from ArtPanel
--- @param image nil|string
local function SetArt(panel, image)
    if panel.data.image == image then
        return
    end
    panel.data.image = image
    panel.bgimage = image or "panels/square.png"
    panel.selfStyle.bgcolor = cond(image ~= nil, "white", "#2a2620ff")
    panel.selfStyle.imageRect = {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
    panel.thinkTime = cond(image ~= nil, 0.1, nil)
end

--- The first paragraph of a text, without markup, cut to a length.
--- @param text any
--- @param limit integer
--- @return string
local function Plain(text, limit)
    if type(text) ~= "string" then
        return ""
    end
    local first = string.match(text, "^%s*(.-)%s*\n%s*\n") or text
    --rich-text tags (<b>...</b>) first, then markdown's marks.
    first = string.gsub(first, "<[^<>]*>", "")
    first = string.gsub(first, "[%*_#]", "")
    first = trim((string.gsub(first, "%s+", " ")))
    if #first > limit then
        --cut on a character boundary, never inside a multi-byte one.
        local cut = limit - 3
        local function Continuation(i)
            local byte = string.byte(first, i)
            return byte ~= nil and byte >= 0x80 and byte < 0xC0
        end
        while cut > 1 and Continuation(cut + 1) do
            cut = cut - 1
        end
        first = trim(string.sub(first, 1, cut)) .. "..."
    end
    return first
end

--- "High Elf" as "HE": a tile's stand-in for missing art.
--- @param name string
--- @return string
local function Initials(name)
    local letters = {}
    for word in string.gmatch(HeroBuild.SaidName(name), "%a+") do
        letters[#letters+1] = string.upper(string.sub(word, 1, 1))
        if #letters == 2 then
            break
        end
    end
    return table.concat(letters)
end

--- An option's description, or "".
--- @param option any a CBOptionWrapper
--- @return string
local function OptionText(option)
    local text = nil
    pcall(function() text = option:GetDescription() end)
    return type(text) == "string" and text or ""
end

--- @class HeroBuilderDetail
--- @field kicker nil|string the small heading ("Subclass", "Feature", an ability's type)
--- @field title nil|string
--- @field sub nil|string a line under the title in the info colour ("Heroic resource: Focus")
--- @field text nil|string markdown
--- @field art nil|string an ancestry's or class's art: a banner over the words
--- @field image nil|string a smaller picture over the words
--- @field panelFn nil|fun(): Panel builds a panel to show under the words (an ability's card, a kit, features)
--- @field facts nil|{label: string, value: string}[] two-column facts under the words
--- @field impl nil|number its automation status, whose label leads the card
--- @field quickBuild nil|boolean the book's Quick Build pick: its line leads the card
--- @field more nil|{tab: string, text: string} other words on a tab of their own (an ancestry's Lore); only a pinned card shows the tabs

--Reads a field from a game-typed object or a plain table, or nil.
--- @param obj any
--- @param key string
--- @return any
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

--- The ability a feature or option stands for (a signature or heroic
--- ability pick, a class feature that is an ability), found the way
--- CharacterBuilder's CBOptionWrapper:Panel finds it.
--- @param option any
--- @return nil|ActivatedAbility
local function FeatureAbility(option)
    local function FromModifiers(modifiers)
        for _, modifier in ipairs(modifiers or {}) do
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
        for _, feature in ipairs(Field(modifierInfo, "features") or {}) do
            ability = FromModifiers(Field(feature, "modifiers"))
            if ability ~= nil then
                return ability
            end
        end
    end
    for _, feature in ipairs(Field(option, "features") or {}) do
        ability = FromModifiers(Field(feature, "modifiers"))
        if ability ~= nil then
            return ability
        end
    end
    return nil
end

--- An ability's card, as the sheet's Abilities list shows it.
--- @param ability ActivatedAbility
--- @return Panel
local function AbilityPanel(ability)
    local lists = rawget(_G, "HeroSheetLists")
    if lists ~= nil and lists.AbilityCard ~= nil then
        return lists.AbilityCard({ability = ability, name = ability.name})
    end
    return ability:Render({width = "100%"}, {})
end

--- An ability's type as the sheet tags it ("Main action", "Maneuver").
--- @param ability ActivatedAbility
--- @return string
local function AbilityKind(ability)
    local lists = rawget(_G, "HeroSheetLists")
    if lists ~= nil and lists.ActionTags ~= nil then
        local ok, tag = pcall(lists.ActionTags, ability, "")
        if ok and type(tag) == "string" then
            return tag
        end
    end
    return T("herobuilder.detail.ability")
end

--- A feature's automation status; nil for anything that tracks none.
--- @param feature any
--- @return nil|number
local function FeatureImpl(feature)
    local impl = nil
    pcall(function()
        if feature.IsDerivedFrom ~= nil and feature.IsDerivedFrom("CharacterFeature") then
            impl = feature:try_get("implementation", 1)
        end
    end)
    return impl
end

--- What a granted feature's (i) shows: an ability's card under its
--- type, or the feature's own words under "Feature".
--- @param feature any
--- @return HeroBuilderDetail
local function FeatureDetail(feature)
    local ability = FeatureAbility(feature)
    if ability ~= nil then
        return {kicker = AbilityKind(ability), title = ability.name, panelFn = function() return AbilityPanel(ability) end}
    end
    local text = nil
    pcall(function() text = feature:GetDescription() end)
    return {kicker = T("herobuilder.detail.feature"), title = Field(feature, "name") or "", text = text, impl = FeatureImpl(feature)}
end

--- Features as the sheet's cards, under a small heading: an ability
--- as its card, any other feature as its name and words on a small card,
--- with its automation under it. A class's choices read as cards too (what
--- it will ask); an ancestry's are left out (its traits to buy are a row).
--- @param details {feature: any}[] FillFeatureDetails entries
--- @param heading string
--- @param withChoices boolean
--- @return nil|fun(): Panel nil when there is no feature to show
local function FeatureStack(details, heading, withChoices)
    local features = {}
    for _, entry in ipairs(details) do
        local feature = entry.feature
        local isChoice = false
        pcall(function() isChoice = feature.IsDerivedFrom("CharacterChoice") end)
        if feature ~= nil and (withChoices or not isChoice) and Engine().FeatureShown(feature) then
            features[#features+1] = feature
        end
    end
    if #features == 0 then
        return nil
    end
    return function()
        --- @type Panel[]
        local children = {
            gui.Label{
                classes = {"heroSheetCardLabel"},
                text = string.upper(heading),
                fontSize = 11.5,
                bold = true,
                width = "100%",
                height = "auto",
            },
        }
        for _, feature in ipairs(features) do
            local ability = FeatureAbility(feature)
            if ability ~= nil then
                local card = AbilityPanel(ability)
                children[#children+1] = gui.Panel{width = "100%", height = "auto", tmargin = 6, card}
            else
                local text = nil
                pcall(function() text = feature:GetDescription() end)
                local impl = FeatureImpl(feature)
                local name = Field(feature, "name") or ""
                children[#children+1] = gui.Panel{
                    classes = {"heroSheetFeatCard"},
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 8,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    hpad = 12,
                    vpad = 9,
                    borderBox = true,
                    tmargin = 6,
                    gui.Label{classes = {"heroSheetCardStrong"}, text = name, fontSize = 15, bold = true, width = "100%", height = "auto"},
                    gui.Label{
                        classes = {"heroSheetCardText", cond(type(text) == "string" and text ~= "", nil, "collapsed")},
                        text = text or "",
                        markdown = true,
                        fontSize = 13.5,
                        width = "100%",
                        height = "auto",
                        tmargin = 3,
                        textAlignment = "topleft",
                    },
                }
                --its automation under it, the diamond then the label.
                if impl ~= nil and gui.ImplementationStatusValues[impl] ~= nil then
                    local diamond = HeroBuilder.Diamond()
                    HeroBuilder.SetDiamond(diamond, impl, false)
                    children[#children+1] = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        tmargin = 3,
                        diamond,
                        gui.Label{classes = {"heroSheetCardSub"}, text = gui.ImplementationStatusValues[impl], fontSize = 12.5, width = "auto", height = "auto", valign = "center"},
                    }
                end
            end
        end
        return gui.Panel{width = "100%", height = "auto", flow = "vertical", tmargin = 4, children = children}
    end
end

--- A kit's equipment, bonuses and signature ability (and its maneuver, if
--- any) under small headings, the abilities as the sheet's cards.
--- @param kit Kit
--- @return fun(): Panel
local function KitPanel(kit)
    return function()
        --- @type Panel[]
        local children = {}
        local function Heading(text)
            children[#children+1] = gui.Label{
                classes = {"heroSheetCardLabel"},
                text = string.upper(text),
                fontSize = 11.5,
                bold = true,
                width = "100%",
                height = "auto",
                tmargin = cond(#children == 0, 0, 10),
            }
        end
        local function Line(text)
            children[#children+1] = gui.Label{
                classes = {"heroSheetCardText"},
                text = text,
                fontSize = 13.5,
                width = "100%",
                height = "auto",
                tmargin = 3,
                textAlignment = "topleft",
            }
        end

        if kit.equipmentDescription ~= "" then
            Heading(T("herobuilder.kit.equipment"))
            Line(kit.equipmentDescription)
        end

        --the same bonuses, in the same order, as the kit's page in the compendium.
        --(each T() names its key in full so tests/uitext_check.lua can find it.)
        --- @type string[]
        local bonuses = {}
        local function Bonus(value, line)
            if value ~= 0 then
                bonuses[#bonuses+1] = line
            end
        end
        Bonus(kit.health, T("herobuilder.kit.stamina", {n = kit.health}))
        Bonus(kit.speed, T("herobuilder.kit.speed", {n = kit.speed}))
        Bonus(kit.range, T("herobuilder.kit.distance", {n = kit.range}))
        Bonus(kit.reach, T("herobuilder.kit.reach", {n = kit.reach}))
        Bonus(kit.area, T("herobuilder.kit.area", {n = kit.area}))
        Bonus(kit.disengage, T("herobuilder.kit.disengage", {n = kit.disengage}))
        Bonus(kit.stability, T("herobuilder.kit.stability", {n = kit.stability}))
        for _, damageType in ipairs(Kit.damageBonusTypes) do
            local bonus = kit:FormatDamageBonus(damageType.id)
            if bonus ~= nil then
                bonuses[#bonuses+1] = T("herobuilder.kit.damage", {type = damageType.text, bonus = bonus})
            end
        end
        if #bonuses > 0 then
            Heading(T("herobuilder.kit.bonuses"))
            for _, bonus in ipairs(bonuses) do
                Line(bonus)
            end
        end

        local function Card(ability)
            children[#children+1] = gui.Panel{width = "100%", height = "auto", tmargin = 6, AbilityPanel(ability)}
        end
        local signatures = kit:SignatureAbilities()
        if #signatures > 0 then
            Heading(T("herobuilder.kit.signature_ability"))
            for _, ability in ipairs(signatures) do
                Card(ability)
            end
        end
        --kitManeuver holds the maneuver ability; some kit data stores a bare `true` with no ability.
        if type(kit.kitManeuver) == "table" then
            Heading(T("herobuilder.kit.maneuver"))
            Card(kit.kitManeuver)
        end

        return gui.Panel{width = "100%", height = "auto", flow = "vertical", children = children}
    end
end

--- The detail for a choice row's option: a kit as the kit card, a
--- subclass with its 1st-level features, an ability pick as its card;
--- anything else as CharacterBuilder's option panel, else its description.
--- @param entry table a RowOptions entry
--- @param typeName string
--- @param kicker string the small heading (the choice's name)
--- @return HeroBuilderDetail
local function OptionDetail(entry, typeName, kicker)
    local option = entry.option
    local impl = nil
    pcall(function() impl = option:GetImplementation() end)
    if typeName == "CharacterKitChoice" then
        local kit = (dmhub.GetTableVisible(Kit.tableName) or {})[entry.id]
        if kit ~= nil then
            return {kicker = kicker, title = kit.name, text = kit.description, panelFn = KitPanel(kit)}
        end
    end
    if typeName == "CharacterSubclassChoice" then
        local subclass = (dmhub.GetTableVisible("subclasses") or {})[entry.id]
        if subclass ~= nil then
            local features = {}
            pcall(function() subclass:FillFeatureDetailsForLevel({}, 1, {}, true, features) end)
            return {
                kicker = kicker,
                title = subclass.name,
                text = subclass:try_get("details"),
                panelFn = FeatureStack(features, T("herobuilder.detail.first_level_features"), true),
            }
        end
    end
    local ability = nil
    pcall(function() ability = FeatureAbility(option:GetOption()) end)
    if ability ~= nil then
        return {kicker = kicker, title = entry.name, impl = impl, panelFn = function() return AbilityPanel(ability) end}
    end
    --Panel() hands back a function that builds the panel (a feature's
    --text, a perk's), or nil.
    local panelFn = nil
    pcall(function() panelFn = option:Panel() end)
    if type(panelFn) == "function" then
        return {kicker = kicker, title = entry.name, impl = impl, panelFn = panelFn}
    end
    return {kicker = kicker, title = entry.name, impl = impl, text = OptionText(option)}
end

--The small heading over a main pick's (i) and pane block.
local STEP_KICKERS = {
    ancestry = T("herobuilder.kicker.ancestry"),
    culture = T("herobuilder.kicker.culture"),
    career = T("herobuilder.kicker.career"),
    class = T("herobuilder.kicker.class"),
    complication = T("herobuilder.kicker.complication"),
}

--- A main pick's own words: an ancestry's or class's details (else its
--- lore), any other item's description.
--- @param stepid string
--- @param item table
--- @return string
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

--- A culture in full: its description, then
--- the aspect it sets in each category with their features, then its language.
--- @param item table
--- @return HeroBuilderDetail
local function CultureDetail(item)
    local aspectsTable = dmhub.GetTableVisible(CultureAspect.tableName) or {}
    local lines = {}
    local description = item:try_get("description")
    if type(description) == "string" and description ~= "" then
        lines[#lines+1] = description
        lines[#lines+1] = ""
    end
    lines[#lines+1] = T("herobuilder.culture.detail_sets")
    lines[#lines+1] = ""
    for _, cat in ipairs(CultureAspect.categories) do
        local aspect = aspectsTable[(item.aspects or {})[cat.id] or ""]
        if aspect ~= nil then
            lines[#lines+1] = string.format("**%s: %s**", cat.text, aspect.name)
            local text = aspect:try_get("description")
            if type(text) == "string" and text ~= "" then
                lines[#lines+1] = text
            end
            local details = {}
            pcall(function() aspect:FillFeatureDetails({}, details) end)
            for _, detailEntry in ipairs(details) do
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
        lines[#lines+1] = T("herobuilder.culture.detail_language", {language = language:DisplayNameWithDetail()})
    end
    return {title = item.name, text = table.concat(lines, "\n")}
end

--- The detail for a step's main pick: its words and art (a
--- complication's own card, a culture's aspects), with a class's heroic
--- resource and 1st-level features and an ancestry's signature traits.
--- @param stepid string
--- @param item table
--- @return HeroBuilderDetail
local function ItemDetail(stepid, item)
    --- @type HeroBuilderDetail
    local detail
    if stepid == "culture" then
        detail = CultureDetail(item)
    else
        detail = {title = item.name, text = BaseItemText(stepid, item)}
        local portrait = item:try_get("portraitid")
        if type(portrait) == "string" and portrait ~= "" then
            --a class's or ancestry's art fills the card; others sit on top.
            if stepid == "class" or stepid == "ancestry" then
                detail.art = portrait
            else
                detail.image = portrait
            end
        end
        --a complication's own card: its Benefit and Drawback.
        if stepid == "complication" then
            detail.panelFn = function()
                return item:Render{width = "100%"}
            end
        end
    end
    detail.kicker = STEP_KICKERS[stepid]
    detail.title = HeroBuild.SaidName(detail.title or item.name)
    if stepid == "class" then
        --a class its data marks as a master class says so where it is named.
        if item:try_get("isMasterClass", false) == true then
            detail.kicker = T("herobuilder.kicker.master_class")
        end
        if item:has_key("heroicResourceName") then
            detail.sub = T("herobuilder.detail.heroic_resource", {resource = item.heroicResourceName})
        end
        local features = {}
        pcall(function() item:FillFeatureDetailsForLevel({}, 1, {}, false, features) end)
        detail.panelFn = FeatureStack(features, T("herobuilder.detail.first_level_features"), true)
    elseif stepid == "ancestry" then
        local features = {}
        pcall(function() item:FillFeatureDetails(1, {}, features) end)
        detail.panelFn = FeatureStack(features, T("herobuilder.detail.signature_trait"), false)
        --the ancestry's Lore (CharacterBuilder's Lore page), on a tab of its own.
        local lore = item:try_get("lore")
        if type(lore) == "string" and trim(lore) ~= "" then
            detail.more = {tab = T("herobuilder.detail.lore_tab"), text = lore}
        end
    elseif stepid == "complication" and detail.panelFn ~= nil then
        --the complication's own card opens with its description: said once.
        detail.text = nil
    end
    return detail --[[@as HeroBuilderDetail]]
end

--The undo list's words for a step's main pick.
local CHANGE_WORDS = {
    ancestry = T("herobuilder.undo.change_ancestry"),
    culture = T("herobuilder.undo.change_culture"),
    career = T("herobuilder.undo.change_career"),
    class = T("herobuilder.undo.change_class"),
}

--The heading over the main pick on the steps that list it in tiles or cards.
local BASE_TITLES = {
    ancestry = T("herobuilder.section.your_ancestry"),
    career = T("herobuilder.section.your_career"),
    class = T("herobuilder.section.your_class"),
}

--- The section for a step's main pick (ancestry, culture, career, class,
--- complication). The pick itself is made by the page (it may confirm).
--- @param token CharacterToken
--- @param stepid string
--- @param base nil|table the step's base status row (Culture has none)
--- @return nil|HeroBuilderSection
local function BaseSection(token, stepid, base)
    local hero = token.properties --[[@as character]]
    local options = {}
    local current = nil
    local chosen = nil
    if stepid == "ancestry" or stepid == "career" or stepid == "class" then
        if stepid == "ancestry" then
            current = hero:try_get("raceid")
        elseif stepid == "career" then
            current = hero:try_get("backgroundid")
        else
            local classItem = hero:GetClass()
            current = classItem ~= nil and classItem.id or nil
        end
        for _, entry in ipairs(Engine().BaseOptions(hero, stepid)) do
            local item = entry.item
            local art = nil
            if stepid ~= "career" then
                local portrait = item:try_get("portraitid")
                art = cond(type(portrait) == "string" and portrait ~= "", portrait, nil)
            end
            options[#options+1] = {
                id = entry.id,
                name = HeroBuild.SaidName(entry.name),
                art = art,
                selected = entry.id == current,
                available = true,
                detail = function() return ItemDetail(stepid, item) end,
            }
            if entry.id == current then
                local text = item:try_get("details")
                if type(text) ~= "string" or text == "" then
                    text = item:try_get("description")
                end
                chosen = {name = HeroBuild.SaidName(entry.name), text = Plain(text, 220), art = art or ""}
            end
        end
        return {
            key = "base",
            title = BASE_TITLES[stepid],
            grid = cond(stepid == "career", "text", "tiles"),
            options = options,
            status = cond(current ~= nil, T("herobuilder.status.done"), T("herobuilder.status.to_choose")),
            statusKind = cond(current ~= nil, "ok", "go"),
            chosen = chosen,
        }
    elseif stepid == "culture" then
        --the typical cultures, the ancestry's own first.
        local culture = hero:try_get("culture")
        current = culture ~= nil and culture:try_get("aggregate") or nil
        local own = Engine().AncestryCultureId(Engine().hero.Ancestry(hero))
        for _, entry in ipairs(Engine().CultureAggregates()) do
            local item = entry.item
            local option = {
                id = entry.id,
                name = entry.name,
                line = cond(entry.id == own, T("herobuilder.culture.own"), nil),
                selected = entry.id == current,
                available = true,
                detail = function() return ItemDetail("culture", item) end,
            }
            if entry.id == own then
                table.insert(options, 1, option)
            else
                options[#options+1] = option
            end
        end
        return {
            key = "base",
            title = T("herobuilder.section.typical_cultures"),
            grid = "text",
            options = options,
            status = cond(current ~= nil and current ~= "", T("herobuilder.status.done"), nil),
            statusKind = "ok",
            search = cond(#options >= SEARCH_AT, T("herobuilder.search.cultures"), nil),
        }
    elseif stepid == "complication" then
        local held = {}
        for _, id in ipairs(Engine().hero.ComplicationIds(hero)) do
            held[id] = true
        end
        local none = next(held) == nil
        --No complication has nothing more to say, so no (i).
        options[1] = {
            id = "",
            name = T("herobuilder.complication.none_name"),
            line = T("herobuilder.complication.none_line"),
            selected = none,
            available = true,
            detail = nil,
        }
        for _, entry in ipairs(Engine().BaseOptions(hero, stepid)) do
            local item = entry.item
            local picked = held[entry.id] == true
            options[#options+1] = {
                id = entry.id,
                name = entry.name,
                line = Plain(item:try_get("description"), LINE_CHARS),
                selected = picked,
                available = true,
                --rated by its least-automated feature; narrative-only parts do not count.
                impl = Engine().ComplicationTier(item),
                hoverText = cond(picked, T("herobuilder.card.picked_hover"), nil),
                detail = function() return ItemDetail(stepid, item) end,
            }
        end
        return {
            key = "base",
            title = T("herobuilder.section.complications"),
            grid = "wide",
            options = options,
            status = cond(none, T("herobuilder.status.none_chosen"), nil),
            hint = cond(Engine().maxComplications == 1, T("herobuilder.complication.hint_one"), T("herobuilder.complication.hint")),
            roll = {text = T("herobuilder.roll.complication"), kind = "complication"},
            search = cond(#options > SEARCH_AT, T("herobuilder.search.complications"), nil),
        }
    end
    return nil
end

--What a long choice list's search calls it ("Search perks"), by its choice
--type; any other list goes by its own name.
local SEARCH_WORDS = {
    CharacterLanguageChoice = T("herobuilder.search.languages"),
    CharacterFeatChoice = T("herobuilder.search.perks"),
    CharacterKitChoice = T("herobuilder.search.kits"),
}

--The grid a choice row's options use, by its choice type.
local ROW_GRIDS = {
    CharacterLanguageChoice = "text",
    CharacterCharacteristicChoice = "text",
    CharacterAspectChoice = "cards",
    CharacterKitChoice = "kits",
}

--- A kit option's second line: the kit's armor and
--- weapons, then its first three bonuses ("Stamina +12 . Stability +1 . ...").
--- @param kitid string
--- @param echelon number Stamina scales with it
--- @return string "" when the kit or EotW's kit reader is missing
local function KitLine(kitid, echelon)
    local kit = (dmhub.GetTableVisible(Kit.tableName) or {})[kitid]
    local eotw = rawget(_G, "EotwHeroSheet")
    if kit == nil or eotw == nil or eotw.KitBonuses == nil or eotw.KitGear == nil then
        return ""
    end
    local lines = {}
    local gear = HeroSheetCard.KitGearText(eotw.KitGear(kit))
    if gear ~= "" then
        lines[#lines+1] = gear
    end
    local bonuses = {}
    for _, bonus in ipairs(eotw.KitBonuses(kit, echelon)) do
        if #bonuses == 3 then
            break
        end
        bonuses[#bonuses+1] = string.format("%s %s", bonus.text, bonus.value)
    end
    if #bonuses > 0 then
        lines[#lines+1] = table.concat(bonuses, " \u{00B7} ")
    end
    return table.concat(lines, "\n")
end

--- @class HeroBuilderCharTile
--- @field id string the characteristic's id
--- @field label string its name
--- @field value nil|integer its score from the array; nil before an array is picked
--- @field fixed boolean set by the class: it cannot be swapped

--- @class HeroBuilderChars
--- @field note string the line after the heading
--- @field tiles HeroBuilderCharTile[]
--- @field array nil|integer the picked array's place in the class's arrays

--- The characteristics heading's line: which the
--- class sets ("Your class has Might and Reason set to +2."), then how the
--- arrays work.
--- @param base table the class's baseCharacteristics
--- @return string
local function CharacteristicsNote(base)
    local byValue = {}
    local order = {}
    for _, id in ipairs(creature.attributeIds or {}) do
        local value = base[id]
        if type(value) == "number" then
            local info = creature.attributesInfo[id]
            if byValue[value] == nil then
                byValue[value] = {}
                order[#order+1] = value
            end
            table.insert(byValue[value], info ~= nil and info.description or id)
        end
    end
    local parts = {}
    for _, value in ipairs(order) do
        local names = byValue[value]
        local list = names[1]
        if #names > 1 then
            list = table.concat(names, ", ", 1, #names - 1) .. T("herobuilder.list.and") .. names[#names]
        end
        parts[#parts+1] = T("herobuilder.chars.set_to", {names = list, value = cond(value >= 0, "+" .. tostring(value), tostring(value))})
    end
    if #parts == 0 then
        return T("herobuilder.chars.note_none")
    end
    return T("herobuilder.chars.note_fixed", {fixed = table.concat(parts, T("herobuilder.list.and"))})
end

--- The characteristics row's model: the five scores, which the class
--- fixes, and the picked array.
--- @param hero character
--- @return nil|HeroBuilderChars
local function CharacteristicsModel(hero)
    local classItem = hero:GetClass()
    local base = classItem ~= nil and classItem:try_get("baseCharacteristics") or nil
    if base == nil then
        return nil
    end
    local build = hero:try_get("attributeBuild")
    local array = build ~= nil and build.array or nil
    local tiles = {}
    for _, id in ipairs(creature.attributeIds or {}) do
        local info = creature.attributesInfo[id]
        local fixed = type(base[id]) == "number"
        local value = nil
        if fixed then
            value = base[id]
        elseif array ~= nil then
            pcall(function() value = hero:GetBaseAttribute(id).baseValue end)
        end
        tiles[#tiles+1] = {id = id, label = info ~= nil and info.description or id, value = value, fixed = fixed}
    end
    return {note = CharacteristicsNote(base), tiles = tiles, array = array}
end

--The Beastheart (CharacterBuilder names it by id too): its companion uses its
--kit's melee damage bonus or a flat one.
local BEASTHEART_CLASS_ID = "0380181e-acad-4cdb-ae6d-c7cd11df6ad2"
local COMPANION_DEFAULT_MELEE = "+0/+0/+4"

--- The switches under Kits: which kit's damage bonus applies
--- when both kits give one, and a Beastheart's Companion melee.
--- @param hero character
--- @return table[] HeroSheetCard.DamageSwitch picks
local function KitSwitches(hero)
    local picks = {}
    pcall(function() picks = HeroSheetCard.DamagePicks(hero) end)
    local classItem = hero:GetClass()
    if classItem ~= nil and classItem.id == BEASTHEART_CLASS_ID then
        local kit = (dmhub.GetTable(Kit.tableName) or {})[hero:try_get("kitid") or ""]
        local melee = nil
        if kit ~= nil then
            pcall(function() melee = kit:FormatDamageBonus("melee") end)
        end
        --nothing to choose when the kit's bonus is the default already.
        if kit ~= nil and melee ~= nil and melee ~= COMPANION_DEFAULT_MELEE then
            local choices = (hero:GetLevelChoices() or {}).companionBonusChoices or {}
            picks[#picks+1] = {
                label = T("herobuilder.kit.companion_melee"),
                value1 = melee,
                value2 = COMPANION_DEFAULT_MELEE,
                name1 = kit.name,
                name2 = T("herobuilder.kit.companion_default"),
                first = choices.melee ~= "default",
                description = T("herobuilder.kit.companion_undo"),
                write = function(hero, which)
                    local levelChoices = hero:GetLevelChoices()
                    local bonus = levelChoices.companionBonusChoices or {}
                    bonus.melee = cond(which == 1, "kit", "default")
                    levelChoices.companionBonusChoices = bonus
                end,
            }
        end
    end
    return picks
end

--- Where each pick on the Hero's build is held, by its name: the step's
--- title and the row's id. A unique option one row holds shows as taken in
--- the others.
--- @param status table Engine().Status
--- @return table<string, {step: string, row: string}>
local function TakenPicks(status)
    local titles = {}
    for _, step in ipairs(Engine().STEPS) do
        titles[step.id] = step.title
    end
    local taken = {}
    for _, stepStatus in ipairs(status.steps) do
        for _, row in ipairs(stepStatus.rows) do
            if not row.base then
                for _, name in ipairs(row.selectedNames or {}) do
                    taken[name] = {step = titles[stepStatus.id] or stepStatus.id, row = row.guid}
                end
            end
        end
    end
    return taken
end

--- A choice's stale picks, or nil when it has none. A complication
--- hidden from the compendium still has its name; an option that was
--- removed has nothing left to name it by, so it shows no chip.
--- @param stepid string
--- @param ids nil|string[] the row's stale ids
--- @return nil|HeroBuilderStale
local function StalePicks(stepid, ids)
    if ids == nil or #ids == 0 then
        return nil
    end
    local names = {}
    if stepid == "complication" then
        local items = dmhub.GetTable(CharacterComplication.tableName) or {}
        for _, id in ipairs(ids) do
            local item = items[id]
            if item ~= nil then
                names[#names+1] = item.name
            end
        end
    end
    return {ids = ids, names = names}
end

--- The section for one choice row of a step.
--- @param token CharacterToken
--- @param stepid string
--- @param row table the row's status
--- @param taken table<string, {step: string, row: string}> from TakenPicks
--- @param rowOptions nil|{options: table[], info: table} the row's options, from the step's AllRowOptions
--- @return nil|HeroBuilderSection
local function RowSection(token, stepid, row, taken, rowOptions)
    if rowOptions == nil then
        return nil
    end
    local entries, info = rowOptions.options, rowOptions.info
    local options = {}
    local spent = 0
    local grid = ROW_GRIDS[info.typeName] or "wide"
    local echelon = 1
    pcall(function() echelon = token.properties:Echelon() end)
    local isArray = info.typeName == "CharacterCharacteristicChoice"
    for _, entry in ipairs(entries) do
        --wide cards carry the option's text (a trait's, a perk's) and kit
        --cards their gear and bonuses; aspects and languages show their names.
        local line = ""
        if grid == "wide" then
            line = Plain(OptionText(entry.option), LINE_CHARS)
        elseif grid == "kits" then
            line = KitLine(entry.id, echelon)
        end
        if info.costsPoints then
            local cost = entry.cost or 1
            if entry.selected then
                spent = spent + cost
            end
            line = TP("herobuilder.card.points", cost, {count = string.format("%d", cost)}) .. " \u{00B7} " .. line
        end
        --a characteristic array's option id is made anew on every read (the
        --engine's note), so the card is known by the array's place instead.
        local id = entry.id
        local arrayIndex = nil
        if isArray then
            pcall(function() arrayIndex = entry.option:GetOption().arrayIndex end)
            id = "array" .. tostring(arrayIndex)
        end
        --why a card cannot be picked: another choice already holds it ("Taken
        --on <step>"), or it costs more points than are left.
        local hoverText = nil
        if entry.selected and not isArray then
            hoverText = T("herobuilder.card.picked_hover")
        elseif not entry.available then
            local holder = taken[entry.name]
            if holder ~= nil and holder.row ~= row.guid then
                line = T("herobuilder.card.taken_on", {step = holder.step})
                hoverText = line
            elseif info.costsPoints then
                hoverText = T("herobuilder.card.no_points")
            end
        end
        local impl = nil
        pcall(function() impl = entry.option:GetImplementation() end)
        local quickBuild = (info.quickBuild or {})[entry.id] == true
        options[#options+1] = {
            id = id,
            name = entry.name,
            line = cond(line ~= "", line, nil),
            selected = entry.selected,
            available = entry.available,
            arrayIndex = arrayIndex,
            impl = impl,
            quickBuild = quickBuild,
            hoverText = hoverText,
            detail = function()
                local detail = OptionDetail(entry, info.typeName, row.name)
                detail.quickBuild = quickBuild
                return detail
            end,
            view = {featureId = row.guid, optionId = entry.id, optionName = entry.name, dailyLimit = 20},
        }
    end
    local status, kind, note
    if info.costsPoints then
        local total = spent + (info.remaining or 0)
        note = T("herobuilder.section.points_to_spend", {count = string.format("%d", total)})
        status = T("herobuilder.status.points_spent", {spent = string.format("%d", spent), total = string.format("%d", total)})
        kind = cond(row.complete, "ok", "go")
    elseif row.complete then
        status, kind = T("herobuilder.status.done"), "ok"
    elseif row.category == "Incident" then
        --story only: never a choice left to make.
        status = T("herobuilder.status.optional")
    else
        status, kind = T("herobuilder.status.left", {count = string.format("%d", math.max(1, row.remaining or 1))}), "go"
    end
    local chars = nil
    if isArray then
        chars = CharacteristicsModel(token.properties --[[@as character]])
        note = chars ~= nil and chars.note or nil
    end
    local switches = nil
    if info.typeName == "CharacterKitChoice" then
        switches = KitSwitches(token.properties --[[@as character]])
    end
    --the inciting incident: the career's table to pick
    --from, or roll on it; the pick is written to the Hero's notes.
    local roll, result = nil, nil
    if info.typeName == "CharacterIncidentChoice" then
        local career = Engine().hero.Career(token.properties --[[@as character]])
        if career ~= nil then
            note = T("herobuilder.incident.note", {career = career.name})
        end
        roll = {text = T("herobuilder.roll.incident"), kind = "incident"}
        result = cond(row.complete, T("herobuilder.incident.saved"), nil)
    end
    local search = nil
    if #entries >= SEARCH_AT and not isArray then
        search = SEARCH_WORDS[info.typeName] or T("herobuilder.search.row", {name = string.lower(row.name)})
    end
    return {
        key = row.guid,
        title = row.name,
        grid = grid,
        options = options,
        note = note,
        status = status,
        statusKind = kind,
        level = math.max(1, row.level or 1),
        remaining = cond(kind == "go", math.max(1, row.remaining or 1), 0),
        chars = chars,
        switches = switches,
        roll = roll,
        result = result,
        search = search,
        stale = StalePicks(stepid, row.stale),
    }
end

--- @class HeroBuilderPaneLine
--- @field name string
--- @field tag nil|string a muted word after the name: the pick that brings it, "Skill", "Language"
--- @field kind nil|string "skill" or "language" for a skill or language granted outright
--- @field detail nil|fun(): nil|HeroBuilderDetail its (i)
--- @field text nil|string the opening of its words (Level up's page shows them under the name)
--- @field level nil|integer the class Level it comes at (the Class step's You gain groups by it)
--- @field heading nil|string a Level heading line ("4th Level") in place of a name

--- Everything a step grants without a choice, for the pane's You gain:
--- the step's own features and abilities, then what its picks bring
--- (a subclass's features, a kit's signature ability, a complication's
--- features), tagged with the pick, then outright skills and languages. The
--- features are read with no picks applied, so a choice's picks never show
--- here (they are the pane's other blocks).
--- @param token CharacterToken
--- @param stepid string
--- @return HeroBuilderPaneLine[]
local function StepGains(token, stepid)
    local hero = token.properties --[[@as character]]
    --a hidden feature (a career's "Handle Animals Skill") is not listed by
    --name, but the skills and languages it grants still are.
    --- @type {feature: any, tag: nil|string, shown: boolean, level: integer}[]
    local found = {}
    local function Add(details, tag)
        for _, entry in ipairs(details) do
            local feature = entry.feature
            --a feature that cannot be typed is left out of You gain (the
            --features list in FeatureStack shows one instead).
            local isChoice = true
            pcall(function() isChoice = feature.IsDerivedFrom("CharacterChoice") end)
            if feature ~= nil and not isChoice then
                found[#found+1] = {feature = feature, tag = tag, shown = Engine().FeatureShown(feature), level = tonumber((entry.levels or {})[1]) or 1}
            end
        end
    end
    local lines = {}
    pcall(function()
        if stepid == "ancestry" then
            local race = Engine().hero.Ancestry(hero)
            if race ~= nil then
                local details = {}
                race:FillFeatureDetails(hero:CharacterLevel(), {}, details)
                Add(details, T("herobuilder.gain.tag_signature_trait"))
            end
        elseif stepid == "culture" then
            local details = {}
            hero:GetCulture():FillFeatureDetails({}, details)
            Add(details, nil)
        elseif stepid == "career" then
            local career = Engine().hero.Career(hero)
            if career ~= nil then
                local details = {}
                career:FillFeatureDetails({}, details)
                Add(details, nil)
            end
        elseif stepid == "class" then
            local extra = hero:ExtraLevelInfo()
            for i, entry in ipairs(hero:GetClassesAndSubClasses()) do
                local details = {}
                entry.class:FillFeatureDetailsForLevel({}, entry.level, extra, i ~= 1, details)
                Add(details, cond(i == 1, nil, entry.class.name))
            end
        elseif stepid == "complication" then
            --a complication's Benefit and Drawback words are its own card (its
            --(i)); its features only carry them out, so they are not listed
            --by name unless one brings an ability. Their skills and languages
            --still are.
            local items = dmhub.GetTableVisible(CharacterComplication.tableName) or {}
            for _, id in ipairs(Engine().hero.ComplicationIds(hero)) do
                local item = items[id]
                if item ~= nil then
                    local details = {}
                    item:FillFeatureDetails({}, details, hero)
                    local first = #found + 1
                    Add(details, item.name)
                    for i = first, #found do
                        found[i].shown = found[i].shown and FeatureAbility(found[i].feature) ~= nil
                    end
                end
            end
        end
    end)

    --a feature that only grants skills or languages reads as those, tagged
    --Skill or Language; one that does more reads as itself too.
    local skills = Skill.SkillsById or {}
    local languages = dmhub.GetTableVisible(Language.tableName) or {}
    local seen = {}
    local profLines = {}
    for _, item in ipairs(found) do
        local feature = item.feature
        local other = 0
        for _, modifier in ipairs(Field(feature, "modifiers") or {}) do
            if Field(modifier, "behavior") == "proficiency" then
                local subtype = Field(modifier, "subtype")
                for id, on in pairs(Field(modifier, "skills") or {}) do
                    if on and not seen[id] then
                        if subtype == "skill" and skills[id] ~= nil then
                            seen[id] = true
                            local skill = skills[id]
                            profLines[#profLines+1] = {name = skill.name, tag = T("herobuilder.gain.tag_skill"), kind = "skill", level = item.level, detail = function()
                                local group = Skill.categoriesById[skill:try_get("category") or ""]
                                return {kicker = group ~= nil and T("herobuilder.detail.group_skill", {group = group.text}) or T("herobuilder.detail.skill"), title = skill.name}
                            end}
                        elseif subtype == "language" and languages[id] ~= nil then
                            seen[id] = true
                            local language = languages[id]
                            profLines[#profLines+1] = {name = language:DisplayName(), tag = T("herobuilder.gain.tag_language"), kind = "language", level = item.level, detail = function()
                                local facts = {{label = T("herobuilder.detail.spoken_by"), value = language:try_get("speakers") or "-"}}
                                if language:DisplayName() ~= language.name then
                                    table.insert(facts, 1, {label = T("herobuilder.detail.in_world_name"), value = language.name})
                                end
                                return {kicker = T("herobuilder.detail.language"), title = language:DisplayName(), facts = facts}
                            end}
                        end
                    end
                end
            else
                other = other + 1
            end
        end
        local name = Field(feature, "name")
        --some ancestries name the trait "Signature Trait: Relentless"; the tag says that already.
        if item.tag == T("herobuilder.gain.tag_signature_trait") and type(name) == "string" then
            name = string.gsub(name, "^[Ss]ignature [Tt]rait:%s*", "")
        end
        local isProfOnly = other == 0 and #(Field(feature, "modifiers") or {}) > 0
        if item.shown and type(name) == "string" and name ~= "" and not isProfOnly and not seen[name] then
            seen[name] = true
            lines[#lines+1] = {name = name, tag = item.tag, level = item.level, detail = function() return FeatureDetail(feature) end}
        end
    end
    --each kit's signature ability, tagged with its kit.
    if stepid == "class" then
        local kits = dmhub.GetTableVisible(Kit.tableName) or {}
        for _, field in ipairs({"kitid", "kitid2"}) do
            local kit = kits[hero:try_get(field) or ""]
            if kit ~= nil then
                local abilities = {}
                pcall(function() abilities = kit:SignatureAbilities() end)
                for _, ability in ipairs(abilities) do
                    lines[#lines+1] = {name = ability.name, tag = kit.name, detail = function()
                        return {kicker = AbilityKind(ability), title = ability.name, panelFn = function() return AbilityPanel(ability) end}
                    end}
                end
            end
        end
    end
    for _, line in ipairs(profLines) do
        lines[#lines+1] = line
    end
    --the Class step's grants from more than one Level: grouped under "1st
    --Level", "4th Level"... headings, as the page groups its choices.
    if stepid == "class" then
        local byLevel = {}
        local levels = {}
        for _, line in ipairs(lines) do
            local level = math.max(1, line.level or 1)
            if byLevel[level] == nil then
                byLevel[level] = {}
                levels[#levels+1] = level
            end
            table.insert(byLevel[level], line)
        end
        if #levels > 1 then
            table.sort(levels)
            lines = {}
            for _, level in ipairs(levels) do
                lines[#lines+1] = {name = "", heading = T("herobuilder.gain.level_heading", {ordinal = Ordinal(level)})}
                for _, line in ipairs(byLevel[level]) do
                    lines[#lines+1] = line
                end
            end
        end
    end
    return lines
end

--Stamina gains by class, Level and compendium version. The classes' Stamina
--formulas read only the Level, so one answer serves every Hero with those
--classes.
--- @type table<string, integer>
local g_staminaGains = {}

--- How much base Stamina a Level adds: the class's Stamina worked out at
--- the Level before and at this one, on a copy of the Hero.
--- @param hero character
--- @param level integer
--- @return integer
local function StaminaGain(hero, level)
    local classIds = {}
    for _, classInfo in ipairs(hero:try_get("classes", {})) do
        classIds[#classIds+1] = tostring(classInfo.classid)
    end
    local key = string.format("%s|%d|%s", table.concat(classIds, ","), level, tostring(dmhub.tablesUpdateId))
    local known = g_staminaGains[key]
    if known ~= nil then
        return known
    end
    local gain = 0
    pcall(function()
        local copy = DeepCopy(hero) --[[@as character]]
        local function At(atLevel)
            copy.levelOverride = atLevel
            for _, classInfo in ipairs(copy:try_get("classes", {})) do
                classInfo.level = atLevel
            end
            return copy:BaseHitpoints()
        end
        local before = At(level - 1)
        gain = math.max(0, math.floor(At(level) - before))
        g_staminaGains[key] = gain
    end)
    return gain
end

--- What a page brings without a choice, for Level up's You gain:
--- its Stamina ("Stamina +9"), then the class's and subclass's
--- features granted on it, with the opening of their words. Read with no
--- picks applied, so a choice's picks are the page's sections. A slow-start
--- page has what its rung adds, and no Stamina.
--- @param token CharacterToken
--- @param page HeroBuilderStep
--- @return HeroBuilderPaneLine[]
local function LevelGains(token, page)
    local hero = token.properties --[[@as character]]
    local level = page.level or 1
    local lines = {}
    if level >= 2 then
        local stamina = StaminaGain(hero, level)
        if stamina > 0 then
            lines[1] = {name = T("herobuilder.levelup.stamina", {amount = string.format("%d", stamina)})}
        end
    end
    local seen = {}
    local key = page.key or Engine().PageKey(level, page.rung)
    pcall(function()
        for _, entry in ipairs(Engine().hero.PageFeatures(hero, level, nil)) do
            local feature = entry.feature
            local name = Field(feature, "name")
            if entry.key == key and not seen[name] then
                seen[name] = true
                local words = nil
                pcall(function() words = feature:GetDescription() end)
                lines[#lines+1] = {
                    name = name,
                    tag = cond(entry.index == 1, nil, entry.class.name),
                    text = Plain(words, LINE_CHARS * 2),
                    detail = function() return FeatureDetail(feature) end,
                }
            end
        end
    end)
    return lines
end

--The steps whose page says what they grant in skills and languages.
local GAIN_STEPS = {ancestry = true, culture = true, career = true, class = true, complication = true}

--The words a grant line may start with that read lower case after "Farmer: ":
--the ones HeroSkillsLanguages.GrantWords writes, from the same text entries.
local LINE_LEADS = {}
for _, word in ipairs({
    T("heroskills.article.a"), T("heroskills.article.an"),
    T("heroskills.number.one"), T("heroskills.number.two"), T("heroskills.number.three"),
    T("heroskills.number.four"), T("heroskills.number.five"), T("heroskills.number.six"),
}) do
    LINE_LEADS[word] = true
end

--- The page's You gain rows: the skills and languages the step grants
--- outright, then each skill or language choice it brings, with what fills
--- it now. The choices themselves are made on Skills & Languages.
--- @param gains HeroBuilderPaneLine[] the step's grants (StepGains): outright skills and languages carry a kind
--- @param pools table[] the step's skill and language choices, from AllRowOptions
--- @return HeroBuilderGainRow[] rows
local function GainRows(gains, pools)
    local rows = {}
    for _, line in ipairs(gains) do
        if line.kind == "skill" or line.kind == "language" then
            rows[#rows+1] = {label = line.tag, value = line.name, open = false}
        end
    end
    local skills = Skill.SkillsById or {}
    local languages = dmhub.GetTableVisible(Language.tableName) or {}
    for _, pool in ipairs(pools) do
        local item, words = HeroSkillsLanguages.GrantWords(pool.feature, pool.kind, pool.capacity, pool.owner)
        --"Two exploration skills" reads "two exploration skills" after the
        --item; a list of named skills keeps its capitals.
        local first, rest = string.match(words, "^(%a+)(.*)$")
        if first ~= nil and LINE_LEADS[first] then
            words = string.lower(first) .. rest
        end
        local names = {}
        for _, id in ipairs(pool.selected) do
            local entry = nil
            if pool.kind == "skill" then
                entry = skills[id]
            else
                entry = languages[id]
            end
            if entry ~= nil then
                if pool.kind == "skill" then
                    names[#names+1] = entry.name
                else
                    names[#names+1] = entry:DisplayName()
                end
            end
        end
        rows[#rows+1] = {
            label = string.format("%s: %s", item, words),
            value = cond(#names > 0, table.concat(names, ", "), nil),
            open = #names < pool.capacity,
        }
    end
    return rows
end

----------------------------------------------------------------------
--The Builder's pieces, shared with the EotW builder: the
--option card, the (i) and its card, the picks pane's blocks. Each takes
--what it shows and what a click does as arguments; none reads the sheet
--window, the token or analytics itself.

--The (i) and its card: a 24-unit target, and a card 430 wide (398 inside
--its padding) that may run to 660 tall.
local INFO_SIZE = 24
local POPUP_INNER = 398
local POPUP_BODY_MAX = 600

--- The automation diamond: the app's diamond (a square turned 45
--- degrees, as on stat blocks), tinted by the scheme's automation colours,
--- with its label on a deliberate hover. On a picked card it keeps a
--- 1.5-unit dark ring. SetDiamond paints it; its colours are set on
--- the panel, so it reads the same in a pop-up as on a card.
--- @param args nil|{enter: nil|fun(), leave: nil|fun()} the pointer came onto it / left it (a card silences its own tooltip meanwhile)
--- @return Panel
function HeroBuilder.Diamond(args)
    args = args or {}
    local ring = gui.Panel{
        classes = {"collapsed"},
        bgimage = "panels/square.png",
        rotate = 45,
        floating = true,
        width = 13,
        height = 13,
        halign = "center",
        valign = "center",
        interactable = false,
    }
    local icon = gui.Panel{
        bgimage = "panels/square.png",
        rotate = 45,
        width = 10,
        height = 10,
        halign = "center",
        valign = "center",
        interactable = false,
    }
    return gui.Panel{
        width = 18,
        height = 18,
        valign = "center",
        rmargin = 4,
        data = {ring = ring, icon = icon, impl = nil},
        hover = function(element)
            if args.enter ~= nil then
                args.enter()
            end
        end,
        dehover = function(element)
            if args.leave ~= nil then
                args.leave()
            end
        end,
        linger = function(element)
            local label = gui.ImplementationStatusValues[element.data.impl or -1]
            if label ~= nil then
                gui.Tooltip(label)(element)
            end
        end,
        ring,
        icon,
    }
end

--- @param panel Panel from Diamond
--- @param impl nil|number
--- @param picked boolean on a picked card, with its ring
function HeroBuilder.SetDiamond(panel, impl, picked)
    panel.data.impl = impl
    panel:SetClass("collapsed", impl == nil)
    if impl ~= nil then
        --the scheme's @implStatus colours (the default scheme fills in any it
        --leaves out); a status outside 0-4 shows as Not Automated.
        local colors = ThemeEngine.GetColorSchemeColors(ThemeEngine.GetActiveColorScheme()) or {}
        panel.data.icon.selfStyle.bgcolor = colors["implStatus" .. tostring(impl)] or colors.implStatus1
        panel.data.ring.selfStyle.bgcolor = HeroSheetTheme.Palette().bg
        panel.data.ring:SetClass("collapsed", not picked)
    end
end

--What a hover on the Quick Build star says.
local QUICK_BUILD_TIP = T("herobuilder.quick_build.tip")

--- The star that marks the book's Quick Build pick: after the diamond
--- on a card or chip, before the (i). SetQuickBuildStar paints it; like the
--- diamond, its colour is set on the panel, so a pop-up shows it the same.
--- @param args nil|{size: nil|number, enter: nil|fun(), leave: nil|fun()} its size (14 by default); the pointer came onto it / left it
--- @return Panel
function HeroBuilder.QuickBuildStar(args)
    args = args or {}
    local size = args.size or 14
    local star = gui.Panel{
        bgimage = "phosphor/star-fill.png",
        width = size,
        height = size,
        valign = "center",
        rmargin = 4,
        hover = function(element)
            if args.enter ~= nil then
                args.enter()
            end
        end,
        dehover = function(element)
            if args.leave ~= nil then
                args.leave()
            end
        end,
        linger = function(element)
            gui.Tooltip(QUICK_BUILD_TIP)(element)
        end,
    }
    HeroBuilder.SetQuickBuildStar(star, true, false)
    return star
end

--- @param panel Panel from QuickBuildStar
--- @param shown boolean the option is the Quick Build's pick
--- @param picked boolean on a picked card or chip: dark, as its words are
function HeroBuilder.SetQuickBuildStar(panel, shown, picked)
    panel:SetClass("collapsed", not shown)
    local palette = HeroSheetTheme.Palette()
    panel.selfStyle.bgcolor = cond(picked, palette.bg, palette.cardLabel)
end

--- The (i)'s card: the option in full. Pinned, it has the light edge
--- and an x and scrolls once it is taller than it may be; on hover a long
--- one is cut short, with a line saying how to read the rest.
--- @param spec HeroBuilderDetail
--- @param pinned boolean
--- @param close fun()
--- @return Panel
function HeroBuilder.DetailCard(spec, pinned, close)
    --pinned, room for a scroll bar; the x sits over the top-right corner,
    --so the heading leaves it room unless a picture is there.
    local width = cond(pinned, POPUP_INNER - 12, POPUP_INNER)
    local headWidth = cond(pinned, width - 34, width)
    local children = {}
    if type(spec.art) == "string" and spec.art ~= "" then
        local art = ArtPanel(spec.art, width, 170, {radius = 8, border = 0})
        art.selfStyle.bmargin = 10
        children[#children+1] = art
        headWidth = width
    elseif type(spec.image) == "string" and spec.image ~= "" then
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            maxWidth = 240,
            maxHeight = 200,
            halign = "center",
            bgimage = spec.image,
            bgcolor = "white",
            cornerRadius = 8,
            bmargin = 10,
            autosizeimage = true,
            interactable = false,
        }
        headWidth = width
    end
    --a pinned card with other words (an ancestry's Lore) switches with
    --two tabs at the right of its kicker line; a hover card cannot be
    --clicked, so it shows only the description.
    local tabbed = pinned and spec.more ~= nil
    --- @type nil|fun(lore: boolean)
    local ShowTab = nil
    local descTab, loreTab
    --- @param text string
    --- @param lore boolean
    --- @return Panel
    local function Tab(text, lore)
        return gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable", cond(lore, nil, "selected")},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 20,
            lmargin = 14,
            valign = "center",
            click = function()
                if ShowTab ~= nil then
                    ShowTab(lore)
                end
            end,
            gui.Label{
                classes = {"heroSheetListTab", cond(lore, nil, "selected")},
                text = string.upper(text),
                fontSize = 11.5,
                bold = true,
                width = "auto",
                height = "auto",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
    end
    local hasKicker = type(spec.kicker) == "string" and spec.kicker ~= ""
    local kicker = nil
    if hasKicker then
        kicker = gui.Label{
            classes = {"heroSheetCardLabel"},
            text = string.upper(spec.kicker),
            fontSize = 11.5,
            bold = true,
            width = cond(tabbed, "auto", headWidth),
            height = "auto",
            halign = "left",
            valign = "center",
        }
    end
    if tabbed then
        descTab = Tab(T("herobuilder.detail.description_tab"), false)
        loreTab = Tab(spec.more.tab, true)
        children[#children+1] = gui.Panel{
            width = headWidth,
            height = "auto",
            flow = "horizontal",
            kicker,
            gui.Panel{width = "auto", height = "auto", flow = "horizontal", halign = "right", descTab, loreTab},
        }
    elseif kicker ~= nil then
        children[#children+1] = kicker
    end
    if type(spec.title) == "string" and spec.title ~= "" then
        children[#children+1] = gui.Label{
            classes = {"heroSheetCardStrong"},
            text = spec.title,
            fontSize = 22,
            bold = true,
            width = headWidth,
            height = "auto",
            halign = "left",
            tmargin = 1,
        }
    end
    if type(spec.sub) == "string" and spec.sub ~= "" then
        children[#children+1] = gui.Label{
            classes = {"heroSheetCardInfo"},
            text = spec.sub,
            fontSize = 13.5,
            width = width,
            height = "auto",
            tmargin = 2,
        }
    end
    --the description: the part a tab swaps for the other words.
    local desc = children
    if tabbed then
        desc = {}
    end
    if spec.quickBuild then
        desc[#desc+1] = gui.Panel{
            width = width,
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            HeroBuilder.QuickBuildStar(),
            gui.Label{
                classes = {"heroSheetCardText"},
                text = QUICK_BUILD_TIP,
                fontSize = 13,
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end
    if spec.impl ~= nil and gui.ImplementationStatusValues[spec.impl] ~= nil then
        local diamond = HeroBuilder.Diamond()
        HeroBuilder.SetDiamond(diamond, spec.impl, false)
        desc[#desc+1] = gui.Panel{
            width = width,
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            diamond,
            gui.Label{
                classes = {"heroSheetCardSub"},
                text = gui.ImplementationStatusValues[spec.impl],
                fontSize = 13,
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end
    if type(spec.text) == "string" and spec.text ~= "" then
        desc[#desc+1] = gui.Label{
            classes = {"heroSheetCardText"},
            text = spec.text,
            markdown = true,
            fontSize = 14,
            width = width,
            height = "auto",
            tmargin = 8,
            textAlignment = "topleft",
        }
    end
    if spec.panelFn ~= nil then
        local ok, panel = pcall(spec.panelFn)
        if ok and panel ~= nil and type(panel) ~= "function" then
            desc[#desc+1] = gui.Panel{
                width = width,
                height = "auto",
                flow = "vertical",
                tmargin = 8,
                panel,
            }
        end
    end
    for i, fact in ipairs(spec.facts or {}) do
        desc[#desc+1] = gui.Panel{
            width = width,
            height = "auto",
            flow = "horizontal",
            tmargin = cond(i == 1, 12, 3),
            gui.Label{classes = {"heroSheetCardSub"}, text = fact.label, fontSize = 13, width = 110, height = "auto", halign = "left"},
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = fact.value,
                fontSize = 13,
                bold = true,
                width = width - 110,
                height = "auto",
                halign = "right",
                textAlignment = "right",
            },
        }
    end
    local body, scroller
    if tabbed then
        local descPanel = gui.Panel{
            width = width,
            height = "auto",
            flow = "vertical",
            children = desc,
        }
        local lorePanel = gui.Panel{
            classes = {"collapsed"},
            width = width,
            height = "auto",
            flow = "vertical",
            gui.Label{
                classes = {"heroSheetCardText"},
                text = spec.more.text,
                markdown = true,
                fontSize = 14,
                width = width,
                height = "auto",
                tmargin = 8,
                textAlignment = "topleft",
            },
        }
        children[#children+1] = descPanel
        children[#children+1] = lorePanel
        --the other words take the description's place, and the card goes
        --back to its top.
        ShowTab = function(lore)
            descPanel:SetClass("collapsed", lore)
            lorePanel:SetClass("collapsed", not lore)
            descTab:SetClassTree("selected", not lore)
            loreTab:SetClassTree("selected", lore)
            HeroSheetWindow.AfterLayout(function()
                if not scroller.valid or not body.valid then
                    return
                end
                if body.renderedHeight > scroller.renderedHeight + 0.5 then
                    scroller.vscroll = true
                end
                scroller.vscrollPosition = 1
            end)
        end
    end
    body = gui.Panel{
        width = width,
        height = "auto",
        flow = "vertical",
        halign = "left",
        children = children,
    }
    scroller = gui.Panel{
        width = POPUP_INNER,
        height = "auto",
        maxHeight = POPUP_BODY_MAX,
        flow = "vertical",
        vscroll = false,
        body,
    }
    local hint = gui.Label{
        classes = {"heroSheetCardSub", "collapsed"},
        text = T("herobuilder.detail.pin_hint"),
        fontSize = 12,
        width = POPUP_INNER,
        height = "auto",
        tmargin = 8,
    }
    --a card taller than it may be scrolls (pinned) or says how to read it.
    HeroSheetWindow.AfterLayout(function()
        if not scroller.valid or not body.valid then
            return
        end
        if body.renderedHeight > scroller.renderedHeight + 0.5 then
            scroller.vscroll = true
            hint:SetClass("collapsed", pinned)
        end
    end)
    return HeroSheetTheme.CardFrame(gui.Panel{
        width = POPUP_INNER,
        height = "auto",
        flow = "vertical",
        scroller,
        hint,
    }, pinned, close)
end

--The (i) pinned now: one at a time.
--- @type nil|Panel
local g_pinnedInfo = nil

--- Close the pinned (i) card, if one is open (the step changed, the Builder
--- closed, another (i) was pinned).
function HeroBuilder.ClosePinned()
    local element = g_pinnedInfo
    g_pinnedInfo = nil
    if element ~= nil and element.valid then
        element.popup = nil
    end
end

--- @class HeroBuilderInfoArgs
--- @field detail fun(): nil|HeroBuilderDetail what its card shows, read each time it shows; nil shows nothing
--- @field side nil|string where the card opens against it: "right" (default) or "left" (the pane's, at the screen's right edge)
--- @field onArt nil|boolean on a tile's art: a dark disc behind it
--- @field shown nil|fun() runs each time its card shows (the caller's analytics)
--- @field enter nil|fun() the pointer came onto it (a card silences its own tooltip meanwhile)
--- @field leave nil|fun() the pointer left it
--- @field extra nil|table more fields for its panel (placement)

--- The (i) on an option or a pick: hovering it shows the option in
--- full at once (it is a deliberate target, so no wait); a click pins the
--- card, which stays and scrolls until x, Esc or another click on the (i).
--- A click on it never picks its card.
--- @param args HeroBuilderInfoArgs
--- @return Panel
function HeroBuilder.InfoButton(args)
    local side = args.side or "right"
    local function Card(pinned, close)
        local ok, spec = pcall(args.detail)
        if not ok or spec == nil then
            return nil
        end
        if args.shown ~= nil then
            args.shown()
        end
        return HeroBuilder.DetailCard(spec, pinned, close)
    end
    local panelArgs = {
        classes = {"heroBuilderInfo", "hoverable", cond(args.onArt, "heroBuilderOnArt", nil)},
        bgimage = "panels/square.png",
        cornerRadius = INFO_SIZE / 2,
        width = INFO_SIZE,
        height = INFO_SIZE,
        valign = "center",
        hover = function(element)
            if args.enter ~= nil then
                args.enter()
            end
            if element.popup ~= nil then
                return
            end
            local frame = Card(false, function() end)
            if frame ~= nil then
                frame.selfStyle.halign = side
                frame.selfStyle.valign = "center"
                element.tooltip = frame
            end
        end,
        dehover = function(element)
            element.tooltip = nil
            if args.leave ~= nil then
                args.leave()
            end
        end,
        click = function(element)
            element.tooltip = nil
            if element.popup ~= nil then
                HeroBuilder.ClosePinned()
                element.popup = nil
                return
            end
            HeroBuilder.ClosePinned()
            local function close()
                if element.valid then
                    element.popup = nil
                end
                if g_pinnedInfo == element then
                    g_pinnedInfo = nil
                end
            end
            local frame = Card(true, close)
            if frame == nil then
                return
            end
            element.popupPositioning = "panel"
            element.popup = gui.Panel{
                width = "auto",
                height = "auto",
                halign = side,
                valign = "center",
                --Esc closes the pinned card before anything else.
                captureEscape = true,
                escapePriority = EscapePriority.DMHUB_POPUP,
                escape = function()
                    close()
                end,
                frame,
            }
            g_pinnedInfo = element
        end,
        gui.Panel{
            classes = {"heroBuilderInfoIcon", cond(args.onArt, "heroBuilderOnArt", nil)},
            bgimage = "phosphor/info.png",
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    for field, value in pairs(args.extra or {}) do
        panelArgs[field] = value
    end
    return gui.Panel(panelArgs)
end

--- @class HeroBuilderCardArgs
--- @field kind string a GRIDS kind
--- @field withLine boolean some option in its grid has a second line
--- @field marks boolean its grid has automation diamonds
--- @field stars nil|boolean its grid has a Quick Build pick: room for the star
--- @field pick fun(option: HeroBuilderOption): boolean a click on the card; true when it saved at once
--- @field hover nil|fun(option: HeroBuilderOption, element: Panel) the pointer came onto the card
--- @field leave nil|fun(element: Panel) the pointer left the card
--- @field shown nil|fun(option: HeroBuilderOption) its (i) card showed

--- A card for an option, built once; SetOptionCard paints an
--- option into it. Art tiles carry the (i) on their art; other cards hold
--- the diamond then the (i) in their top-right corner. Only the parts a
--- card shows are built (a page can hold a hundred cards).
--- @param args HeroBuilderCardArgs
--- @return Panel
function HeroBuilder.OptionCard(args)
    --an art tile's art is this tall (its width is GRIDS.tiles.min).
    local TILE_ART_HEIGHT = 78
    local kind = args.kind
    local parts = {}
    local card
    --the (i) and the diamond have tooltips of their own: while the pointer
    --is on one, the card's tooltip stays away so it cannot replace theirs.
    local function EnterMark()
        card.data.overMark = true
        card.tooltip = nil
    end
    local function LeaveMark()
        card.data.overMark = false
    end
    parts.info = HeroBuilder.InfoButton{
        enter = EnterMark,
        leave = LeaveMark,
        detail = function()
            local option = card.data.option
            if option == nil or option.detail == nil then
                return nil
            end
            return option.detail()
        end,
        onArt = kind == "tiles",
        shown = function()
            local option = card.data.option
            if option ~= nil and args.shown ~= nil then
                args.shown(option)
            end
        end,
        --on a tile, over the art's bottom-right corner.
        extra = cond(kind == "tiles", {floating = true, halign = "right", valign = "top", tmargin = TILE_ART_HEIGHT - INFO_SIZE - 3, rmargin = 3}, nil),
    }
    local cardArgs = {
        classes = {"heroBuilderCard", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = cond(kind == "text", 8, 10),
        width = GRIDS[kind].min,
        height = "auto",
        flow = "vertical",
        hpad = cond(kind == "text", 10, 12),
        vpad = cond(kind == "text", 7, 9),
        borderBox = true,
        halign = "left",
        valign = "top",
        data = {parts = parts, overMark = false},
        hover = function(element)
            local option = element.data.option
            if option ~= nil and args.hover ~= nil then
                args.hover(option, element)
            end
        end,
        dehover = function(element)
            if args.leave ~= nil then
                args.leave(element)
            end
        end,
        --why it cannot be picked, or how to drop a pick, on a deliberate hover.
        linger = function(element)
            local option = element.data.option
            if option ~= nil and option.hoverText ~= nil and not element.data.overMark then
                gui.Tooltip(option.hoverText)(element)
            end
        end,
        --a save and its repaint take a moment: the card answers the click at
        --once, and a second click before the repaint is ignored (it would undo
        --the first).
        click = function(element)
            local option = element.data.option
            if option == nil or element.data.pending then
                return
            end
            if args.pick(option) then
                element.data.pending = true
                element:SetClassTree("selected", not option.selected)
                element:SetClassTree("unavailable", false)
                --a save that never comes back must not lock the card.
                dmhub.Schedule(3, function()
                    if not mod.unloaded and element.valid and element.data.pending and element.data.option ~= nil then
                        HeroBuilder.SetOptionCard(element, element.data.option)
                    end
                end)
            end
        end,
    }
    if kind == "tiles" then
        cardArgs.classes = {"hoverable"}
        cardArgs.bgimage = "panels/square.png"
        cardArgs.bgcolor = "clear"
        cardArgs.border = 0
        cardArgs.hpad = 0
        cardArgs.vpad = 0
        parts.art = ArtPanel(nil, GRIDS.tiles.min, TILE_ART_HEIGHT)
        parts.initials = gui.Label{
            classes = {"heroBuilderCaps"},
            text = "",
            fontSize = 15,
            bold = true,
            width = "100%",
            height = "100%",
            textAlignment = "center",
            interactable = false,
        }
        parts.art:AddChild(parts.initials)
        --the name sits on a plate that fills when the tile is picked. It
        --shows in full: at least the art's width, wider and still centred
        --where the name needs it; FitGrid keeps neighbours apart.
        parts.name = gui.Label{
            classes = {"heroBuilderTileName"},
            bgimage = "panels/square.png",
            cornerRadius = 4,
            text = "",
            fontSize = 11,
            width = "auto",
            minWidth = GRIDS.tiles.min,
            height = "auto",
            hpad = 4,
            vpad = 1,
            borderBox = true,
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            tmargin = 3,
            interactable = false,
        }
        cardArgs.children = {parts.art, parts.name, parts.info}
    else
        --every card in a grid is one size whatever its words: a text card
        --holds a two-line name, an option card a name and three lines; a
        --longer name ends in an ellipsis. The name leaves
        --room for the corner's marks; the words under it take the width.
        cardArgs.height = CARD_HEIGHTS[kind]
        cardArgs.flow = "none"
        local markRoom = cond(args.marks, 2 * INFO_SIZE + 8, INFO_SIZE + 6) + cond(args.stars, 18, 0)
        if kind == "text" then
            parts.name = gui.Label{
                classes = {"heroBuilderCardName"},
                text = "",
                fontSize = 13,
                bold = true,
                width = string.format("100%%-%d", markRoom),
                height = "auto",
                halign = "left",
                textWrap = true,
                interactable = false,
            }
        else
            parts.name = HeroSheetTheme.EllipsisLabel{
                classes = {"heroBuilderCardName"},
                text = "",
                fontSize = 14.5,
                bold = true,
                width = string.format("100%%-%d", markRoom),
                height = "auto",
                halign = "left",
            }
        end
        local children = {parts.name}
        if args.withLine then
            parts.line = gui.Label{
                classes = {"heroBuilderCardLine"},
                text = "",
                fontSize = cond(kind == "text", 11.5, 12.5),
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 2,
                textWrap = true,
                interactable = false,
            }
            children[#children+1] = parts.line
        end
        local content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = cond(kind == "wide" or kind == "kits", "top", "center"),
            interactable = false,
            children = children,
        }
        local marks = {}
        if args.marks then
            parts.diamond = HeroBuilder.Diamond{enter = EnterMark, leave = LeaveMark}
            marks[#marks+1] = parts.diamond
        end
        if args.stars then
            parts.star = HeroBuilder.QuickBuildStar{enter = EnterMark, leave = LeaveMark}
            marks[#marks+1] = parts.star
        end
        marks[#marks+1] = parts.info
        cardArgs.children = {
            content,
            --a little above the padding's top, clear of the line under the name.
            gui.Panel{
                floating = true,
                width = "auto",
                height = INFO_SIZE,
                flow = "horizontal",
                halign = "right",
                valign = "top",
                tmargin = -5,
                children = marks,
            },
        }
    end
    card = gui.Panel(cardArgs)
    return card
end

--- @param card Panel from OptionCard
--- @param option HeroBuilderOption
function HeroBuilder.SetOptionCard(card, option)
    card.data.option = option
    card.data.pending = false
    local parts = card.data.parts
    parts.name.text = option.name
    card:SetClassTree("selected", option.selected)
    card:SetClassTree("unavailable", not option.available and not option.selected)
    parts.info:SetClass("collapsed", option.detail == nil)
    if parts.art ~= nil then
        parts.initials.text = cond(option.art == nil, Initials(option.name), "")
        SetArt(parts.art, option.art)
        --a picked tile, and the tile whose art fills the pane, are framed.
        parts.art.selfStyle.border = cond(option.selected or card:HasClass("heroBuilderShown"), 2, 1)
    else
        if parts.line ~= nil then
            parts.line.text = option.line or ""
            parts.line:SetClass("collapsed", option.line == nil)
        end
        if parts.diamond ~= nil then
            HeroBuilder.SetDiamond(parts.diamond, option.impl, option.selected)
        end
        if parts.star ~= nil then
            HeroBuilder.SetQuickBuildStar(parts.star, option.quickBuild == true, option.selected)
        end
    end
end

--Art tiles keep their art's size; a name wider than the art spills evenly
--either side of it. The tiles sit at one even pitch, just wide enough that
--no two neighbouring names come closer than this, from the left and
--wrapping as needed (not spread across the row).
local TILE_NAME_GAP = 6
--a tile name's plate pads its words this much in all, either side together.
local TILE_NAME_PAD = 8

--- @param grid {kind: string, cards: Panel[], width: nil|number, nameWidths: nil|number[]}
--- @param width number
local function FitTiles(grid, width)
    local art = GRIDS.tiles.min
    local widths = grid.nameWidths or {}
    local least = art + GRIDS.tiles.gap
    --one tile at a time is picked: its name is bold on a plate, its
    --neighbour's plain words beside it.
    local function Plate(nameW)
        return cond(nameW > art, nameW * 1.07, art)
    end
    local function Words(nameW)
        return nameW - TILE_NAME_PAD
    end
    for i = 1, #grid.cards - 1 do
        local leftW = widths[i] or art
        local rightW = widths[i + 1] or art
        local reach = math.max(Plate(leftW) + Words(rightW), Words(leftW) + Plate(rightW)) / 2
        least = math.max(least, reach + TILE_NAME_GAP)
    end
    local count = #grid.cards
    local gap = math.max(GRIDS.tiles.gap, math.ceil(least - art))
    local cols = math.max(1, math.min(count, math.floor((width + gap) / (art + gap))))
    for i, card in ipairs(grid.cards) do
        card.selfStyle.width = art
        card.selfStyle.rmargin = cond(i % cols == 0, 0, gap)
        card.selfStyle.bmargin = GRIDS.tiles.gap
    end
    grid.width = width
end

--- The widths of a tile grid's names as laid out (with the plate's padding,
--- never under the art's width); then the grid is fitted again. A name on a
--- page that has never shown measures wrongly, so this waits until the
--- names have been drawn, trying a few times a second for a while; a page
--- that shows later asks again.
--- @param grid {kind: string, cards: Panel[], width: nil|number, nameWidths: nil|number[], measuring: nil|boolean}
local function MeasureTiles(grid)
    if grid.nameWidths ~= nil or grid.measuring then
        return
    end
    grid.measuring = true
    local tries = 0
    --whether a panel and everything above it is showing (no collapsed ancestor).
    local function Showing(panel)
        local node = panel
        while node ~= nil do
            if node:HasClass("collapsed") then
                return false
            end
            node = node.parent
        end
        return true
    end
    local function Try()
        if mod.unloaded then
            return
        end
        local first = grid.cards[1]
        if first ~= nil and first.valid and not Showing(first) then
            --a hidden page measures wrongly; its next paint while shown asks again.
            grid.measuring = false
            return
        end
        local widths = {}
        for i, card in ipairs(grid.cards) do
            if not card.valid then
                grid.measuring = false
                return
            end
            local name = card.data.parts.name
            if name.renderedHeight <= 0 or name.text == "" then
                tries = tries + 1
                if tries < 40 then
                    dmhub.Schedule(0.25, Try)
                else
                    grid.measuring = false
                end
                return
            end
            local ok, size = pcall(function() return name:CalculatePreferredSize() end)
            widths[i] = cond(ok and size ~= nil, size.x, GRIDS.tiles.min)
        end
        grid.measuring = false
        grid.nameWidths = widths
        if grid.width ~= nil then
            FitTiles(grid, grid.width)
        end
    end
    HeroSheetWindow.AfterLayout(Try)
end

--- Sizes a grid's cards for a width: as many across as fit at the grid's
--- least width, sharing the row. Art tiles keep their size and sit at an
--- even pitch their names fit (FitTiles).
--- @param grid {kind: string, cards: Panel[], width: nil|number, nameWidths: nil|number[], measuring: nil|boolean}
--- @param width number
function HeroBuilder.FitGrid(grid, width)
    if grid.kind == "tiles" then
        FitTiles(grid, width)
        MeasureTiles(grid)
        return
    end
    local spec = GRIDS[grid.kind]
    local cols = math.max(1, math.floor((width + spec.gap) / (spec.min + spec.gap)))
    local cardW = math.floor((width - spec.gap * (cols - 1)) / cols)
    for i, card in ipairs(grid.cards) do
        card.selfStyle.width = cardW
        card.selfStyle.rmargin = cond(i % cols == 0, 0, spec.gap)
        card.selfStyle.bmargin = spec.gap
    end
    grid.width = width
end

--- @class HeroBuilderPaneSpec
--- @field title string the small heading
--- @field status nil|string its state at the right ("Done", "1 to choose")
--- @field statusKind nil|string "ok" or "go"
--- @field lines nil|HeroBuilderPaneLine[] its picks or grants
--- @field none nil|string what shows without lines ("Not chosen", "After you choose a class")
--- @field open nil|boolean still to choose: a gold bar down its left edge
--- @field waits nil|boolean waits on the step's main pick: dashed, bare, not clickable
--- @field boxes nil|{value: string, label: string}[] the characteristics' five boxes

--- One line of a pane block: a name, a muted tag, its (i) at the right.
--- @return Panel
local function PaneLine()
    local line
    local name = HeroSheetTheme.EllipsisLabel{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 14.5,
        width = string.format("100%%-%d", INFO_SIZE + 6),
        height = "auto",
        halign = "left",
        valign = "center",
    }
    local info = HeroBuilder.InfoButton{
        side = "left",
        detail = function()
            local spec = line.data.spec
            if spec == nil or spec.detail == nil then
                return nil
            end
            return spec.detail()
        end,
        extra = {halign = "right"},
    }
    --a Level heading in place of a name (the Class step's You gain).
    local heading = gui.Label{
        classes = {"heroBuilderCaps", "collapsed"},
        text = "",
        uppercase = true,
        fontSize = 10.5,
        bold = true,
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "bottom",
        textWrap = false,
    }
    line = gui.Panel{
        width = "100%",
        height = INFO_SIZE,
        flow = "none",
        tmargin = 5,
        data = {name = name, info = info, heading = heading, spec = nil},
        name,
        info,
        heading,
    }
    return line
end

--- A block of the picks pane, built once; SetPaneBlock paints it.
--- @param click nil|fun() a click on it (scrolls the page to its choice)
--- @return Panel
function HeroBuilder.PaneBlock(click)
    local title = gui.Label{
        classes = {"heroBuilderBlockHead"},
        text = "",
        uppercase = true,
        fontSize = 11.5,
        bold = true,
        width = "100%-100",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    }
    local status = gui.Label{
        classes = {"heroBuilderBlockStatus"},
        text = "",
        fontSize = 12,
        bold = true,
        width = 100,
        height = "auto",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        textWrap = false,
    }
    local lines = gui.Panel{width = "100%", height = "auto", flow = "vertical"}
    local none = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13.5,
        width = "100%",
        height = "auto",
        tmargin = 5,
    }
    --an open choice's gold bar: a floating bar cannot take an auto-height
    --block's height, so it is sized once the block has laid out.
    local bar = gui.Panel{
        classes = {"heroBuilderBlockBar", "collapsed"},
        bgimage = "panels/square.png",
        floating = true,
        width = 3,
        height = 1,
        halign = "left",
        valign = "center",
        x = -12,
        interactable = false,
    }
    local head = gui.Panel{width = "100%", height = 16, flow = "none", title, status}
    local block
    block = gui.Panel{
        classes = {"heroBuilderBlock", cond(click ~= nil, "hoverable", nil)},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 12,
        vpad = 10,
        borderBox = true,
        bmargin = 10,
        data = {title = title, status = status, lines = lines, none = none, bar = bar, head = head, pool = {}, boxes = nil, shown = {}},
        click = function(element)
            if click ~= nil and not element:HasClass("heroBuilderBlockWaits") then
                click()
            end
        end,
        head,
        lines,
        none,
        bar,
    }
    return block
end

--- A name with a small muted word after it (the pick that brings it).
--- @param name string
--- @param tag string
--- @return string rich text
local function TaggedName(name, tag)
    return string.format("%s  <size=80%%><color=%s>%s</color></size>", name, HeroSheetTheme.Palette().cardSub, tag)
end

--- @param block Panel from PaneBlock
--- @param spec HeroBuilderPaneSpec
function HeroBuilder.SetPaneBlock(block, spec)
    local parts = block.data
    parts.title.text = spec.title
    parts.status.text = spec.status or ""
    parts.status:SetClass("collapsed", spec.status == nil)
    parts.status:SetClass("ok", spec.statusKind == "ok")
    parts.status:SetClass("go", spec.statusKind == "go")
    block:SetClass("heroBuilderBlockWaits", spec.waits == true)
    local lines = spec.lines or {}
    --lines are kept and repainted; extras are collapsed, never destroyed.
    for i, lineSpec in ipairs(lines) do
        local line = parts.pool[i]
        if line == nil then
            line = PaneLine()
            parts.pool[i] = line
            parts.lines:AddChild(line)
        end
        line.data.spec = lineSpec
        local text = lineSpec.name
        if lineSpec.tag ~= nil and lineSpec.tag ~= "" then
            text = TaggedName(lineSpec.name, lineSpec.tag)
        end
        local isHeading = lineSpec.heading ~= nil
        line.data.name.text = text
        line.data.name:SetClass("collapsed", isHeading)
        line.data.heading.text = lineSpec.heading or ""
        line.data.heading:SetClass("collapsed", not isHeading)
        line.data.info:SetClass("collapsed", isHeading or lineSpec.detail == nil)
        line:SetClass("collapsed", false)
    end
    for i = #lines + 1, #parts.pool do
        parts.pool[i]:SetClass("collapsed", true)
    end
    parts.none.text = spec.none or ""
    parts.none:SetClass("collapsed", #lines > 0 or spec.none == nil or spec.boxes ~= nil)
    --the characteristics read as five boxes (built the first time).
    if spec.boxes ~= nil and parts.boxes == nil then
        local cells = {}
        for i = 1, 5 do
            local value = gui.Label{classes = {"heroSheetCardStrong"}, text = "", fontSize = 17, bold = true, width = "100%", height = "auto", textAlignment = "center"}
            local label = gui.Label{classes = {"heroSheetCardSub"}, text = "", uppercase = true, fontSize = 9.5, width = "100%", height = "auto", textAlignment = "center"}
            cells[i] = gui.Panel{
                classes = {"heroBuilderBox"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 7,
                width = "18.4%",
                height = "auto",
                vpad = 4,
                borderBox = true,
                rmargin = cond(i < 5, "2%", 0),
                flow = "vertical",
                data = {value = value, label = label},
                value,
                label,
            }
        end
        parts.boxes = gui.Panel{width = "100%", height = "auto", flow = "horizontal", tmargin = 8, children = cells}
        block:AddChild(parts.boxes)
    end
    if parts.boxes ~= nil then
        parts.boxes:SetClass("collapsed", spec.boxes == nil)
        for i, cell in ipairs(parts.boxes.children) do
            local box = (spec.boxes or {})[i]
            cell.data.value.text = box ~= nil and box.value or ""
            cell.data.label.text = box ~= nil and box.label or ""
        end
    end
    local open = spec.open == true and spec.waits ~= true
    parts.bar:SetClass("collapsed", not open)
    if open then
        HeroSheetWindow.AfterLayout(function()
            if not block.valid or not parts.head.valid or parts.head.renderedHeight <= 0 then
                return
            end
            local scale = parts.head.renderedHeight / 16
            parts.bar.selfStyle.height = math.max(1, block.renderedHeight / scale - 2)
        end)
    end
end

--- @class HeroBuilderPaneMainSpec
--- @field kicker string the step's name
--- @field name string
--- @field blurb nil|string
--- @field art nil|string the pick's art (Ancestry and Class show a banner; "" draws its initials)
--- @field detail nil|fun(): nil|HeroBuilderDetail its (i)

--- The pane's block for a step's main pick: its art on Ancestry and
--- Class, its name with an (i), the opening of its words. SetPaneMain paints it.
--- @param click nil|fun()
--- @return Panel
function HeroBuilder.PaneMain(click)
    local art = ArtPanel(nil, "100%", 168, {radius = 9, border = 0})
    local initials = gui.Label{
        classes = {"heroBuilderCaps"},
        text = "",
        fontSize = 52,
        bold = true,
        width = "100%",
        height = "100%",
        textAlignment = "center",
        interactable = false,
    }
    art:AddChild(initials)
    local kicker = gui.Label{
        classes = {"heroBuilderBlockHead"},
        text = "",
        uppercase = true,
        fontSize = 11.5,
        bold = true,
        width = "100%",
        height = "auto",
    }
    local name = HeroSheetTheme.EllipsisLabel{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 20,
        bold = true,
        width = string.format("100%%-%d", INFO_SIZE + 6),
        height = "auto",
        halign = "left",
        valign = "center",
    }
    local block
    local info = HeroBuilder.InfoButton{
        side = "left",
        detail = function()
            local spec = block.data.spec
            if spec == nil or spec.detail == nil then
                return nil
            end
            return spec.detail()
        end,
        extra = {halign = "right"},
    }
    local blurb = gui.Label{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = "auto",
        tmargin = 4,
        textWrap = true,
    }
    block = gui.Panel{
        classes = {"heroBuilderBlock", cond(click ~= nil, "hoverable", nil)},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = 10,
        data = {art = art, initials = initials, kicker = kicker, name = name, info = info, blurb = blurb, spec = nil},
        click = function()
            if click ~= nil then
                click()
            end
        end,
        art,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 12,
            tpad = 10,
            bpad = 12,
            borderBox = true,
            kicker,
            gui.Panel{width = "100%", height = "auto", flow = "none", tmargin = 3, name, info},
            blurb,
        },
    }
    return block
end

--- @param block Panel from PaneMain
--- @param spec HeroBuilderPaneMainSpec
function HeroBuilder.SetPaneMain(block, spec)
    local parts = block.data
    parts.spec = spec
    parts.art:SetClass("collapsed", spec.art == nil)
    if spec.art ~= nil then
        SetArt(parts.art, cond(spec.art ~= "", spec.art, nil))
        parts.initials.text = cond(spec.art == "", Initials(spec.name), "")
    end
    parts.kicker.text = spec.kicker
    parts.name.text = spec.name
    parts.info:SetClass("collapsed", spec.detail == nil)
    parts.blurb.text = spec.blurb or ""
    parts.blurb:SetClass("collapsed", spec.blurb == nil or spec.blurb == "")
end

--- The EotW builder's own rules, kept when it runs this Builder: no Undo
--- or Level picker, Finish only for a complete Hero, its own close button,
--- a single-step mode and locked steps.
--- @class HeroBuilderEotw
--- @field title nil|string the heading in place of Create / Edit Your Hero
--- @field subtitle nil|string the line after the Hero's name, in place of Build at Level
--- @field only nil|string show this step alone: no stepper, Back, Fill or Next (Change Appearance)
--- @field lockedSteps nil|table<string, boolean> steps whose main pick is fixed: the page shows only the chosen card
--- @field closeWords fun(complete: boolean): string, nil|string the close button's words and tooltip, by whether every step is done
--- @field close fun(finished: boolean) closes the Builder: finished when the Hero is complete
--- @field stillToDo fun(steps: string[]): string Finish on an incomplete Hero: the footer line naming the steps left
--- @field reviewBanner nil|fun(hero: string): string Review's banner, in EotW's words ({hero} as the main banner fills it)

--- @class HeroBuilderArgs
--- @field back fun() leaves the Builder for the sheet (Back to the sheet, Finish)
--- @field review nil|fun(review: nil|{top: number, bottom: number}) Review shows the sheet itself between the stepper and footer, top and bottom units from the Builder's edges; nil when another step shows
--- @field host nil|HeroBuilderHost where it shows; nil for the Hero sheet window
--- @field eotw nil|HeroBuilderEotw the Encounter of the Week builder's rules; nil in the main game
--- @field levelUp nil|boolean Level up: the Builder's frame showing one page per Level waiting (Engine().hero.LevelsWaiting), Finish Level N on each

--- Build the Builder. It shows the open Hero (Host().token()) and listens
--- for heroBuilderLayout (width, height in Builder units, from the window),
--- heroBuilderOpen (shown again: back to the first step with picks left) and
--- heroSheetHero (another Hero).
--- @param args HeroBuilderArgs
--- @return Panel
function HeroBuilder.Create(args)
    --this Builder's host is the one on screen from now (and again whenever it opens).
    g_host = args.host
    local eotw = args.eotw
    local levelUp = args.levelUp == true
    local steps = Steps(levelUp)
    --- @type table<string, integer>
    local stepIndex = {}
    --Level up's page steps by their place (Engine().PageKey).
    --- @type table<integer, string>
    local keyStep = {}
    for i, step in ipairs(steps) do
        stepIndex[step.id] = i
        if step.key ~= nil then
            keyStep[step.key] = step.id
        end
    end

    local state = {
        --the step showing; nil picks the first one with picks left.
        step = nil,
        --the layout size, in Builder units.
        width = 1371,
        height = 721,
        --the last failed write's error, shown in the footer until the next
        --action.
        --- @type nil|string
        error = nil,
        --EotW's Finish on an incomplete Hero: the footer names the steps left
        --until the next action.
        --- @type nil|string
        notice = nil,
        --what the last Fill in the rest did: shown in the footer while
        --the step and the build stay as it left them.
        --- @type nil|{count: integer, step: string, key: string}
        filled = nil,
        --Level up: the pages waiting when it opened, lowest first. The row
        --of pills keeps them, Done or not, until it opens again.
        --- @type HeroBuildPage[]
        queue = {},
        --- @type table<string, boolean>
        inQueue = {},
        --the page that shows, so another page starts at its top.
        --- @type nil|string
        shownLevel = nil,
        --Level up without a respite: the Level being taken. The
        --Hero stays at the Level below until Finish; nil on the respite path.
        --- @type nil|integer
        manual = nil,
    }

    local root
    local Paint
    --puts the live card back after a hover's preview (set below).
    --- @type nil|fun()
    local EndPreview = nil
    --builds a step's page ahead of a click (set with the pages below).
    --- @type nil|fun(stepid: nil|string)
    local prewarm = nil

    --Runs a write. If it fails, the footer shows the error until the next action.
    --- @param fn fun()
    local function Guard(fn)
        state.error = nil
        state.notice = nil
        local ok, err = pcall(fn)
        if not ok then
            state.error = tostring(err)
            printf("Hero Builder: %s", state.error)
            Paint()
        end
    end

    --The Hero Level up shows. On the manual path (no respite) it is a copy at the
    --Level being taken, its kept picks applied; writes still go to the Hero
    --(Save raises the Level only while it writes). Kept while the build is.
    --- @type {key: nil|string, token: nil|CharacterToken}
    local view = {key = nil, token = nil}
    --- @return nil|CharacterToken
    local function ViewToken()
        local token = Host().token()
        local manual = state.manual
        if token == nil or token.properties == nil or manual == nil then
            return token
        end
        local key = BuildKey(token) .. "|" .. tostring(manual)
        if view.key ~= key then
            local copy = DeepCopy(token.properties) --[[@as character]]
            Engine().hero.SetLevel(copy, manual)
            copy:Invalidate()
            --a stand-in token: the build engine reads only these from one.
            local shown = {charid = token.charid, properties = copy, name = token.name, portrait = token.portrait}
            view = {key = key, token = shown --[[@as CharacterToken]]}
        end
        return view.token
    end

    --- @param stepid string
    local function GoTo(stepid)
        if state.step == stepid then
            return
        end
        state.step = stepid
        state.error = nil
        if EndPreview ~= nil then
            EndPreview()
        end
        Paint()
    end

    --- title row ---

    local heading = gui.Label{
        classes = {"heroSheetTitle"},
        text = "",
        fontSize = 26,
        bold = true,
        width = "auto",
        height = "auto",
        halign = "left",
        textWrap = false,
    }
    local nameLabel = gui.Label{
        classes = {"heroSheetMuted"},
        text = "",
        fontSize = 14,
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 4,
        textWrap = false,
    }
    local levelPicker = Picker{
        width = 56,
        options = (function()
            local options = {}
            for level = 1, 10 do
                options[#options+1] = {id = level, text = tostring(level)}
            end
            return options
        end)(),
        idChosen = 1,
        change = function(element)
            ---@cast element Dropdown
            local level = tonumber(element.idChosen) or 1
            local token = Host().token()
            if token ~= nil and token.properties:CharacterLevel() ~= level then
                Guard(function() SetLevel(level, nil) end)
            end
        end,
    }
    local slowPicker = Picker{
        width = 180,
        options = (function()
            local options = {{id = 0, text = ""}}
            for i, rung in ipairs(RUNGS) do
                options[#options+1] = {id = i, text = rung}
            end
            return options
        end)(),
        idChosen = 0,
        change = function(element)
            ---@cast element Dropdown
            local rung = tonumber(element.idChosen) or 0
            Guard(function() SetLevel(1, cond(rung > 0, rung, nil)) end)
        end,
    }
    --Slow start sits beside the Level at Level 1 only: the Director always
    --sees it, a player only while their Hero is on a rung.
    local slowGroup = gui.Panel{
        classes = {"collapsed"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        lmargin = 12,
        gui.Label{
            classes = {"heroSheetFieldLabel"},
            text = T("herobuilder.title.slow_start"),
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        },
        slowPicker,
    }
    --Level up names the page's Level after the Hero's name; the
    --Level and slow-start pickers are the Builder's alone.
    local pageLevelLabel = gui.Label{
        classes = {"heroSheetMuted", cond(levelUp, nil, "collapsed")},
        text = "",
        fontSize = 14,
        width = "auto",
        height = "auto",
        valign = "center",
        textWrap = false,
    }
    local subRow = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        tmargin = 1,
        nameLabel,
        pageLevelLabel,
        gui.Label{
            classes = {"heroSheetMuted", cond(levelUp or eotw ~= nil, "collapsed", nil)},
            text = T("herobuilder.title.build_at_level"),
            fontSize = 14,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        },
        levelPicker,
        slowGroup,
        --EotW's line in Build at Level's place (its Level comes from the town).
        gui.Label{
            classes = {"heroSheetMuted", cond(eotw ~= nil and eotw.subtitle ~= nil, nil, "collapsed")},
            text = eotw ~= nil and eotw.subtitle or "",
            fontSize = 14,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
        },
    }
    levelPicker:SetClass("collapsed", levelUp or eotw ~= nil)

    local PaintUndo
    local undoButton = Button{
        text = T("herobuilder.title.undo"),
        click = function()
            if not TurnHistoryTakesUndo() then
                dmhub.Undo()
            end
        end,
        --a combat turn can start or end while the Builder shows.
        think = function()
            PaintUndo()
        end,
        tooltip = function()
            if TurnHistoryTakesUndo() then
                return T("herobuilder.title.undo_off")
            end
            local undo = dmhub.undoState
            if undo ~= nil and undo.undoDescription ~= nil then
                return T("herobuilder.title.undo_tooltip", {change = undo.undoDescription})
            end
            return nil
        end,
    }
    PaintUndo = function()
        local undo = dmhub.undoState
        local off = undo == nil or undo.undoDescription == nil or TurnHistoryTakesUndo()
        if off ~= undoButton:HasClass("heroSheetDisabled") then
            undoButton:SetClass("heroSheetDisabled", off)
        end
    end
    --whether every step is done, for EotW's close button (Paint keeps it).
    local allComplete = false
    local backToSheet = Button{
        text = T("herobuilder.title.back_to_sheet"),
        click = function()
            HeroBuilder.ClosePinned()
            if eotw ~= nil then
                eotw.close(allComplete)
                return
            end
            args.back()
        end,
        tooltip = function()
            if eotw ~= nil then
                local _, tip = eotw.closeWords(allComplete)
                return tip
            end
            return nil
        end,
    }
    backToSheet.selfStyle.lmargin = 7
    --EotW's writes are not undoable.
    undoButton:SetClass("collapsed", eotw ~= nil)

    local headRow = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = HEAD_ROW_HEIGHT,
        flow = "horizontal",
        hpad = 16,
        borderBox = true,
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            heading,
            subRow,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            undoButton,
            backToSheet,
        },
    }

    --- the stepper ---

    --Other choices shows only while something asks for one; Paint
    --keeps this up to date, and the pills, Back and Next follow it.
    local otherShown = false
    --the stepper row's width, for refitting the pills when a step shows or hides.
    local pillRowW = 1300

    --- @param stepid string
    --- @return boolean
    local function StepShown(stepid)
        if levelUp then
            return state.inQueue[stepid] == true
        end
        if eotw ~= nil then
            if eotw.only ~= nil then
                return stepid == eotw.only
            end
            --EotW's Review is its own sheet, read only, when the host shows one.
            if stepid == REVIEW then
                return args.review ~= nil
            end
        end
        return stepid ~= OTHER or otherShown
    end

    --- The step the page machinery builds for a step: Level up's pages are
    --- the Class step's, one Level's choices at a time.
    --- @param stepid string
    --- @return string
    local function PageStep(stepid)
        return cond(levelUp, "class", stepid)
    end

    --- The next shown step from the step at index i, going dir (1 or -1).
    --- @param i integer
    --- @param dir integer
    --- @return nil|integer
    local function Neighbour(i, dir)
        local index = i + dir
        while steps[index] ~= nil do
            if StepShown(steps[index].id) then
                return index
            end
            index = index + dir
        end
        return nil
    end

    --a pill's padding either side, its mark's width, and the gap between the
    --mark and the step's name: FitPills sizes pills from them.
    local PILL_PAD = 8
    local PILL_MARK = 22
    local PILL_TITLE_GAP = 8

    --each pill's parts, painted in place: {pill, mark, number, tick, title, sub}.
    local pills = {}
    local pillPanels = {}
    for i, step in ipairs(steps) do
        local number = gui.Label{
            classes = {"heroBuilderMarkText"},
            text = tostring(i),
            fontSize = 11,
            bold = true,
            width = "100%",
            height = "100%",
            textAlignment = "center",
            interactable = false,
        }
        local tick = gui.Panel{
            classes = {"heroBuilderTick", "collapsed"},
            bgimage = "phosphor/check-bold.png",
            width = 12,
            height = 12,
            halign = "center",
            valign = "center",
            interactable = false,
        }
        local mark = gui.Panel{
            classes = {"heroBuilderMark"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 11,
            width = PILL_MARK,
            height = PILL_MARK,
            valign = "center",
            interactable = false,
            number,
            tick,
        }
        local title = gui.Label{
            classes = {"heroSheetTitle"},
            text = step.title,
            fontSize = 13.5,
            bold = true,
            width = "100%",
            height = "auto",
            textWrap = false,
            interactable = false,
        }
        --a long pick ends in an ellipsis; its pill names it in full on hover.
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = {"heroBuilderPillSub"},
            text = "",
            fontSize = 11.5,
            width = "100%",
            height = "auto",
        }
        local stepid = step.id
        local pill = gui.Panel{
            classes = {"heroBuilderPill", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 10,
            width = 150,
            height = STEPPER_HEIGHT,
            hpad = PILL_PAD,
            borderBox = true,
            flow = "horizontal",
            rmargin = cond(i < #steps, PILL_GAP, 0),
            click = function(element)
                GoTo(stepid)
            end,
            hover = function(element)
                if prewarm ~= nil then
                    prewarm(stepid)
                end
            end,
            mark,
            gui.Panel{
                width = string.format("100%%-%d", PILL_MARK + PILL_TITLE_GAP),
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = PILL_TITLE_GAP,
                title,
                sub,
            },
        }
        pills[stepid] = {pill = pill, mark = mark, number = number, tick = tick, sub = sub}
        pillPanels[#pillPanels+1] = pill
    end
    local stepper = gui.Panel{
        width = "100%",
        height = STEPPER_HEIGHT,
        flow = "horizontal",
        tmargin = STEPPER_GAP,
        children = pillPanels,
    }

    --Pills size to their step names, and share what is left of the row: a
    --name's room is at least 100 units.
    --- @param rowW number
    local function FitPills(rowW)
        pillRowW = rowW
        local natural = {}
        local total = 0
        local count = 0
        for i, step in ipairs(steps) do
            if StepShown(step.id) then
                local textW = math.max(100, math.ceil(HeroSheetTheme.TextWidth(step.title, 13.5) * 0.9))
                natural[i] = PILL_PAD + PILL_MARK + PILL_TITLE_GAP + textW + PILL_PAD
                total = total + natural[i]
                count = count + 1
            end
        end
        local extra = math.max(0, rowW - total - PILL_GAP * (count - 1))
        local each = math.floor(extra / math.max(1, count))
        local last = nil
        for i, step in ipairs(steps) do
            local pill = pills[step.id].pill
            pill:SetClass("collapsed", natural[i] == nil)
            if natural[i] ~= nil then
                pill.selfStyle.width = natural[i] + each
                pill.selfStyle.rmargin = PILL_GAP
                last = pill
            end
        end
        if last ~= nil then
            last.selfStyle.rmargin = 0
        end
    end

    --- the body ---

    local card = HeroSheetCard.BuilderCard(Host().block, Host().token)
    local cardColumn = gui.Panel{
        width = 300,
        height = 500,
        flow = "vertical",
        card,
    }

    --- the page ---

    local pageTitle = gui.Label{
        classes = {"heroSheetTitle"},
        text = "",
        fontSize = 26,
        bold = true,
        width = "100%",
        height = "auto",
    }
    --the gap above the lead under the page's title, and above each section
    --and Level header; ScrollToSection adds them up to find a section.
    local LEAD_GAP = 4
    local SECTION_GAP = 18
    local pageLead = gui.Label{
        classes = {"heroSheetMuted"},
        text = "",
        fontSize = 14.5,
        width = "100%",
        height = "auto",
        tmargin = LEAD_GAP,
        textWrap = true,
    }
    --a manual Level up's note under the lead: when the Level
    --rises, and what that does to the experience.
    local pageNote = gui.Label{
        classes = {"heroSheetMuted", "collapsed"},
        text = "",
        fontSize = 14.5,
        width = "100%",
        height = "auto",
        tmargin = 4,
        textWrap = true,
    }
    --the step's sections: one holder per step, built for its shape and kept.
    local pageContent = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    local pageBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        rpad = 6,
        bpad = 16,
        borderBox = true,
        pageTitle,
        pageLead,
        pageNote,
        pageContent,
    }
    --scrolls only once the page is taller than it: a scrolling panel lays out
    --everything in it on every change, which costs time on a long page.
    local pageScroll = gui.Panel{
        width = "100%",
        height = 400,
        flow = "vertical",
        valign = "top",
        vscroll = false,
        pageBody,
    }
    local page = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = 640,
        height = 500,
        lmargin = COLUMN_GAP,
        flow = "vertical",
        tpad = 14,
        hpad = 18,
        borderBox = true,
        pageScroll,
    }

    --- the picks pane: "Your <step>", one block per choice ---

    local paneTitle = gui.Label{
        classes = {"heroSheetTitle"},
        text = "",
        fontSize = 20,
        bold = true,
        width = "100%-120",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    --Skills & Languages' picks left, at the heading's right end.
    local paneStatus = gui.Label{
        classes = {"heroBuilderBlockStatus", "collapsed"},
        text = "",
        fontSize = 12,
        bold = true,
        width = 120,
        height = "auto",
        halign = "right",
        valign = "center",
        textAlignment = "right",
        textWrap = false,
    }
    --each step's blocks: one holder per step, built for its shape and kept.
    local paneContent = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 10,
    }
    local paneScroll = gui.Panel{
        width = "100%",
        height = 400,
        flow = "vertical",
        valign = "top",
        vscroll = false,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            hpad = 16,
            vpad = 14,
            borderBox = true,
            gui.Panel{width = "100%", height = 28, flow = "none", paneTitle, paneStatus},
            paneContent,
        },
    }

    --The art showcase: before a pick on Ancestry or Class, the hovered
    --tile's whole art fills the pane, uncovered (the art is the draw). Only
    --its step and name sit on a fade at the foot,
    --tying the picture to its tile across the page; its words are on the
    --tile's (i).
    local artImage = ArtPanel(nil, "100%", "100%", {radius = 10, border = 0})
    local artInitials = gui.Label{
        classes = {"heroBuilderCaps"},
        text = "",
        fontSize = 96,
        bold = true,
        width = "100%",
        height = "60%",
        textAlignment = "center",
        interactable = false,
    }
    artImage:AddChild(artInitials)
    local artKicker = gui.Label{
        classes = {"heroSheetCardLabel"},
        text = "",
        fontSize = 11.5,
        bold = true,
        width = "100%",
        height = "auto",
    }
    local artTitle = gui.Label{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 22,
        bold = true,
        width = "100%",
        height = "auto",
        tmargin = 1,
    }
    --the fade runs from dark at the foot (y 0) to clear above the words.
    local artStrip = gui.Panel{
        bgimage = true,
        bgcolor = "white",
        gradient = gui.Gradient{
            point_a = {x = 0, y = 0},
            point_b = {x = 0, y = 1},
            stops = {
                {position = 0, color = "#0a0a09e6"},
                {position = 0.5, color = "#0a0a09b0"},
                {position = 1, color = "#0a0a0900"},
            },
        },
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        valign = "bottom",
        flow = "vertical",
        hpad = 16,
        tpad = 30,
        bpad = 12,
        borderBox = true,
        interactable = false,
        artKicker,
        artTitle,
    }
    local paneArt = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        flow = "none",
        artImage,
        artStrip,
    }

    local pane = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = 340,
        height = 500,
        lmargin = COLUMN_GAP,
        flow = "none",
        paneScroll,
        paneArt,
    }

    --Turns a scrolling column's scroll on once its content is taller than it,
    --and off again when it fits, after the content has laid out.
    --- @param scroller Panel
    local function FitScroll(scroller)
        HeroSheetWindow.AfterLayout(function()
            if not scroller.valid then
                return
            end
            local content = scroller.children[1]
            if content == nil or not content.valid then
                return
            end
            local over = content.renderedHeight > scroller.renderedHeight + 0.5
            if (scroller.vscroll == true) ~= over then
                scroller.vscroll = over
            end
            --the engine then skips cards well outside the view, so a long page scrolls
            --faster. Set only once the scroll view exists: before that the engine errors.
            if over and scroller == pageScroll and not scroller.hideObjectsOutOfScroll then
                scroller.hideObjectsOutOfScroll = true
            end
        end)
    end

    --The art showcase's tile: {stepid, key, card}, or nil.
    local showcase = nil

    --Fills the pane with an option's whole art and its name, or puts
    --the pane's blocks back with nil.
    --- @param spec nil|HeroBuilderDetail
    local function ShowArt(spec)
        paneArt:SetClass("collapsed", spec == nil)
        paneScroll:SetClass("collapsed", spec ~= nil)
        if spec == nil then
            return
        end
        local art = type(spec.art) == "string" and spec.art ~= "" and spec.art or nil
        SetArt(artImage, art)
        artInitials.text = cond(art == nil, Initials(spec.title or ""), "")
        artKicker.text = string.upper(spec.kicker or "")
        artTitle.text = spec.title or ""
    end

    --The tile whose art fills the pane is outlined: the shown tile's
    --art and name take the strong colour.
    --- @param tile nil|Panel
    local function MarkShown(tile)
        if showcase ~= nil and showcase.card ~= nil and showcase.card.valid and showcase.card ~= tile then
            showcase.card:SetClassTree("heroBuilderShown", false)
            showcase.card.data.parts.art.selfStyle.border = 1
        end
        if tile ~= nil and tile.valid then
            tile:SetClassTree("heroBuilderShown", true)
            tile.data.parts.art.selfStyle.border = 2
        end
    end

    --options whose (i) card has been reported as viewed, this time the Builder is open.
    local viewed = {}

    --- writing ---

    --One change to the Hero, saved as one undo step, then the Builder and the
    --card repaint from it. On a manual Level up the change is made at the
    --Level being taken; pass asIs = true to write the Hero at its own Level
    --(Finish and Cancel do).
    --- @param description string the undo list's words
    --- @param fn fun(hero: character)
    --- @param asIs nil|boolean
    local function Save(description, fn, asIs)
        local manual = state.manual
        if manual ~= nil and not asIs then
            local inner = fn
            fn = function(hero)
                Engine().hero.AtLevel(hero, manual, function() inner(hero) end)
            end
        end
        Guard(function()
            SaveOrRaise(description, fn)
            Host().changed()
        end)
    end

    --Changing a main pick that other picks hang on asks first, listing what goes.
    --- @param args {stepid: string, from: string, lines: string[], apply: fun()}
    local function ConfirmChange(args)
        local titles = {ancestry = T("herobuilder.confirm.title_ancestry"), career = T("herobuilder.confirm.title_career"), class = T("herobuilder.confirm.title_class")}
        local changes = {ancestry = T("herobuilder.confirm.change_ancestry"), career = T("herobuilder.confirm.change_career"), class = T("herobuilder.confirm.change_class")}
        local frame
        local bullets = {}
        for _, line in ipairs(args.lines) do
            bullets[#bullets+1] = gui.Label{
                classes = {"heroSheetCardText"},
                text = "\u{2022} " .. line,
                fontSize = 14,
                width = "100%",
                height = "auto",
                lmargin = 8,
                tmargin = 3,
            }
        end
        local content = gui.Panel{
            width = 520,
            height = "auto",
            flow = "vertical",
            pad = 18,
            borderBox = true,
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = titles[args.stepid],
                fontSize = 18,
                bold = true,
                width = "100%",
                height = "auto",
            },
            gui.Label{
                classes = {"heroSheetCardText"},
                text = T("herobuilder.confirm.body", {from = args.from}),
                fontSize = 14,
                width = "100%",
                height = "auto",
                tmargin = 8,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                tmargin = 4,
                children = bullets,
            },
            gui.Label{
                classes = {"heroSheetCardSub"},
                text = T("herobuilder.confirm.note"),
                fontSize = 13,
                width = "100%",
                height = "auto",
                tmargin = 10,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 14,
                HeroSheetTheme.WindowButton(T("herobuilder.confirm.keep", {from = args.from}), function()
                    HeroSheetWindow.ClosePopup(frame)
                end, false),
                HeroSheetTheme.WindowButton(changes[args.stepid], function()
                    HeroSheetWindow.ClosePopup(frame)
                    args.apply()
                end, true),
            },
        }
        --the frame's height: the title, body, note and buttons, then one line
        --per bullet. A bullet that wraps makes the content scroll.
        local CONFIRM_FIXED_HEIGHT = 160
        local CONFIRM_LINE_HEIGHT = 22
        frame = HeroSheetWindow.ShowPopup{
            content = content,
            width = 520,
            height = CONFIRM_FIXED_HEIGHT + CONFIRM_LINE_HEIGHT * #args.lines,
            modal = true,
        }
    end

    --- What a click on a card changes, as a change to make to a Hero; nil when
    --- a click changes nothing. A click saves it; a hover makes it on a
    --- copy of the Hero to preview it, so the two always agree.
    --- @param stepid string
    --- @param sectionKey string "base", or the choice row's id
    --- @param option HeroBuilderOption
    --- @param preview nil|boolean for a preview: a card that cannot be picked still shows what it would do
    --- @return nil|fun(hero: character)
    local function PickChange(stepid, sectionKey, option, preview)
        local build = Engine().hero
        local id = option.id
        if sectionKey == "base" then
            if stepid == "complication" then
                if id == "" then
                    return function(hero) build.SetComplication(hero, nil) end
                end
                return function(hero) build.ToggleComplication(hero, id) end
            elseif option.selected then
                return nil
            elseif stepid == "ancestry" then
                return function(hero) build.SetAncestry(hero, id) end
            elseif stepid == "career" then
                return function(hero) build.SetCareer(hero, id) end
            elseif stepid == "class" then
                return function(hero) build.SetClass(hero, id) end
            elseif stepid == "culture" then
                return function(hero) build.SetCultureAggregate(hero, id, false) end
            end
            return nil
        elseif option.arrayIndex ~= nil then
            --the characteristics always hold an array: nothing to drop.
            if option.selected then
                return nil
            end
            local index = option.arrayIndex --[[@as integer]]
            return function(hero) build.SetCharacteristics(hero, index, nil) end
        elseif option.selected then
            return function(hero) build.Unchoose(hero, stepid, sectionKey, id) end
        elseif option.available or preview then
            return function(hero) build.Choose(hero, stepid, sectionKey, id) end
        end
        return nil
    end

    --A step's main pick: the change confirm first when picks hang on it.
    --- @param stepid string
    --- @param option HeroBuilderOption
    --- @return boolean saved now (false when nothing changed or a confirm asks first)
    local function PickBase(stepid, option)
        local token = Host().token()
        if token == nil then
            return false
        end
        local hero = token.properties --[[@as character]]
        if stepid == "complication" then
            Save(cond(option.id == "", T("herobuilder.undo.no_complication"), T("herobuilder.undo.change_complications")), PickChange(stepid, "base", option) --[[@as fun(hero: character)]])
            return true
        end
        if option.selected then
            return false
        end
        local previous = nil
        local fromName = nil
        if stepid == "ancestry" then
            previous = hero:try_get("raceid")
            local race = Engine().hero.Ancestry(hero)
            fromName = race ~= nil and HeroBuild.SaidName(race.name) or nil
        elseif stepid == "career" then
            previous = hero:try_get("backgroundid")
            local career = Engine().hero.Career(hero)
            fromName = career ~= nil and career.name or nil
        elseif stepid == "class" then
            local classItem = hero:GetClass()
            previous = classItem ~= nil and classItem.id or nil
            fromName = classItem ~= nil and classItem.name or nil
        end
        local change = PickChange(stepid, "base", option)
        if change == nil then
            return false
        end
        local function Apply()
            Save(CHANGE_WORDS[stepid], change)
            if stepid ~= "culture" then
                Track("build_change", {
                    changeType = stepid,
                    newValue = option.id,
                    previousValue = previous,
                    dailyLimit = 10,
                })
            end
        end
        --what the change clears: every pick the step's rows hold. A first
        --pick (or culture's, which has no confirm) asks nothing, so the rows
        --are only read when a confirm could follow, from the kept status.
        local lines = {}
        if fromName ~= nil then
            for _, stepStatus in ipairs(Status(token).steps) do
                if stepStatus.id == stepid then
                    for _, row in ipairs(stepStatus.rows) do
                        if not row.base and #(row.selectedNames or {}) > 0 then
                            lines[#lines+1] = string.format("%s: %s", row.name, table.concat(row.selectedNames, ", "))
                        end
                    end
                end
            end
        end
        --a culture that follows the ancestry says what it becomes. It never asks
        --by itself: any culture pick turns the follow off, so it holds none.
        if stepid == "ancestry" and #lines > 0 then
            local culture = hero:try_get("culture")
            local untouched = true
            for _, aspectId in pairs(culture ~= nil and culture.aspects or {}) do
                if aspectId ~= "" then
                    untouched = false
                end
            end
            local followsid = Engine().AncestryCultureId((dmhub.GetTableVisible(Race.tableName) or {})[option.id])
            local follows = followsid ~= nil and (dmhub.GetTableVisible(Culture.tableName) or {})[followsid] or nil
            if follows ~= nil and not untouched and hero:try_get(Engine().AUTO_CULTURE_FIELD, false) == true then
                lines[#lines+1] = T("herobuilder.confirm.culture_follows", {culture = follows.name})
            end
        end
        if #lines == 0 or fromName == nil then
            Apply()
            return true
        end
        ConfirmChange{stepid = stepid, from = fromName, lines = lines, apply = Apply}
        return false
    end

    --A card in a step's page was clicked: its section says what that does.
    --- @param stepid string
    --- @param sectionKey string "base", or the choice row's id
    --- @param option HeroBuilderOption
    --- @return boolean saved now
    local function Pick(stepid, sectionKey, option)
        if not Host().canWrite() then
            return false
        end
        if sectionKey == "base" then
            return PickBase(stepid, option)
        end
        local change = PickChange(stepid, sectionKey, option)
        if change == nil then
            return false
        elseif option.selected then
            --clicking a pick drops it.
            Save(T("herobuilder.undo.drop_pick"), change)
            Track("ability_respec", {featureId = sectionKey, removedOptionId = option.id, removedOptionName = option.name, dailyLimit = 10})
        else
            Save(T("herobuilder.undo.make_choice"), change)
            Track("builder_selection", {featureId = sectionKey, optionId = option.id, optionName = option.name, isFinal = true, dailyLimit = 20})
        end
        return true
    end

    --- live-card previews ---

    --How long the pointer rests on a card before its preview is worked out,
    --so sweeping across a page works nothing out.
    local PREVIEW_DWELL = 0.08
    --How long the card waits after the pointer leaves before showing the
    --Hero again, so moving straight onto the next card does not flick back.
    local PREVIEW_LEAVE = 0.06
    --previews by option, kept while the build is unchanged: working one out
    --makes the pick on a copy of the Hero, which is slow across a whole row.
    --- @type {key: nil|string, before: nil|HeroSheetCardNumbers, specs: table<string, HeroSheetCardPreview|false>}
    local previewCache = {key = nil, before = nil, specs = {}}
    --a newer hover or a leave cancels a preview still waiting.
    local previewGen = 0
    --the card under the pointer. Moving from one card to the next can report
    --the old card's leave after the new card's hover; only the card under
    --the pointer may end its preview.
    --- @type nil|Panel
    local previewCard = nil
    --where the pointer was at the last card hover (screen pixels).
    --- @type nil|{x: number, y: number}
    local previewPointer = nil

    --- True when the pointer itself moved since the last card hover. Scrolling
    --- a page slides cards under a still pointer, each one reporting a hover;
    --- those cards should not preview.
    --- @return boolean
    local function PointerMoved()
        local ok, pos = pcall(function() return dmhub.mouseScreenPosition end)
        if not ok or pos == nil then
            return true
        end
        local moved = previewPointer == nil or previewPointer.x ~= pos.x or previewPointer.y ~= pos.y
        previewPointer = {x = pos.x, y = pos.y}
        return moved
    end

    --- Shows on the live card what clicking an option would change: the pick
    --- is made on a copy of the Hero, so the Hero itself is never touched and
    --- nothing previewed can upload.
    --- @param stepid string
    --- @param sectionKey string
    --- @param option HeroBuilderOption
    --- @param element Panel the hovered card
    local function PreviewOption(stepid, sectionKey, option, element)
        previewGen = previewGen + 1
        previewCard = element
        local gen = previewGen
        --a card arriving under a still pointer (the page scrolling) shows the
        --Hero, not a preview: moving the pointer onto it previews it.
        if not PointerMoved() then
            if card.valid then
                card.data.preview(nil)
            end
            return
        end
        dmhub.Schedule(PREVIEW_DWELL, function()
            if mod.unloaded or gen ~= previewGen or previewCard ~= element or not card.valid then
                return
            end
            --a manual Level up previews on its copy at the Level being taken.
            local token = ViewToken()
            local change = PickChange(stepid, sectionKey, option, true)
            if token == nil or token.properties == nil or change == nil then
                card.data.preview(nil)
                return
            end
            local key = BuildKey(token)
            if previewCache.key ~= key then
                previewCache = {key = key, before = HeroSheetCard.BuilderNumbers(token.properties), specs = {}}
            end
            local id = table.concat({stepid, sectionKey, tostring(option.id), tostring(option.selected)}, "|")
            local spec = previewCache.specs[id]
            if spec == nil then
                spec = false
                local copy = DeepCopy(token.properties) --[[@as character]]
                if pcall(change, copy) then
                    pcall(function() copy:Invalidate() end)
                    spec = HeroSheetCard.BuilderPreview(previewCache.before --[[@as HeroSheetCardNumbers]], HeroSheetCard.BuilderNumbers(copy)) or false
                end
                previewCache.specs[id] = spec
            end
            card.data.preview(spec or nil)
        end)
    end

    --- The pointer left a card: the Hero shows again after a moment, unless
    --- it has already reached another card.
    --- @param element Panel
    local function LeavePreview(element)
        if previewCard ~= element then
            return
        end
        previewCard = nil
        previewGen = previewGen + 1
        local gen = previewGen
        dmhub.Schedule(PREVIEW_LEAVE, function()
            if not mod.unloaded and gen == previewGen and previewCard == nil and card.valid then
                card.data.preview(nil)
            end
        end)
    end

    EndPreview = function()
        previewGen = previewGen + 1
        previewCard = nil
        if card.valid then
            card.data.preview(nil)
        end
    end

    --A pick made at random, as CharacterBuilder rolls: the dice roll in
    --the open, then the row they land on is picked. The dice take a moment,
    --so the pick is dropped if the Builder has moved to another Hero by then.
    --- @param roll string dice, "1d6"
    --- @param description string what the roll says it is for
    --- @param land fun(total: number) the pick for a result
    local function RollFor(roll, description, land)
        local token = Host().token()
        if token == nil or not Host().canWrite() then
            return
        end
        local charid = token.charid
        dmhub.Roll{
            roll = roll,
            description = description,
            tokenid = charid,
            complete = function(rollResult)
                local live = Host().token()
                if mod.unloaded or live == nil or live.charid ~= charid or rollResult == nil then
                    return
                end
                land(rollResult.total)
            end,
        }
    end

    --- Roll an inciting incident: the career's table for the row (its id is
    --- the table's), and the row the dice land on is the pick.
    --- @param section HeroBuilderSection
    local function RollIncident(section)
        local token = Host().token()
        local career = token ~= nil and Engine().hero.Career(token.properties --[[@as character]]) or nil
        --- @type nil|RollTable
        local found = nil
        for _, characteristic in ipairs(career ~= nil and career:try_get("characteristics", {}) or {}) do
            if characteristic.tableid == section.key then
                found = characteristic:GetRollTable()
            end
        end
        if found == nil then
            return
        end
        local rollTable = found
        local info = rollTable:CalculateRollInfo()
        if info == nil then
            return
        end
        RollFor(info.roll, section.title, function(total)
            local index = rollTable:RowIndexFromDiceResult(total)
            local row = index ~= nil and rollTable.rows[index] or nil
            if row == nil then
                return
            end
            Save(T("herobuilder.undo.make_choice"), function(hero) Engine().hero.Choose(hero, "career", section.key, row.id) end)
            Track("builder_selection", {featureId = section.key, optionId = row.id, isFinal = true, dailyLimit = 20})
        end)
    end

    --- Roll a complication: one of those offered and not held yet, in name
    --- order, as CharacterBuilder rolls over its list; the roll adds it.
    local function RollComplication()
        local token = Host().token()
        if token == nil then
            return
        end
        local hero = token.properties --[[@as character]]
        local held = {}
        for _, id in ipairs(Engine().hero.ComplicationIds(hero)) do
            held[id] = true
        end
        local open = {}
        for _, entry in ipairs(Engine().BaseOptions(hero, "complication")) do
            if not held[entry.id] then
                open[#open+1] = entry
            end
        end
        if #open == 0 then
            return
        end
        --d10s read as digits (two make 1-100), spread over the list: a Hero's
        --dice set skins only d3, d6 and d10, so a 1d99 rolled default dice.
        local roll, faces = "1d10", 10
        --each extra d10 is the next digit up: 1d10*100+1d10*10+1d10.
        while faces < #open do
            roll = string.format("1d10*%d+%s", faces, roll)
            faces = faces * 10
        end
        if faces > 10 then
            roll = string.format("%s-%d", roll, (faces - 10) // 9)
        end
        RollFor(roll, T("herobuilder.roll.complication_description"), function(total)
            local entry = open[math.max(1, math.min(#open, math.ceil(total * #open / faces)))]
            --held by now (picked while the dice rolled): a toggle would drop it.
            local live = Host().token()
            if live == nil then
                return
            end
            for _, id in ipairs(Engine().hero.ComplicationIds(live.properties --[[@as character]])) do
                if id == entry.id then
                    return
                end
            end
            Save(T("herobuilder.undo.change_complications"), function(liveHero) Engine().hero.ToggleComplication(liveHero, entry.id) end)
        end)
    end

    --- cards and sections ---

    --The page's inner width, which the card grids are fitted to.
    local innerW = 560
    --the pages built so far, by step: {holder, shape, sections, key, width, pane, fresh}.
    local built = {}
    local shownPage = nil
    --Level up's Skills & Languages block (PaintLevelSkills builds it): one page's
    --skill and language choices. sig names the choices and widths it was built for.
    --- @type nil|{sig: string, key: nil|string, page: Panel, pane: Panel, sections: table<string, Panel>, controls: table<string, HeroSkillsPanelControl>}
    local levelSkills = nil
    --the shown Level up page's skill and language choices (LevelStatus pools), for the footer.
    --- @type nil|table<string, table<string, integer>>
    local levelPools = nil

    --- @param grid {kind: string, cards: Panel[], width: nil|number, nameWidths: nil|number[], measuring: nil|boolean}
    local function FitGrid(grid)
        --the five characteristic tiles share the page's width.
        if grid.kind == "chars" then
            local tileW = math.floor((innerW - 8 * (#grid.cards - 1)) / math.max(1, #grid.cards))
            for i, tile in ipairs(grid.cards) do
                tile.selfStyle.width = tileW
                tile.selfStyle.rmargin = cond(i == #grid.cards, 0, 8)
            end
            grid.width = innerW
            return
        end
        HeroBuilder.FitGrid(grid, innerW)
    end

    --Before a pick on Ancestry or Class, a tile's hover fills the pane with
    --its art and the pane keeps it; after a pick a tile's hover previews on
    --the live card instead.
    --- @param stepid string
    --- @param option HeroBuilderOption
    --- @param tile Panel
    local function TileHover(stepid, option, tile)
        local entry = built[stepid]
        if entry == nil or not entry.fresh or (stepid ~= "ancestry" and stepid ~= "class") then
            return
        end
        if showcase ~= nil and showcase.key == option.id and showcase.stepid == stepid then
            return
        end
        local ok, spec = pcall(option.detail)
        if not ok or spec == nil then
            return
        end
        MarkShown(tile)
        showcase = {stepid = stepid, key = option.id, card = tile, spec = spec}
        ShowArt(spec)
    end

    --- A section's heading: its name in tan capitals, an optional muted
    --- note, the state plate at the right (or another panel there, such as
    --- the languages' search), and the faint rule under it.
    --- @param title string
    --- @param right nil|Panel replaces the state plate at the heading's right
    --- @param before nil|Panel sits just before the state plate (a list's search)
    --- @return Panel[] the heading and its rule, to start the section with
    --- @return Panel status the state plate
    --- @return Panel note
    local function SectionHead(title, right, before)
        local status = gui.Label{
            classes = {"heroBuilderStatus"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            text = "",
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            hpad = 10,
            vpad = 2,
            borderBox = true,
            halign = "right",
            valign = "center",
            textWrap = false,
        }
        local note = gui.Label{
            classes = {"heroSheetMuted"},
            text = "",
            fontSize = 12.5,
            width = "auto",
            height = "auto",
            lmargin = 10,
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        local caps = gui.Label{
            classes = {"heroBuilderCaps"},
            text = title,
            uppercase = true,
            fontSize = 12,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        }
        local row = {caps, note, status}
        --a panel in the plate's place keeps the plate, collapsed: every panel
        --made must be attached, or the engine reports it.
        if right ~= nil then
            right.selfStyle.halign = "right"
            right.selfStyle.valign = "center"
            status:SetClass("collapsed", true)
            row = {caps, note, right, status}
        elseif before ~= nil then
            --the plate sits at the right end; the field just before it.
            before.selfStyle.halign = "right"
            before.selfStyle.valign = "center"
            before.selfStyle.rmargin = 10
            row = {caps, note, before, status}
        end
        return {
            gui.Panel{
                width = "100%",
                height = 26,
                flow = "horizontal",
                bmargin = 6,
                children = row,
            },
            gui.Panel{classes = {"heroBuilderRule"}, bgimage = "panels/square.png", width = "100%", height = 1},
        }, status, note
    end

    --- A section's outer panel: a clear ring that a pane block's click lights
    --- for a moment (Flash).
    --- @param children Panel[]
    --- @param tmargin nil|number the gap above it (SECTION_GAP by default)
    --- @return Panel
    local function SectionPanel(children, tmargin)
        return gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 2,
            borderColor = "#00000000",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = tmargin or SECTION_GAP,
            data = {},
            children = children,
        }
    end

    local BuildCharacteristics
    local LevelHeader

    --The characteristic picked first for a click-swap, by id; nil when none.
    local charPick = nil
    --the shown characteristics section's tiles, for repainting the gold ring.
    --- @type table<string, Panel>
    local charTiles = {}

    local function PaintCharPick()
        for id, tile in pairs(charTiles) do
            if tile.valid then
                tile:SetClass("selected", charPick == id)
            end
        end
    end

    --A characteristic being dragged: the chip on the pointer, where the
    --pointer started (pop-up layer units), and the tile it is over.
    --- @type nil|{tile: Panel, chip: Panel, start: {x: number, y: number}, over: nil|Panel}
    local charDrag = nil

    --- Where the pointer is during a tile's drag: its start plus how far it
    --- has moved (the engine finds no targets while the tile stays put, so
    --- the Builder hit-tests the pointer, as the Inventory's drag does).
    --- @param tile Panel
    --- @return {x: number, y: number}
    local function CharDragPointer(tile)
        local start = charDrag ~= nil and charDrag.start or {x = 0, y = 0}
        local delta = tile.dragDelta
        return {x = start.x + delta.x, y = start.y + delta.y}
    end

    --- The swappable tile under a point, other than the dragged one.
    --- @param point {x: number, y: number}
    --- @param from Panel
    --- @return nil|Panel
    local function CharTileAt(point, from)
        for _, tile in pairs(charTiles) do
            if tile ~= from and tile.valid and tile.data.swappable then
                local rect = Tabletop.PanelRect(tile)
                if rect ~= nil and rect.w > 0 and point.x >= rect.x and point.x <= rect.x + rect.w and point.y >= rect.y and point.y <= rect.y + rect.h then
                    return tile
                end
            end
        end
        return nil
    end

    --- End a characteristic drag: the chip goes and the tiles look as before.
    local function CharDragEnd()
        local drag = charDrag
        charDrag = nil
        if drag == nil then
            return
        end
        if drag.chip.valid then
            drag.chip:DestroySelf()
        end
        if drag.tile.valid then
            drag.tile:SetClass("heroBuilderCharDragging", false)
        end
        if drag.over ~= nil and drag.over.valid then
            drag.over:SetClass("heroBuilderCharOver", false)
        end
    end

    --- Swaps two free characteristics' scores: they trade places in
    --- the picked array.
    --- @param firstId string
    --- @param secondId string
    local function SwapCharacteristics(firstId, secondId)
        charPick = nil
        PaintCharPick()
        Save(T("herobuilder.undo.make_choice"), function(hero)
            local build = hero:try_get("attributeBuild")
            if build == nil or build.array == nil then
                return
            end
            local slots = {}
            for field, value in pairs(build) do
                if field ~= "array" then
                    slots[field] = value
                end
            end
            slots[firstId], slots[secondId] = slots[secondId], slots[firstId]
            Engine().hero.SetCharacteristics(hero, build.array, slots)
        end)
    end

    --- The characteristics section: "Array" and a pill per array (a
    --- click assigns it in order), then the five scores. A free score swaps
    --- with another by dragging it there or by clicking both; one the class
    --- fixes is locked and says so on hover.
    --- @param stepid string
    --- @param section HeroBuilderSection
    --- @param children Panel[] the heading, from SectionHead
    --- @param status Panel
    --- @param note Panel
    --- @return table parts
    BuildCharacteristics = function(stepid, section, children, status, note)
        local sectionKey = section.key
        local pills = {}
        --- @type Panel[]
        local pillRow = {
            gui.Label{
                classes = {"heroSheetMuted"},
                text = T("herobuilder.chars.array"),
                fontSize = 13,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                rmargin = 8,
                textWrap = false,
            },
        }
        for _, option in ipairs(section.options) do
            local pill = gui.Panel{
                classes = {"heroBuilderCard", "hoverable"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 8,
                width = "auto",
                height = 30,
                hpad = 12,
                borderBox = true,
                halign = "left",
                valign = "center",
                rmargin = 6,
                data = {option = option},
                click = function(element)
                    local picked = element.data.option
                    if picked ~= nil and not picked.selected and Pick(stepid, sectionKey, picked) then
                        --the array answers at once; the repaint confirms it.
                        for _, other in pairs(pills) do
                            other:SetClassTree("selected", other == element)
                        end
                    end
                end,
                gui.Label{
                    classes = {"heroBuilderCardName"},
                    text = option.name,
                    fontSize = 13.5,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                },
            }
            pills[option.id] = pill
            pillRow[#pillRow+1] = pill
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 10,
            children = pillRow,
        }
        --- @type table<string, Panel>
        local tiles = {}
        local tileList = {}
        for _, model in ipairs(section.chars.tiles) do
            local value = gui.Label{
                classes = {"heroSheetCardStrong"},
                text = "",
                fontSize = 24,
                bold = true,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                interactable = false,
            }
            local caption = gui.Label{
                classes = {"heroSheetCardSub"},
                text = T("herobuilder.chars.set_by_class"),
                fontSize = 9.5,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                interactable = false,
            }
            local tile = gui.Panel{
                classes = {"heroBuilderCharTile"},
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 8,
                width = 100,
                height = 76,
                flow = "vertical",
                vpad = 7,
                borderBox = true,
                data = {id = model.id, swappable = false, fixed = model.fixed, value = value, caption = caption},
                linger = function(element)
                    if element.data.fixed then
                        gui.Tooltip(T("herobuilder.chars.set_by_class_tooltip"))(element)
                    end
                end,
                --click, not press: press would swallow the start of a drag.
                click = function(element)
                    if not element.data.swappable or not Host().canWrite() then
                        return
                    end
                    local id = element.data.id
                    if charPick == nil or charTiles[charPick] == nil then
                        charPick = id
                    elseif charPick == id then
                        charPick = nil
                    else
                        SwapCharacteristics(charPick, id)
                        return
                    end
                    PaintCharPick()
                end,
                --the tile stays and a chip follows the pointer (as an item's
                --drag does); the tile under it is edged.
                dragMove = false,
                dragThreshold = 6,
                beginDrag = function(element)
                    CharDragEnd()
                    local layer = HeroSheetWindow.PopupLayer()
                    local rect = Tabletop.PanelRect(element)
                    if not element.data.swappable or not Host().canWrite() or layer == nil or rect == nil then
                        return
                    end
                    local mousePoint = element.mousePoint
                    local moved = element.dragDelta
                    local start = {x = rect.x + mousePoint.x * rect.w - moved.x, y = rect.y + (1 - mousePoint.y) * rect.h - moved.y}
                    --the tile's own size and look, its value alone,
                    --held by its middle; the pop-up layer is in screen units.
                    local zoom = HeroSheetWindow.Zoom()
                    local chip = gui.Panel{
                        classes = {"heroBuilderCharTile", "heroBuilderCharFree"},
                        styles = {HeroSheetTheme.RootStyles(), BuilderRules()},
                        bgimage = "panels/square.png",
                        border = 1,
                        cornerRadius = 8,
                        width = 100,
                        height = 76,
                        uiscale = zoom,
                        pivot = {x = 0, y = 1},
                        halign = "left",
                        valign = "top",
                        interactable = false,
                        data = {w = 100 * zoom, h = 76 * zoom},
                        gui.Label{
                            classes = {"heroSheetCardStrong"},
                            text = element.data.value.text,
                            fontSize = 24,
                            bold = true,
                            width = "100%",
                            height = "auto",
                            halign = "center",
                            valign = "center",
                            textAlignment = "center",
                        },
                    }
                    layer:AddChild(chip)
                    chip.x = math.floor(start.x + moved.x - chip.data.w / 2)
                    chip.y = math.floor(start.y + moved.y - chip.data.h / 2)
                    chip:SetAsLastSibling()
                    charDrag = {tile = element, chip = chip, start = start, over = nil}
                    element:SetClass("heroBuilderCharDragging", true)
                end,
                dragging = function(element)
                    if charDrag == nil or charDrag.tile ~= element or not charDrag.chip.valid then
                        return
                    end
                    local pointer = CharDragPointer(element)
                    charDrag.chip.x = math.floor(pointer.x - charDrag.chip.data.w / 2)
                    charDrag.chip.y = math.floor(pointer.y - charDrag.chip.data.h / 2)
                    local over = CharTileAt(pointer, element)
                    if over ~= charDrag.over then
                        if charDrag.over ~= nil and charDrag.over.valid then
                            charDrag.over:SetClass("heroBuilderCharOver", false)
                        end
                        if over ~= nil then
                            over:SetClass("heroBuilderCharOver", true)
                        end
                        charDrag.over = over
                    end
                end,
                drag = function(element)
                    local target = nil
                    if charDrag ~= nil and charDrag.tile == element then
                        target = CharTileAt(CharDragPointer(element), element)
                    end
                    CharDragEnd()
                    if target ~= nil and Host().canWrite() then
                        SwapCharacteristics(element.data.id, target.data.id)
                    end
                end,
                gui.Label{
                    classes = {"heroBuilderCaps"},
                    text = string.upper(model.label),
                    fontSize = 10.5,
                    bold = true,
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    interactable = false,
                },
                value,
                caption,
            }
            tiles[model.id] = tile
            tileList[#tileList+1] = tile
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 10,
            children = tileList,
        }
        local grid = {kind = "chars", cards = tileList}
        FitGrid(grid)
        local parts = {
            panel = SectionPanel(children),
            status = status,
            note = note,
            cards = {},
            grid = grid,
        }
        --- @param model HeroBuilderSection
        parts.paintChars = function(model)
            for _, option in ipairs(model.options) do
                local pill = pills[option.id]
                if pill ~= nil then
                    pill.data.option = option
                    pill:SetClassTree("selected", option.selected)
                end
            end
            charTiles = tiles
            for _, tileModel in ipairs(model.chars.tiles) do
                local tile = tiles[tileModel.id]
                if tile ~= nil then
                    local swappable = not tileModel.fixed and model.chars.array ~= nil
                    tile.data.fixed = tileModel.fixed
                    tile.data.swappable = swappable
                    tile.draggable = swappable
                    --a tile that can move says so under the pointer.
                    tile.hoverCursor = cond(swappable, "hand", "default")
                    tile:SetClass("heroBuilderCharFree", swappable)
                    tile:SetClass("hoverable", swappable)
                    tile:SetClass("selected", charPick == tileModel.id)
                    local score = tileModel.value
                    if score == nil then
                        tile.data.value.text = "-"
                    else
                        tile.data.value.text = cond(score > 0, "+" .. tostring(score), tostring(score))
                    end
                    tile.data.caption:SetClass("collapsed", not tileModel.fixed)
                end
            end
        end
        return parts
    end

    --- A Level group's header on the Class step: "2nd-Level Features"
    --- with what is left in the group; a click folds the group away or opens it.
    --- @param entry table the step's page entry (entry.folded keeps the folded Levels)
    --- @param level integer
    --- @return {panel: Panel, paint: fun(left: integer, folded: boolean)}
    LevelHeader = function(entry, level)
        --a caret: down while the group is open, right while folded.
        local chevron = gui.Panel{
            classes = {"heroBuilderCaret"},
            bgimage = "phosphor/caret-down-fill.png",
            width = 14,
            height = 14,
            halign = "left",
            valign = "center",
            rmargin = 6,
            interactable = false,
        }
        local status = gui.Label{
            classes = {"heroBuilderStatus"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            text = "",
            fontSize = 12.5,
            bold = true,
            width = "auto",
            height = "auto",
            hpad = 10,
            vpad = 2,
            borderBox = true,
            halign = "right",
            valign = "center",
            textWrap = false,
            interactable = false,
        }
        local header
        header = {
            panel = gui.Panel{
                classes = {"hoverable"},
                bgimage = "panels/square.png",
                bgcolor = "clear",
                width = "100%",
                height = 32,
                flow = "horizontal",
                tmargin = SECTION_GAP,
                --a repaint builds an opened group's sections the first time.
                click = function()
                    entry.folded = entry.folded or {}
                    entry.folded[level] = not entry.folded[level]
                    Paint()
                end,
                chevron,
                gui.Label{
                    classes = {"heroSheetTitle"},
                    text = T("herobuilder.class.level_heading", {ordinal = Ordinal(level)}),
                    fontSize = 17,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                },
                status,
            },
            paint = function(left, folded)
                status.text = cond(left > 0, T("herobuilder.status.left", {count = string.format("%d", left)}), T("herobuilder.status.done"))
                status:SetClass("go", left > 0)
                status:SetClass("ok", left == 0)
                chevron.bgimage = cond(folded, "phosphor/caret-right-fill.png", "phosphor/caret-down-fill.png")
            end,
        }
        return header
    end

    --- The page's You gain section: one row per grant, what the step
    --- gives on the left and what fills it on the right ("Not chosen" while
    --- a choice is open), with the way to Skills & Languages in its heading
    --- when it has choices. Built for its number of rows, then painted.
    --- @param section HeroBuilderSection
    --- @return table parts
    local function BuildGain(section)
        local link = gui.Label{
            classes = {"heroSheetFeatLink", "hoverable"},
            text = T("herobuilder.gain.link"),
            fontSize = 13,
            underline = true,
            width = "auto",
            height = "auto",
            textWrap = false,
            click = function()
                GoTo("skills")
            end,
        }
        local children, status, note = SectionHead(section.title, link)
        local rows = {}
        for i = 1, #section.gain do
            local label = gui.Label{classes = {"heroBuilderCaps"}, text = "", fontSize = 13.5, width = "58%", height = "auto", halign = "left", valign = "center", textAlignment = "left"}
            local value = gui.Label{classes = {"heroSheetCardStrong"}, text = "", fontSize = 13.5, bold = true, width = "auto", height = "auto", valign = "center", textWrap = false}
            local none = gui.Label{classes = {"heroSheetMuted"}, text = T("herobuilder.status.not_chosen"), fontSize = 13.5, width = "auto", height = "auto", valign = "center", textWrap = false}
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vpad = 6,
                borderBox = true,
                label,
                gui.Panel{width = "auto", height = "auto", flow = "horizontal", halign = "right", valign = "center", value, none},
            }
            children[#children+1] = gui.Panel{bgimage = "panels/square.png", bgcolor = "#ffffff12", width = "100%", height = 1}
            rows[i] = {label = label, value = value, none = none}
        end
        local parts = {panel = SectionPanel(children), status = status, note = note, cards = {}}
        parts.paintGain = function(gainSection)
            link:SetClass("collapsed", not gainSection.link)
            for i, row in ipairs(gainSection.gain) do
                local cells = rows[i]
                if cells ~= nil then
                    cells.label.text = row.label
                    cells.value.text = row.value or ""
                    cells.value:SetClass("collapsed", row.value == nil)
                    --a two-skill choice with one picked reads "Navigate", a dot, then Not chosen.
                    cells.none.text = cond(row.value ~= nil, " \u{00B7} " .. T("herobuilder.status.not_chosen"), T("herobuilder.status.not_chosen"))
                    cells.none:SetClass("collapsed", not row.open)
                end
            end
        end
        return parts
    end

    --- Level up's You gain: the Level's Stamina, then each feature
    --- it brings with the opening of its words and its (i). Built for its
    --- lines (they are the section's shape), so it is never repainted.
    --- @param section HeroBuilderSection
    --- @return table parts
    local function BuildLevelGain(section)
        local children, status, note = SectionHead(section.title)
        for _, line in ipairs(section.levelGain or {}) do
            local text = line.name
            if line.tag ~= nil then
                text = TaggedName(line.name, line.tag)
            end
            --- @type Panel[]
            local head = {
                gui.Label{
                    classes = {"heroSheetCardStrong"},
                    text = text,
                    fontSize = 14.5,
                    bold = true,
                    width = string.format("100%%-%d", INFO_SIZE + 6),
                    height = "auto",
                    halign = "left",
                    valign = "center",
                },
            }
            if line.detail ~= nil then
                head[#head+1] = HeroBuilder.InfoButton{detail = line.detail, extra = {halign = "right"}}
            end
            --- @type Panel[]
            local rows = {
                gui.Panel{width = "100%", height = INFO_SIZE, flow = "none", children = head},
            }
            if line.text ~= nil and line.text ~= "" then
                rows[#rows+1] = gui.Label{
                    classes = {"heroSheetCardSub"},
                    text = line.text,
                    fontSize = 13.5,
                    width = "100%",
                    height = "auto",
                    tmargin = 2,
                }
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                vpad = 6,
                borderBox = true,
                children = rows,
            }
            children[#children+1] = gui.Panel{bgimage = "panels/square.png", bgcolor = "#ffffff12", width = "100%", height = 1}
        end
        status:SetClass("collapsed", true)
        return {panel = SectionPanel(children), status = status, note = note, cards = {}, static = true}
    end

    --- The row under a section's heading for picks no longer offered: chips
    --- for the old picks that still have a name, a warning, and Remove, which
    --- drops them all. Built with every section and collapsed until needed.
    --- @param stepid string
    --- @param sectionKey string
    --- @return {panel: Panel, paint: fun(stale: nil|HeroBuilderStale)}
    local function StaleRow(stepid, sectionKey)
        --- @type string[]
        local ids = {}
        local chips = gui.Panel{width = "100%", height = "auto", flow = "horizontal", wrap = true}
        --- @type Label[]
        local chipLabels = {}
        local remove = Button{
            text = T("herobuilder.row.remove"),
            small = true,
            click = function()
                local drop = ids
                Save(T("herobuilder.undo.drop_pick"), function(hero)
                    for _, id in ipairs(drop) do
                        if stepid == "complication" then
                            Engine().hero.ToggleComplication(hero, id)
                        else
                            Engine().hero.Unchoose(hero, stepid, sectionKey, id)
                        end
                    end
                end)
            end,
        }
        remove.selfStyle.halign = "right"
        local panel = gui.Panel{
            classes = {"heroBuilderStaleRow", "collapsed"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 12,
            vpad = 8,
            borderBox = true,
            tmargin = 8,
            gui.Panel{
                width = "100%-110",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                chips,
                gui.Label{
                    classes = {"heroSheetDanger"},
                    text = T("herobuilder.stale.warning"),
                    fontSize = 13.5,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                },
            },
            remove,
        }
        return {
            panel = panel,
            paint = function(stale)
                local shown = stale ~= nil and #stale.ids > 0
                panel:SetClass("collapsed", not shown)
                if not shown then
                    return
                end
                ---@cast stale HeroBuilderStale
                ids = stale.ids
                for i, name in ipairs(stale.names) do
                    local chip = chipLabels[i]
                    if chip == nil then
                        chip = gui.Label{
                            classes = {"heroBuilderStaleChip"},
                            bgimage = "panels/square.png",
                            border = 1,
                            cornerRadius = 6,
                            text = "",
                            fontSize = 13,
                            bold = true,
                            width = "auto",
                            height = "auto",
                            hpad = 8,
                            vpad = 2,
                            borderBox = true,
                            rmargin = 6,
                            bmargin = 4,
                            textWrap = false,
                        }
                        chipLabels[i] = chip
                        chips:AddChild(chip)
                    end
                    chip.text = name
                    chip:SetClass("collapsed", false)
                end
                for i = #stale.names + 1, #chipLabels do
                    chipLabels[i]:SetClass("collapsed", true)
                end
                chips:SetClass("collapsed", #stale.names == 0)
            end,
        }
    end

    --- A section of picks kept for one higher Level: each pick's name
    --- with Remove. Built for its rows (they are in its shape), so it is only
    --- painted for its heading.
    --- @param section HeroBuilderSection
    --- @return table parts
    local function BuildKept(section)
        local children, status, note = SectionHead(section.title)
        for _, row in ipairs(section.kept or {}) do
            local guid, id = row.guid, row.id
            local remove = Button{
                text = T("herobuilder.row.remove"),
                small = true,
                click = function()
                    Save(T("herobuilder.undo.drop_pick"), function(hero)
                        Engine().hero.DropKept(hero, guid, id)
                    end)
                end,
            }
            remove.selfStyle.halign = "right"
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 6,
                gui.Label{
                    classes = {"heroSheetCardStrong"},
                    text = row.name,
                    fontSize = 14,
                    bold = true,
                    width = "100%-110",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                },
                remove,
            }
        end
        --the dashed box sits inside the section's flash ring.
        local box = gui.Panel{
            classes = {"heroBuilderKeptBox"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 12,
            vpad = 8,
            borderBox = true,
            children = children,
        }
        return {panel = SectionPanel({box}), status = status, note = note, cards = {}, static = true}
    end

    --- A section of a page: heading and state, a rules note, the cards.
    --- @param stepid string
    --- @param section HeroBuilderSection
    --- @return table parts {panel, status, note, cards, grid}
    local function BuildSection(stepid, section)
        if section.gain ~= nil then
            return BuildGain(section)
        end
        if section.levelGain ~= nil then
            return BuildLevelGain(section)
        end
        if section.kept ~= nil then
            return BuildKept(section)
        end
        --a long list's search sits on its heading; it hides the cards
        --whose names miss, but never a picked one or No complication.
        local parts = nil
        local search = nil
        if section.search ~= nil then
            search = gui.SearchInput{
                placeholderText = section.search,
                text = "",
                width = 210,
                height = 26,
                borderBox = true,
                hover = gui.Tooltip(T("herobuilder.search.tooltip")),
                edit = function(element)
                    if parts ~= nil then
                        parts.query = trim(element.text or "")
                        parts.filter()
                    end
                end,
            }
        end
        local children, status, note = SectionHead(section.title, nil, search)
        local stale = StaleRow(stepid, section.key)
        children[#children+1] = stale.panel
        --no chosen card above the tiles: the pane's top card shows the pick,
        --and the picked tile or card fills.
        --- @type table<string, Panel>
        local cards = {}
        local cardList = {}
        --wide and kit cards always have room for a line ("Taken on <step>"
        --can arrive later); other cards only when some option has one.
        local withLine = section.grid == "wide" or section.grid == "kits"
        for _, option in ipairs(section.options) do
            withLine = withLine or option.line ~= nil
        end
        local marks = false
        local stars = false
        for _, option in ipairs(section.options) do
            marks = marks or option.impl ~= nil
            stars = stars or option.quickBuild == true
        end
        local sectionKey = section.key
        if section.chars ~= nil then
            local charParts = BuildCharacteristics(stepid, section, children, status, note)
            charParts.paintStale = stale.paint
            return charParts
        end
        for _, option in ipairs(section.options) do
            local card = HeroBuilder.OptionCard{
                kind = section.grid,
                withLine = withLine,
                marks = marks,
                stars = stars,
                pick = function(picked)
                    return Pick(stepid, sectionKey, picked)
                end,
                --every card's hover previews its pick on the live card; a
                --tile's also fills the pane with its art before a pick.
                hover = function(hovered, element)
                    if section.grid == "tiles" then
                        TileHover(stepid, hovered, element)
                    end
                    PreviewOption(stepid, sectionKey, hovered, element)
                end,
                leave = function(element)
                    LeavePreview(element)
                end,
                --the (i) card's first showing for an option is reported, once
                --each time the Builder opens.
                shown = function(shownOption)
                    local viewKey = sectionKey .. "|" .. shownOption.id
                    if shownOption.view ~= nil and not viewed[viewKey] then
                        viewed[viewKey] = true
                        Track("builder_ability_view", shownOption.view)
                    end
                end,
            }
            cards[option.id] = card
            cardList[#cardList+1] = card
        end
        local grid = {kind = section.grid, cards = cardList}
        --a rules note between the heading and the cards (complications').
        if section.hint ~= nil then
            children[#children+1] = gui.Label{
                classes = {"heroSheetMuted"},
                text = section.hint,
                fontSize = 12.5,
                width = "100%",
                height = "auto",
                tmargin = 8,
            }
        end
        --a pick at random, after the note and before the cards.
        if section.roll ~= nil then
            local kind = section.roll.kind
            local button = RollButton(section.roll.text, function()
                if kind == "incident" then
                    RollIncident(section)
                else
                    RollComplication()
                end
            end)
            button.selfStyle.tmargin = 8
            children[#children+1] = button
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 8,
            children = cardList,
        }
        --a line under the cards about the pick ("Saved to your notes.").
        local result = nil
        if section.roll ~= nil then
            result = gui.Label{
                classes = {"heroSheetMuted", "collapsed"},
                text = "",
                fontSize = 12.5,
                width = "100%",
                height = "auto",
                tmargin = 8,
            }
            children[#children+1] = result
        end
        --under Kits, the damage switches and Companion melee,
        --built as they are needed.
        local switchHolder = nil
        if section.switches ~= nil then
            switchHolder = gui.Panel{width = 520, height = "auto", flow = "vertical", halign = "left"}
            children[#children+1] = switchHolder
        end
        FitGrid(grid)
        parts = {
            switchHolder = switchHolder,
            switches = {},
            panel = SectionPanel(children),
            status = status,
            note = note,
            cards = cards,
            grid = grid,
            result = result,
            query = "",
            options = section.options,
            paintStale = stale.paint,
        }
        --shows the cards the search lets through (all of them with no search).
        parts.filter = function()
            for _, option in ipairs(parts.options) do
                local card = cards[option.id]
                if card ~= nil then
                    local shown = option.id == "" or option.selected or SearchMatch(option.name, parts.query)
                    card:SetClass("collapsed", not shown)
                end
            end
        end
        return parts
    end

    --- @param parts table from BuildSection
    --- @param section HeroBuilderSection
    local function PaintSection(parts, section)
        parts.status.text = section.status or ""
        parts.status:SetClass("collapsed", section.status == nil)
        parts.status:SetClass("ok", section.statusKind == "ok")
        parts.status:SetClass("go", section.statusKind == "go")
        parts.note.text = section.note or ""
        parts.note:SetClass("collapsed", section.note == nil)
        if parts.paintStale ~= nil then
            parts.paintStale(section.stale)
        end
        if parts.static then
            return
        end
        if parts.paintChars ~= nil then
            parts.paintChars(section)
            return
        end
        if parts.paintGain ~= nil then
            parts.paintGain(section)
            return
        end
        for _, option in ipairs(section.options) do
            local card = parts.cards[option.id]
            if card ~= nil then
                HeroBuilder.SetOptionCard(card, option)
            end
        end
        --a pick or a drop changes which cards the search must keep.
        parts.options = section.options
        if parts.query ~= "" then
            parts.filter()
        end
        if parts.result ~= nil then
            parts.result.text = section.result or ""
            parts.result:SetClass("collapsed", section.result == nil)
        end
        if parts.grid ~= nil and parts.grid.kind == "tiles" then
            MeasureTiles(parts.grid)
        end
        --the switches are kept and repainted; ones not needed collapse.
        if parts.switchHolder ~= nil then
            local picks = section.switches or {}
            for i, pick in ipairs(picks) do
                local switch = parts.switches[i]
                if switch == nil then
                    switch = HeroSheetCard.DamageSwitch()
                    parts.switches[i] = switch
                    parts.switchHolder:AddChild(switch.panel)
                end
                switch.paint(pick)
                switch.panel:SetClass("collapsed", false)
            end
            for i = #picks + 1, #parts.switches do
                parts.switches[i].panel:SetClass("collapsed", true)
            end
        end
    end

    --You gain for each step, kept while the build is unchanged.
    local gainsCache = {}

    --- @param token CharacterToken
    --- @param stepid string
    --- @return HeroBuilderPaneLine[]
    local function Gains(token, stepid)
        local key = BuildKey(token)
        local cached = gainsCache[stepid]
        if cached == nil or cached.key ~= key then
            cached = {key = key, lines = StepGains(token, stepid)}
            gainsCache[stepid] = cached
        end
        return cached.lines
    end

    --- Level up's You gain for one page (LevelGains), kept the same way.
    --- @param token CharacterToken
    --- @param page HeroBuilderStep
    --- @return HeroBuilderPaneLine[]
    local function LevelGainLines(token, page)
        local key = BuildKey(token)
        local cached = gainsCache[page.id]
        if cached == nil or cached.key ~= key then
            cached = {key = key, lines = LevelGains(token, page)}
            gainsCache[page.id] = cached
        end
        return cached.lines
    end

    --- The sections a step's page shows, and its shape: the sections and
    --- their options, which decide whether the kept page can be repainted.
    --- fresh: the step's main pick is not made yet, so the pane shows its
    --- outline (or the art showcase) rather than picks.
    --- Level up's page (stepStatus.levelUp, its rows that page's) has no
    --- main pick: the page's You gain, then its choices.
    --- @param token CharacterToken
    --- @param stepStatus table
    --- @return {shape: string, sections: HeroBuilderSection[], fresh: boolean, levelGains: nil|HeroBuilderPaneLine[]}
    local function StepModel(token, stepStatus)
        local stepid = stepStatus.id
        local sections = {}
        local baseSection = nil
        --- @type nil|HeroBuilderPaneLine[]
        local levelGains = nil
        if stepStatus.levelUp ~= nil then
            levelGains = LevelGainLines(token, stepStatus.levelUp)
            if #levelGains > 0 then
                sections[1] = {key = "levelgain", title = T("herobuilder.gain.title"), grid = "text", options = {}, levelGain = levelGains}
            end
            local taken = TakenPicks(Status(token))
            local allOptions = Engine().AllRowOptions(token, stepid)
            for _, row in ipairs(stepStatus.rows) do
                local section = RowSection(token, stepid, row, taken, allOptions[row.guid])
                if section ~= nil then
                    sections[#sections+1] = section
                end
            end
        else
            local base = nil
            for _, row in ipairs(stepStatus.rows) do
                if row.base then
                    base = row
                end
            end
            local status = Status(token)
            --picks kept for higher Levels lead the Class page, one section
            --per Level, outside the Level groups.
            if stepid == "class" then
                local byLevel = {}
                local levels = {}
                for _, choice in ipairs(status.kept or {}) do
                    if byLevel[choice.level] == nil then
                        byLevel[choice.level] = {}
                        levels[#levels+1] = choice.level
                    end
                    for _, pick in ipairs(choice.picks) do
                        table.insert(byLevel[choice.level], {guid = choice.guid, id = pick.id, name = pick.name})
                    end
                end
                for _, level in ipairs(levels) do
                    sections[#sections+1] = {
                        key = "kept" .. tostring(level),
                        title = T("herobuilder.kept.title", {level = string.format("%d", level)}),
                        grid = "text",
                        options = {},
                        kept = byLevel[level],
                    }
                end
            end
            baseSection = BaseSection(token, stepid, base)
            --EotW's locked step (a rebuild keeps its ancestry and class): only
            --the chosen card shows.
            if baseSection ~= nil and eotw ~= nil and eotw.lockedSteps ~= nil and eotw.lockedSteps[stepid] then
                local chosen = {}
                for _, option in ipairs(baseSection.options) do
                    if option.selected then
                        chosen[#chosen+1] = option
                    end
                end
                if #chosen > 0 then
                    baseSection.options = chosen
                end
            end
            if baseSection ~= nil then
                --a complication hidden from the compendium is a stale pick.
                baseSection.stale = StalePicks(stepid, base ~= nil and base.stale or nil)
                sections[#sections+1] = baseSection
            end
            local taken = TakenPicks(status)
            --every row's options from one build of the step (the engine builds
            --the whole step to answer for a single row), and its skill and
            --language choices from the same build.
            local allOptions, pools = Engine().AllRowOptions(token, stepid)
            --a class's skill choices from its 2nd Level on (4th, 7th, 10th, a
            --perk's) get a You gain of their own, under their Level.
            local firstPools = {}
            --- @type table<integer, table[]>
            local laterPools = {}
            local laterLevels = {}
            for _, pool in ipairs(pools or {}) do
                if stepid == "class" and pool.level > 1 then
                    if laterPools[pool.level] == nil then
                        laterPools[pool.level] = {}
                        laterLevels[#laterLevels+1] = pool.level
                    end
                    table.insert(laterPools[pool.level], pool)
                else
                    firstPools[#firstPools+1] = pool
                end
            end
            table.sort(laterLevels)
            --what the step grants in skills and languages, straight after
            --its main choice.
            if GAIN_STEPS[stepid] then
                local rows = GainRows(Gains(token, stepid), firstPools)
                if #rows > 0 then
                    sections[#sections+1] = {
                        key = "gain",
                        title = T("herobuilder.gain.title"),
                        grid = "text",
                        options = {},
                        gain = rows,
                        link = #firstPools > 0,
                    }
                end
            end
            --each later Level's You gain leads that Level's choices.
            local nextLater = 1
            --- @param upTo integer
            local function AddLaterGains(upTo)
                while laterLevels[nextLater] ~= nil and laterLevels[nextLater] <= upTo do
                    local level = laterLevels[nextLater]
                    sections[#sections+1] = {
                        key = "gain" .. tostring(level),
                        title = T("herobuilder.gain.title"),
                        grid = "text",
                        options = {},
                        gain = GainRows({}, laterPools[level]),
                        link = true,
                        level = level,
                    }
                    nextLater = nextLater + 1
                end
            end
            for _, row in ipairs(stepStatus.rows) do
                if not row.base then
                    local section = RowSection(token, stepid, row, taken, allOptions[row.guid])
                    if section ~= nil then
                        AddLaterGains(section.level or 1)
                        sections[#sections+1] = section
                    end
                end
            end
            AddLaterGains(math.huge)
        end
        --a Level's page is built again for another Level.
        local shape = {stepid, stepStatus.levelUp ~= nil and stepStatus.levelUp.id or ""}
        for _, section in ipairs(sections) do
            local ids = {}
            for _, option in ipairs(section.options) do
                ids[#ids+1] = option.id
            end
            --You gain and kept picks are built for their rows: a new row
            --builds them again.
            for _, row in ipairs(section.gain or {}) do
                ids[#ids+1] = row.label
            end
            for _, row in ipairs(section.kept or {}) do
                ids[#ids+1] = row.guid .. "/" .. row.id
            end
            for _, line in ipairs(section.levelGain or {}) do
                ids[#ids+1] = line.name
            end
            section.shape = section.key .. ":" .. table.concat(ids, ",")
            shape[#shape+1] = section.shape
        end
        local fresh = false
        if baseSection ~= nil and (stepid == "ancestry" or stepid == "career" or stepid == "class") then
            fresh = baseSection.chosen == nil
        elseif stepid == "culture" then
            --a culture is chosen whole or built from its aspects.
            fresh = true
            for _, section in ipairs(sections) do
                for _, option in ipairs(section.options) do
                    if option.selected then
                        fresh = false
                    end
                end
            end
        end
        return {shape = table.concat(shape, "|"), sections = sections, fresh = fresh, levelGains = levelGains}
    end

    --- The pane's five characteristic boxes: each value as the card shows it.
    --- @param token CharacterToken
    --- @return {value: string, label: string}[]
    local function Characteristics(token)
        local props = token.properties
        local boxes = {}
        for _, id in ipairs(creature.attributeIds or {}) do
            local info = creature.attributesInfo[id]
            local value = 0
            pcall(function() value = props:GetAttribute(id):Modifier() end)
            boxes[#boxes+1] = {value = cond(value > 0, "+" .. tostring(value), tostring(value)), label = info ~= nil and info.description or id}
        end
        return boxes
    end

    --A section's ring lights in the info colour and fades out, so the eye
    --finds the choice a block pointed to.
    --- @param panel Panel
    local function Flash(panel)
        local gen = (panel.data.flashGen or 0) + 1
        panel.data.flashGen = gen
        local color = HeroSheetTheme.WithAlpha(HeroSheetTheme.Palette().rawInfo, 1)
        local steps = 12
        for i = 0, steps do
            dmhub.Schedule(i * 0.1, function()
                if mod.unloaded or not panel.valid or panel.data.flashGen ~= gen then
                    return
                end
                panel.selfStyle.borderColor = HeroSheetTheme.ToHex(color, 1 - i / steps)
            end)
        end
    end

    --A plate of the lent Appearance surface flashes the same way, then
    --takes its own border back (a section's is clear; a plate's is not).
    --- @param plate Panel
    local function FlashPlate(plate)
        Flash(plate)
        local gen = plate.data.flashGen
        dmhub.Schedule(1.4, function()
            if not mod.unloaded and plate.valid and plate.data.flashGen == gen then
                plate.selfStyle.borderColor = nil
            end
        end)
    end

    --The Appearance step's footer words for its status rows.
    local APPEARANCE_LINKS = {name = T("herobuilder.footer.appearance_name"), portrait = T("herobuilder.footer.appearance_art")}

    --the page's scrolling column's height in Builder units (set by Layout).
    local pageScrollHeight = 400

    --Scrolls the page so a choice's section starts at its top, and flashes
    --it (a pane block's click). There is no engine scroll-into-view, so
    --the offset is summed from the rendered heights above the section.
    --- @param stepid string
    --- @param key string the section's key
    local function ScrollToSection(stepid, key)
        local entry = built[stepid]
        --a section in a folded Level group: open the group, then scroll once
        --it has built and laid out.
        local group = entry ~= nil and entry.groupOf ~= nil and entry.groupOf[key] or nil
        if group ~= nil and entry.folded ~= nil and entry.folded[group] == true then
            entry.folded[group] = false
            Paint()
            HeroSheetWindow.AfterLayout(function()
                ScrollToSection(stepid, key)
            end)
            return
        end
        local parts = entry ~= nil and entry.sections ~= nil and entry.sections[key] or nil
        --Level up's skill and language choices sit under the class choices:
        --scroll past those to the block's section.
        local skillsSection = levelSkills ~= nil and levelSkills.sections[key] or nil
        if parts == nil and entry ~= nil and skillsSection ~= nil and levelSkills ~= nil then
            Flash(skillsSection)
            if pageScroll.vscroll ~= true or pageScroll.renderedHeight <= 0 then
                return
            end
            local range = pageBody.renderedHeight - pageScroll.renderedHeight
            local before = pageBody.renderedHeight - levelSkills.page.renderedHeight
            for _, panel in ipairs(levelSkills.page.children) do
                if panel == skillsSection then
                    break
                end
                before = before + panel.renderedHeight
            end
            if range > 0 then
                pageScroll.vscrollPosition = 1 - math.max(0, math.min(range, before)) / range
            end
            return
        end
        if parts == nil or not parts.panel.valid then
            return
        end
        Flash(parts.panel)
        if pageScroll.vscroll ~= true or pageScroll.renderedHeight <= 0 then
            return
        end
        local scale = pageScroll.renderedHeight / pageScrollHeight
        local range = pageBody.renderedHeight - pageScroll.renderedHeight
        if range <= 0 then
            return
        end
        local offset = pageTitle.renderedHeight
        if not pageLead:HasClass("collapsed") then
            offset = offset + pageLead.renderedHeight + LEAD_GAP * scale
        end
        for _, panel in ipairs(entry.holder.children) do
            if panel == parts.panel then
                break
            end
            if not panel:HasClass("collapsed") then
                offset = offset + panel.renderedHeight + SECTION_GAP * scale
            end
        end
        --the section's own top margin, less 6 units of air above it.
        offset = offset + (SECTION_GAP - 6) * scale
        local top = math.max(0, math.min(range, offset))
        pageScroll.vscrollPosition = 1 - top / range
    end

    --What a fresh step will ask, before its main pick.
    local OUTLINE = {
        ancestry = {T("herobuilder.outline.ancestry"), T("herobuilder.outline.signature_trait"), T("herobuilder.outline.purchased_traits")},
        culture = {T("herobuilder.outline.culture"), T("herobuilder.outline.environment"), T("herobuilder.outline.organization"), T("herobuilder.outline.upbringing"), T("herobuilder.outline.language")},
        career = {T("herobuilder.outline.career"), T("herobuilder.outline.perk"), T("herobuilder.outline.inciting_incident")},
        class = {T("herobuilder.outline.class"), T("herobuilder.outline.subclass"), T("herobuilder.outline.characteristics"), T("herobuilder.outline.kit"), T("herobuilder.outline.heroic_abilities")},
    }
    local AFTER = {
        ancestry = T("herobuilder.outline.after_ancestry"),
        culture = T("herobuilder.outline.after_culture"),
        career = T("herobuilder.outline.after_career"),
        class = T("herobuilder.outline.after_class"),
    }

    --- Paints a step's pane: the outline of a fresh step, or
    --- the main pick's card, You gain and one block per choice. Blocks are
    --- built once per step and repainted; one not needed is collapsed.
    --- @param token CharacterToken
    --- @param stepid string
    --- @param model {sections: HeroBuilderSection[], fresh: boolean, levelGains: nil|HeroBuilderPaneLine[]}
    --- @param entry table the step's page entry
    local function PaintPane(token, stepid, model, entry)
        local pane = entry.pane
        if pane == nil then
            pane = {holder = gui.Panel{width = "100%", height = "auto", flow = "vertical"}, blocks = {}, outline = {}, order = nil}
            paneContent:AddChild(pane.holder)
            pane.holder:SetClass("collapsed", entry ~= shownPage)
            entry.pane = pane
        end
        --- @type Panel[]
        local order = {}
        local keys = {}
        local function Use(key, panel)
            order[#order+1] = panel
            keys[#keys+1] = key
        end
        --- @param gains HeroBuilderPaneLine[]
        local function UseGains(gains)
            if #gains > 0 then
                if pane.gain == nil then
                    pane.gain = HeroBuilder.PaneBlock(nil)
                end
                HeroBuilder.SetPaneBlock(pane.gain, {title = T("herobuilder.gain.title"), lines = gains})
                Use("gain", pane.gain)
            end
        end
        if model.fresh and OUTLINE[stepid] ~= nil then
            for i, name in ipairs(OUTLINE[stepid]) do
                local block = pane.outline[i]
                if block == nil then
                    block = HeroBuilder.PaneBlock(nil)
                    pane.outline[i] = block
                end
                if i == 1 then
                    HeroBuilder.SetPaneBlock(block, {title = name, status = T("herobuilder.status.to_choose"), statusKind = "go", none = T("herobuilder.status.not_chosen"), open = true})
                else
                    HeroBuilder.SetPaneBlock(block, {title = name, none = T("herobuilder.outline.waits", {pick = AFTER[stepid]}), waits = true})
                end
                Use("outline" .. i, block)
            end
        else
            --the page's You gain stays on the page: the pane has its own;
            --picks kept for a higher Level are not this Level's picks.
            local paneSections = {}
            for _, section in ipairs(model.sections) do
                if section.gain == nil and section.kept == nil and section.levelGain == nil then
                    paneSections[#paneSections+1] = section
                end
            end
            --Level up has no main pick: its You gain leads the pane.
            if model.levelGains ~= nil then
                UseGains(model.levelGains)
            end
            for _, section in ipairs(paneSections) do
                local key = section.key
                local picked = {}
                for _, option in ipairs(section.options) do
                    if option.selected then
                        picked[#picked+1] = option
                    end
                end
                if key == "base" and stepid ~= "complication" then
                    --the main pick leads, as a card with its art on Ancestry
                    --and Class; a culture built from aspects has none.
                    local option = picked[1]
                    if option ~= nil then
                        if pane.main == nil then
                            pane.main = HeroBuilder.PaneMain(function()
                                ScrollToSection(stepid, "base")
                            end)
                        end
                        local chosen = section.chosen
                        HeroBuilder.SetPaneMain(pane.main, {
                            kicker = STEP_KICKERS[stepid] or "",
                            name = chosen ~= nil and chosen.name or option.name,
                            blurb = chosen ~= nil and chosen.text or option.line,
                            art = cond(stepid == "ancestry" or stepid == "class", option.art or "", nil),
                            detail = option.detail,
                        })
                        Use("main", pane.main)
                    end
                    UseGains(Gains(token, stepid))
                else
                    local block = pane.blocks[key]
                    if block == nil then
                        block = HeroBuilder.PaneBlock(function()
                            ScrollToSection(stepid, key)
                        end)
                        pane.blocks[key] = block
                    end
                    local lines = {}
                    local boxes = nil
                    if section.options[1] ~= nil and section.options[1].arrayIndex ~= nil then
                        --the characteristics read as their five values, not the array's name.
                        boxes = Characteristics(token)
                    else
                        for _, option in ipairs(picked) do
                            lines[#lines+1] = {name = option.name, detail = option.detail}
                        end
                    end
                    HeroBuilder.SetPaneBlock(block, {
                        title = section.title,
                        status = section.status,
                        statusKind = section.statusKind,
                        lines = lines,
                        --a choice done with nothing to list (an inciting
                        --incident kept in the notes) shows only its state.
                        none = cond(#lines == 0 and section.statusKind == "ok", nil, T("herobuilder.status.not_chosen")),
                        open = section.statusKind == "go",
                        boxes = boxes,
                    })
                    Use(key, block)
                    --a complication's grants follow the complications.
                    if key == "base" then
                        UseGains(Gains(token, stepid))
                    end
                end
            end
        end
        --every block made stays attached (left out of children, a panel is
        --destroyed); the ones not used are collapsed. Only a change in which
        --blocks show reorders them.
        local signature = table.concat(keys, "|")
        if pane.order ~= signature then
            local used = {}
            local all = {}
            for _, panel in ipairs(order) do
                used[panel] = true
                all[#all+1] = panel
            end
            local spare = {}
            if pane.main ~= nil then
                spare[#spare+1] = pane.main
            end
            if pane.gain ~= nil then
                spare[#spare+1] = pane.gain
            end
            for _, panel in ipairs(pane.outline) do
                spare[#spare+1] = panel
            end
            for _, panel in pairs(pane.blocks) do
                spare[#spare+1] = panel
            end
            for _, panel in ipairs(spare) do
                if used[panel] == nil then
                    used[panel] = false
                    all[#all+1] = panel
                end
            end
            pane.holder.children = all
            for panel, shown in pairs(used) do
                panel:SetClass("collapsed", not shown)
            end
            pane.order = signature
        end
    end

    --The pane on Skills & Languages before any step has given a choice.
    local SKILLS_EMPTY = T("herobuilder.skills.empty")

    --The pane's inner width, which Skills & Languages' rows are fitted to.
    local paneInnerW = 300

    --Paints the pane heading's state on Skills & Languages (the picks left).
    --- @param entry table the skills page entry
    local function PaintPaneStatus(entry)
        paneStatus:SetClass("collapsed", entry.status == nil)
        paneStatus.text = entry.status or ""
        paneStatus:SetClass("go", entry.statusKind == "go")
        paneStatus:SetClass("ok", entry.statusKind == "ok")
    end

    --The Skills & Languages page: Your choices (the skill grants, then the
    --language grants, and what is known already) sit in the pane; the page
    --is the skills by group and the languages with their search, at its
    --full width. The rows and chips are the sheet's Skills & Languages
    --component (HeroSkillsLanguages.Panel) in its parts mode; each
    --pick saves as it is made. The page is built again only when the Hero's
    --picks change some other way (another client, Undo), so a selected row
    --survives a pick.
    --- @param token CharacterToken
    --- @return table entry
    local function SkillsPage(token)
        local hero = token.properties --[[@as character]]
        local entry = {shape = "skills", width = string.format("%s|%s", tostring(innerW), tostring(paneInnerW))}
        --- @type HeroSkillsDraft[]
        local drafts = {}
        --the pane heading's state: the picks left over both lists; none
        --before any step has given a choice.
        local function PaintStatus()
            local left = 0
            local grants = 0
            --what is left of each kind, for the footer.
            entry.left = {}
            for i, draft in ipairs(drafts) do
                local kind = cond(i == 1, "skill", "language")
                entry.left[kind] = 0
                for _, row in ipairs(draft.grants) do
                    grants = grants + 1
                    left = left + math.max(0, row.capacity - #row.picks)
                    entry.left[kind] = entry.left[kind] + math.max(0, row.capacity - #row.picks)
                end
            end
            entry.status = cond(grants == 0, nil, cond(left > 0, T("herobuilder.status.left", {count = string.format("%d", left)}), T("herobuilder.status.done")))
            entry.statusKind = cond(left > 0, "go", "ok")
            if shownPage == entry then
                PaintPaneStatus(entry)
            end
        end
        --- @type table<string, HeroSkillsParts>
        local parts = {}
        --- @type table<string, HeroSkillsPanelControl>
        local controls = {}
        for _, kind in ipairs({"skill", "language"}) do
            local draft = HeroSkillsLanguages.Read(hero, kind, nil, Engine())
            drafts[#drafts+1] = draft
            local _, control = HeroSkillsLanguages.Panel{
                draft = draft,
                width = innerW,
                rowWidth = paneInnerW,
                parts = true,
                stars = true,
                --the chips fill in over the next frames, so the page opens
                --without a pause.
                slice = true,
                onBuilt = function()
                    if shownPage == entry then
                        FitScroll(pageScroll)
                    end
                end,
                onChange = function(changedDraft)
                    PaintStatus()
                    if not HeroSkillsLanguages.Changed(changedDraft) then
                        return
                    end
                    Save(cond(kind == "skill", T("herobuilder.undo.change_skills"), T("herobuilder.undo.change_languages")), function(hero)
                        HeroSkillsLanguages.Apply(hero, changedDraft)
                    end)
                    if state.error ~= nil then
                        --not saved: the next paint rebuilds the page from the Hero.
                        entry.key = nil
                        return
                    end
                    HeroSkillsLanguages.Rebaseline(changedDraft)
                    local live = Host().token()
                    if live ~= nil then
                        entry.key = BuildKey(live)
                    end
                end,
            }
            controls[kind] = control
            parts[kind] = control.parts --[[@as HeroSkillsParts]]
        end
        --Esc, and leaving the step, clear a selected row first.
        entry.clearSelection = function()
            return controls.skill.ClearSelection()
        end

        local skillsHead, skillsStatus = SectionHead(T("herobuilder.skills.skills"))
        skillsStatus:SetClass("collapsed", true)
        skillsHead[#skillsHead+1] = parts.skill.chips
        local languagesHead = SectionHead(T("herobuilder.skills.languages"), parts.language.search)
        languagesHead[#languagesHead+1] = parts.language.chips
        local sections = {}
        for i, children in ipairs({skillsHead, languagesHead}) do
            --an edge that can flash, as every page section has (the footer's links).
            sections[#sections+1] = SectionPanel(children, cond(i == 1, 10, SECTION_GAP))
        end
        --the footer's links scroll to these, by kind.
        entry.sections = {skill = {panel = sections[1]}, language = {panel = sections[2]}}
        entry.holder = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = sections,
        }
        local grants = #drafts[1].grants + #drafts[2].grants
        local emptyLabel = gui.Label{
            classes = {"heroSheetCardSub", cond(grants > 0, "collapsed", nil)},
            text = SKILLS_EMPTY,
            fontSize = 13.5,
            width = "100%",
            height = "auto",
        }
        entry.pane = {
            holder = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                emptyLabel,
                parts.skill.rows,
                parts.language.rows,
                parts.skill.known,
                parts.language.known,
            },
        }
        --- The Hero's build changed elsewhere (another step's pick, another
        --- client): read it again into the panels already built. False when
        --- the skills or languages offered changed, so the page builds anew.
        --- @param live CharacterToken
        --- @return boolean
        entry.repaint = function(live)
            local fresh = {}
            for i, kind in ipairs({"skill", "language"}) do
                fresh[i] = HeroSkillsLanguages.Read(live.properties --[[@as character]], kind, nil, Engine())
            end
            for i, kind in ipairs({"skill", "language"}) do
                if not controls[kind].SetDraft(fresh[i]) then
                    return false
                end
                drafts[i] = fresh[i]
            end
            emptyLabel:SetClass("collapsed", #drafts[1].grants + #drafts[2].grants > 0)
            PaintStatus()
            entry.key = BuildKey(live)
            return true
        end
        PaintStatus()
        entry.key = BuildKey(token)
        pageContent:AddChild(entry.holder)
        paneContent:AddChild(entry.pane.holder)
        return entry
    end

    --A step's page, made ready: the kept one repainted, or built for a new
    --shape, and its pane with it. A page built while another shows stays hidden.
    --- @param token CharacterToken
    --- @param stepid string
    --- @param stepStatus table
    --- @param opening boolean the step is about to show (not already showing): Level groups fold afresh
    --- @return table entry
    local function EnsurePage(token, stepid, stepStatus, opening)
        local entry = built[stepid]
        if stepid == "skills" then
            local width = string.format("%s|%s", tostring(innerW), tostring(paneInnerW))
            --a change of build repaints the page in place; a new width (the app
            --window resized, Font Size), or a change in what is offered, builds it anew.
            local repainted = false
            if entry ~= nil and entry.width == width then
                repainted = entry.key == BuildKey(token)
                if not repainted then
                    local ok, result = pcall(entry.repaint, token)
                    if not ok then
                        dmhub.Error("Builder: the Skills page failed to repaint: " .. tostring(result))
                    end
                    repainted = ok and result == true
                end
            end
            if not repainted then
                if entry ~= nil then
                    entry.holder:DestroySelf()
                    entry.pane.holder:DestroySelf()
                end
                entry = SkillsPage(token)
            end
        else
            --the step's model is kept while the build is unchanged: folding a
            --Level group or coming back to a step needs no new one.
            local modelKey = table.concat({stepid, stepStatus.levelUp ~= nil and tostring(stepStatus.levelUp.id) or "", token.charid, BuildKey(token)}, "|")
            local model = (entry ~= nil and entry.modelKey == modelKey and entry.model) or StepModel(token, stepStatus)
            if entry == nil then
                entry = {sections = {}, holder = gui.Panel{width = "100%", height = "auto", flow = "vertical"}}
                pageContent:AddChild(entry.holder)
            end
            entry.modelKey = modelKey
            --with choices from more than one Level, the Class step groups
            --them under "1st-Level Features"... headers.
            local grouped = false
            --Level up shows one Level, so it needs no groups.
            if stepid == "class" and stepStatus.levelUp == nil then
                for _, section in ipairs(model.sections) do
                    grouped = grouped or (section.kept == nil and (section.level or 1) > 1)
                end
            end
            --each section's group and what is left in each: a section joins
            --the Level it falls in; a choice nested under an earlier Level's
            --stays with its parent.
            local groupOf = {}
            local left = {}
            local order = {}
            do
                local group = 1
                local seen = {}
                for _, section in ipairs(model.sections) do
                    --picks kept for a higher Level lead the page, in no group.
                    if section.kept == nil then
                        local level = section.level or 1
                        if grouped and (level > group or not seen[group]) then
                            group = math.max(group, level)
                            if not seen[group] then
                                seen[group] = true
                                order[#order+1] = group
                            end
                        end
                        groupOf[section.key] = group
                        left[group] = (left[group] or 0) + (section.remaining or 0)
                    end
                end
            end
            entry.groupOf = cond(grouped, groupOf, nil)
            --when the step opens, a finished group above the 1st Level starts
            --folded; one with picks left never does. A folded group's sections
            --are built when it first opens.
            entry.folded = entry.folded or {}
            if grouped then
                for _, group in ipairs(order) do
                    if opening then
                        entry.folded[group] = group > 1 and (left[group] or 0) == 0
                    elseif entry.folded[group] == nil then
                        entry.folded[group] = false
                    end
                end
            end
            --- @param section HeroBuilderSection
            --- @return boolean
            local function Shown(section)
                return not grouped or entry.folded[groupOf[section.key]] ~= true
            end
            --a new shape, or an opened group not built yet, sets the children again.
            local missing = false
            for _, section in ipairs(model.sections) do
                local parts = entry.sections[section.key]
                if Shown(section) and (parts == nil or parts.shape ~= section.shape) then
                    missing = true
                end
            end
            local shape = model.shape .. cond(grouped, "|grouped", "")
            if entry.shape ~= shape or missing then
                --a new shape (a subclass that brings a choice) builds only
                --the sections whose options changed; the rest are kept.
                local kept = {}
                local panels = {}
                local headed = {}
                entry.levels = entry.levels or {}
                for _, section in ipairs(model.sections) do
                    local group = groupOf[section.key]
                    if grouped and group ~= nil and not headed[group] then
                        headed[group] = true
                        local header = entry.levels[group]
                        if header == nil then
                            header = LevelHeader(entry, group)
                            entry.levels[group] = header
                        end
                        panels[#panels+1] = header.panel
                    end
                    local parts = entry.sections[section.key]
                    if Shown(section) and (parts == nil or parts.shape ~= section.shape) then
                        parts = BuildSection(stepid, section)
                        parts.shape = section.shape
                    end
                    if parts ~= nil and parts.shape == section.shape then
                        parts.group = cond(grouped, group, nil)
                        kept[section.key] = parts
                        panels[#panels+1] = parts.panel
                    end
                end
                --headers no longer used stay attached (left out, a panel is
                --destroyed) and collapsed.
                for level, header in pairs(entry.levels) do
                    header.panel:SetClass("collapsed", not headed[level])
                    if not headed[level] then
                        panels[#panels+1] = header.panel
                    end
                end
                entry.holder.children = panels
                entry.sections = kept
                entry.shape = shape
            end
            for _, section in ipairs(model.sections) do
                local parts = entry.sections[section.key]
                if parts ~= nil and parts.shape == section.shape then
                    PaintSection(parts, section)
                    parts.panel:SetClass("collapsed", parts.group ~= nil and entry.folded[parts.group] == true)
                end
            end
            --each Level header says what is left in its group.
            for level, header in pairs(entry.levels or {}) do
                header.paint(left[level] or 0, entry.folded[level] == true)
            end
            --a choice another pick just brought (a subclass's skill
            --choice) flashes once. A main pick bringing a whole step's
            --choices at once flashes nothing.
            local before = entry.model
            if before ~= nil and not opening and not before.fresh then
                local had = {}
                for _, section in ipairs(before.sections) do
                    had[section.key] = true
                end
                for _, section in ipairs(model.sections) do
                    local parts = entry.sections[section.key]
                    if not had[section.key] and section.statusKind == "go" and parts ~= nil then
                        Flash(parts.panel)
                    end
                end
            end
            entry.model = model
            entry.fresh = model.fresh
            PaintPane(token, stepid, model, entry)
        end
        if built[stepid] ~= entry then
            built[stepid] = entry
            entry.holder:SetClass("collapsed", entry ~= shownPage)
            if entry.pane ~= nil then
                entry.pane.holder:SetClass("collapsed", entry ~= shownPage)
            end
        end
        return entry
    end

    --Shows a step's page and its pane.
    --- @param token CharacterToken
    --- @param stepid string
    --- @param stepStatus table
    local function ShowPage(token, stepid, stepStatus)
        local entry = EnsurePage(token, stepid, stepStatus, built[stepid] == nil or built[stepid] ~= shownPage)
        if shownPage ~= entry then
            --leaving Skills & Languages clears a selected row.
            if shownPage ~= nil and shownPage.clearSelection ~= nil then
                shownPage.clearSelection()
            end
            for _, other in pairs(built) do
                other.holder:SetClass("collapsed", other ~= entry)
                if other.pane ~= nil then
                    other.pane.holder:SetClass("collapsed", other ~= entry)
                end
            end
            shownPage = entry
            pageScroll.vscrollPosition = 1
            paneScroll.vscrollPosition = 1
            --a new step starts from its outline, with nothing pinned, and no
            --half-made characteristic swap.
            charPick = nil
            HeroBuilder.ClosePinned()
            MarkShown(nil)
            showcase = nil
        end
        --a pick ends the showcase: the pane becomes the step's picks.
        if showcase ~= nil and (showcase.stepid ~= stepid or not entry.fresh) then
            MarkShown(nil)
            showcase = nil
        end
        ShowArt(showcase ~= nil and showcase.spec or nil)
        if stepid == "skills" then
            PaintPaneStatus(entry)
        else
            paneStatus:SetClass("collapsed", true)
        end
        FitScroll(pageScroll)
        FitScroll(paneScroll)
    end

    --Builds a step's page ahead of a click while the pointer rests on its
    --way in (its pill, Back, Next), so the click shows it at once (a page's
    --first build is slow enough to notice).
    --- @param stepid nil|string
    local function PrewarmNow(stepid)
        if levelUp then
            return
        end
        local token = Host().token()
        if stepid == nil or stepid == state.step or stepid == "appearance" or token == nil or token.properties == nil then
            return
        end
        local status = Status(token)
        local stepStatus = cond(stepid == OTHER, status.other, nil)
        for _, candidate in ipairs(status.steps) do
            if candidate.id == stepid then
                stepStatus = candidate
            end
        end
        --Review has no page of its own (it shows the sheet), so nothing to build.
        if stepStatus == nil then
            return
        end
        --a built page is brought up to date when it shows.
        if built[stepid] == nil or stepid == "skills" then
            Engine().Cached(EnsurePage, token, stepid, stepStatus, true)
        end
    end
    --The pointer must rest this long (s) on a way in before its page builds,
    --so sweeping across the pills builds nothing on the way past.
    local PREWARM_DWELL = 0.1
    local prewarmGen = 0
    --- @param stepid nil|string
    local function Prewarm(stepid)
        prewarmGen = prewarmGen + 1
        local gen = prewarmGen
        dmhub.Schedule(PREWARM_DWELL, function()
            if mod.unloaded or gen ~= prewarmGen or root == nil or not root.valid then
                return
            end
            PrewarmNow(stepid)
        end)
    end
    prewarm = Prewarm

    --The Appearance step: the sheet's Appearance surface, lent while
    --the step shows. Its art column takes the card's place and its tabs span
    --the page and pane columns; the surface's tier is the Builder's room
    --(Medium at 1371, Wide at 1920).
    local apSlot = gui.Panel{
        classes = {"collapsed"},
        width = 600,
        height = 500,
        lmargin = COLUMN_GAP,
        flow = "vertical",
    }
    --- @type nil|HeroAppearanceView
    local apView = nil
    --what Layout gives the surface: its tier and the card column's width.
    local apHost = {tier = "medium", cardW = 300, w = 600, h = 500}

    local body = gui.Panel{
        width = "100%",
        height = 500,
        flow = "horizontal",
        tmargin = BODY_GAP,
        cardColumn,
        page,
        pane,
        apSlot,
    }

    --- True while this Builder holds the lent surface.
    --- @return boolean
    local function HoldsAppearance()
        return apView ~= nil and apView.body.valid and apView.body.parent == apSlot
    end

    --Lays the lent surface out for the room Layout gave it.
    local function SizeAppearance()
        if not HoldsAppearance() then
            return
        end
        local view = apView --[[@as HeroAppearanceView]]
        local host = {builder = true, shown = true, columnUnits = apHost.cardW}
        for _, panel in ipairs({view.column, view.body}) do
            panel:FireEventTree("heroAppearanceHost", host)
            panel:FireEventTree("heroSheetTier", apHost.tier)
            panel:FireEventTree("heroSheetLayout", apHost.w, apHost.h)
        end
    end

    --Shows the Appearance step's surface, or gives it back to the sheet. A
    --Builder not on screen borrows nothing (it repaints under the sheet).
    --- @param on boolean
    local function HostAppearance(on)
        if on then
            local view = Host().lendAppearance()
            if view ~= nil then
                --the sheet's content was built anew (a reload): the old
                --surface it lent goes.
                if apView ~= nil and apView ~= view and HoldsAppearance() then
                    apView.column:DestroySelf()
                    apView.body:DestroySelf()
                end
                local arriving = view.body.parent ~= apSlot
                apView = view
                if arriving then
                    view.column:Unparent()
                    cardColumn:AddChild(view.column)
                    view.body:Unparent()
                    apSlot:AddChild(view.body)
                    view.column:SetClass("collapsed", false)
                    view.body:SetClass("collapsed", false)
                    --each arrival opens on Look.
                    view.show("look")
                    SizeAppearance()
                end
            end
        elseif HoldsAppearance() then
            Host().returnAppearance()
        end
        local hosting = on and HoldsAppearance()
        card:SetClass("collapsed", hosting)
        page:SetClass("collapsed", hosting)
        pane:SetClass("collapsed", hosting)
        apSlot:SetClass("collapsed", not hosting)
    end

    --- Review ---
    --Review is the sheet itself: the title row and the body give way to the
    --banner, and the window draws the live Character tab over the
    --space left under it; the stepper and the footer stay.
    local reviewBannerText = gui.Label{
        classes = {"heroSheetCardText"},
        text = "",
        fontSize = 15,
        width = "100%",
        height = "auto",
        valign = "center",
        textWrap = true,
    }
    local reviewBanner = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock", "collapsed"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = BANNER_HEIGHT,
        tmargin = REVIEW_GAP,
        hpad = 18,
        borderBox = true,
        reviewBannerText,
    }
    local reviewSpace = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = 100,
        tmargin = REVIEW_GAP,
        interactable = false,
    }
    --- Where the sheet shows on Review, in Builder units from the top and bottom.
    --- @return {top: number, bottom: number}
    local function ReviewInsets()
        return {
            top = PAD_TOP + STEPPER_GAP + STEPPER_HEIGHT + REVIEW_GAP + BANNER_HEIGHT + REVIEW_GAP,
            bottom = BODY_GAP + FOOTER_HEIGHT + PAD_BOTTOM,
        }
    end

    --- the footer ---

    --- Level up's page showing (its step: "level2", "rung3"), or nil.
    --- @return nil|HeroBuilderStep
    local function LevelUpPage()
        local index = stepIndex[state.step or ""]
        if not levelUp or index == nil then
            return nil
        end
        return steps[index]
    end

    --- What a page's Finish and its undo step say: "Finish Level 3", or a
    --- slow-start rung's "Finish Second Encounter".
    --- @param page HeroBuilderStep
    --- @return string
    local function FinishWords(page)
        if page.rung ~= nil then
            return T("herobuilder.levelup.finish_rung", {rung = page.title})
        end
        return T("herobuilder.levelup.finish_level", {level = string.format("%d", page.level or 1)})
    end

    --- The picks a page still has open, for Finish's analytics.
    --- @type nil|fun(page: HeroBuilderStep): integer
    local PicksOpen = nil
    --the footer's width and its Finish button's (a slow-start page's is
    --wider); FitFooter (set with the painting) sizes the footer from them.
    local footerRowW = 1300
    local finishW = FOOTER_BUTTON_WIDTH
    --- @type fun()
    local FitFooter

    --- Level up's Finish: marks the page as seen (a manual Level up raises
    --- the Level here), then opens the next page waiting, or returns to the
    --- sheet after the last. Finish works with choices still open; the card
    --- keeps "Choices to make". It never heals the Hero.
    local function FinishLevel()
        local token = Host().token()
        local page = LevelUpPage()
        if token == nil or page == nil or page.level == nil or page.key == nil then
            return
        end
        local hero = token.properties --[[@as character]]
        local level = page.level --[[@as integer]]
        local key = page.key --[[@as integer]]
        local words = FinishWords(page)
        local left = 0
        if PicksOpen ~= nil then
            left = PicksOpen(page)
        end
        local path = cond(level == 1, "slowstart", "respite")
        local manual = state.manual
        if manual ~= nil then
            path = "manual"
            Save(words, function(liveHero)
                Engine().hero.SetLevel(liveHero, manual)
                Engine().hero.MarkLevelsSeen(liveHero, manual)
            end, true)
            state.manual = nil
        elseif level == 1 then
            if (hero:try_get("rungSeen") or 5) < key then
                Save(words, function(liveHero)
                    Engine().hero.FinishRung(liveHero, key)
                end)
            end
        elseif Engine().hero.LevelUnseen(hero, level) then
            Save(words, function(liveHero)
                Engine().hero.FinishLevel(liveHero, level)
            end)
        end
        if state.error ~= nil then
            --the write failed: stay on this page, where the error shows.
            state.manual = manual
            return
        end
        Track("level_up_finish", {level = level, rung = page.rung, path = path, choicesLeft = left, dailyLimit = 20})
        for _, waiting in ipairs(state.queue) do
            if waiting.key > key then
                GoTo(PageStepId(waiting))
                return
            end
        end
        HeroBuilder.ClosePinned()
        args.back()
    end

    --- Cancel on a manual Level up: the picks kept for the Level
    --- go, in one undo step, and the sheet shows the Hero at their Level.
    local function CancelLevel()
        local token = Host().token()
        local manual = state.manual
        if token ~= nil and manual ~= nil then
            local any = false
            for _, choice in ipairs(Engine().hero.KeptPicks(token.properties --[[@as character]])) do
                any = any or choice.level == manual
            end
            if any then
                Save(T("herobuilder.undo.cancel_level", {level = string.format("%d", manual)}), function(hero)
                    Engine().hero.DropKeptForLevel(hero, manual)
                end, true)
                if state.error ~= nil then
                    --the write failed: stay open, where the error shows.
                    return
                end
            end
        end
        state.manual = nil
        HeroBuilder.ClosePinned()
        args.back()
    end

    --Level up has no Back: on the manual path (no respite) this is its Cancel.
    local backButton = Button{
        text = T("herobuilder.footer.back"),
        footer = true,
        click = function()
            if levelUp then
                CancelLevel()
                return
            end
            local index = Neighbour(stepIndex[state.step or ""] or 1, -1)
            if index ~= nil then
                GoTo(steps[index].id)
            end
        end,
        hover = function()
            local index = Neighbour(stepIndex[state.step or ""] or 1, -1)
            if prewarm ~= nil and index ~= nil then
                prewarm(steps[index].id)
            end
        end,
    }
    local nextButton = Button{
        text = T("herobuilder.footer.next"),
        footer = true,
        click = function()
            if levelUp then
                HeroSheetWindow.QuietWindowSound()
                FinishLevel()
                return
            end
            local index = Neighbour(stepIndex[state.step or ""] or 1, 1)
            if index == nil then
                --EotW finishes only a complete Hero: else it goes to the
                --first step left and says which are.
                if eotw ~= nil then
                    local token = Host().token()
                    local status = token ~= nil and Status(token) or nil
                    if status ~= nil and not status.complete then
                        local titles = {}
                        for _, id in ipairs(status.incomplete) do
                            local step = Engine().STEP_BY_ID[id]
                            titles[#titles+1] = step ~= nil and step.title or id
                        end
                        state.notice = eotw.stillToDo(titles)
                        local first = status.incomplete[1]
                        if first ~= nil and stepIndex[first] ~= nil and first ~= state.step then
                            GoTo(first)
                        else
                            Paint()
                        end
                        return
                    end
                    HeroBuilder.ClosePinned()
                    eotw.close(true)
                    return
                end
                --Finish always finishes, in one press.
                HeroBuilder.ClosePinned()
                HeroSheetWindow.QuietWindowSound()
                args.back()
            else
                GoTo(steps[index].id)
            end
        end,
        hover = function()
            local index = Neighbour(stepIndex[state.step or ""] or 1, 1)
            if prewarm ~= nil and index ~= nil then
                prewarm(steps[index].id)
            end
        end,
    }
    nextButton.selfStyle.halign = "right"
    --Level up's button is always a Finish: a press plays the lock-in sound.
    nextButton:SetClass("heroBuilderLockIn", levelUp)
    backButton:SetClass("collapsed", levelUp)
    --EotW's single-step mode (Change Appearance) closes from its title row.
    if eotw ~= nil and eotw.only ~= nil then
        backButton:SetClass("collapsed", true)
        nextButton:SetClass("collapsed", true)
    end

    --- Fill in the rest ---

    --The steps Fill works on, in the stepper's order: Review has nothing to fill.
    local FILL_SKIPS = {[REVIEW] = true}
    --a main pick's row in the preview, as the step's outline names it.
    local FILL_BASE_LABELS = {
        ancestry = T("herobuilder.fill.ancestry"),
        culture = T("herobuilder.fill.culture"),
        career = T("herobuilder.fill.career"),
        class = T("herobuilder.fill.class"),
        follows = T("herobuilder.fill.follows"),
        uncomplicate = T("herobuilder.fill.uncomplicate"),
    }
    --- @type table<string, string>
    local stepTitles = {}
    for _, step in ipairs(steps) do
        stepTitles[step.id] = step.title
    end

    --- @class HeroBuilderFillRow
    --- @field step string
    --- @field label string the choice, as its page names it
    --- @field value string the pick, or what goes
    --- @field quickBuild boolean
    --- @field removes boolean

    --- @class HeroBuilderFillPlan
    --- @field entries HeroBuildFillEntry[] what ApplyFill makes
    --- @field rows HeroBuilderFillRow[] what the pop-up lists
    --- @field key string the build it was worked out from (BuildKey)
    --- @field look nil|{name: nil|string, art: nil|string} the Appearance step's name and art (token fields, saved apart)

    --- What Fill gives the Appearance step: a generated
    --- name and the class's art (the ancestry's before a class), each only
    --- when missing. Read from the copy Fill left, so Every step names and
    --- dresses the ancestry and class it is about to pick.
    --- @param token CharacterToken
    --- @param copy character
    --- @param rows HeroBuilderFillRow[] the Name and Art rows join these
    --- @return {name: nil|string, art: nil|string}
    local function PlanLook(token, copy, rows)
        local look = {}
        if trim(token.name or "") == "" then
            look.name = Engine().GenerateName(copy)
            if look.name ~= nil then
                rows[#rows+1] = {step = "appearance", label = T("herobuilder.fill.name"), value = look.name, quickBuild = false, removes = false}
            end
        end
        if not Engine().PortraitIsSet(token.portrait) then
            local art, from = "", ""
            local classItem = copy:GetClass()
            if classItem ~= nil then
                art, from = classItem:try_get("portraitid", ""), classItem.name
            end
            local race = Engine().hero.Ancestry(copy)
            if art == "" and race ~= nil then
                art, from = race:try_get("portraitid", ""), HeroBuild.SaidName(race.name)
            end
            if art ~= "" then
                look.art = art
                rows[#rows+1] = {step = "appearance", label = T("herobuilder.fill.art"), value = T("herobuilder.fill.art_from", {source = from}), quickBuild = false, removes = false}
            end
        end
        return look
    end

    --- What Fill would choose on these steps, worked out on a copy of
    --- the Hero, each change named as the page names its choice:
    --- skills and languages by the Skills & Languages row that holds them.
    --- @param token CharacterToken
    --- @param stepids string[]
    --- @param pages nil|table<integer, boolean> Level up: only the choices on these pages (Engine().PageKey)
    --- @return HeroBuilderFillPlan
    local function PlanFill(token, stepids, pages)
        --the Appearance step's name and art are the token's, planned apart.
        local heroSteps = {}
        local withLook = false
        for _, stepid in ipairs(stepids) do
            if stepid == "appearance" then
                withLook = true
            else
                heroSteps[#heroSteps+1] = stepid
            end
        end
        stepids = heroSteps
        local entries, copy = Engine().hero.PlanFill(token.properties --[[@as character]], stepids, pages)
        local grantTitles = {}
        for _, kind in ipairs({"skill", "language"}) do
            local ok, draft = pcall(HeroSkillsLanguages.Read, copy, kind, nil, Engine())
            if ok and draft ~= nil then
                for _, grant in ipairs(draft.grants) do
                    for _, id in ipairs(grant.picks) do
                        grantTitles[kind .. ":" .. id] = grant.title
                    end
                end
            end
        end
        --two choices with one name add their Level, as the footer does.
        local nameCount = {}
        for _, stepid in ipairs(stepids) do
            for _, row in ipairs(Engine().hero.StepStatus(nil, copy, stepid).rows) do
                if not row.base then
                    local key = stepid .. "|" .. tostring(row.name)
                    nameCount[key] = (nameCount[key] or 0) + 1
                end
            end
        end
        --- @type HeroBuilderFillRow[]
        local rows = {}
        for _, entry in ipairs(entries) do
            local label = FILL_BASE_LABELS[entry.op]
            if entry.op == "pool" then
                label = grantTitles[tostring(entry.kind) .. ":" .. tostring(entry.id)] or cond(entry.kind == "skill", T("herobuilder.skills.skills"), T("herobuilder.skills.languages"))
            elseif label == nil then
                label = entry.label or ""
                if (nameCount[entry.step .. "|" .. label] or 0) > 1 then
                    label = T("herobuilder.fill.label_level", {label = label, level = string.format("%d", math.max(1, entry.level or 1))})
                end
            end
            local value = entry.name or ""
            if entry.removes then
                value = T("herobuilder.fill.removes", {pick = entry.name or T("herobuilder.fill.removes_unnamed")})
            elseif entry.op == "ancestry" then
                value = HeroBuild.SaidName(value)
            end
            --Level up groups every page's rows under its pill's name.
            local step = entry.step
            if pages ~= nil then
                step = keyStep[entry.page or 0] or LevelStepId(math.max(2, entry.level or 2))
            end
            rows[#rows+1] = {step = step, label = label, value = value, quickBuild = entry.quickBuild == true, removes = entry.removes == true}
        end
        local look = nil
        if withLook then
            look = PlanLook(token, copy, rows)
        end
        return {entries = entries, rows = rows, key = BuildKey(token), look = look}
    end

    local fillButton
    --the open pop-up's plans: this step's, every step's (planned when first
    --shown: planning is slow), and which shows.
    --- @type nil|{here: HeroBuilderFillPlan, every: nil|HeroBuilderFillPlan, all: boolean}
    local fillOpen = nil
    --- @type fun(all: boolean)
    local ShowFill

    local function CloseFill()
        fillOpen = nil
        if fillButton ~= nil and fillButton.valid then
            fillButton.popup = nil
        end
    end

    --- What Fill would choose on every step (Level up: every Level waiting).
    --- @param token CharacterToken
    --- @return HeroBuilderFillPlan
    local function PlanEvery(token)
        if levelUp then
            local all = {}
            for _, waiting in ipairs(state.queue) do
                all[waiting.key] = true
            end
            return PlanFill(token, {"class"}, all)
        end
        local stepids = {}
        for _, step in ipairs(steps) do
            if not FILL_SKIPS[step.id] and StepShown(step.id) then
                stepids[#stepids+1] = step.id
            end
        end
        return PlanFill(token, stepids)
    end

    --- Work out what Fill would choose, then show it: this step first,
    --- or every step when this one has nothing left. With nothing left
    --- anywhere, the footer says so instead.
    local function OpenFill()
        local token = ViewToken()
        if token == nil or not Host().canWrite() then
            return
        end
        HeroBuilder.ClosePinned()
        if EndPreview ~= nil then
            EndPreview()
        end
        state.filled = nil
        Guard(function()
            local here = {entries = {}, rows = {}, key = BuildKey(token)}
            if levelUp then
                local page = LevelUpPage()
                here = PlanFill(token, {"class"}, {[page ~= nil and page.key or 0] = true})
            elseif state.step ~= nil and not FILL_SKIPS[state.step] then
                here = PlanFill(token, {state.step})
            end
            --every step is planned now only when this one has nothing left.
            local every = nil
            if #here.rows == 0 then
                every = PlanEvery(token)
                if #every.rows == 0 then
                    state.filled = {count = 0, step = state.step or "", key = BuildKey(token)}
                    Paint()
                    return
                end
            end
            fillOpen = {here = here, every = every, all = #here.rows == 0}
            ShowFill(fillOpen.all)
        end)
    end

    --- Make a plan's choices as one undo step, then say how many.
    --- @param plan HeroBuilderFillPlan
    local function ApplyFillPlan(plan)
        local token = ViewToken()
        if token == nil then
            return
        end
        --the Hero changed under the preview (another window or player): show
        --what Fill would choose now instead.
        if BuildKey(token) ~= plan.key then
            CloseFill()
            OpenFill()
            return
        end
        local all = fillOpen ~= nil and fillOpen.all == true
        CloseFill()
        local count = 0
        --the name and art are the token's, not the build's: saved first, as
        --their own Undo step under the build's (the engine saves them apart).
        local look = plan.look
        if look ~= nil and (look.name ~= nil or look.art ~= nil) then
            Guard(function()
                Host().saveAppearance(function(editToken)
                    if look.name ~= nil and trim(editToken.name or "") == "" then
                        editToken.name = look.name
                        count = count + 1
                    end
                    if look.art ~= nil and not Engine().PortraitIsSet(editToken.portrait) then
                        editToken.portrait = look.art
                        editToken.offTokenPortrait = ""
                        count = count + 1
                    end
                end)
            end)
            if state.error ~= nil then
                --the name and art did not save: stop here, with the error
                --showing, rather than let the build's save clear it.
                Paint()
                return
            end
        end
        if #plan.entries > 0 then
            Save(T("herobuilder.undo.fill"), function(hero)
                count = count + Engine().hero.ApplyFill(hero, plan.entries)
            end)
        end
        local live = Host().token()
        if state.error == nil and live ~= nil then
            state.filled = {count = count, step = state.step or "", key = BuildKey(live)}
            --analytics: how many picks Fill made, and where.
            local page = LevelUpPage()
            if levelUp and page ~= nil then
                Track("builder_fill", {scope = cond(all, "every Level", "Level"), level = page.level, rung = page.rung, picks = count, dailyLimit = 10})
            else
                Track("builder_fill", {scope = cond(all, "every step", "step"), stepId = state.step or "", picks = count, dailyLimit = 10})
            end
        end
        Paint()
    end

    --The pop-up's inner width: a 470-unit frame less its padding.
    local FILL_WIDTH = 438
    local FILL_LABEL_WIDTH = 150
    --past this the list scrolls.
    local FILL_LIST_MAX = 430

    --- The pop-up's parts for the open plans: the heading, the choices
    --- (grouped by step for every step), the note, then the buttons.
    --- @param all boolean every step's plan
    --- @return Panel[]
    local function FillContent(all)
        local open = fillOpen --[[@as {here: HeroBuilderFillPlan, every: nil|HeroBuilderFillPlan, all: boolean}]]
        local plan = open.here
        if all then
            plan = open.every --[[@as HeroBuilderFillPlan]]
        end
        local palette = HeroSheetTheme.Palette()
        local list = {}
        local lastStep = nil
        local anyStar = false
        for _, row in ipairs(plan.rows) do
            if all and row.step ~= lastStep then
                lastStep = row.step
                list[#list+1] = gui.Label{
                    classes = {"heroSheetCardLabel"},
                    text = string.upper(stepTitles[row.step] or row.step),
                    fontSize = 11.5,
                    bold = true,
                    width = FILL_WIDTH,
                    height = "auto",
                    tmargin = cond(#list == 0, 2, 12),
                }
            end
            anyStar = anyStar or row.quickBuild
            --- @type Panel[]
            local value = {
                gui.Label{
                    classes = {"heroSheetCardStrong"},
                    text = row.value,
                    fontSize = 13.5,
                    width = "auto",
                    maxWidth = FILL_WIDTH - FILL_LABEL_WIDTH - 30,
                    height = "auto",
                    valign = "center",
                    textWrap = true,
                },
            }
            if row.quickBuild then
                local star = HeroBuilder.QuickBuildStar{size = 13}
                star.selfStyle.lmargin = 5
                value[#value+1] = star
            end
            list[#list+1] = gui.Panel{
                bgimage = "panels/square.png",
                bgcolor = "clear",
                --a faint rule under each row (y1 is the bottom edge).
                border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
                borderColor = "#ffffff12",
                width = FILL_WIDTH,
                height = "auto",
                flow = "horizontal",
                vpad = 6,
                borderBox = true,
                gui.Label{
                    text = row.label,
                    color = palette.cardLab,
                    fontSize = 13.5,
                    width = FILL_LABEL_WIDTH,
                    height = "auto",
                    valign = "center",
                    textWrap = true,
                },
                gui.Panel{
                    width = FILL_WIDTH - FILL_LABEL_WIDTH - 10,
                    height = "auto",
                    flow = "horizontal",
                    lmargin = 10,
                    valign = "center",
                    children = value,
                },
            }
        end
        local body = gui.Panel{
            width = FILL_WIDTH,
            height = "auto",
            flow = "vertical",
            children = list,
        }
        local scroller = gui.Panel{
            width = FILL_WIDTH,
            height = "auto",
            maxHeight = FILL_LIST_MAX,
            flow = "vertical",
            vscroll = false,
            tmargin = 6,
            body,
        }
        HeroSheetWindow.AfterLayout(function()
            if scroller.valid and body.valid and body.renderedHeight > scroller.renderedHeight + 0.5 then
                scroller.vscroll = true
            end
        end)
        local kept = T("herobuilder.fill.note_kept")
        local note
        if anyStar then
            local star = HeroBuilder.QuickBuildStar{size = 13}
            star.selfStyle.valign = "top"
            star.selfStyle.tmargin = 2
            note = gui.Panel{
                width = FILL_WIDTH,
                height = "auto",
                flow = "horizontal",
                tmargin = 10,
                star,
                gui.Label{
                    classes = {"heroSheetCardSub"},
                    text = T("herobuilder.fill.note_star", {kept = kept}),
                    fontSize = 13,
                    width = FILL_WIDTH - 17,
                    height = "auto",
                    textWrap = true,
                },
            }
        else
            note = gui.Label{
                classes = {"heroSheetCardSub"},
                text = kept,
                fontSize = 13,
                width = FILL_WIDTH,
                height = "auto",
                tmargin = 10,
                textWrap = true,
            }
        end
        --the other scope, offered only when this step has something to fill
        --(in Level up, only while more than one Level waits).
        local buttonRow = {}
        --what Fill names its scope: a step, a Level, or a page once the slow
        --start's pages wait too.
        local noun = T("herobuilder.fill.noun_step")
        if levelUp then
            noun = T("herobuilder.fill.noun_level")
            for _, waiting in ipairs(state.queue) do
                if waiting.level == 1 then
                    noun = T("herobuilder.fill.noun_page")
                end
            end
        end
        if #open.here.rows > 0 and (not levelUp or #state.queue > 1) then
            local words = cond(all, T("herobuilder.fill.scope_this", {noun = noun}), T("herobuilder.fill.scope_every", {noun = noun}))
            local toggle = HeroSheetTheme.WindowButton(words, function()
                ShowFill(not all)
            end, false)
            toggle.selfStyle.lmargin = 0
            toggle.selfStyle.halign = "left"
            buttonRow[#buttonRow+1] = toggle
        end
        buttonRow[#buttonRow+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            HeroSheetTheme.WindowButton(T("herobuilder.fill.cancel"), CloseFill, false),
            HeroSheetTheme.WindowButton(T("herobuilder.fill.apply"), function()
                ApplyFillPlan(plan)
            end, true),
        }
        local buttons = gui.Panel{
            width = FILL_WIDTH,
            height = "auto",
            flow = "horizontal",
            tmargin = 12,
            children = buttonRow,
        }
        return {
            gui.Label{
                classes = {"heroSheetCardStrong"},
                text = cond(all, T("herobuilder.fill.title_every", {noun = noun}), T("herobuilder.fill.title_this", {noun = noun})),
                fontSize = 16,
                bold = true,
                width = FILL_WIDTH,
                height = "auto",
            },
            scroller,
            note,
            buttons,
        }
    end

    --The pop-up opens over the footer, its right edge at Next's left, and
    --stays until Cancel, Fill these, Esc or a click away.
    ShowFill = function(all)
        if fillOpen == nil then
            return
        end
        if all and fillOpen.every == nil then
            local token = ViewToken()
            local open = fillOpen
            if token == nil then
                return
            end
            Guard(function()
                open.every = PlanEvery(token)
            end)
            if open.every == nil or fillOpen ~= open then
                return
            end
        end
        fillOpen.all = all
        fillButton.popup = nil
        fillButton.popupPositioning = nextButton
        fillButton.popup = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            captureEscape = true,
            escapePriority = EscapePriority.DMHUB_POPUP,
            escape = function()
                CloseFill()
            end,
            HeroSheetTheme.CardFrame(gui.Panel{
                width = FILL_WIDTH,
                height = "auto",
                flow = "vertical",
                children = FillContent(all),
            }, false, function() end),
        }
    end

    fillButton = Button{
        text = T("herobuilder.footer.fill"),
        footer = true,
        click = function()
            if fillButton.popup ~= nil then
                CloseFill()
            else
                OpenFill()
            end
        end,
    }
    fillButton:SetClass("collapsed", eotw ~= nil and eotw.only ~= nil)

    --the footer's padding either side, the gap before the message, and the
    --room kept between the message and Next; FitFooter sizes the message
    --from them.
    local FOOTER_PAD = 14
    local MESSAGE_GAP = 14
    local NEXT_GAP = 12
    --what is left on the step and a failed write's error. Each
    --thing left is a link that scrolls to its section and flashes it.
    local message = gui.Label{
        classes = {"heroSheetMuted"},
        text = "",
        fontSize = 14,
        width = MESSAGE_WIDTH,
        height = "auto",
        valign = "center",
        lmargin = MESSAGE_GAP,
        textWrap = true,
        links = true,
        press = function(element)
            local link = element.linkHovered
            if link == nil or state.step == nil then
                return
            end
            if string.starts_with(link, "sec:") then
                ScrollToSection(PageStep(state.step), string.sub(link, 5))
            elseif string.starts_with(link, "step:") then
                GoTo(string.sub(link, 6))
            elseif link == "ap:name" and HoldsAppearance() then
                (apView --[[@as HeroAppearanceView]]).editName()
            elseif link == "ap:art" and HoldsAppearance() then
                local plate = (apView --[[@as HeroAppearanceView]]).revealArt()
                if plate ~= nil and plate.valid then
                    FlashPlate(plate)
                end
            end
        end,
    }

    --- A footer list that stays within two lines: links from the end are
    --- dropped for "and N more" until the plain words fit.
    --- @param line fun(list: string): string the whole line, made around the list
    --- @param links string[] the marked-up links
    --- @param plain string[] each link's words, to measure
    --- @param lastSep string what goes before the last item (" and " or ", ")
    --- @return string
    local function FitLinks(line, links, plain, lastSep)
        local budget = 2 * MESSAGE_WIDTH * 0.9
        for shown = #links, 1, -1 do
            local more = #links - shown
            local words = {}
            local marked = {}
            for i = 1, shown do
                words[i] = plain[i]
                marked[i] = links[i]
            end
            if more > 0 then
                words[#words+1] = T("herobuilder.footer.more", {count = string.format("%d", more)})
                marked[#marked+1] = words[#words]
            end
            local sep = more > 0 and T("herobuilder.list.and") or lastSep
            local function Join(list)
                if #list == 1 then
                    return list[1]
                end
                return table.concat(list, ", ", 1, #list - 1) .. sep .. list[#list]
            end
            if shown == 1 or HeroSheetTheme.TextWidth(line(Join(words)), 14) <= budget then
                return line(Join(marked))
            end
        end
        return line("")
    end

    --- The footer line for a step: a failed write's error, else
    --- "Still to choose here:" and each choice left, a link to its section.
    --- A step's main pick reads as its outline says it ("an ancestry"); two
    --- choices with one name ("Perk") add their Level. On Review it is
    --- "Still to do:" and each step with something left, a link to it.
    --- @param stepid string
    --- @param byId table<string, table> each step's status
    local function PaintMessage(stepid, byId)
        message:SetClass("heroSheetDanger", state.error ~= nil)
        message:SetClass("heroSheetMuted", state.error == nil)
        if state.error == nil and state.notice ~= nil then
            message.text = state.notice
            return
        end
        if state.error ~= nil then
            message.text = T("herobuilder.footer.error", {error = state.error})
            return
        end
        --what Fill in the rest did, until the next change or step.
        local filled = state.filled
        if filled ~= nil then
            local token = Host().token()
            if token ~= nil and filled.step == stepid and filled.key == BuildKey(token) then
                local filledCount = filled.count
                message.text = cond(filledCount == 0, T("herobuilder.footer.nothing_to_fill"), TP("herobuilder.footer.filled", filledCount, {count = string.format("%d", filledCount)}))
                return
            end
            state.filled = nil
        end
        local color = HeroSheetTheme.Palette().strong
        if stepid == REVIEW then
            local links, plain = {}, {}
            for _, step in ipairs(steps) do
                local stepStatus = byId[step.id]
                if step.id ~= REVIEW and StepShown(step.id) and stepStatus ~= nil and (stepStatus.stale or PicksLeft(stepStatus) > 0) then
                    links[#links+1] = string.format("<color=%s><u><link=step:%s>%s</link></u></color>", color, step.id, step.title)
                    plain[#plain+1] = step.title
                end
            end
            message.text = cond(#links > 0, FitLinks(function(list) return T("herobuilder.footer.still_to_do", {list = list}) end, links, plain, ", "), T("herobuilder.footer.all_chosen"))
            return
        end
        --the Appearance step: a link to set the name and one to choose the
        --art, for whichever is still missing.
        if stepid == "appearance" then
            local links = {}
            local stepStatus = byId.appearance
            for _, row in ipairs(stepStatus ~= nil and stepStatus.rows or {}) do
                local word = APPEARANCE_LINKS[row.guid]
                if word ~= nil and not row.complete then
                    links[#links+1] = string.format("<color=%s><u><link=ap:%s>%s</link></u></color>", color, row.guid == "name" and "name" or "art", word)
                end
            end
            message.text = cond(#links > 0, T("herobuilder.footer.still_to_choose", {list = table.concat(links, T("herobuilder.list.and"))}), "")
            return
        end
        --- @type {key: string, text: string, level: integer}[]
        local items = {}
        local entry = built[PageStep(stepid)]
        if stepid == "skills" and entry ~= nil and entry.left ~= nil then
            for _, kind in ipairs({"skill", "language"}) do
                if (entry.left[kind] or 0) > 0 then
                    items[#items+1] = {key = kind, text = cond(kind == "skill", T("herobuilder.skills.skills"), T("herobuilder.skills.languages")), level = 1}
                end
            end
        elseif entry ~= nil and entry.model ~= nil then
            for _, section in ipairs(entry.model.sections) do
                if section.statusKind == "go" and section.gain == nil and section.kept == nil then
                    local text = trim(section.title)
                    if section.key == "base" and AFTER[stepid] ~= nil then
                        text = AFTER[stepid]
                    end
                    items[#items+1] = {key = section.key, text = text, level = section.level or 1}
                end
            end
            --Level up's skill and language choices: links to their block.
            local page = levelUp and LevelUpPage() or nil
            if page ~= nil and levelPools ~= nil then
                for _, kind in ipairs({"skill", "language"}) do
                    local left = 0
                    for _, poolLeft in pairs(levelPools[kind]) do
                        left = left + poolLeft
                    end
                    if left > 0 then
                        items[#items+1] = {key = kind, text = cond(kind == "skill", T("herobuilder.skills.skills"), T("herobuilder.skills.languages")), level = page.level or 1}
                    end
                end
            end
        end
        if #items == 0 then
            message.text = ""
            return
        end
        local count = {}
        for _, item in ipairs(items) do
            count[item.text] = (count[item.text] or 0) + 1
        end
        --each link light cream and underlined, in the muted line.
        local links = {}
        for _, item in ipairs(items) do
            local text = item.text
            if count[text] > 1 then
                text = T("herobuilder.footer.item_level", {item = text, level = string.format("%d", item.level)})
            end
            links[#links+1] = string.format("<color=%s><u><link=sec:%s>%s</link></u></color>", color, item.key, text)
        end
        local plain = {}
        for i, item in ipairs(items) do
            plain[i] = count[item.text] > 1 and T("herobuilder.footer.item_level", {item = item.text, level = string.format("%d", item.level)}) or item.text
        end
        message.text = FitLinks(function(list) return T("herobuilder.footer.still_to_choose", {list = list}) end, links, plain, T("herobuilder.list.and"))
    end
    local footer = gui.Panel{
        classes = {"heroSheetPlate"},
        bgimage = "panels/square.png",
        cornerRadius = 10,
        width = "100%",
        height = FOOTER_HEIGHT,
        tmargin = BODY_GAP,
        flow = "horizontal",
        hpad = FOOTER_PAD,
        borderBox = true,
        backButton,
        message,
        fillButton,
        nextButton,
    }

    --- painting ---

    --- The Class step's status in a Builder status.
    --- @param status table
    --- @return nil|table
    local function ClassStatus(status)
        for _, stepStatus in ipairs(status.steps) do
            if stepStatus.id == "class" then
                return stepStatus
            end
        end
        return nil
    end

    --- One page of Level up: the Class step's status with only the rows on
    --- that page (Engine().PageGroups), marked levelUp. Its skill and
    --- language choices are not rows: `pools` lists them by kind
    --- (choice guid to picks left), for the page's Skills & Languages block.
    --- @param hero character
    --- @param classStatus table
    --- @param page HeroBuilderStep
    --- @return table
    local function LevelStatus(hero, classStatus, page)
        local list = Engine().hero.LevelRows(hero)
        local own = {}
        local guids = {}
        for i, row in ipairs(list) do
            own[i] = row.level
            guids[i] = row.guid
        end
        --the slow start's pages, for a Hero Level up shows them to.
        local firstLevel = nil
        if hero:try_get("rungSeen") ~= nil then
            firstLevel = Engine().hero.FirstLevelPages(hero)
        end
        local rows = {}
        local pools = {skill = {}, language = {}}
        for i, group in ipairs(Engine().PageGroups(own, guids, firstLevel, #list)) do
            local row = list[i]
            if group == page.key then
                if row.pool ~= nil then
                    pools[row.pool][row.guid] = cond(row.complete, 0, math.max(1, row.remaining or 1))
                else
                    rows[#rows+1] = row
                end
            end
        end
        return {id = "class", title = classStatus.title, rows = rows, levelUp = page, pools = pools}
    end

    --- Picks left in a page's skill and language choices, by kind.
    --- @param levelStatus table LevelStatus
    --- @param kind string
    --- @return integer
    local function PoolsLeft(levelStatus, kind)
        local left = 0
        for _, poolLeft in pairs(levelStatus.pools[kind]) do
            left = left + poolLeft
        end
        return left
    end

    --- Level up's Skills & Languages block: the
    --- page's skill and language choices in the Skills & Languages
    --- component's parts mode, as the Skills step shows them: the chips under
    --- the class choices, the rows in the pane after their blocks. Only this
    --- page's choices are rows; what the Hero has already shows as Known. Built
    --- for one page's choices and repainted while those stay; none when the
    --- page has none.
    --- @param token CharacterToken the Hero Level up shows (ViewToken)
    --- @param levelStatus table LevelStatus
    local function PaintLevelSkills(token, levelStatus)
        local kinds = {}
        local sig = {tostring(innerW), tostring(paneInnerW)}
        for _, kind in ipairs({"skill", "language"}) do
            local guids = {}
            for guid, _ in pairs(levelStatus.pools[kind]) do
                guids[#guids+1] = guid
            end
            table.sort(guids)
            if #guids > 0 then
                kinds[#kinds+1] = kind
            end
            sig[#sig+1] = table.concat(guids, ",")
        end
        local signature = table.concat(sig, "|")
        if levelSkills ~= nil and levelSkills.sig ~= signature then
            levelSkills.page:DestroySelf()
            levelSkills.pane:DestroySelf()
            levelSkills = nil
        end
        if #kinds == 0 then
            return
        end
        local hero = token.properties --[[@as character]]
        if levelSkills ~= nil and levelSkills.key ~= BuildKey(token) then
            --another pick or client changed the Hero: read it into the built panels.
            local fresh = true
            for _, kind in ipairs(kinds) do
                local draft = HeroSkillsLanguages.Read(hero, kind, levelStatus.pools[kind], Engine())
                fresh = fresh and levelSkills.controls[kind].SetDraft(draft)
            end
            if fresh then
                levelSkills.key = BuildKey(token)
            else
                levelSkills.page:DestroySelf()
                levelSkills.pane:DestroySelf()
                levelSkills = nil
            end
        end
        if levelSkills ~= nil then
            return
        end

        local sections = {}
        local controls = {}
        local pageChildren = {}
        local paneChildren = {}
        for _, kind in ipairs(kinds) do
            local draft = HeroSkillsLanguages.Read(hero, kind, levelStatus.pools[kind], Engine())
            local _, control = HeroSkillsLanguages.Panel{
                draft = draft,
                width = innerW,
                rowWidth = paneInnerW,
                parts = true,
                stars = true,
                slice = true,
                onBuilt = function()
                    FitScroll(pageScroll)
                end,
                onChange = function(changedDraft)
                    if not HeroSkillsLanguages.Changed(changedDraft) then
                        return
                    end
                    Save(cond(kind == "skill", T("herobuilder.undo.change_skills"), T("herobuilder.undo.change_languages")), function(liveHero)
                        HeroSkillsLanguages.Apply(liveHero, changedDraft)
                    end)
                    if state.error ~= nil then
                        --not saved: the next paint rebuilds the block from the Hero.
                        if levelSkills ~= nil then
                            levelSkills.key = nil
                        end
                        return
                    end
                    HeroSkillsLanguages.Rebaseline(changedDraft)
                    --the save's repaint keeps these panels (and a selected row).
                    local shown = ViewToken()
                    if levelSkills ~= nil and shown ~= nil then
                        levelSkills.key = BuildKey(shown)
                    end
                end,
            }
            controls[kind] = control
            local parts = control.parts --[[@as HeroSkillsParts]]
            local head, status = SectionHead(cond(kind == "skill", T("herobuilder.skills.skills"), T("herobuilder.skills.languages")), cond(kind == "language", parts.search, nil))
            status:SetClass("collapsed", true)
            head[#head+1] = parts.chips
            --an edge that can flash, as every page section has (the footer's links).
            sections[kind] = SectionPanel(head)
            pageChildren[#pageChildren+1] = sections[kind]
            paneChildren[#paneChildren+1] = parts.rows
            --a Level shows only its own choices, not the Known already line;
            --it stays attached in a collapsed holder (every panel made must be).
            paneChildren[#paneChildren+1] = gui.Panel{classes = {"collapsed"}, width = 1, height = 1, parts.known}
        end
        levelSkills = {
            sig = signature,
            key = BuildKey(token),
            page = gui.Panel{width = "100%", height = "auto", flow = "vertical", children = pageChildren},
            pane = gui.Panel{width = "100%", height = "auto", flow = "vertical", children = paneChildren},
            sections = sections,
            controls = controls,
        }
        pageContent:AddChild(levelSkills.page)
        paneContent:AddChild(levelSkills.pane)
        --Esc clears a selected row before it leaves, as on the Skills step.
        local entry = built.class
        if entry ~= nil then
            entry.clearSelection = function()
                local cleared = false
                if levelSkills ~= nil then
                    for _, control in pairs(levelSkills.controls) do
                        cleared = control.ClearSelection() or cleared
                    end
                end
                return cleared
            end
        end
    end

    PicksOpen = function(page)
        local token = ViewToken()
        local classStatus = token ~= nil and ClassStatus(Status(token)) or nil
        if token == nil or classStatus == nil then
            return 0
        end
        local open = 0
        local levelStatus = LevelStatus(token.properties --[[@as character]], classStatus, page)
        for _, row in ipairs(levelStatus.rows) do
            if not row.complete then
                open = open + math.max(1, row.remaining or 1)
            end
        end
        return open + PoolsLeft(levelStatus, "skill") + PoolsLeft(levelStatus, "language")
    end

    --- A manual Level up's note: when the Level rises,
    --- and, for a Hero without the experience for it, what that does.
    --- @param hero character the Hero at their own Level
    --- @param level integer the Level being taken
    --- @return string
    local function ManualNote(hero, level)
        local note = T("herobuilder.levelup.manual_note", {level = string.format("%d", level)})
        local perLevel = tonumber(dmhub.GetSettingValue("xpperlevel")) or 16
        if perLevel <= 0 then
            perLevel = 16
        end
        if (tonumber(hero:try_get("xp", 0)) or 0) < (level - 1) * perLevel then
            note = note .. " " .. T("herobuilder.levelup.manual_xp_note")
        end
        return note
    end

    --- The standing preview a manual Level up shows on the card: the
    --- Hero at the Level being taken, against the Hero as they are.
    --- @type {key: nil|string, spec: nil|HeroSheetCardPreview}
    local standing = {key = nil, spec = nil}
    --- @param live CharacterToken
    --- @param shown CharacterToken the copy Level up shows
    local function PaintStanding(live, shown)
        local key = BuildKey(live) .. "|" .. BuildKey(shown)
        if standing.key ~= key then
            local spec = HeroSheetCard.BuilderPreview(HeroSheetCard.BuilderNumbers(live.properties), HeroSheetCard.BuilderNumbers(shown.properties))
                or {kit = {}, also = {}}
            spec.level = state.manual
            standing = {key = key, spec = spec}
        end
        if card.valid then
            card.data.stand(standing.spec)
        end
    end

    --- Paints one step's pill: its state's colours on the mark, number and
    --- line under the name, the tick when done, and the open step selected.
    --- @param step HeroBuilderStep
    --- @param number integer its place among the pills shown
    --- @param pillState string "done", "todo", "optional", "stale" or "plain"
    --- @param sub string the line under its name
    local function PaintPill(step, number, pillState, sub)
        local parts = pills[step.id]
        for _, part in ipairs({parts.mark, parts.number, parts.sub}) do
            for _, stateName in ipairs({"done", "todo", "optional", "stale"}) do
                part:SetClass(stateName, stateName == pillState)
            end
        end
        parts.tick:SetClass("collapsed", pillState ~= "done")
        parts.number:SetClass("collapsed", pillState == "done")
        parts.number.text = tostring(number)
        parts.sub.text = sub
        parts.pill:SetClassTree("selected", step.id == state.step)
    end

    --- Level up's paint: the page's heading, the pills while
    --- more than one page waits, that page and its pane, its Finish. On the
    --- manual path the card shows the Level being taken.
    --- @param token CharacterToken the Hero Level up shows (ViewToken)
    --- @param status table
    local function PaintLevelUp(token, status)
        local hero = token.properties --[[@as character]]
        local classStatus = ClassStatus(status)
        if classStatus == nil or #state.queue == 0 then
            return
        end
        local page = LevelUpPage()
        if page == nil or not state.inQueue[page.id] then
            state.step = PageStepId(state.queue[1])
            page = LevelUpPage()
        end
        if page == nil or page.key == nil then
            return
        end
        local level = page.level or 1
        --another page starts at its top, nothing pinned.
        if state.shownLevel ~= page.id then
            state.shownLevel = page.id
            pageScroll.vscrollPosition = 1
            paneScroll.vscrollPosition = 1
            HeroBuilder.ClosePinned()
        end
        --a slow-start rung's page is named for the rung.
        local ordinal = Ordinal(level)
        local features = T("herobuilder.levelup.features", {ordinal = ordinal})
        if page.rung ~= nil then
            heading.text = T("herobuilder.levelup.rung_heading", {rung = page.title})
            features = T("herobuilder.levelup.rung_features", {rung = page.title})
            pageLevelLabel.text = T("herobuilder.levelup.level", {level = "1"}) .. " \u{00B7} " .. page.title
        else
            heading.text = T("herobuilder.levelup.heading", {ordinal = ordinal})
            pageLevelLabel.text = T("herobuilder.levelup.level", {level = string.format("%d", level)})
        end
        local name = token.name
        local named = type(name) == "string" and trim(name) ~= ""
        nameLabel.text = cond(named, tostring(name) .. " \u{00B7}", "")
        nameLabel:SetClass("collapsed", not named)

        --each pill: picks left, Done, or (a page with no choices not yet
        --finished) Nothing to choose.
        local waiting = {}
        for _, waitingPage in ipairs(Engine().hero.LevelsWaiting(hero)) do
            waiting[waitingPage.key] = waitingPage
        end
        local number = 0
        for _, step in ipairs(steps) do
            if StepShown(step.id) then
                number = number + 1
            end
            local waitingPage = waiting[step.key or 0]
            local pillState, sub = "done", T("herobuilder.status.done")
            if waitingPage ~= nil and waitingPage.left > 0 then
                pillState, sub = "todo", T("herobuilder.status.left", {count = string.format("%d", waitingPage.left)})
            elseif waitingPage ~= nil and waitingPage.choices == 0 then
                pillState, sub = "plain", T("herobuilder.pill.nothing_to_choose")
            end
            PaintPill(step, number, pillState, sub)
        end

        local levelStatus = LevelStatus(hero, classStatus, page)
        --EotW's Level up closes with its own words: done once no Level waits.
        if eotw ~= nil then
            local live = Host().token()
            allComplete = live ~= nil and #Engine().hero.LevelsWaiting(live.properties --[[@as character]]) == 0
            backToSheet.data.label.text = (eotw.closeWords(allComplete))
        end
        pageTitle.text = page.title
        if #levelStatus.rows == 0 and next(levelStatus.pools.skill) == nil and next(levelStatus.pools.language) == nil then
            pageLead.text = cond(page.rung ~= nil, T("herobuilder.levelup.lead_nothing_rung", {features = features}), T("herobuilder.levelup.lead_nothing_level", {features = features}))
        else
            pageLead.text = T("herobuilder.levelup.lead", {features = features})
        end
        pageLead:SetClass("collapsed", false)
        local live = Host().token()
        local manual = state.manual
        if manual ~= nil and live ~= nil then
            pageNote.text = ManualNote(live.properties --[[@as character]], manual)
            PaintStanding(live, token)
        elseif card.valid then
            card.data.stand(nil)
        end
        pageNote:SetClass("collapsed", manual == nil)
        paneTitle.text = T("herobuilder.levelup.pane_title", {features = features})
        paneTitle:SetClass("collapsed", false)
        ShowPage(token, "class", levelStatus)
        PaintLevelSkills(token, levelStatus)
        levelPools = levelStatus.pools
        PaintMessage(state.step, {})
        nextButton.data.label.text = FinishWords(page)
        local width = cond(page.rung ~= nil, FINISH_RUNG_WIDTH, FOOTER_BUTTON_WIDTH)
        if width ~= finishW then
            finishW = width
            FitFooter()
        end
        --the manual path's Cancel sits where the Builder has Back.
        backButton.data.label.text = T("herobuilder.footer.cancel")
        backButton:SetClass("collapsed", manual == nil)
        PaintUndo()
    end

    --Shows the open Hero's build: the heading, the Level, the pills, the page
    --heading and the footer. Panels are only painted, never rebuilt.
    local PaintNow
    --a repaint builds each step's rows once, however many parts ask.
    Paint = function()
        Engine().Cached(PaintNow)
        --the picture shows the class's art (the ancestry's before a class)
        --until the player picks their own; written after the paint, outside
        --its cache. The mark keeps the picture written, so a new class moves
        --it on but a picture set anywhere else is left alone.
        --Not an undo step: the next paint would only put it back.
        local token = Host().token()
        if token == nil or token.properties == nil or levelUp or not Host().canWrite() then
            return
        end
        local art = Engine().FollowedPortrait(token)
        if art ~= nil then
            local field = Engine().AUTO_PORTRAIT_FIELD
            token.portrait = art
            token:UploadAppearance()
            token:RefreshAppearanceLocally()
            if token.properties:try_get(field) ~= art then
                Host().save{
                    description = "Portrait",
                    undoable = false,
                    execute = function(props)
                        props[field] = art
                    end,
                }
            end
        end
    end
    PaintNow = function()
        local token = Host().token()
        if token == nil or token.properties == nil or root == nil or not root.valid then
            return
        end
        if levelUp then
            local shown = ViewToken() --[[@as CharacterToken]]
            PaintLevelUp(shown, Status(shown))
            return
        end
        local hero = token.properties --[[@as character]]
        local status = Status(token)
        if state.step == nil or stepIndex[state.step] == nil then
            state.step = FirstOpenStep(status)
        end
        --EotW's single-step mode shows only its one step, whatever is open.
        if eotw ~= nil and eotw.only ~= nil then
            state.step = eotw.only
        end

        --a new Hero is created until it has a class (the heading says which).
        heading.text = cond(hero:GetClass() == nil, T("herobuilder.title.create"), T("herobuilder.title.edit"))
        if eotw ~= nil then
            heading.text = eotw.title or heading.text
            allComplete = status.complete == true
            backToSheet.data.label.text = (eotw.closeWords(allComplete))
        end
        local name = token.name
        if type(name) == "string" and trim(name) ~= "" then
            nameLabel.text = name .. " \u{00B7}"
            nameLabel:SetClass("collapsed", false)
        else
            nameLabel:SetClass("collapsed", true)
        end
        local level = hero:CharacterLevel()
        levelPicker.idChosen = level
        local rung = hero:ExtraLevelInfo().encounter
        if type(rung) ~= "number" then
            rung = nil
        end
        slowGroup:SetClass("collapsed", eotw ~= nil or not (level == 1 and (dmhub.isDM or rung ~= nil)))
        slowPicker.idChosen = rung or 0

        local byId = {}
        for _, stepStatus in ipairs(status.steps) do
            byId[stepStatus.id] = stepStatus
        end
        byId[OTHER] = status.other
        if (status.other ~= nil) ~= otherShown then
            otherShown = status.other ~= nil
            FitPills(pillRowW)
            if not otherShown and state.step == OTHER then
                state.step = FirstOpenStep(status)
            end
        end
        local number = 0
        for _, step in ipairs(steps) do
            if StepShown(step.id) then
                number = number + 1
            end
            local pillState, sub = PillState(token, byId[step.id])
            PaintPill(step, number, pillState, sub)
        end

        local index = stepIndex[state.step]
        local current = steps[index]
        pageTitle.text = current.title
        local lead = LEADS[current.id]
        if current.id == "class" and hero:GetClass() ~= nil then
            lead = CLASS_LEAD_PICKED
        end
        pageLead.text = lead or ""
        pageLead:SetClass("collapsed", lead == nil)
        --the pane's heading names the step; Appearance and Review have pages
        --of their own.
        local hasPane = byId[current.id] ~= nil and current.id ~= "appearance" and current.id ~= OTHER
        paneTitle.text = cond(hasPane, T("herobuilder.pane.title", {step = current.title}), "")
        paneTitle:SetClass("collapsed", not hasPane)
        --Review shows the sheet itself under the banner.
        local reviewing = current.id == REVIEW
        headRow:SetClass("collapsed", reviewing)
        body:SetClass("collapsed", reviewing)
        reviewBanner:SetClass("collapsed", not reviewing)
        reviewSpace:SetClass("collapsed", not reviewing)
        HostAppearance(current.id == "appearance")
        if reviewing then
            local heroName = cond(type(name) == "string" and trim(name) ~= "", name, T("herobuilder.review.your_hero"))
            if eotw ~= nil and eotw.reviewBanner ~= nil then
                reviewBannerText.text = eotw.reviewBanner(heroName)
            else
                reviewBannerText.text = T("herobuilder.review.banner", {hero = heroName})
            end
        elseif current.id ~= "appearance" and byId[current.id] ~= nil then
            ShowPage(token, current.id, byId[current.id])
        end
        if args.review ~= nil then
            if reviewing then
                args.review(ReviewInsets())
            else
                args.review(nil)
            end
        end
        PaintMessage(current.id, byId)

        --Next reads Skip for now while the step has picks left; the last
        --step's is Finish.
        backButton:SetClass("heroSheetDisabled", Neighbour(index, -1) == nil)
        local nextText = T("herobuilder.footer.next")
        nextButton:SetClass("heroBuilderLockIn", Neighbour(index, 1) == nil)
        if Neighbour(index, 1) == nil then
            nextText = T("herobuilder.footer.finish")
        elseif byId[current.id] ~= nil and PicksLeft(byId[current.id]) > 0 then
            nextText = T("herobuilder.footer.skip")
        end
        nextButton.data.label.text = nextText
        PaintUndo()
    end

    --The footer: Back (Cancel on a manual Level up), the message, Fill in
    --the rest, then Next; the message line takes the width the buttons leave.
    FitFooter = function()
        nextButton.selfStyle.width = finishW
        local others = cond(levelUp and state.manual == nil, 1, 2)
        message.selfStyle.width = footerRowW - 2 * FOOTER_PAD - others * FOOTER_BUTTON_WIDTH - finishW - MESSAGE_GAP - NEXT_GAP
    end

    --Sizes every part for the Builder's layout size (set by the window).
    local function Layout()
        local width, height = state.width, state.height
        root.selfStyle.width = width
        root.selfStyle.height = height
        local rowW = width - 2 * PAD_X
        FitPills(rowW)
        --Level up shows its pills only while more than one Level waits.
        local stepperH = STEPPER_GAP + STEPPER_HEIGHT
        --EotW's single-step mode has nowhere else to go.
        if (levelUp and #state.queue <= 1) or (eotw ~= nil and eotw.only ~= nil) then
            stepperH = 0
        end
        stepper:SetClass("collapsed", stepperH == 0)
        local bodyH = math.floor(height - PAD_TOP - HEAD_ROW_HEIGHT - stepperH - BODY_GAP - BODY_GAP - FOOTER_HEIGHT - PAD_BOTTOM)
        local cardW, detailW = ColumnWidths(rowW)
        local pageW = rowW - cardW - detailW - 2 * COLUMN_GAP
        body.selfStyle.height = bodyH
        cardColumn.selfStyle.width = cardW
        cardColumn.selfStyle.height = bodyH
        page.selfStyle.width = pageW
        page.selfStyle.height = bodyH
        pageScroll.selfStyle.height = bodyH - 14
        pane.selfStyle.width = detailW
        pane.selfStyle.height = bodyH
        paneScroll.selfStyle.height = bodyH
        apHost = {
            tier = cond(rowW >= HeroSheetWindow.TIER_WIDE, "wide", "medium"),
            cardW = cardW,
            w = pageW + COLUMN_GAP + detailW,
            h = bodyH,
        }
        apSlot.selfStyle.width = apHost.w
        apSlot.selfStyle.height = bodyH
        SizeAppearance()
        pageScrollHeight = bodyH - 14
        footerRowW = rowW
        FitFooter()
        --on Review the sheet shows through this space (the window places it).
        local insets = ReviewInsets()
        reviewSpace.selfStyle.height = math.max(1, height - insets.top - insets.bottom)
        --the cards fill the page less its padding and room for a scroll bar;
        --a new width refits the kept pages (the Skills page, and Level up's
        --Skills & Languages block, build again).
        local newInner = pageW - 36 - 6 - 12
        --the pane's blocks leave room for its padding and a scroll bar.
        local newPaneInner = detailW - 32 - 12
        if newInner ~= innerW or newPaneInner ~= paneInnerW then
            innerW = newInner
            paneInnerW = newPaneInner
            for _, entry in pairs(built) do
                --You gain and kept picks have no cards to fit.
                for _, parts in pairs(entry.sections or {}) do
                    if parts.grid ~= nil then
                        FitGrid(parts.grid)
                    end
                end
            end
            --only a paint rebuilds them, and the window sends no paint after
            --a resize.
            if (built.skills ~= nil and shownPage == built.skills) or levelSkills ~= nil then
                Paint()
            end
            FitScroll(pageScroll)
        end
    end

    --- Level up opens on the pages waiting now, the lowest first; the
    --- pills keep them until it opens again. With none waiting, the sheet's
    --- Level up button opens the next Level's page (the manual path).
    --- @param manual nil|boolean
    local function OpenQueue(manual)
        local token = Host().token()
        state.queue = {}
        state.inQueue = {}
        state.manual = nil
        local classStatus = nil
        if token ~= nil and token.properties ~= nil then
            classStatus = ClassStatus(Status(token))
        end
        if token ~= nil and classStatus ~= nil then
            state.queue = Engine().hero.LevelsWaiting(token.properties --[[@as character]])
        end
        if token ~= nil and #state.queue == 0 and manual == true then
            local hero = token.properties --[[@as character]]
            state.manual = Engine().hero.ManualLevel(hero)
            local shown = ViewToken()
            if state.manual ~= nil and shown ~= nil then
                local level = state.manual --[[@as integer]]
                local page = {level = level, key = Engine().PageKey(level, nil), left = 0, choices = 0}
                --the new Level's own count, read from the copy at that Level.
                local copy = DeepCopy(shown.properties) --[[@as character]]
                copy.levelUpSeen = level - 1
                local shownClass = ClassStatus(Status(shown))
                for _, waitingPage in ipairs(shownClass ~= nil and Engine().hero.LevelsWaiting(copy) or {}) do
                    if waitingPage.level == level then
                        page = waitingPage
                    end
                end
                state.queue = {page}
            end
        end
        for _, waiting in ipairs(state.queue) do
            state.inQueue[PageStepId(waiting)] = true
        end
        state.step = nil
        state.shownLevel = nil
        if state.queue[1] ~= nil then
            state.step = PageStepId(state.queue[1])
        end
        if card.valid then
            card.data.stand(nil)
        end
        Layout()
    end

    --the block that repaints the Builder when the build changes (below).
    --- @type nil|Panel
    local frameBlock = nil

    root = gui.Panel{
        classes = {"heroBuilder"},
        styles = BuilderRules(),
        width = state.width,
        height = state.height,
        halign = "left",
        valign = "top",
        flow = "vertical",
        hpad = PAD_X,
        tpad = PAD_TOP,
        bpad = PAD_BOTTOM,
        borderBox = true,
        create = function(element)
            HeroSheetTheme.Track(element, function(panel)
                panel.styles = BuilderRules()
            end)
        end,
        --a closed EotW Builder hands the file's helpers back to the sheet.
        destroy = function(element)
            if g_host == args.host then
                g_host = nil
            end
        end,
        heroBuilderLayout = function(element, width, height)
            state.width = width
            state.height = height
            Layout()
        end,
        --- @param at nil|{step: nil|string, section: nil|string, manual: nil|boolean} a deep link's target, or Level up's manual path
        heroBuilderOpen = function(element, at)
            g_host = args.host
            state.step = nil
            if levelUp then
                OpenQueue(at ~= nil and at.manual == true)
            elseif at ~= nil and at.step ~= nil and stepIndex[at.step] ~= nil then
                state.step = at.step
            end
            viewed = {}
            HeroBuilder.ClosePinned()
            Paint()
            --a hidden Builder does not repaint on changes (it is stale until
            --shown); this paint covers them, so the catch-up need not paint again.
            if frameBlock ~= nil then
                Host().drawn(frameBlock)
            end
            --once the step's page is laid out, scroll to the choice and flash
            --it. A page built just now turns its scrolling on only after its
            --first layout (FitScroll), so the scroll waits a layout more.
            if at ~= nil and at.section ~= nil and state.step == at.step then
                local step, section = at.step --[[@as string]], at.section --[[@as string]]
                HeroSheetWindow.AfterLayout(function()
                    HeroSheetWindow.AfterLayout(function()
                        if not mod.unloaded and state.step == step then
                            ScrollToSection(step, section)
                        end
                    end)
                end)
            end
        end,
        data = {
            --Esc (HeroSheet's onEscape) first clears a selected skill row;
            --true when it did, so the Builder stays open.
            escape = function()
                return shownPage ~= nil and shownPage.clearSelection ~= nil and shownPage.clearSelection() == true
            end,
        },
        heroSheetHero = function(element, token)
            state.step = nil
            if levelUp then
                OpenQueue()
            end
            HeroBuilder.ClosePinned()
            MarkShown(nil)
            showcase = nil
        end,
        headRow,
        stepper,
        body,
        reviewBanner,
        reviewSpace,
        footer,
        --what the Builder paints follows the Hero's build: repainted when it
        --changes here or on another client.
        Host().block({
            create = function(element)
                frameBlock = element
            end,
            floating = true,
            interactable = false,
            width = 1,
            height = 1,
        }, {
            name = "builder frame",
            builder = true,
            signature = function(token)
                return BuildKey(token)
            end,
            refresh = function(panel, token)
                Paint()
            end,
        }),
    }
    return root
end

--A reload (F4) of this file leaves the sheet window holding a Builder (and
--a Level up) built by the old code: drop them, and when one is showing,
--open the new one in its place.
local g_live = rawget(_G, "g_heroSheetLive")
if g_live ~= nil and g_live.window ~= nil and g_live.window.valid and (g_live.window.data.builderPanel ~= nil or g_live.window.data.levelUpPanel ~= nil) then
    g_live.window.data.builderPanel = nil
    g_live.window.data.levelUpPanel = nil
    dmhub.Schedule(0.1, function()
        local state = HeroSheet.State()
        local token = Host().token()
        if not mod.unloaded and state ~= nil and state.tab == "Builder" and token ~= nil then
            if state.levelUp == true then
                HeroSheet.OpenLevelUp()
            else
                HeroSheet.Open(token, "Builder")
            end
        end
    end)
end

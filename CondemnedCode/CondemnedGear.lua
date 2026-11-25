local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- The Condemned: Experimental Gear ("Gearing Up")
--------------------------------------------------------------------------------
--Before the mission the Director opens a window for the whole table where each hero
--chooses experimental gear and grenades; the Director then hands it all out. This
--part is the state and the hand out; the window is built on top of it.
--
--Storage:
--  * The "condemnedGear" document: the allowance, whether the window is open, each
--    hero's choices as one JSON string, and which heroes are done. Every write copies the
--    whole document, so it holds only this, and two players choosing at once write
--    different keys. Done has its own key so pressing it never rewrites the choices.
--  * What a hero was given is a marker on the hero (MARKER), written in the same write
--    as the items. An undo takes both away together, so nothing is given twice.

CondemnedGear = rawget(_G, "CondemnedGear") or {}

local T = UIText.T

local DOC_ID = "condemnedGear"
local MARKER = "condemnedGearDelivered"

--- What each hero may take, as the book gives it.
CondemnedGear.BOOK_ALLOWANCE = { gear = 1, grenades = 3 }

--- The gear, in the order the window shows it (tbl_Gear ids).
CondemnedGear.GEAR = {
    "bd64f33f-554f-4720-b9f9-96fc78bfbe67", --Ashen Armor
    "9086521b-1a4d-47cc-b1a9-b5d8a7dfdd3b", --Incineration Lance
    "c08ccd52-c535-4671-af62-efcd39516b0b", --Infiltration Suit
    "faf2fccc-7ee7-4128-9e0b-c680cc42deb5", --The Silencer
    "76757099-7981-49ab-ab7d-fad9616ee321", --Blackpowder Launcher
    "3e02a067-8e4e-4578-a4ad-de94f8029988", --Targeting Lens
}

--- The grenades, in the order the window shows them (tbl_Gear ids).
CondemnedGear.GRENADES = {
    "f8128ac0-f69f-405c-a4b3-9c2fef636bcc", --Blackpowder Grenade
    "2adbc6cc-3583-49f6-a2e7-e6c0e84a6481", --Ignition Grenade
    "5c09ffd7-3463-41d9-8161-6bda48096327", --Stun Grenade
    "c2f84597-0493-4457-93b7-d2065d9b7640", --Remote Grenade
    "480ce7ad-23d4-4655-9943-ff7f0b9359b2", --Shaped Grenade
}

--- @class CondemnedGearAllowance
--- @field gear integer pieces of gear each hero may take
--- @field grenades integer grenades each hero may take

--- @class CondemnedGearChoices
--- @field gear string[] the chosen gear's itemids
--- @field grenades table<string, integer> grenade itemid -> how many
--- @field done nil|boolean the hero's player pressed Done; any later change clears it

--- @class CondemnedGearHero
--- @field charid string
--- @field token CharacterToken
--- @field name string

local function Doc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

--Changes the gear document. Not undoable: a -/+ click should not fill anyone's undo list.
local function ChangeDoc(description, fn)
    local doc = Doc()
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description, { undoable = false })
end

--- The document's path, for a panel's monitorGame.
--- @return string
function CondemnedGear.DocPath()
    return mod:GetDocumentPath(DOC_ID)
end

--- What each hero may take. Reads the book's numbers until the Director changes them.
--- @return CondemnedGearAllowance
function CondemnedGear.Allowance()
    local allow = Doc().data.allow
    local book = CondemnedGear.BOOK_ALLOWANCE
    if type(allow) ~= "table" then
        return { gear = book.gear, grenades = book.grenades }
    end
    return {
        gear = math.floor(tonumber(allow.gear) or book.gear),
        grenades = math.floor(tonumber(allow.grenades) or book.grenades),
    }
end

--- @param gear integer
--- @param grenades integer
function CondemnedGear.SetAllowance(gear, grenades)
    ChangeDoc("Experimental gear allowance", function(data)
        data.allow = { gear = math.max(0, gear), grenades = math.max(0, grenades) }
    end)
end

--- True while the window is open for the table.
--- @return boolean
function CondemnedGear.IsOpen()
    return Doc().data.open == true
end

--- @param open boolean
function CondemnedGear.SetOpen(open)
    ChangeDoc(open and "Open experimental gear" or "Close experimental gear", function(data)
        data.open = open or nil
    end)
end

--- Starts Gearing Up over: closes the window for everyone and clears every hero's choices.
--- Leaves the allowance and anything already handed out alone (the delivered marker is
--- what stops a hero being given their gear twice).
function CondemnedGear.Reset()
    ChangeDoc("Reset experimental gear", function(data)
        data.open = nil
        data.choices = nil
        data.done = nil
    end)
end

--A hero's stored choices, or empty ones when nothing (or nothing readable) is stored.
--- @param raw any
--- @return CondemnedGearChoices
local function DecodeChoices(raw)
    local result = { gear = {}, grenades = {} }
    if type(raw) ~= "string" then
        return result
    end
    local ok, decoded = pcall(dmhub.FromJson, raw)
    local value = ok and type(decoded) == "table" and decoded.success and decoded.result or nil
    if type(value) ~= "table" then
        return result
    end
    for _, itemid in ipairs(value.gear or {}) do
        result.gear[#result.gear + 1] = itemid
    end
    for itemid, count in pairs(value.grenades or {}) do
        count = math.floor(tonumber(count) or 0)
        if count > 0 then
            result.grenades[itemid] = count
        end
    end
    return result
end

--- What a hero has chosen so far, and whether their player pressed Done.
--- @param charid string
--- @return CondemnedGearChoices
function CondemnedGear.Choices(charid)
    local data = Doc().data
    local result = DecodeChoices((data.choices or {})[charid])
    result.done = (data.done or {})[charid] == true or nil
    return result
end

--- Store a hero's choices (the whole set, replacing what was there); nil clears them.
--- Any change sets the hero back to choosing until Done is pressed again.
--- @param charid string
--- @param choices nil|CondemnedGearChoices
function CondemnedGear.SetChoices(charid, choices)
    local stored = nil
    if choices ~= nil then
        stored = { gear = choices.gear, grenades = choices.grenades }
    end
    ChangeDoc("Choose experimental gear", function(data)
        data.choices = data.choices or {}
        data.choices[charid] = stored ~= nil and dmhub.ToRawJson(stored) or nil
        if data.done ~= nil then
            data.done[charid] = nil
        end
    end)
end

--- Mark a hero's choices as finished (the Done button). They may be fewer than the
--- allowance; changing them afterwards (SetChoices) sets the hero back to choosing.
--- @param charid string
function CondemnedGear.SetDone(charid)
    ChangeDoc("Done choosing experimental gear", function(data)
        data.done = data.done or {}
        data.done[charid] = true
    end)
end

--- How many grenades a set of choices holds.
--- @param choices CondemnedGearChoices
--- @return integer
function CondemnedGear.GrenadeCount(choices)
    local total = 0
    for _, count in pairs(choices.grenades) do
        total = total + count
    end
    return total
end

--- What a hero was handed out, or nil when they have not had their gear yet.
--- @param token nil|CharacterToken
--- @return nil|CondemnedGearChoices
function CondemnedGear.Delivered(token)
    if token == nil or token.properties == nil then
        return nil
    end
    return token.properties:try_get(MARKER)
end

--- The heroes choosing gear: the Campaign panel's roster, less anyone blown up.
--- @return CondemnedGearHero[]
function CondemnedGear.Heroes()
    local result = {}
    for _, entry in ipairs(CondemnedCampaign.Roster()) do
        if CondemnedCampaign.CollarStatus(entry.charid, entry.token) ~= "detonated" then
            result[#result + 1] = entry
        end
    end
    return result
end

--- The heroes this user chooses for: every hero for the Director; a player's own heroes;
--- failing that their primary character, when it is one of the heroes. Empty when the
--- Director chooses for them.
--- @return CondemnedGearHero[]
function CondemnedGear.MyHeroes()
    local heroes = CondemnedGear.Heroes()
    if dmhub.isDM then
        return heroes
    end
    local own = {}
    for _, entry in ipairs(heroes) do
        if entry.token.ownerId == dmhub.userid then
            own[#own + 1] = entry
        end
    end
    if #own > 0 then
        return own
    end
    local primary = dmhub.primaryCharacter
    if primary ~= nil then
        for _, entry in ipairs(heroes) do
            if entry.charid == primary.charid then
                return { entry }
            end
        end
    end
    return {}
end

--- Where a hero is up to: "given" (handed out), "over" (more than the allowance, after
--- the Director lowered it), "done" (their player pressed Done, whatever they chose),
--- "nothing" or "choosing".
--- @param entry CondemnedGearHero
--- @return string
function CondemnedGear.Status(entry)
    if CondemnedGear.Delivered(entry.token) ~= nil then
        return "given"
    end
    local allow = CondemnedGear.Allowance()
    local choices = CondemnedGear.Choices(entry.charid)
    local gear, grenades = #choices.gear, CondemnedGear.GrenadeCount(choices)
    if gear > allow.gear or grenades > allow.grenades then
        return "over"
    end
    if choices.done then
        return "done"
    end
    if gear == 0 and grenades == 0 then
        return "nothing"
    end
    return "choosing"
end

--true from pressing Hand out until the server answers, so a second press sends nothing.
local g_handingOut = false

--- True while a hand out waits for the server's answer.
--- @return boolean
function CondemnedGear.IsHandingOut()
    return g_handingOut
end

--Gives one hero their choices, equipping gear into a free slot (else it stays in the
--inventory), and leaves the marker. Runs inside the hand out's write. Skips a hero whose
--marker this screen already sees, e.g. after another Director's Hand out has arrived.
--- @param hero creature
--- @param choices CondemnedGearChoices
local function GiveChoices(hero, choices)
    if hero:try_get(MARKER) ~= nil then
        return
    end
    for _, itemid in ipairs(choices.gear) do
        hero:GiveItem(itemid, 1)
        HeroSheetWrite.EquipOnHero(hero, itemid)
    end
    for itemid, count in pairs(choices.grenades) do
        hero:GiveItem(itemid, count)
    end
    hero[MARKER] = dmhub.DeepCopy(choices)
end

--- Director only. Gives every hero who has not had their gear yet what they chose, as one
--- write the server applies whole or not at all, then closes the window for everyone.
--- onDone(ok, count) runs when the server answers: ok false means another change to a
--- hero got in first and nothing was given. Returns false and why when nothing was sent:
--- "busy" (not the Director, or a hand out already waiting), "over" (someone Over limit)
--- or "nothing" (no hero who still needs gear has chosen any).
--- @param onDone nil|fun(ok: boolean, count: integer)
--- @return boolean sent
--- @return nil|string why
function CondemnedGear.HandOut(onDone)
    if g_handingOut or not dmhub.isDM then
        return false, "busy"
    end
    --- @type {token: CharacterToken, choices: CondemnedGearChoices}[]
    local pending = {}
    for _, entry in ipairs(CondemnedGear.Heroes()) do
        local status = CondemnedGear.Status(entry)
        if status == "over" then
            return false, "over"
        end
        --a hero with nothing chosen (Done or not) gets no marker, so a later round can still
        --give them gear: pressing Done by mistake must not lock a hero out.
        local choices = CondemnedGear.Choices(entry.charid)
        local empty = #choices.gear == 0 and CondemnedGear.GrenadeCount(choices) == 0
        if status ~= "given" and not empty then
            pending[#pending + 1] = { token = entry.token, choices = choices }
        end
    end
    if #pending == 0 then
        return false, "nothing"
    end

    local holders = {}
    for _, item in ipairs(pending) do
        holders[#holders + 1] = item.token
    end

    g_handingOut = true
    dmhub.AtomicChange{
        holders = holders,
        description = T("condemned.gear.hand_out"),
        execute = function()
            for _, item in ipairs(pending) do
                GiveChoices(item.token.properties, item.choices)
            end
        end,
        onSuccess = function()
            if mod.unloaded or not g_handingOut then
                return
            end
            g_handingOut = false
            CondemnedGear.SetOpen(false)
            if onDone ~= nil then
                onDone(true, #pending)
            end
        end,
        onFail = function(error, step)
            if mod.unloaded then
                return
            end
            print(string.format("CONDEMNED GEAR:: hand out %s refused: %s", tostring(step), tostring(error)))
            --an undo or redo refused later has nothing waiting on it.
            if step == "do" and g_handingOut then
                g_handingOut = false
                if onDone ~= nil then
                    onDone(false, #pending)
                end
            end
        end,
    }
    return true
end

--- How many heroes have had their gear, out of how many heroes there are.
--- @return integer given
--- @return integer total
function CondemnedGear.HandedOutCount()
    local heroes = CondemnedGear.Heroes()
    local given = 0
    for _, entry in ipairs(heroes) do
        if CondemnedGear.Delivered(entry.token) ~= nil then
            given = given + 1
        end
    end
    return given, #heroes
end

--- True once the gear has gone out: the window is closed and a hero has their marker.
--- @return boolean
function CondemnedGear.AnyHandedOut()
    if CondemnedGear.IsOpen() then
        return false
    end
    for _, entry in ipairs(CondemnedGear.Heroes()) do
        if CondemnedGear.Delivered(entry.token) ~= nil then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
--A modal pop-up the Director's Open puts on every screen. Anyone can close theirs and
--reopen it from the floating tab or the Campaign Tracker while it is open. Built once;
--changes repaint it in place.

local OPEN_EVENT = "condemnedGearOpen"

--design size in sheet units, before Font Size zooms it.
local WINDOW_WIDTH = 1040
local WINDOW_HEIGHT = 672
local BAND_HEIGHT = 56

--Narrower than this (a large Font Size capped by the screen), gear shows as one row per
--item: three cards would be too narrow to read.
local ROWS_BELOW = 930

--The band's art: the painting on the journal's "Handout: Experimental Gear" page,
--cropped to the collar (engine image rects count y from the bottom).
local BAND_ART = "296d2a75-fd85-4ca4-aff4-e069e361f144"
local BAND_ART_RECT = { x1 = 0.025, y1 = 0.523, x2 = 0.992, y2 = 0.714 }

--- @type nil|Panel
local g_frame = nil

--The hero the window is choosing for; nil shows the party table (the Director, or a
--player with several heroes).
--- @type nil|string
local g_charid = nil

--The hero a player chooses for when the window opens: their only hero. The Director,
--and a player with several, start on the party table.
--- @return nil|string
local function StartingHero()
    if dmhub.isDM then
        return nil
    end
    local mine = CondemnedGear.MyHeroes()
    if #mine == 1 then
        return mine[1].charid
    end
    return nil
end

--- @param charid string
--- @return nil|CondemnedGearHero
local function FindHero(charid)
    for _, entry in ipairs(CondemnedGear.Heroes()) do
        if entry.charid == charid then
            return entry
        end
    end
    return nil
end

--The item shown in the preview pane, in this user's window.
--- @type string
local g_selected = CondemnedGear.GEAR[1]

--True while the window is too narrow for gear cards: one row per item instead.
local g_useRows = false

--the body under the band, and its two columns: the list, and the preview pane.
local BODY_HEIGHT = WINDOW_HEIGHT - BAND_HEIGHT
local BODY_HPAD = 14
local BODY_VPAD = 11
--the picker's footer under both columns, which holds Done (its rule included).
local DONE_FOOT = 56
local PANE_WIDTH = 357
local COLUMN_GAP = 14
local LIST_WIDTH = WINDOW_WIDTH - 2 * BODY_HPAD - COLUMN_GAP - PANE_WIDTH
--room the list keeps for its scroll bar.
local SCROLL_GUTTER = 10
local LIST_INNER = LIST_WIDTH - SCROLL_GUTTER
local CARD_GAP = 8
local CARD_WIDTH = math.floor((LIST_INNER - 2 * CARD_GAP) / 3)
local CARD_HEIGHT = 116
--a gear card's padding, art and the gap after the art: its name column gets the rest.
local CARD_PAD = 9
local CARD_ART = 44
local CARD_TEXT_WIDTH = CARD_WIDTH - 2 * CARD_PAD - CARD_ART - CARD_PAD
--a grenade row's padding, art and gap, and the room its -/+ count takes on the right.
local ROW_PAD = 8
local ROW_ART = 36
local ROW_ART_GAP = 10
local ROW_STEPPER_ROOM = 90
--the pane's "n chosen" label beside its button, for a grenade the hero has some of.
local CHOSEN_COUNT_ROOM = 110

--Colours the hero sheet's classes do not have: a chosen item's edge and the Over limit
--pill. Built from the scheme's palette and compiled once per palette.
local g_gearStyles = { key = nil, styles = nil }

--- @return table[]
local function GearStyles()
    local palette = HeroSheetTheme.Palette()
    local key = dmhub.ToJson(palette)
    if g_gearStyles.key == key and g_gearStyles.styles ~= nil then
        return g_gearStyles.styles
    end
    local rules = {
        --above the hero sheet's row edges (priority 5 and under).
        { selectors = { "cgChosen" }, borderColor = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.rawSuccess, 0.7)), priority = 10 },
        --the shown item's edge wins over the chosen one.
        { selectors = { "cgChosen", "heroSheetRowPinned" }, borderColor = palette.cardStrong, priority = 11 },
        { selectors = { "cgArt" }, bgcolor = palette.tile, borderColor = palette.tileBorder },
        { selectors = { "cgOverPill" }, borderColor = palette.warning, color = palette.warning },
        { selectors = { "cgSuccessIcon" }, bgcolor = palette.cardSuccess },
        --the window's own surface: the scheme's plate colour.
        { selectors = { "cgWindow" }, bgcolor = palette.plate },
        { selectors = { "cgTab" }, borderColor = palette.tileBorder },
        --the main action: solid gold (the scheme's info colour) with dark bold words.
        { selectors = { "heroSheetButton", "cgGold" }, bgcolor = palette.rawInfo, borderColor = palette.rawInfo, priority = 10 },
        { selectors = { "heroSheetButton", "cgGold", "hover" }, brightness = 1.12, priority = 11 },
        { selectors = { "heroSheetButtonLabel", "cgGold" }, color = palette.bg, bold = true, priority = 10 },
        --status pills: their colour wins over the pill's own muted text.
        { selectors = { "heroSheetPill", "heroSheetCardSuccess" }, color = palette.cardSuccess, priority = 10 },
        { selectors = { "heroSheetPill", "heroSheetCardLabel" }, color = palette.cardLabel, priority = 10 },
        { selectors = { "heroSheetPill", "heroSheetWarning" }, color = palette.warning, priority = 10 },
    }
    local compiled = {}
    for i, rule in ipairs(rules) do
        compiled[i] = gui.Style(rule)
    end
    g_gearStyles = { key = key, styles = compiled }
    return compiled
end

--The window's buttons are a frame with a label inside; these change both at once.
local DIM_OPACITY = 0.45

--- Solid gold (the scheme's info colour), for a window's main action.
--- @param button Panel a HeroSheetTheme.WindowButton
--- @param gold boolean
local function SetGold(button, gold)
    button:SetClass("cgGold", gold)
    button.children[1]:SetClass("cgGold", gold)
end

--- Dim a button that can't be used now. Opacity is not passed on to children, so the
--- label is dimmed too.
--- @param button Panel a HeroSheetTheme.WindowButton
--- @param dimmed boolean
local function Dim(button, dimmed)
    local opacity = dimmed and DIM_OPACITY or 1
    button.selfStyle.opacity = opacity
    button.children[1].selfStyle.opacity = opacity
end

--- True when this user may change the hero's choices: the Director, or their own hero
--- before it has been handed out.
--- @param hero CondemnedGearHero
--- @return boolean
local function CanChooseFor(hero)
    if CondemnedGear.Delivered(hero.token) ~= nil then
        return false
    end
    if dmhub.isDM then
        return true
    end
    for _, entry in ipairs(CondemnedGear.MyHeroes()) do
        if entry.charid == hero.charid then
            return true
        end
    end
    return false
end

--- What the window shows for a hero: what they were given once handed out, else their
--- choices so far.
--- @param hero CondemnedGearHero
--- @return CondemnedGearChoices
local function ShownChoices(hero)
    return CondemnedGear.Delivered(hero.token) or CondemnedGear.Choices(hero.charid)
end

--An item's picture in a small framed square, the size given.
--- @param item table a tbl_Gear row
--- @param size number
--- @return Panel
local function ItemArt(item, size)
    return gui.Panel{
        classes = { "cgArt" },
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = size,
        height = size,
        halign = "left",
        valign = "center",
        interactable = false,
        gui.Panel{
            bgimage = item.iconid,
            bgcolor = "white",
            width = "86%",
            height = "86%",
            halign = "center",
            valign = "center",
        },
    }
end

--A list section's heading: its name, the "n / max" count, and the Over limit pill.
--Paint it with heading:FireEvent("count", n, max).
--- @param text string
--- @return Panel
local function SectionHeading(text)
    local count = gui.Label{
        classes = { "heroSheetCardSub" },
        text = "",
        width = "auto",
        height = "auto",
        fontSize = 13,
        lmargin = 10,
        halign = "left",
        valign = "bottom",
    }
    local pill = gui.Label{
        classes = { "heroSheetPill", "cgOverPill" },
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        cornerRadius = 9,
        text = T("condemned.gear.over_limit"),
        width = "auto",
        height = 20,
        hpad = 8,
        borderBox = true,
        fontSize = 12,
        bold = true,
        lmargin = 10,
        halign = "left",
        valign = "center",
        linger = gui.Tooltip(T("condemned.gear.over_limit_tip")),
    }
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        count = function(element, chosen, max)
            count.text = T("condemned.gear.count", { n = chosen, max = max })
            count:SetClass("heroSheetCardSuccess", chosen == max)
            count:SetClass("heroSheetWarning", chosen > max)
            count:SetClass("heroSheetCardSub", chosen < max)
            pill:SetClass("collapsed", chosen <= max)
        end,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 24,
            gui.Label{
                classes = { "heroSheetCardStrong" },
                text = string.upper(text),
                width = "auto",
                height = "auto",
                fontSize = 15,
                bold = true,
                halign = "left",
                valign = "bottom",
            },
            count,
            pill,
        },
        gui.Panel{
            classes = { "heroSheetDialogRule" },
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            tmargin = 6,
        },
    }
end

--The "Chosen" mark on a gear card.
--- @return Panel
local function ChosenMark()
    return gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        interactable = false,
        gui.Panel{
            classes = { "cgSuccessIcon" },
            bgimage = "phosphor/check-bold.png",
            width = 12,
            height = 12,
            valign = "center",
        },
        gui.Label{
            classes = { "heroSheetCardSuccess" },
            text = string.upper(T("condemned.gear.chosen")),
            width = "auto",
            height = "auto",
            fontSize = 11,
            bold = true,
            lmargin = 4,
            valign = "center",
        },
    }
end

--Builds the list of gear and grenades for the hero being chosen for. Built once; its
--"paint" event sets counts, chosen edges, the shown item and the steppers.
--repaint() repaints the whole window (after a choice is written).
--- @param repaint fun()
--- @return Panel
local function BuildList(repaint)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}

    local function Hero()
        return g_charid ~= nil and FindHero(g_charid) or nil
    end

    local function Select(itemid)
        g_selected = itemid
        repaint()
    end

    local gearHeading = SectionHeading(T("condemned.gear.gear"))
    local grenadeHeading = SectionHeading(T("condemned.gear.grenades"))

    --Each gear item has a card (three to a row) and a one-line form for a narrow window.
    --Each set is built the first time the window needs it and kept; a layout change
    --shows the other set.
    local cards = {}
    local rows = {}
    local cardList = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = LIST_INNER + CARD_GAP,
        height = "auto",
        tmargin = 8,
    }
    local rowList = gui.Panel{
        flow = "vertical",
        width = LIST_INNER,
        height = "auto",
        tmargin = 8,
    }
    local function BuildCards()
        for _, itemid in ipairs(CondemnedGear.GEAR) do
            local item = gearTable[itemid]
            if item ~= nil then
                local keywords = HeroSheetInventory.Keywords(item)
                local flavor = item:try_get("flavor", "")
                cards[#cards + 1] = gui.Panel{
                    classes = { "heroSheetListRow", "hoverable" },
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 10,
                    width = CARD_WIDTH,
                    height = CARD_HEIGHT,
                    flow = "vertical",
                    pad = CARD_PAD,
                    borderBox = true,
                    rmargin = CARD_GAP,
                    bmargin = CARD_GAP,
                    data = { itemid = itemid },
                    click = function()
                        Select(itemid)
                    end,
                    gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = 46,
                        interactable = false,
                        ItemArt(item, CARD_ART),
                        gui.Panel{
                            flow = "vertical",
                            width = CARD_TEXT_WIDTH,
                            height = "auto",
                            lmargin = CARD_PAD,
                            valign = "center",
                            gui.Label{
                                classes = { "heroSheetCardStrong" },
                                text = item.name,
                                width = "100%",
                                height = "auto",
                                maxHeight = 38,
                                fontSize = 15,
                                bold = true,
                                textWrap = true,
                            },
                            HeroSheetTheme.EllipsisLabel{
                                classes = { "heroSheetCardSub" },
                                text = keywords,
                                width = "100%",
                                height = "auto",
                                fontSize = 12,
                            },
                        },
                    },
                    gui.Label{
                        classes = { "heroSheetCardLab" },
                        text = flavor,
                        width = "100%",
                        height = 32,
                        fontSize = 12,
                        italics = true,
                        textWrap = true,
                        textOverflow = "ellipsis",
                        tmargin = 4,
                        interactable = false,
                    },
                    gui.Panel{
                        width = "100%",
                        height = "auto",
                        valign = "bottom",
                        interactable = false,
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            ChosenMark(),
                        },
                    },
                }
                cardList:AddChild(cards[#cards])
            end
        end
    end
    local function BuildRows()
        for _, itemid in ipairs(CondemnedGear.GEAR) do
            local item = gearTable[itemid]
            if item ~= nil then
                local keywords = HeroSheetInventory.Keywords(item)
                local flavor = item:try_get("flavor", "")
                rows[#rows + 1] = gui.Panel{
                    classes = { "heroSheetListRow", "hoverable" },
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 8,
                    width = LIST_INNER,
                    height = 52,
                    flow = "horizontal",
                    hpad = ROW_PAD,
                    borderBox = true,
                    bmargin = 5,
                    data = { itemid = itemid },
                    click = function()
                        Select(itemid)
                    end,
                    ItemArt(item, ROW_ART),
                    gui.Panel{
                        flow = "vertical",
                        width = LIST_INNER - 2 * ROW_PAD - ROW_ART - ROW_ART_GAP - ROW_STEPPER_ROOM,
                        height = "auto",
                        lmargin = ROW_ART_GAP,
                        valign = "center",
                        interactable = false,
                        gui.Panel{
                            flow = "horizontal",
                            width = "100%",
                            height = "auto",
                            gui.Label{
                                classes = { "heroSheetCardStrong" },
                                text = item.name,
                                width = "auto",
                                height = "auto",
                                fontSize = 15,
                                bold = true,
                                textWrap = false,
                                valign = "bottom",
                            },
                            HeroSheetTheme.EllipsisLabel{
                                classes = { "heroSheetCardSub" },
                                text = keywords,
                                width = 260,
                                height = "auto",
                                fontSize = 12,
                                lmargin = 8,
                                valign = "bottom",
                            },
                        },
                        HeroSheetTheme.EllipsisLabel{
                            classes = { "heroSheetCardLab" },
                            text = flavor,
                            width = "100%",
                            height = "auto",
                            fontSize = 12,
                            italics = true,
                        },
                    },
                    gui.Panel{
                        width = 90,
                        height = "auto",
                        valign = "center",
                        interactable = false,
                        gui.Panel{
                            width = "auto",
                            height = "auto",
                            halign = "right",
                            ChosenMark(),
                        },
                    },
                }
                rowList:AddChild(rows[#rows])
            end
        end
    end

    --The grenades: a row each with a -/+ count.
    local grenadeRows = {}
    for _, itemid in ipairs(CondemnedGear.GRENADES) do
        local item = gearTable[itemid]
        if item ~= nil then
            local function Count()
                local hero = Hero()
                return hero ~= nil and (ShownChoices(hero).grenades[itemid] or 0) or 0
            end
            local stepper = HeroSheetInventoryActions.Stepper(Count, function(count)
                local hero = Hero()
                if hero == nil or not CanChooseFor(hero) then
                    return
                end
                local choices = CondemnedGear.Choices(hero.charid)
                choices.grenades[itemid] = count > 0 and count or nil
                CondemnedGear.SetChoices(hero.charid, choices)
                g_selected = itemid
                repaint()
            end, function()
                --room left under the allowance for this grenade.
                local hero = Hero()
                if hero == nil then
                    return 0
                end
                local choices = ShownChoices(hero)
                local others = CondemnedGear.GrenadeCount(choices) - (choices.grenades[itemid] or 0)
                return math.max(Count(), CondemnedGear.Allowance().grenades - others)
            end, {
                min = 0,
                canEdit = function()
                    local hero = Hero()
                    return hero ~= nil and CanChooseFor(hero)
                end,
                plusTip = function()
                    local hero = Hero()
                    local max = CondemnedGear.Allowance().grenades
                    if hero ~= nil and CondemnedGear.GrenadeCount(ShownChoices(hero)) >= max then
                        return T("condemned.gear.grenades_full_tip", { max = max })
                    end
                    return nil
                end,
            })
            stepper.selfStyle.halign = "right"
            grenadeRows[#grenadeRows + 1] = gui.Panel{
                classes = { "heroSheetListRow", "hoverable" },
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 8,
                width = LIST_INNER,
                height = 38,
                flow = "horizontal",
                hpad = 6,
                borderBox = true,
                bmargin = 5,
                data = { itemid = itemid },
                click = function()
                    Select(itemid)
                end,
                ItemArt(item, 28),
                gui.Label{
                    classes = { "heroSheetCardStrong" },
                    text = item.name,
                    width = "auto",
                    height = "auto",
                    fontSize = 14,
                    bold = true,
                    lmargin = 10,
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                    interactable = false,
                },
                HeroSheetTheme.EllipsisLabel{
                    classes = { "heroSheetCardSub" },
                    text = HeroSheetInventory.Keywords(item),
                    width = 150,
                    height = "auto",
                    fontSize = 12,
                    lmargin = 8,
                    halign = "left",
                    valign = "center",
                },
                stepper,
            }
        end
    end
    --the grenades share one flavour line: the book gives it once, for all of them.
    local firstGrenade = gearTable[CondemnedGear.GRENADES[1]]

    local inner = gui.Panel{
        flow = "vertical",
        width = LIST_INNER,
        height = "auto",
        valign = "top",
        gearHeading,
        cardList,
        rowList,
        gui.Panel{ width = 1, height = 10 },
        grenadeHeading,
        gui.Label{
            classes = { "heroSheetCardLab" },
            text = firstGrenade ~= nil and firstGrenade:try_get("flavor", "") or "",
            width = "100%",
            height = "auto",
            fontSize = 12,
            italics = true,
            textWrap = true,
            tmargin = 6,
        },
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            tmargin = 8,
            children = grenadeRows,
        },
    }

    return gui.Panel{
        width = LIST_WIDTH,
        height = "100%",
        vscroll = true,
        paint = function(element)
            local hero = Hero()
            if hero == nil then
                return
            end
            if g_useRows and #rows == 0 then
                BuildRows()
            elseif not g_useRows and #cards == 0 then
                BuildCards()
            end
            local allow = CondemnedGear.Allowance()
            local choices = ShownChoices(hero)
            gearHeading:FireEvent("count", #choices.gear, allow.gear)
            grenadeHeading:FireEvent("count", CondemnedGear.GrenadeCount(choices), allow.grenades)
            local chosen = {}
            for _, itemid in ipairs(choices.gear) do
                chosen[itemid] = true
            end
            for _, list in ipairs({ cards, rows }) do
                for _, panel in ipairs(list) do
                    local itemid = panel.data.itemid
                    panel:SetClass("cgChosen", chosen[itemid] == true)
                    panel:SetClass("heroSheetRowPinned", g_selected == itemid)
                    --the mark is the card's last child.
                    local children = panel.children
                    children[#children]:SetClass("collapsed", chosen[itemid] ~= true)
                end
            end
            for _, panel in ipairs(grenadeRows) do
                local itemid = panel.data.itemid
                panel:SetClass("cgChosen", (choices.grenades[itemid] or 0) > 0)
                panel:SetClass("heroSheetRowPinned", g_selected == itemid)
            end
            cardList:SetClass("collapsed", g_useRows)
            rowList:SetClass("collapsed", not g_useRows)
            element:FireEventTree("refreshNumber")
        end,
        inner,
    }
end

--Changes to a hero's choices, from the pane's button. Each reads the stored choices just
--before writing, so a change from another screen that has already arrived is kept.
--- @param hero CondemnedGearHero
--- @param change fun(choices: CondemnedGearChoices)
local function ChangeChoices(hero, change)
    local choices = CondemnedGear.Choices(hero.charid)
    change(choices)
    CondemnedGear.SetChoices(hero.charid, choices)
end

--A small upper-case heading in the pane ("YOU GAIN").
--- @param text string
--- @return Panel
local function PaneHeading(text)
    return gui.Label{
        classes = { "heroSheetCardLabel" },
        text = string.upper(text),
        width = "100%",
        height = "auto",
        fontSize = 11,
        bold = true,
        tmargin = 12,
        bmargin = 5,
    }
end

--The pane beside the list: the shown item in full, and the one button that chooses it.
--Built once; "paint" fills it for the shown item. The slow parts are kept: what
--equipping would change is worked out once per hero, item and equipment, and an
--ability card is built the first time it is shown for a hero.
--- @param repaint fun()
--- @return Panel
local function BuildPane(repaint)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local innerWidth = PANE_WIDTH - SCROLL_GUTTER
    local FOOT_HEIGHT = 54

    local artImage = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "86%",
        height = "86%",
        halign = "center",
        valign = "center",
    }
    local name = gui.Label{
        classes = { "heroSheetCardStrong" },
        text = "",
        width = "100%",
        height = "auto",
        fontSize = 19,
        bold = true,
        textWrap = true,
    }
    local kind = gui.Label{
        classes = { "heroSheetCardLabel" },
        text = "",
        width = "100%",
        height = "auto",
        fontSize = 13,
        bold = true,
        tmargin = 2,
    }
    local flavor = gui.Label{
        classes = { "heroSheetCardLab" },
        text = "",
        width = "100%",
        height = "auto",
        fontSize = 13,
        italics = true,
        textWrap = true,
        tmargin = 8,
    }

    --What choosing it would change: pills built as needed and reused.
    local chipHeading = PaneHeading("")
    local chipHolder = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
    }
    local chipSection = gui.Panel{ flow = "vertical", width = "100%", height = "auto", chipHeading, chipHolder }
    --- @type {panel: Panel, text: Panel, mark: Panel}[]
    local chipPanels = {}
    --- @type {label: string, change: number}[]
    local chips = {}
    local chipsKey = nil

    --Ability cards, one holder per hero and item, kept once built.
    local gainHolder = gui.Panel{ flow = "vertical", width = "100%", height = "auto" }
    local gainSection = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        PaneHeading(T("condemned.gear.you_gain")),
        gainHolder,
    }
    --- @type table<string, Panel>
    local gainCards = {}

    --The three Levels of a piece of gear, the reached ones lit (as the inventory's pane).
    --- @type {panel: Panel, title: Panel, body: Panel}[]
    local tierBlocks = {}
    local tierSection = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        PaneHeading(T("condemned.gear.by_level")),
    }
    for i, tier in ipairs(HeroSheetInventory.TIERS) do
        local title = gui.Label{
            classes = { "heroSheetCardLabel" },
            text = string.upper(tier.name),
            fontSize = 11,
            bold = true,
            width = "100%",
            height = "auto",
        }
        local body = gui.Label{
            classes = { "heroSheetCardText" },
            text = "",
            markdown = true,
            fontSize = 13,
            width = "100%",
            height = "auto",
            textWrap = true,
            tmargin = 3,
        }
        local panel = gui.Panel{
            classes = { "heroSheetTier" },
            bgimage = "panels/square.png",
            cornerRadius = 8,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 9,
            borderBox = true,
            bmargin = 6,
            title,
            body,
        }
        tierBlocks[i] = { panel = panel, title = title, body = body }
        tierSection:AddChild(panel)
    end

    --The footer: how many of a grenade are chosen, and the button.
    local chosenCount = gui.Label{
        classes = { "heroSheetCardSuccess" },
        text = "",
        width = "auto",
        height = "auto",
        fontSize = 13,
        bold = true,
        halign = "left",
        valign = "center",
    }
    --what the button does now; nil when it is dimmed.
    --- @type nil|fun()
    local action = nil
    local button = HeroSheetTheme.WindowButton("", function()
        if action ~= nil then
            action()
            repaint()
        end
    end, true)
    button.selfStyle.halign = "right"
    --its width is set to fill the footer, so the shared button's left margin would push it past the edge.
    button.selfStyle.lmargin = 0
    local buttonLabel = button.children[1]

    --- @param text string
    --- @param fn nil|fun() nil dims the button
    --- @param tip nil|string why it is dimmed
    --- @param gold nil|boolean the main action's gold (Choose); Put back is plain
    local function SetButton(text, fn, tip, gold)
        buttonLabel.text = text
        action = fn
        button.data.tip = tip
        SetGold(button, gold == true)
        Dim(button, fn == nil)
    end

    local body = gui.Panel{
        width = PANE_WIDTH,
        height = BODY_HEIGHT - 2 * BODY_VPAD - FOOT_HEIGHT - DONE_FOOT,
        vscroll = true,
        gui.Panel{
            flow = "vertical",
            width = innerWidth,
            height = "auto",
            valign = "top",
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                gui.Panel{
                    classes = { "cgArt" },
                    bgimage = "panels/square.png",
                    border = 1,
                    cornerRadius = 8,
                    width = 56,
                    height = 56,
                    halign = "left",
                    valign = "center",
                    artImage,
                },
                gui.Panel{
                    flow = "vertical",
                    width = innerWidth - 56 - 12,
                    height = "auto",
                    lmargin = 12,
                    valign = "center",
                    name,
                    kind,
                },
            },
            gui.Panel{
                classes = { "heroSheetDialogRule" },
                bgimage = "panels/square.png",
                width = "100%",
                height = 1,
                tmargin = 8,
            },
            flavor,
            chipSection,
            gainSection,
            tierSection,
        },
    }

    return gui.Panel{
        flow = "vertical",
        width = PANE_WIDTH,
        height = "100%",
        lmargin = COLUMN_GAP - math.floor(COLUMN_GAP / 2),
        paint = function(element)
            local hero = g_charid ~= nil and FindHero(g_charid) or nil
            local item = gearTable[g_selected]
            if hero == nil or item == nil then
                return
            end
            local token = hero.token
            local grenade = table.contains(CondemnedGear.GRENADES, g_selected)
            local delivered = CondemnedGear.Delivered(token) ~= nil
            local choices = ShownChoices(hero)
            local allow = CondemnedGear.Allowance()
            local level = 1
            pcall(function() level = token.properties:CharacterLevel() end)

            artImage.bgimage = item.iconid
            name.text = item.name
            kind.text = HeroSheetInventory.Keywords(item)
            --the grenades share the book's one flavour line.
            local flavorItem = grenade and gearTable[CondemnedGear.GRENADES[1]] or item
            flavor.text = flavorItem ~= nil and flavorItem:try_get("flavor", "") or ""

            local chosen = table.contains(choices.gear, g_selected)

            --What equipping it would change. Gear only; once handed out the hero is
            --wearing it, so there is nothing left to preview.
            if grenade or delivered then
                chips = {}
                chipsKey = nil
            else
                --worked out again only when the hero, the item, their equipment or Level changes.
                local key = string.format("%s|%s|%s|%d", hero.charid, g_selected, dmhub.ToJson(token.properties:Equipment()), level)
                if key ~= chipsKey then
                    chipsKey = key
                    chips = {}
                    pcall(function()
                        local slot = HeroSheetWrite.EquipSlot(token.properties, g_selected, true)
                        if slot ~= nil then
                            for _, change in ipairs(EotwHeroSheet.EquipPreview(token, g_selected, nil, slot) or {}) do
                                local from, to = tonumber(change.from), tonumber(change.to)
                                if from ~= nil and to ~= nil and from ~= to then
                                    chips[#chips + 1] = { label = change.label, change = to - from }
                                end
                            end
                        end
                    end)
                end
            end
            chipSection:SetClass("collapsed", #chips == 0)
            chipHeading.text = string.upper(chosen and T("condemned.gear.giving_you") or T("condemned.gear.would_change"))
            local palette = HeroSheetTheme.Palette()
            for i, chip in ipairs(chips) do
                local pill = chipPanels[i]
                if pill == nil then
                    pill = {
                        text = gui.Label{
                            classes = { "heroSheetCardSub" },
                            text = "",
                            width = "auto",
                            height = "auto",
                            fontSize = 12.5,
                            textWrap = false,
                            valign = "center",
                            interactable = false,
                        },
                        mark = HeroSheetCard.Mark(),
                    }
                    pill.panel = gui.Panel{
                        classes = { "heroSheetPill" },
                        bgimage = "panels/square.png",
                        bgcolor = "clear",
                        border = 1,
                        cornerRadius = 9,
                        width = "auto",
                        height = 22,
                        hpad = 9,
                        borderBox = true,
                        flow = "horizontal",
                        rmargin = 6,
                        bmargin = 4,
                        halign = "left",
                        valign = "center",
                        pill.text,
                        pill.mark,
                    }
                    chipPanels[i] = pill
                    chipHolder:AddChild(pill.panel)
                end
                pill.text.text = string.format("%s <b><color=%s>%s%d</color></b>", chip.label, palette.cardStrong, chip.change > 0 and "+" or "-", math.abs(chip.change))
                HeroSheetCard.SetMark(pill.mark, chip.change > 0)
                pill.panel:SetClass("collapsed", false)
            end
            for i = #chips + 1, #chipPanels do
                chipPanels[i].panel:SetClass("collapsed", true)
            end

            --You gain: the item's abilities, as this hero would use them.
            local cardKey = hero.charid .. "|" .. g_selected
            if gainCards[cardKey] == nil then
                local cards = {}
                local abilities = {}
                if grenade then
                    local ability = item:try_get("consumable")
                    if ability ~= nil then
                        abilities[1] = { ability = ability }
                    end
                else
                    for _, feature in ipairs(item:try_get("features", {})) do
                        for _, granted in ipairs(HeroSheetFeatures.GrantedAbilities(feature)) do
                            abilities[#abilities + 1] = granted
                        end
                    end
                end
                for _, granted in ipairs(abilities) do
                    local card = nil
                    pcall(function()
                        if granted.ability ~= nil then
                            card = CreateAbilityTooltip(granted.ability, { token = token, width = innerWidth, bgcolor = "#00000000" })
                        elseif granted.trigger ~= nil then
                            card = granted.trigger:Render{ token = token, width = innerWidth }
                        end
                    end)
                    if card ~= nil then
                        cards[#cards + 1] = card
                    end
                end
                gainCards[cardKey] = gui.Panel{
                    flow = "vertical",
                    width = "100%",
                    height = "auto",
                    data = { count = #cards },
                    children = cards,
                }
                gainHolder:AddChild(gainCards[cardKey])
            end
            for keyed, holder in pairs(gainCards) do
                holder:SetClass("collapsed", keyed ~= cardKey)
            end
            gainSection:SetClass("collapsed", gainCards[cardKey].data.count == 0)

            --By Level: gear only.
            tierSection:SetClass("collapsed", grenade)
            if not grenade then
                for i, tier in ipairs(HeroSheetInventory.TIERS) do
                    local block = tierBlocks[i]
                    local text = item:try_get(tier.field)
                    local has = type(text) == "string" and text ~= ""
                    local reached = level >= tier.level
                    block.panel:SetClass("collapsed", not has)
                    block.body.text = has and text or ""
                    block.panel:SetClass("heroSheetTierReached", reached)
                    block.title:SetClass("heroSheetTierDim", not reached)
                    block.body:SetClass("heroSheetTierDim", not reached)
                end
            end

            --The button.
            local count = grenade and (choices.grenades[g_selected] or 0) or 0
            chosenCount.text = count > 0 and T("condemned.gear.n_chosen", { n = count }) or ""
            --the button fills the footer, beside the count when there is one.
            button.selfStyle.width = PANE_WIDTH - (count > 0 and CHOSEN_COUNT_ROOM or 0)
            button:SetClass("collapsed", not delivered and not CanChooseFor(hero))
            local selected = g_selected
            if delivered then
                SetButton(T("condemned.gear.handed_out"), nil, nil)
            elseif grenade then
                if CondemnedGear.GrenadeCount(choices) >= allow.grenades then
                    SetButton(T("condemned.gear.choose_one"), nil, T("condemned.gear.grenades_full_tip", { max = allow.grenades }), true)
                else
                    SetButton(T("condemned.gear.choose_one"), function()
                        ChangeChoices(hero, function(stored)
                            stored.grenades[selected] = (stored.grenades[selected] or 0) + 1
                        end)
                    end, nil, true)
                end
            elseif chosen then
                SetButton(T("condemned.gear.put_back"), function()
                    ChangeChoices(hero, function(stored)
                        for i = #stored.gear, 1, -1 do
                            if stored.gear[i] == selected then
                                table.remove(stored.gear, i)
                            end
                        end
                    end)
                end, nil)
            elseif #choices.gear < allow.gear then
                SetButton(T("condemned.gear.choose"), function()
                    ChangeChoices(hero, function(stored)
                        stored.gear[#stored.gear + 1] = selected
                    end)
                end, nil, true)
            elseif allow.gear == 1 and #choices.gear == 1 then
                local current = gearTable[choices.gear[1]]
                SetButton(T("condemned.gear.swap"), function()
                    ChangeChoices(hero, function(stored)
                        stored.gear = { selected }
                    end)
                end, nil, true)
                button.data.tip = T("condemned.gear.swap_tip", { name = current ~= nil and current.name or "" })
            else
                SetButton(T("condemned.gear.choose"), nil, T("condemned.gear.gear_full_tip", { n = #choices.gear, max = allow.gear }), true)
            end
        end,
        body,
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = FOOT_HEIGHT,
            gui.Panel{
                classes = { "heroSheetDialogRule" },
                bgimage = "panels/square.png",
                width = "100%",
                height = 1,
                bmargin = 9,
            },
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                chosenCount,
                button,
            },
        },
    }
end

--The party table's columns, in sheet units, inside a row's padding.
local PARTY_HPAD = 16
local ROW_HPAD = 12
local COL_HERO = 290
local COL_GEAR = 290
local COL_GRENADES = 266
local COL_STATUS = 96
local COL_GAP = 14
--a gear cell's art and the gap after it: the GEAR header starts past them, over the name.
local GEAR_ART = 26
local GEAR_ART_GAP = 8
local GEAR_ART_SLOT = GEAR_ART + GEAR_ART_GAP
--the allowance's highest grenade count: three times the book's three.
local MAX_GRENADES = 9
--the party table's height, and its height while the Hand out confirm takes the room below.
local ROWS_HEIGHT = 380
local ROWS_HEIGHT_CONFIRMING = 190

--Status pill text and colour class, by CondemnedGear.Status.
local STATUS_PILL = {
    done = { id = "condemned.gear.status_done", class = "heroSheetCardSuccess" },
    choosing = { id = "condemned.gear.status_choosing", class = "heroSheetCardLabel" },
    nothing = { id = "condemned.gear.status_nothing", class = "heroSheetCardSub" },
    over = { id = "condemned.gear.over_limit", class = "heroSheetWarning" },
    given = { id = "condemned.gear.handed_out", class = "heroSheetCardSuccess" },
}

--Under a hero's name in the party table: their class, and the player who owns them.
--- @param token CharacterToken
--- @return string
local function HeroSubline(token)
    local className = nil
    pcall(function()
        --heroes are characters; GetClass is a character method.
        local classItem = (token.properties --[[@as character]]):GetClass()
        className = classItem ~= nil and classItem.name or nil
    end)
    local owner = token.ownerId
    local player = nil
    if owner ~= nil and owner ~= "" and owner ~= "PARTY" then
        player = owner
        pcall(function() player = dmhub.GetDisplayName(owner) or owner end)
    end
    if className ~= nil and player ~= nil then
        return T("condemned.gear.hero_sub", { class = className, player = player })
    end
    return className or player or ""
end

--The party table: the Director's (allowance, every hero, Hand out), or a player's with
--several heroes (their own heroes only). A row opens the picker for that hero. Rows are
--built when the list of heroes changes and painted on every change.
--- @param repaint fun()
--- @return Panel
local function BuildParty(repaint)
    local gearTable = dmhub.GetTable("tbl_Gear") or {}
    local book = CondemnedGear.BOOK_ALLOWANCE
    local director = dmhub.isDM

    --- @param text string
    --- @param width number
    local function Column(text, width)
        return gui.Label{
            classes = { "heroSheetCardLabel" },
            text = string.upper(text),
            width = width,
            height = "auto",
            fontSize = 13,
            bold = true,
            rmargin = COL_GAP,
            halign = "left",
        }
    end

    --The allowance: how much each hero may take (Director only, until Hand out).
    local function CanSetAllowance()
        --fixed once anyone has their gear, so a second round plays by the same numbers.
        return director and CondemnedGear.HandedOutCount() == 0
    end
    local function AllowanceStepper(field, max)
        return HeroSheetInventoryActions.Stepper(function()
            return CondemnedGear.Allowance()[field]
        end, function(count)
            local allow = CondemnedGear.Allowance()
            allow[field] = count
            CondemnedGear.SetAllowance(allow.gear, allow.grenades)
            repaint()
        end, max, { min = 0, canEdit = CanSetAllowance })
    end
    --- @param text string
    local function AllowanceWord(text)
        return gui.Label{
            classes = { "heroSheetCardStrong" },
            text = text,
            width = "auto",
            height = "auto",
            fontSize = 14,
            lmargin = 6,
            rmargin = 22,
            halign = "left",
            valign = "center",
        }
    end
    local reset = gui.Label{
        classes = { "heroSheetCardLabel", "link", "underline" },
        bgimage = "panels/square.png",
        bgcolor = "#00000001",
        text = T("condemned.gear.reset"),
        width = "auto",
        height = "auto",
        fontSize = 13,
        lmargin = 10,
        valign = "center",
        press = function()
            if CanSetAllowance() then
                CondemnedGear.SetAllowance(book.gear, book.grenades)
                repaint()
            end
        end,
    }
    local allowRow = gui.Panel{
        classes = { "heroSheetListRow" },
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = 48,
        flow = "horizontal",
        hpad = ROW_HPAD,
        borderBox = true,
        bmargin = 12,
        gui.Label{
            classes = { "heroSheetCardLabel" },
            text = string.upper(T("condemned.gear.each_hero_takes")),
            width = "auto",
            height = "auto",
            fontSize = 11,
            bold = true,
            rmargin = 18,
            halign = "left",
            valign = "center",
        },
        AllowanceStepper("gear", #CondemnedGear.GEAR),
        AllowanceWord(T("condemned.gear.allow_gear")),
        AllowanceStepper("grenades", MAX_GRENADES),
        AllowanceWord(T("condemned.gear.allow_grenades")),
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            gui.Panel{
                classes = { "heroSheetMutedIcon" },
                bgimage = "phosphor/info.png",
                width = 16,
                height = 16,
                valign = "center",
                linger = gui.Tooltip(T("condemned.gear.book_tip")),
            },
            reset,
        },
    }

    local hint = gui.Label{
        classes = { "heroSheetCardSub" },
        text = T("condemned.gear.own_list_hint"),
        width = "100%",
        height = "auto",
        fontSize = 14,
        bmargin = 10,
    }

    local header = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        hpad = ROW_HPAD,
        borderBox = true,
        Column(T("condemned.gear.col_hero"), COL_HERO + GEAR_ART_SLOT),
        Column(T("condemned.gear.col_gear"), COL_GEAR - GEAR_ART_SLOT),
        Column(T("condemned.gear.col_grenades"), COL_GRENADES),
    }

    --- @type {charid: string, paint: fun(hero: CondemnedGearHero)}[]
    local rows = {}
    local rowsKey = nil
    local rowHolder = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
    }
    local rowScroll = gui.Panel{
        width = "100%",
        height = ROWS_HEIGHT,
        vscroll = true,
        tmargin = 6,
        rowHolder,
    }

    --One hero's row: built once, painted from their choices (or what they were given).
    --- @param hero CondemnedGearHero
    local function BuildRow(hero)
        local name = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardStrong" },
            text = hero.name,
            width = "100%",
            height = "auto",
            fontSize = 15,
            bold = true,
        }
        local sub = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardSub" },
            text = "",
            width = "100%",
            height = "auto",
            fontSize = 12,
        }
        local gearArt = gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "white",
            width = GEAR_ART,
            height = GEAR_ART,
            rmargin = GEAR_ART_GAP,
            halign = "left",
            valign = "center",
        }
        local gearText = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardText" },
            text = "",
            width = COL_GEAR - GEAR_ART_SLOT,
            height = "auto",
            fontSize = 14,
            halign = "left",
            valign = "center",
        }
        local grenadeText = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardText" },
            text = "",
            width = COL_GRENADES,
            height = "auto",
            fontSize = 14,
            rmargin = COL_GAP,
            halign = "left",
            valign = "center",
        }
        local pill = gui.Label{
            classes = { "heroSheetPill" },
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            cornerRadius = 9,
            text = "",
            width = "auto",
            height = 22,
            hpad = 9,
            borderBox = true,
            fontSize = 12,
            bold = true,
            --clear of the table's scroll bar.
            rmargin = 12,
            halign = "right",
            valign = "center",
        }
        local panel = gui.Panel{
            classes = { "heroSheetListRow", "hoverable" },
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "100%",
            height = 56,
            flow = "horizontal",
            hpad = ROW_HPAD,
            borderBox = true,
            bmargin = 6,
            click = function()
                CondemnedGear.ChooseFor(hero.charid)
            end,
            --every cell starts at its column's left edge, whatever is in the others.
            gui.Panel{
                flow = "vertical",
                width = COL_HERO,
                height = "auto",
                rmargin = COL_GAP,
                halign = "left",
                valign = "center",
                interactable = false,
                name,
                sub,
            },
            gui.Panel{
                flow = "horizontal",
                width = COL_GEAR,
                height = "auto",
                rmargin = COL_GAP,
                halign = "left",
                valign = "center",
                interactable = false,
                gearArt,
                gearText,
            },
            grenadeText,
            gui.Panel{
                width = COL_STATUS,
                height = "auto",
                halign = "left",
                valign = "center",
                interactable = false,
                pill,
            },
        }
        rowHolder:AddChild(panel)
        rows[#rows + 1] = {
            charid = hero.charid,
            paint = function(current)
                local choices = ShownChoices(current)
                name.text = current.name
                sub.text = HeroSubline(current.token)
                --the gear: its art and name, or "No gear".
                local names = {}
                for _, itemid in ipairs(choices.gear) do
                    local item = gearTable[itemid]
                    if item ~= nil then
                        names[#names + 1] = item.name
                    end
                end
                local first = gearTable[choices.gear[1] or ""]
                --an empty slot keeps its room, so "No gear" starts where a gear name does.
                gearArt.selfStyle.opacity = first ~= nil and 1 or 0
                if first ~= nil then
                    gearArt.bgimage = first.iconid
                end
                gearText.text = #names > 0 and table.concat(names, ", ") or T("condemned.gear.no_gear")
                gearText:SetClass("heroSheetCardSub", #names == 0)
                gearText.selfStyle.italics = #names == 0
                --the grenades by short name: "3 Blackpowder, 1 Stun", or "No grenades".
                local parts = {}
                for _, itemid in ipairs(CondemnedGear.GRENADES) do
                    local count = choices.grenades[itemid] or 0
                    local item = gearTable[itemid]
                    if count > 0 and item ~= nil then
                        local short = string.gsub(item.name, "%s+[Gg]renade$", "")
                        parts[#parts + 1] = string.format("%d %s", count, short)
                    end
                end
                grenadeText.text = #parts > 0 and table.concat(parts, ", ") or T("condemned.gear.no_grenades")
                grenadeText:SetClass("heroSheetCardSub", #parts == 0)
                grenadeText.selfStyle.italics = #parts == 0
                local status = STATUS_PILL[CondemnedGear.Status(current)] or STATUS_PILL.nothing
                pill.text = T(status.id)
                for _, entry in pairs(STATUS_PILL) do
                    pill:SetClass(entry.class, entry.class == status.class)
                end
                pill:SetClass("cgOverPill", status == STATUS_PILL.over)
            end,
        }
    end

    --Hand out, with its confirm when not everyone is done.
    local confirmLines = gui.Label{
        classes = { "heroSheetCardText" },
        text = "",
        width = "100%",
        height = "auto",
        fontSize = 14,
        textWrap = true,
        valign = "top",
        vmargin = 4,
    }
    local fixNote = gui.Label{
        classes = { "heroSheetWarning" },
        text = T("condemned.gear.fix_over_first"),
        width = "auto",
        height = "auto",
        fontSize = 13,
        lmargin = 12,
        halign = "left",
        valign = "center",
    }
    local showConfirm = false
    local function Finish(ok, count)
        if ok then
            HeroSheetWindow.Toast(UIText.Plural("condemned.gear.handed_out_to", count))
        else
            HeroSheetWindow.Toast(T("condemned.gear.refused"))
            audio.FireSoundEvent("UI.Error_Generic")
        end
        repaint()
    end
    local function StartHandOut()
        showConfirm = false
        local _, why = CondemnedGear.HandOut(Finish)
        if why == "nothing" then
            HeroSheetWindow.Toast(T("condemned.gear.nothing_to_hand_out"))
        end
        repaint()
    end
    --HandOut refuses while someone is Over limit; the button is dimmed then too.
    local anyway = HeroSheetTheme.WindowButton(T("condemned.gear.hand_out_anyway"), StartHandOut, true)
    anyway.selfStyle.lmargin = 0
    anyway.selfStyle.halign = "left"
    SetGold(anyway, true)
    local keepOpen = HeroSheetTheme.WindowButton(T("condemned.gear.keep_open"), function()
        showConfirm = false
        repaint()
    end, false)
    keepOpen.selfStyle.halign = "left"
    local confirm = gui.Panel{
        classes = { "heroSheetListRow", "cgOverPill" },
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        tmargin = 8,
        gui.Label{
            classes = { "heroSheetCardStrong" },
            text = T("condemned.gear.not_done"),
            width = "auto",
            height = "auto",
            fontSize = 14,
            bold = true,
            halign = "left",
        },
        --a fixed height that scrolls, so a long list never pushes Hand out off the window.
        gui.Panel{
            width = "100%",
            height = 104,
            vscroll = true,
            confirmLines,
        },
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 6,
            anyway,
            keepOpen,
            fixNote,
        },
    }

    local tally = gui.Label{
        classes = { "heroSheetCardText" },
        text = "",
        width = "auto",
        height = "auto",
        fontSize = 14,
        halign = "left",
        valign = "center",
    }
    local handOut = HeroSheetTheme.WindowButton(T("condemned.gear.hand_out"), function()
        local given, total = CondemnedGear.HandedOutCount()
        if not director or CondemnedGear.IsHandingOut() or (total > 0 and given == total) then
            return
        end
        for _, hero in ipairs(CondemnedGear.Heroes()) do
            local status = CondemnedGear.Status(hero)
            if status ~= "done" and status ~= "given" then
                showConfirm = true
                repaint()
                return
            end
        end
        StartHandOut()
    end, true)
    handOut.selfStyle.halign = "right"
    SetGold(handOut, true)
    local footer = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = 44,
        tmargin = 10,
        tally,
        handOut,
    }

    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",
        hpad = PARTY_HPAD,
        vpad = 14,
        borderBox = true,
        paint = function(element)
            if g_charid ~= nil then
                element:SetClass("collapsed", true)
                return
            end
            --the Director lists every hero; a player, their own.
            local listed = director and CondemnedGear.Heroes() or CondemnedGear.MyHeroes()
            --a player with no hero of their own sees the window's "Director chooses" line instead.
            element:SetClass("collapsed", not director and #listed == 0)
            --rows follow the list of heroes; built again only when that changes.
            local ids = {}
            for _, hero in ipairs(listed) do
                ids[#ids + 1] = hero.charid
            end
            local key = table.concat(ids, ",")
            if key ~= rowsKey then
                rowsKey = key
                rowHolder.children = {}
                rows = {}
                for _, hero in ipairs(listed) do
                    BuildRow(hero)
                end
            end
            for i, hero in ipairs(listed) do
                rows[i].paint(hero)
            end

            allowRow:SetClass("collapsed", not director)
            hint:SetClass("collapsed", director)
            footer:SetClass("collapsed", not director)
            local allow = CondemnedGear.Allowance()
            --Hand out hides once every hero has their gear; until then it stays for a later round.
            local givenCount, heroCount = CondemnedGear.HandedOutCount()
            local handedOut = heroCount > 0 and givenCount == heroCount
            reset:SetClass("collapsed", givenCount > 0 or (allow.gear == book.gear and allow.grenades == book.grenades))
            element:FireEventTree("refreshNumber")

            --the footer: how many are done, or who got their gear.
            local done, given, over = 0, 0, false
            local lines = {}
            for _, hero in ipairs(listed) do
                local status = CondemnedGear.Status(hero)
                if status == "done" then
                    done = done + 1
                elseif status == "given" then
                    given = given + 1
                else
                    over = over or status == "over"
                    local id = status == "over" and "condemned.gear.not_done_over"
                        or status == "nothing" and "condemned.gear.not_done_nothing"
                        or "condemned.gear.not_done_choosing"
                    lines[#lines + 1] = T(id, { name = hero.name })
                end
            end
            if handedOut then
                tally.text = UIText.Plural("condemned.gear.handed_out_to", given)
            else
                tally.text = T("condemned.gear.tally", { done = done, total = #listed - given })
            end
            handOut:SetClass("collapsed", handedOut)
            local waiting = CondemnedGear.IsHandingOut()
            handOut.data.tip = waiting and T("condemned.gear.waiting") or T("condemned.gear.hand_out_tip")
            Dim(handOut, waiting)

            --the confirm, while it is up and someone is not done.
            local confirming = showConfirm and #lines > 0 and not handedOut and not waiting
            confirm:SetClass("collapsed", not confirming)
            confirmLines.text = table.concat(lines, "\n")
            fixNote:SetClass("collapsed", not over)
            Dim(anyway, over)
            --the table gives the confirm its room.
            rowScroll.selfStyle.height = confirming and ROWS_HEIGHT_CONFIRMING or ROWS_HEIGHT
        end,
        allowRow,
        hint,
        header,
        gui.Panel{
            classes = { "heroSheetDialogRule" },
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            tmargin = 6,
        },
        rowScroll,
        confirm,
        footer,
    }
end

--- True while this user's window is up.
--- @return boolean
function CondemnedGear.IsWindowShowing()
    return g_frame ~= nil and g_frame.valid
end

--- Close this user's window.
function CondemnedGear.CloseWindow()
    HeroSheetWindow.ClosePopup(g_frame)
    g_frame = nil
end

--Builds the window's content once. Paint (the root's "paint" event) sets what changes.
--- @return Panel
local function BuildWindow()
    local title = gui.Label{
        classes = { "heroSheetCardStrong" },
        text = string.upper(T("condemned.gear.title")),
        width = "auto",
        height = "auto",
        fontSize = 18,
        bold = true,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    local who = HeroSheetTheme.EllipsisLabel{
        classes = { "heroSheetCardLabel" },
        text = "",
        width = 360,
        height = "auto",
        fontSize = 14,
        bold = true,
        lmargin = 12,
        halign = "left",
        valign = "center",
    }
    local back = HeroSheetTheme.WindowButton(T("condemned.gear.return_to_party"), function()
        g_charid = nil
        if g_frame ~= nil and g_frame.valid then
            g_frame:FireEventTree("paint")
        end
    end, false)
    back.selfStyle.halign = "left"
    back.selfStyle.lmargin = 0
    back.selfStyle.rmargin = 12

    --the band's art fades in from the window's colour on its left, so it has no hard edge.
    local fade = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "100%",
        height = "100%",
        interactable = false,
    }
    local function PaintFade()
        local plate = HeroSheetTheme.ParseHex(HeroSheetTheme.Palette().plate) or { r = 0, g = 0, b = 0, a = 1 }
        fade.selfStyle.gradient = gui.Gradient{
            point_a = { x = 0, y = 0 },
            point_b = { x = 1, y = 0 },
            --the engine blends in linear light, so the stops are stronger than they look.
            stops = {
                { position = 0, color = HeroSheetTheme.ToHex(plate, 1) },
                { position = 0.3, color = HeroSheetTheme.ToHex(plate, 0.94) },
                { position = 0.6, color = HeroSheetTheme.ToHex(plate, 0.78) },
                { position = 1, color = HeroSheetTheme.ToHex(plate, 0.5) },
            },
        }
    end
    PaintFade()
    --The app's standard close control, as map windows and the Hero sheet draw it; its
    --colours come from the caption rules, read again on a scheme change.
    local CLOSE_WIDTH = 36
    local close = gui.Panel{
        styles = Tabletop.CaptionStyles(),
        width = CLOSE_WIDTH,
        height = "100%",
        halign = "right",
        create = function(element)
            HeroSheetTheme.Track(element, function(panel)
                panel.styles = Tabletop.CaptionStyles()
            end)
        end,
        Tabletop.WindowControl{
            icon = "window-chrome/chrome-close.png",
            danger = true,
            hover = gui.Tooltip(T("condemned.gear.close")),
            click = function()
                CondemnedGear.CloseWindow()
            end,
        },
    }
    local band = gui.Panel{
        width = "100%",
        height = BAND_HEIGHT,
        flow = "horizontal",
        paint = PaintFade,
        --the art ends just left of the close control.
        gui.Panel{
            bgimage = BAND_ART,
            bgcolor = "white",
            imageRect = BAND_ART_RECT,
            width = 210,
            height = BAND_HEIGHT,
            halign = "right",
            rmargin = CLOSE_WIDTH,
            floating = true,
            interactable = false,
            fade,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            lmargin = 18,
            halign = "left",
            valign = "center",
            back,
            title,
            who,
        },
        close,
    }

    --A player with no hero of their own: the Director chooses for them.
    local nobody = gui.Label{
        classes = { "heroSheetCardSub" },
        text = T("condemned.gear.director_chooses"),
        width = "auto",
        height = "auto",
        fontSize = 16,
        halign = "center",
        valign = "center",
    }
    local content
    local function Repaint()
        if content ~= nil and content.valid then
            content:FireEventTree("paint")
        end
    end

    --Done: the hero's choices are finished. A player's window closes (the floating tab
    --brings it back); the Director, or a player with several heroes, goes back to the list.
    local done = HeroSheetTheme.WindowButton(T("condemned.gear.done"), function()
        local hero = g_charid ~= nil and FindHero(g_charid) or nil
        if hero == nil or not CanChooseFor(hero) or CondemnedGear.Status(hero) == "over" then
            return
        end
        CondemnedGear.SetDone(hero.charid)
        if dmhub.isDM or #CondemnedGear.MyHeroes() > 1 then
            g_charid = nil
            Repaint()
        else
            CondemnedGear.CloseWindow()
        end
    end, true)
    done.selfStyle.halign = "right"
    SetGold(done, true)

    --The picker: the list and the item's pane side by side, over the Done footer.
    local picker = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",
        hpad = BODY_HPAD,
        vpad = BODY_VPAD,
        borderBox = true,
        paint = function(element)
            local hero = g_charid ~= nil and FindHero(g_charid) or nil
            element:SetClass("collapsed", hero == nil)
            if hero == nil then
                return
            end
            local status = CondemnedGear.Status(hero)
            done:SetClass("collapsed", status == "given" or not CanChooseFor(hero))
            local over = status == "over"
            done.data.tip = over and T("condemned.gear.over_limit_tip") or (not dmhub.isDM and T("condemned.gear.done_tip") or nil)
            Dim(done, over)
        end,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = BODY_HEIGHT - 2 * BODY_VPAD - DONE_FOOT,
            BuildList(Repaint),
            --the line between the list and the pane, in the gap's middle.
            gui.Panel{
                classes = { "heroSheetDialogRule" },
                bgimage = "panels/square.png",
                width = 1,
                height = "100%",
                lmargin = math.floor(COLUMN_GAP / 2) - 1,
                opacity = 0.6,
            },
            BuildPane(Repaint),
        },
        gui.Panel{
            classes = { "heroSheetDialogRule" },
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            opacity = 0.6,
        },
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = DONE_FOOT - 1,
            done,
        },
    }

    local body = gui.Panel{
        width = "100%",
        height = BODY_HEIGHT,
        flow = "vertical",
        nobody,
        BuildParty(Repaint),
        picker,
    }

    content = gui.Panel{
        classes = { "cgWindow" },
        bgimage = "panels/square.png",
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        flow = "vertical",
        data = { wasOpen = CondemnedGear.IsOpen() },
        monitorGame = CondemnedGear.DocPath(),
        refreshGame = function(element)
            --Closed for the table (Hand out or Close for everyone): close this copy too.
            local open = CondemnedGear.IsOpen()
            if element.data.wasOpen and not open then
                CondemnedGear.CloseWindow()
                return
            end
            element.data.wasOpen = open
            element:FireEventTree("paint")
        end,
        multimonitor = { "fontsize", "iconrail" },
        monitor = function(element)
            local useRows = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < ROWS_BELOW
            if useRows ~= g_useRows then
                g_useRows = useRows
                element:FireEventTree("paint")
            end
        end,
        paint = function(element)
            local hero = g_charid ~= nil and FindHero(g_charid) or nil
            if hero == nil then
                g_charid = nil
            end
            --the party table is the way back, for whoever has one.
            local hasParty = dmhub.isDM or #CondemnedGear.MyHeroes() > 1
            back:SetClass("collapsed", hero == nil or not hasParty)
            if hero == nil then
                who.text = ""
            elseif hasParty then
                who.text = T("condemned.gear.choosing_for", { name = hero.name })
            else
                who.text = hero.name
            end
            nobody:SetClass("collapsed", dmhub.isDM or #CondemnedGear.MyHeroes() > 0)
        end,
        band,
        gui.Panel{
            classes = { "heroSheetDialogRule" },
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
        },
        body,
    }
    content.styles = GearStyles()
    HeroSheetTheme.Track(content, function(panel)
        panel.styles = GearStyles()
        --the band's fade is painted in the scheme's colour too.
        panel:FireEventTree("paint")
    end)
    return content
end

--- Show the picker for one hero in this user's window (the party table's rows call it).
--- @param charid string
function CondemnedGear.ChooseFor(charid)
    g_charid = charid
    if g_frame ~= nil and g_frame.valid then
        g_frame:FireEventTree("paint")
    end
end

--- Show this user's window (already showing: bring it to the front).
function CondemnedGear.ShowWindow()
    if g_frame ~= nil and g_frame.valid then
        g_frame:SetAsLastSibling()
        return
    end
    g_charid = StartingHero()
    g_useRows = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < ROWS_BELOW
    local content = BuildWindow()
    local frame
    frame = HeroSheetWindow.ShowPopup{
        content = content,
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        modal = true,
        onClose = function()
            --a window closed just before a new one opened must not forget the new one.
            if g_frame == frame then
                g_frame = nil
            end
        end,
    }
    g_frame = frame
    content:FireEventTree("paint")
end

--- Director only: open the window for the table and put it on every screen.
function CondemnedGear.OpenForAll()
    if not dmhub.isDM then
        return
    end
    CondemnedGear.SetOpen(true)
    --every map: a player can be looking at another one.
    dmhub.BroadcastRemoteEvent(OPEN_EVENT, dmhub.GenerateGuid(), {}, true, true)
    CondemnedGear.ShowWindow()
    HeroSheetWindow.Toast(T("condemned.gear.opened_for_all"))
end

dmhub.RegisterRemoteEvent(OPEN_EVENT, function(info)
    if mod.unloaded or dmhub.isDM then
        return
    end
    CondemnedGear.ShowWindow()
end)

--The players' way back: a small "Experimental Gear [Open]" tab, bottom left of the screen,
--while the window is open for the table but closed on this screen. It sits above the
--action bar's strip (about 58 high) so a wide bar on a narrow screen never covers it.
local TAB_BOTTOM = 76
local g_tab = nil
--the last reason KeepTab logged for not building the tab yet (logged once per change).
--- @type nil|string
local g_tabWait = nil

--- @return boolean
local function TabWanted()
    if dmhub.isDM or not CondemnedGear.IsOpen() or CondemnedGear.IsWindowShowing() then
        return false
    end
    return #CondemnedGear.MyHeroes() > 0
end

--- @return Panel
local function CreateTab()
    local open = HeroSheetTheme.WindowButton(T("condemned.gear.reopen_button"), function()
        CondemnedGear.ShowWindow()
    end, false)
    SetGold(open, true)
    local box = gui.Panel{
        classes = { "cgWindow", "cgTab", "collapsed" },
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        flow = "horizontal",
        width = "auto",
        height = "auto",
        lpad = 14,
        rpad = 6,
        vpad = 6,
        borderBox = true,
        gui.Label{
            classes = { "heroSheetCardStrong" },
            text = T("condemned.gear.reopen_label"),
            width = "auto",
            height = "auto",
            fontSize = 14,
            valign = "center",
        },
        open,
    }
    box.styles = GearStyles()
    --Polled, because closing the window on this screen doesn't change the document. The
    --wrapper never collapses, as a collapsed panel stops thinking; only the box hides.
    local shown = nil
    local tab = gui.Panel{
        styles = HeroSheetTheme.RootStyles(),
        floating = true,
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "bottom",
        lmargin = 16,
        bmargin = TAB_BOTTOM,
        thinkTime = 0.25,
        think = function(element)
            local want = TabWanted()
            if want ~= shown then
                shown = want
                box:SetClass("collapsed", not want)
                print(string.format("CONDEMNED GEAR:: tab %s (dm=%s open=%s window=%s heroes=%d)", want and "shown" or "hidden",
                    tostring(dmhub.isDM), tostring(CondemnedGear.IsOpen()), tostring(CondemnedGear.IsWindowShowing()), #CondemnedGear.MyHeroes()))
            end
        end,
        box,
    }
    HeroSheetTheme.Track(tab, function(panel)
        panel.styles = HeroSheetTheme.RootStyles()
        box.styles = GearStyles()
    end)
    return tab
end

--The HUD is built after this file loads and is rebuilt with the game, so keep checking.
local function KeepTab()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(2, KeepTab)
    if g_tab ~= nil and g_tab.valid then
        return
    end
    --During a game load the old HUD's layer can still be referenced after it's torn down,
    --and GameHud.instance can be false. Wait for a valid layer.
    local hud = GameHud.instance
    local layer = hud and hud.mainDialogPanel or nil
    if not layer or not layer.valid then
        local why = string.format("hud=%s layer=%s", tostring(hud), tostring(layer ~= nil))
        if why ~= g_tabWait then
            g_tabWait = why
            print("CONDEMNED GEAR:: tab waiting: " .. why)
        end
        return
    end
    local tab = CreateTab()
    local ok, err = pcall(gui.ShowDialog, mod, tab)
    if not ok then
        print("CONDEMNED GEAR:: tab not added, trying again: " .. tostring(err))
        tab:DestroySelf()
        return
    end
    g_tab = tab
    print("CONDEMNED GEAR:: tab built")
end
dmhub.Schedule(2, KeepTab)

--A player who closed the window gets it back from the Campaign Tracker while it is open.
local function CreateReopenSection()
    local row = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        bmargin = 10,
        gui.Label{
            classes = { "bold" },
            text = T("condemned.gear.reopen_label"),
            width = "auto",
            height = "auto",
            fontSize = 14,
            valign = "center",
        },
        gui.Button{
            classes = { "sizeS" },
            text = T("condemned.gear.reopen_button"),
            width = 70,
            height = 24,
            fontSize = 12,
            lmargin = 10,
            valign = "center",
            press = function()
                CondemnedGear.ShowWindow()
            end,
        },
    }
    local function Paint()
        row:SetClass("collapsed", dmhub.isDM or not CondemnedGear.IsOpen())
    end
    Paint()
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorGame = CondemnedGear.DocPath(),
        refreshGame = Paint,
        row,
    }
end

local campaignTracker = rawget(_G, "CampaignTracker")
if campaignTracker ~= nil and campaignTracker.RegisterSection ~= nil then
    campaignTracker.RegisterSection{
        id = "condemnedGear",
        ord = -21,
        create = CreateReopenSection,
    }
end

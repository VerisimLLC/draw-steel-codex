local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- The Condemned: Experimental Gear ("Gearing Up")
--------------------------------------------------------------------------------
--Before the mission the Director opens a window for the whole table where each hero
--chooses experimental gear and grenades; the Director then hands it all out. This
--part is the state and the hand out; the window is built on top of it.
--
--Storage:
--  * The "condemnedGear" document: the allowance, whether the window is open, and each
--    hero's choices as one JSON string. Every write copies the whole document, so it
--    holds only this, and two players choosing at once write different keys.
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

--- What a hero has chosen so far.
--- @param charid string
--- @return CondemnedGearChoices
function CondemnedGear.Choices(charid)
    return DecodeChoices((Doc().data.choices or {})[charid])
end

--- Store a hero's choices (the whole set, replacing what was there); nil clears them.
--- @param charid string
--- @param choices nil|CondemnedGearChoices
function CondemnedGear.SetChoices(charid, choices)
    ChangeDoc("Choose experimental gear", function(data)
        data.choices = data.choices or {}
        data.choices[charid] = choices ~= nil and dmhub.ToRawJson(choices) or nil
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
--- the Director lowered it), "done" (exactly the allowance), "nothing" or "choosing".
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
    if gear == allow.gear and grenades == allow.grenades then
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
--inventory), and leaves the marker. Runs inside the hand out's write; a hero who already
--has the marker (a second Director, or a Firebase game, which skips the server's check)
--is left alone.
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
--- hero got in first and nothing was given. Returns false when nothing was sent: not the
--- Director, a hand out already waiting, someone Over limit, or every hero already has
--- their gear.
--- @param onDone nil|fun(ok: boolean, count: integer)
--- @return boolean
function CondemnedGear.HandOut(onDone)
    if g_handingOut or not dmhub.isDM then
        return false
    end
    --- @type {token: CharacterToken, choices: CondemnedGearChoices}[]
    local pending = {}
    for _, entry in ipairs(CondemnedGear.Heroes()) do
        local status = CondemnedGear.Status(entry)
        if status == "over" then
            return false
        end
        if status ~= "given" then
            pending[#pending + 1] = { token = entry.token, choices = CondemnedGear.Choices(entry.charid) }
        end
    end
    if #pending == 0 then
        return false
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
--A modal pop-up (HeroSheetWindow.ShowPopup: it follows Font Size and the colour
--scheme, and caps itself to the screen). The Director's Open puts it on every screen;
--anyone can close theirs and reopen it from the Campaign Tracker while it is open.
--It is built once when it opens; clicks and remote changes repaint it in place.

local OPEN_EVENT = "condemnedGearOpen"

--design size in sheet units, before Font Size zooms it.
local WINDOW_WIDTH = 1040
local WINDOW_HEIGHT = 672
local BAND_HEIGHT = 56

--Narrower than this (the screen capping a large Font Size), the gear list shows one
--row per item instead of cards: the list then has under about 38 lines of text width.
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
local g_rows = false

--the body under the band, and its two columns: the list, and the preview pane.
local BODY_HEIGHT = WINDOW_HEIGHT - BAND_HEIGHT
local BODY_HPAD = 14
local BODY_VPAD = 11
local PANE_WIDTH = 357
local COLUMN_GAP = 14
local LIST_WIDTH = WINDOW_WIDTH - 2 * BODY_HPAD - COLUMN_GAP - PANE_WIDTH
--room the list keeps for its scroll bar.
local SCROLL_GUTTER = 10
local LIST_INNER = LIST_WIDTH - SCROLL_GUTTER
local CARD_GAP = 8
local CARD_WIDTH = math.floor((LIST_INNER - 2 * CARD_GAP) / 3)
local CARD_HEIGHT = 132

--Colours the hero sheet's classes do not have: a chosen item's edge and the Over limit
--pill. Built from the scheme's palette, and built again when the scheme changes.
--- @return table[]
local function GearStyles()
    local palette = HeroSheetTheme.Palette()
    return {
        --above the hero sheet's row edges (priority 5 and under).
        { selectors = { "cgChosen" }, borderColor = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.rawSuccess, 0.7)), priority = 10 },
        --the shown item's edge wins over the chosen one.
        { selectors = { "cgChosen", "heroSheetRowPinned" }, borderColor = palette.cardStrong, priority = 11 },
        { selectors = { "cgArt" }, bgcolor = palette.tile, borderColor = palette.tileBorder },
        { selectors = { "cgOverPill" }, borderColor = palette.warning, color = palette.warning },
        { selectors = { "cgSuccessIcon" }, bgcolor = palette.cardSuccess },
    }
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
        count = function(element, n, max)
            count.text = T("condemned.gear.count", { n = n, max = max })
            count:SetClass("heroSheetCardSuccess", n == max)
            count:SetClass("heroSheetWarning", n > max)
            count:SetClass("heroSheetCardSub", n < max)
            pill:SetClass("collapsed", n <= max)
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

    --Each gear item has a card (three to a row) and a one-line form for a narrow window;
    --a layout change shows the other set, nothing is rebuilt.
    local cards = {}
    local rows = {}
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
                pad = 9,
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
                    ItemArt(item, 44),
                    gui.Panel{
                        flow = "vertical",
                        width = CARD_WIDTH - 18 - 44 - 9,
                        height = "auto",
                        lmargin = 9,
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
                    height = 34,
                    fontSize = 12,
                    italics = true,
                    textWrap = true,
                    textOverflow = "ellipsis",
                    tmargin = 6,
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
            rows[#rows + 1] = gui.Panel{
                classes = { "heroSheetListRow", "hoverable" },
                bgimage = "panels/square.png",
                border = 1,
                cornerRadius = 8,
                width = LIST_INNER,
                height = 52,
                flow = "horizontal",
                hpad = 8,
                borderBox = true,
                bmargin = 5,
                data = { itemid = itemid },
                click = function()
                    Select(itemid)
                end,
                ItemArt(item, 36),
                gui.Panel{
                    flow = "vertical",
                    width = LIST_INNER - 16 - 36 - 10 - 90,
                    height = "auto",
                    lmargin = 10,
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
        end
    end
    local cardList = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = LIST_INNER + CARD_GAP,
        height = "auto",
        tmargin = 8,
        children = cards,
    }
    local rowList = gui.Panel{
        flow = "vertical",
        width = LIST_INNER,
        height = "auto",
        tmargin = 8,
        children = rows,
    }

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
                height = 42,
                flow = "horizontal",
                hpad = 6,
                borderBox = true,
                bmargin = 5,
                data = { itemid = itemid },
                click = function()
                    Select(itemid)
                end,
                ItemArt(item, 30),
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
            cardList:SetClass("collapsed", g_rows)
            rowList:SetClass("collapsed", not g_rows)
            element:FireEventTree("refreshNumber")
        end,
        inner,
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

    local band = gui.Panel{
        classes = { "heroSheetCard" },
        bgimage = "panels/square.png",
        width = "100%",
        height = BAND_HEIGHT,
        flow = "horizontal",
        hpad = 18,
        borderBox = true,
        --art, then a fade over its left edge so the title reads against it.
        gui.Panel{
            bgimage = BAND_ART,
            bgcolor = "white",
            imageRect = BAND_ART_RECT,
            width = 200,
            height = BAND_HEIGHT,
            halign = "right",
            rmargin = 30,
            opacity = 0.75,
            floating = true,
            interactable = false,
        },
        back,
        title,
        who,
        gui.Button{
            classes = { "closeButton" },
            halign = "right",
            valign = "center",
            hover = gui.Tooltip(T("condemned.gear.close")),
            press = function()
                CondemnedGear.CloseWindow()
            end,
        },
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

    --The picker: the list, and the preview pane (chunk 4) beside it.
    local picker = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "100%",
        hpad = BODY_HPAD,
        vpad = BODY_VPAD,
        borderBox = true,
        paint = function(element)
            element:SetClass("collapsed", g_charid == nil)
        end,
        BuildList(Repaint),
        gui.Panel{
            width = PANE_WIDTH,
            height = "100%",
            lmargin = COLUMN_GAP,
        },
    }

    --The party table (chunk 5) goes here too.
    local body = gui.Panel{
        width = "100%",
        height = BODY_HEIGHT,
        flow = "vertical",
        nobody,
        picker,
    }

    content = gui.Panel{
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        flow = "vertical",
        data = { wasOpen = CondemnedGear.IsOpen() },
        monitorGame = CondemnedGear.DocPath(),
        refreshGame = function(element)
            --Hand out closed it for the table: close this copy too.
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
            local rows = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < ROWS_BELOW
            if rows ~= g_rows then
                g_rows = rows
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
        body,
    }
    content.styles = GearStyles()
    HeroSheetTheme.Track(content, function(panel)
        panel.styles = GearStyles()
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
    g_rows = HeroSheetWindow.DialogWidth(WINDOW_WIDTH) < ROWS_BELOW
    local content = BuildWindow()
    g_frame = HeroSheetWindow.ShowPopup{
        content = content,
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        modal = true,
        onClose = function()
            g_frame = nil
        end,
    }
    content:FireEventTree("paint")
end

--- Director only: open the window for the table and put it on every screen.
function CondemnedGear.OpenForAll()
    if not dmhub.isDM then
        return
    end
    CondemnedGear.SetOpen(true)
    dmhub.BroadcastRemoteEvent(OPEN_EVENT, dmhub.GenerateGuid(), {}, true)
    CondemnedGear.ShowWindow()
    HeroSheetWindow.Toast(T("condemned.gear.opened_for_all"))
end

dmhub.RegisterRemoteEvent(OPEN_EVENT, function(info)
    if mod.unloaded or dmhub.isDM then
        return
    end
    CondemnedGear.ShowWindow()
end)

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

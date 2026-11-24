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
--pill. Built from the scheme's palette and compiled once per palette (as RootStyles is).
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
            if g_rows and #rows == 0 then
                BuildRows()
            elseif not g_rows and #cards == 0 then
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
            cardList:SetClass("collapsed", g_rows)
            rowList:SetClass("collapsed", not g_rows)
            element:FireEventTree("refreshNumber")
        end,
        inner,
    }
end

--- @param itemid string
--- @return boolean
local function IsGrenade(itemid)
    for _, id in ipairs(CondemnedGear.GRENADES) do
        if id == itemid then
            return true
        end
    end
    return false
end

--Changes to a hero's choices, from the pane's button. Each reads the stored choices
--fresh, so a change made on another screen meanwhile is kept.
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
    local have = gui.Label{
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
    local buttonLabel = button.children[1]

    --- @param text string
    --- @param fn nil|fun() nil dims the button
    --- @param tip nil|string why it is dimmed
    local function SetButton(text, fn, tip)
        buttonLabel.text = text
        action = fn
        button.data.tip = tip
        local opacity = fn ~= nil and 1 or 0.45
        button.selfStyle.opacity = opacity
        buttonLabel.selfStyle.opacity = opacity
    end

    local body = gui.Panel{
        width = PANE_WIDTH,
        height = BODY_HEIGHT - 2 * BODY_VPAD - FOOT_HEIGHT,
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
        lmargin = COLUMN_GAP,
        paint = function(element)
            local hero = g_charid ~= nil and FindHero(g_charid) or nil
            local item = gearTable[g_selected]
            if hero == nil or item == nil then
                return
            end
            local token = hero.token
            local grenade = IsGrenade(g_selected)
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

            local chosen = false
            for _, itemid in ipairs(choices.gear) do
                if itemid == g_selected then
                    chosen = true
                end
            end

            --What equipping it would change. Gear only; once handed out the hero is
            --wearing it, so there is nothing left to preview.
            local key = string.format("%s|%s|%s|%d", hero.charid, g_selected, dmhub.ToJson(token.properties:Equipment()), level)
            if grenade or delivered then
                chips = {}
                chipsKey = nil
            elseif key ~= chipsKey then
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
            have.text = count > 0 and T("condemned.gear.n_chosen", { n = count }) or ""
            button:SetClass("collapsed", not delivered and not CanChooseFor(hero))
            local selected = g_selected
            if delivered then
                SetButton(T("condemned.gear.handed_out"), nil, nil)
            elseif grenade then
                if CondemnedGear.GrenadeCount(choices) >= allow.grenades then
                    SetButton(T("condemned.gear.choose_one"), nil, T("condemned.gear.grenades_full_tip", { max = allow.grenades }))
                else
                    SetButton(T("condemned.gear.choose_one"), function()
                        ChangeChoices(hero, function(c)
                            c.grenades[selected] = (c.grenades[selected] or 0) + 1
                        end)
                    end, nil)
                end
            elseif chosen then
                SetButton(T("condemned.gear.put_back"), function()
                    ChangeChoices(hero, function(c)
                        for i = #c.gear, 1, -1 do
                            if c.gear[i] == selected then
                                table.remove(c.gear, i)
                            end
                        end
                    end)
                end, nil)
            elseif #choices.gear < allow.gear then
                SetButton(T("condemned.gear.choose"), function()
                    ChangeChoices(hero, function(c)
                        c.gear[#c.gear + 1] = selected
                    end)
                end, nil)
            elseif allow.gear == 1 and #choices.gear == 1 then
                local current = gearTable[choices.gear[1]]
                SetButton(T("condemned.gear.swap"), function()
                    ChangeChoices(hero, function(c)
                        c.gear = { selected }
                    end)
                end, nil)
                button.data.tip = T("condemned.gear.swap_tip", { name = current ~= nil and current.name or "" })
            else
                SetButton(T("condemned.gear.choose"), nil, T("condemned.gear.gear_full_tip", { n = #choices.gear, max = allow.gear }))
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
                have,
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

--A grenade's short name for the party table: "Blackpowder" for "Blackpowder Grenade".
--- @param item table a tbl_Gear row
--- @return string
local function ShortGrenadeName(item)
    local short = string.gsub(item.name, "%s+[Gg]renade$", "")
    return short
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

    --The heroes this table lists.
    local function Listed()
        if director then
            return CondemnedGear.Heroes()
        end
        return CondemnedGear.MyHeroes()
    end

    --- @param text string
    --- @param width number
    local function Column(text, width)
        return gui.Label{
            classes = { "heroSheetCardLabel" },
            text = string.upper(text),
            width = width,
            height = "auto",
            fontSize = 11,
            bold = true,
            rmargin = COL_GAP,
            halign = "left",
        }
    end

    --The allowance: how much each hero may take (Director only, until Hand out).
    local function CanSetAllowance()
        return director and not CondemnedGear.AnyHandedOut()
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
        AllowanceStepper("gear", 6),
        AllowanceWord(T("condemned.gear.allow_gear")),
        AllowanceStepper("grenades", 9),
        AllowanceWord(T("condemned.gear.allow_grenades")),
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            gui.Label{
                classes = { "heroSheetCardSub" },
                text = T("condemned.gear.book"),
                width = "auto",
                height = "auto",
                fontSize = 13,
                valign = "center",
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
        Column(T("condemned.gear.col_hero"), COL_HERO),
        Column(T("condemned.gear.col_gear"), COL_GEAR),
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
        height = 340,
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
            width = 26,
            height = 26,
            rmargin = 8,
            valign = "center",
        }
        local gearText = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardText" },
            text = "",
            width = COL_GEAR - 34,
            height = "auto",
            fontSize = 14,
            valign = "center",
        }
        local grenadeText = HeroSheetTheme.EllipsisLabel{
            classes = { "heroSheetCardText" },
            text = "",
            width = COL_GRENADES,
            height = "auto",
            fontSize = 14,
            rmargin = COL_GAP,
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
            gui.Panel{
                flow = "vertical",
                width = COL_HERO,
                height = "auto",
                rmargin = COL_GAP,
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
                valign = "center",
                interactable = false,
                gearArt,
                gearText,
            },
            grenadeText,
            gui.Panel{
                width = COL_STATUS,
                height = "auto",
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
                gearArt:SetClass("collapsed", first == nil)
                if first ~= nil then
                    gearArt.bgimage = first.iconid
                end
                gearText.text = #names > 0 and table.concat(names, ", ") or T("condemned.gear.no_gear")
                gearText:SetClass("heroSheetCardSub", #names == 0)
                gearText.selfStyle.italics = #names == 0
                --the grenades: "3 Blackpowder, 1 Stun", or "No grenades".
                local parts = {}
                for _, itemid in ipairs(CondemnedGear.GRENADES) do
                    local count = choices.grenades[itemid] or 0
                    local item = gearTable[itemid]
                    if count > 0 and item ~= nil then
                        parts[#parts + 1] = string.format("%d %s", count, ShortGrenadeName(item))
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
    local function HandOut()
        showConfirm = false
        CondemnedGear.HandOut(Finish)
        repaint()
    end
    local anyway = HeroSheetTheme.WindowButton(T("condemned.gear.hand_out_anyway"), function()
        local over = false
        for _, hero in ipairs(CondemnedGear.Heroes()) do
            if CondemnedGear.Status(hero) == "over" then
                over = true
            end
        end
        if not over then
            HandOut()
        end
    end, true)
    anyway.selfStyle.lmargin = 0
    anyway.selfStyle.halign = "left"
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
        if not director or CondemnedGear.IsHandingOut() or CondemnedGear.AnyHandedOut() then
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
        HandOut()
    end, true)
    handOut.selfStyle.halign = "right"
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
            local listed = Listed()
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
            local handedOut = CondemnedGear.AnyHandedOut()
            reset:SetClass("collapsed", handedOut or (allow.gear == book.gear and allow.grenades == book.grenades))
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
                tally.text = T("condemned.gear.tally", { done = done, total = #listed })
            end
            handOut:SetClass("collapsed", handedOut)
            local waiting = CondemnedGear.IsHandingOut()
            handOut.data.tip = waiting and T("condemned.gear.waiting") or T("condemned.gear.hand_out_tip")
            handOut.selfStyle.opacity = waiting and 0.45 or 1
            handOut.children[1].selfStyle.opacity = waiting and 0.45 or 1

            --the confirm, while it is up and someone is not done.
            local confirming = showConfirm and #lines > 0 and not handedOut and not waiting
            confirm:SetClass("collapsed", not confirming)
            confirmLines.text = table.concat(lines, "\n")
            fixNote:SetClass("collapsed", not over)
            --opacity is not passed on to children: dim the label too.
            anyway.selfStyle.opacity = over and 0.45 or 1
            anyway.children[1].selfStyle.opacity = over and 0.45 or 1
            --the table gives the confirm its room.
            rowScroll.selfStyle.height = confirming and 190 or 380
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
        BuildPane(Repaint),
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

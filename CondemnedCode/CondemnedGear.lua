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

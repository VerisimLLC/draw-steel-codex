local mod = dmhub.GetModLoading()

--Encounter of the Week: the Arcane Market, where Blackbottom's heroes buy
--consumable treasures between encounters. Design:
--EncounterOfTheWeek/EncounterOfTheWeek.md, "The Arcane Market".
--
--  * A hero shops by making a Presence test (Alchemy or Magic may apply):
--    tier 1 finds 2 treasures on offer, tier 2 finds 3, tier 3 finds 4, and a
--    natural 19-20 finds 4 and lets the hero buy one more than usual.
--  * A hero may buy as many of the offered treasures as their Wealth (each
--    one once). Treasures cost nothing else.
--  * One roll and one round of buying per hero until that hero comes home
--    from another Town Gate encounter. Proving Pits games do not count.
--  * The stock: every echelon 1 consumable whose automation is Gold, plus
--    the extras below, read live from the compendium.
--
--Where it is kept: on the hero's own record, properties.eotwMarket, pushed to
--the City like any other edit, so the item and the purchase that paid for it
--land in one write. A market visit belongs to the hero's current "epoch", the
--number of encounters they have brought home (properties.eotwOutcomes, which
--EotwRoster.ApplyOutcome stamps once per Town Gate game), so coming home from
--an encounter opens a fresh visit without anything having to clear it.

EotwMarket = {}

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"
local GREEN = "#9fd38a"

--The test: Presence, with these skills (+2 when the hero has one).
EotwMarket.CHARACTERISTIC = "prs"
EotwMarket.SKILLS = { "Alchemy", "Magic" }

--Draw Steel's test tiers: 11 or lower, 12-16, 17 or higher; a natural 19-20
--is a critical.
local TIER2_TOTAL = 12
local TIER3_TOTAL = 17
EotwMarket.CRITICAL_NATURAL = 19

--How many treasures each tier finds on offer.
EotwMarket.OFFER_BY_TIER = { 2, 3, 4 }

--Treasures stocked although their automation is below Gold. Imp's Tongue is
--Silver only because the engine cannot run a real-time hour; in Encounter of
--the Week an "until the hour ends" effect lasts the whole encounter, so it
--works as written there.
EotwMarket.EXTRA_STOCK = {
    ["b4ff06aa-75ae-4ed5-86e5-e6e22a29e09e"] = true, --Imp's Tongue
}

--Bumped whenever a hero's market changes; UIs poll it.
EotwMarket.revision = 0

--Dev (/eotwmarket critical): the next market roll counts as a natural 20.
EotwMarket.forceCritical = false

local function Bump()
    EotwMarket.revision = EotwMarket.revision + 1
end

--- the stock -----------------------------------------------------------------

--Is this compendium item one the market sells?
---@param itemid string
---@param item equipment
---@return boolean
local function Stocked(itemid, item)
    if not EquipmentCategory.IsConsumable(item) then
        return false
    end
    if item:try_get("hiddenFromPlayers", false) == true then
        return false
    end
    if EotwMarket.EXTRA_STOCK[itemid] then
        return true
    end
    if (tonumber(item:try_get("echelon", 1)) or 1) ~= 1 then
        return false
    end
    if (tonumber(item:try_get("implementation", 1)) or 1) < gui.ImplementationStatus.Gold then
        return false
    end
    --a book treasure says what crafting it takes; the fishing meals (also
    --Gold echelon 1 consumables) are rewards, not treasures, and say nothing.
    local prerequisite = item:try_get("itemPrerequisite", "")
    return type(prerequisite) == "string" and prerequisite ~= ""
end

--Everything the market can offer: { {itemid, item}, ... } by name.
---@return {itemid: string, item: equipment}[]
function EotwMarket.Stock()
    local result = {}
    local gear = dmhub.GetTable("tbl_Gear") or {}
    for itemid, item in unhidden_pairs(gear) do
        if Stocked(itemid, item) then
            result[#result+1] = { itemid = itemid, item = item }
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.item.name) < tostring(b.item.name)
    end)
    return result
end

--- a hero's visit ------------------------------------------------------------

--How many encounters this hero has brought home: a new one opens the market
--to them again.
---@param tok CharacterToken
---@return integer
function EotwMarket.Epoch(tok)
    local count = 0
    pcall(function()
        local applied = rawget(tok.properties, "eotwOutcomes")
        if type(applied) == "table" then
            for k, v in pairs(applied) do
                if type(k) == "string" and v == true then
                    count = count + 1
                end
            end
        end
    end)
    return count
end

--The hero's market visit since their last encounter, or nil if they have
--not shopped since: {epoch, rollid, natural, total, tier, critical, skill,
--offer = {itemid = place} (read it with EotwMarket.Offer), bought = {itemid = true}}.
---@param tok CharacterToken
---@return table|nil
function EotwMarket.Visit(tok)
    local visit = nil
    pcall(function()
        local stored = rawget(tok.properties, "eotwMarket")
        if type(stored) == "table" and stored.epoch == EotwMarket.Epoch(tok) then
            visit = stored
        end
    end)
    return visit
end

--The hero's Wealth score (0 if it cannot be read).
---@param tok CharacterToken
---@return integer
function EotwMarket.Wealth(tok)
    local wealth = 0
    pcall(function() wealth = tok.properties:CalculateNamedCustomAttribute("Wealth") or 0 end)
    return math.max(0, math.floor(tonumber(wealth) or 0))
end

--How many treasures this hero may buy on this visit: their Wealth, one more
--after a critical.
---@param tok CharacterToken
---@param visit table
---@return integer
function EotwMarket.PurchaseLimit(tok, visit)
    return EotwMarket.Wealth(tok) + cond(visit.critical == true, 1, 0)
end

--How many treasures this hero has bought on this visit.
---@param visit table
---@return integer
function EotwMarket.BoughtCount(visit)
    local n = 0
    for _, v in pairs(type(visit.bought) == "table" and visit.bought or {}) do
        if v == true then
            n = n + 1
        end
    end
    return n
end

--The market's skills this hero has, by name.
---@param tok CharacterToken
---@return string[]
function EotwMarket.TrainedSkills(tok)
    local trained = {}
    pcall(function()
        for _, skill in ipairs(Skill.SkillsInfo) do
            for _, name in ipairs(EotwMarket.SKILLS) do
                if skill.name == name and tok.properties:ProficientInSkill(skill) then
                    trained[#trained+1] = name
                end
            end
        end
    end)
    return trained
end

--The roll's bonus and its formula as text: 2d10 + Presence (+2 for a skill).
---@param tok CharacterToken
---@param skill string|nil
---@return integer bonus
---@return string formula
function EotwMarket.RollBonus(tok, skill)
    local value = 0
    pcall(function() value = tok.properties:GetAttribute(EotwMarket.CHARACTERISTIC):Modifier() end)
    local info = creature.attributesInfo[EotwMarket.CHARACTERISTIC]
    local parts = { "2d10", string.format("%+d %s", value, info ~= nil and info.description or "Presence") }
    local bonus = value
    if skill ~= nil and skill ~= "" then
        bonus = bonus + 2
        parts[#parts+1] = string.format("+2 %s", skill)
    end
    return bonus, table.concat(parts, " ")
end

--The tier (1-3) of a total.
---@param total integer
---@param natural integer
---@return integer
local function Tier(total, natural)
    if natural >= EotwMarket.CRITICAL_NATURAL or total >= TIER3_TOTAL then
        return 3
    elseif total >= TIER2_TOTAL then
        return 2
    end
    return 1
end

--Why this hero cannot shop right now, or nil if they can.
---@param heroid string
---@return string|nil
function EotwMarket.Blocked(heroid)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil or not EotwRoster.IsInStep(heroid) then
        return "Loading..."
    end
    local away = EotwRoster.AwayHeroes()[heroid]
    if away ~= nil then
        return string.format("Away: %s", away)
    end
    return nil
end

--Write the hero's visit (a fresh table, so the change is seen and saved) and
--push the hero. onDone(ok, message).
---@param heroid string
---@param description string
---@param visit table the visit as it stands; execute changes a copy of it
---@param execute fun(props: creature, visit: table)
---@param onDone nil|fun(ok: boolean, message: string|nil)
local function ChangeVisit(heroid, description, visit, execute, onDone)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil then
        if onDone ~= nil then
            onDone(false, "That hero is not ready yet.")
        end
        return
    end
    tok:ModifyProperties{
        description = description,
        undoable = false,
        execute = function()
            local props = tok.properties
            local copy = {}
            for k, v in pairs(visit) do
                copy[k] = v
            end
            execute(props, copy)
            props.eotwMarket = copy
        end,
    }
    Bump()
    --let the property write land before the export, as EotwRoster does.
    dmhub.Schedule(0.3, function()
        if mod.unloaded then
            return
        end
        EotwRoster.PushHero(heroid, function(ok, message)
            Bump()
            if onDone ~= nil then
                onDone(ok, message)
            end
        end)
    end)
end

--Choose `count` different treasures from the stock at random, as itemid ->
--its place on the stall. A map, not a list: the City stores lists as
--numeric-keyed objects, which need not come back as a Lua sequence.
---@param count integer
---@return table<string, integer>
local function PickOffer(count)
    local pool = EotwMarket.Stock()
    local offer = {}
    local n = 0
    while n < count and #pool > 0 do
        local i = math.random(1, #pool)
        n = n + 1
        offer[pool[i].itemid] = n
        table.remove(pool, i)
    end
    return offer
end

--The treasures on offer on a visit, in their stall order.
---@param visit table
---@return string[]
function EotwMarket.Offer(visit)
    local entries = {}
    for itemid, place in pairs(type(visit.offer) == "table" and visit.offer or {}) do
        if type(itemid) == "string" then
            entries[#entries+1] = { itemid = itemid, place = tonumber(place) or 0 }
        end
    end
    table.sort(entries, function(a, b) return a.place < b.place end)
    local result = {}
    for _, e in ipairs(entries) do
        result[#result+1] = e.itemid
    end
    return result
end

--Roll the hero's Presence test and open their visit. args = {heroid, skill,
--previewPanel?, begin = function(rollInfo, bonus), cancel = function(),
--done = function(ok, visitOrMessage)}. With previewPanel (a gui.DicePreview
--cage) the dice only rest there, armed, until the player clicks or throws
--them; cancel() fires if a throw is too weak to roll.
function EotwMarket.Roll(args)
    local tok = dmhub.GetCharacterById(args.heroid)
    local blocked = EotwMarket.Blocked(args.heroid)
    if tok == nil or blocked ~= nil then
        args.done(false, blocked or "That hero is not ready yet.")
        return
    end
    if EotwMarket.Visit(tok) ~= nil then
        args.done(false, "This hero has already shopped. The stalls change after their next encounter.")
        return
    end
    local bonus = EotwMarket.RollBonus(tok, args.skill)
    dmhub.Roll{
        roll = string.format("2d10%+d", bonus),
        description = "The Arcane Market",
        preview = args.previewPanel ~= nil,
        previewPanel = args.previewPanel,
        cancel = function()
            if not mod.unloaded and args.cancel ~= nil then
                args.cancel()
            end
        end,
        begin = function(rollInfo)
            if not mod.unloaded and args.begin ~= nil then
                args.begin(rollInfo, bonus)
            end
        end,
        complete = function(rollInfo)
            if mod.unloaded then
                return
            end
            local natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
            local total = math.floor(tonumber(rollInfo.total) or 0)
            --dev: /eotwmarket critical makes this roll a natural 20.
            if EotwMarket.forceCritical then
                EotwMarket.forceCritical = false
                printf("EotW town (dev): this market roll counts as a natural 20 (the dice said %d)", natural)
                natural = 20
                total = 20 + bonus
            end
            local tier = Tier(total, natural)
            local visit = {
                epoch = EotwMarket.Epoch(tok),
                rollid = dmhub.GenerateGuid(),
                natural = natural,
                total = total,
                tier = tier,
                critical = natural >= EotwMarket.CRITICAL_NATURAL,
                skill = args.skill or "",
                offer = PickOffer(EotwMarket.OFFER_BY_TIER[tier]),
                bought = {},
            }
            --written at once: closing the market now must not allow a re-roll.
            ChangeVisit(args.heroid, "Shopped at the Arcane Market", visit, function() end, function(ok, message)
                if not ok then
                    printf("EotW town: the market visit was not saved to the city yet: %s", tostring(message))
                end
            end)
            args.done(true, visit)
        end,
    }
end

--Why the hero cannot buy this offered treasure, or nil if they can.
---@param heroid string
---@param itemid string
---@return string|nil
function EotwMarket.BuyBlocked(heroid, itemid)
    local blocked = EotwMarket.Blocked(heroid)
    if blocked ~= nil then
        return blocked
    end
    local tok = dmhub.GetCharacterById(heroid)
    local visit = tok ~= nil and EotwMarket.Visit(tok) or nil
    if tok == nil or visit == nil then
        return "Make the Presence test first."
    end
    local offered = false
    for _, id in ipairs(EotwMarket.Offer(visit)) do
        if id == itemid then
            offered = true
        end
    end
    if not offered then
        return "That treasure is not on offer to this hero."
    end
    if type(visit.bought) == "table" and visit.bought[itemid] == true then
        return "Already bought."
    end
    if EotwMarket.BoughtCount(visit) >= EotwMarket.PurchaseLimit(tok, visit) then
        return "No purchases left until this hero's next encounter."
    end
    return nil
end

--Buy one offered treasure: it goes into the hero's inventory. onDone(ok, message).
---@param heroid string
---@param itemid string
---@param onDone nil|fun(ok: boolean, message: string|nil)
function EotwMarket.Buy(heroid, itemid, onDone)
    local blocked = EotwMarket.BuyBlocked(heroid, itemid)
    local tok = dmhub.GetCharacterById(heroid)
    if blocked ~= nil or tok == nil then
        if onDone ~= nil then
            onDone(false, blocked)
        end
        return
    end
    local visit = EotwMarket.Visit(tok) or {}
    ChangeVisit(heroid, "Bought a treasure at the Arcane Market", visit, function(props, copy)
        local bought = {}
        for k, v in pairs(type(copy.bought) == "table" and copy.bought or {}) do
            bought[k] = v
        end
        bought[itemid] = true
        copy.bought = bought
        props:GiveItem(itemid, 1)
    end, onDone)
end

--- UI bits ---------------------------------------------------------------------

--The tier lines shown before the roll: { {label, text}, ... }.
local TIER_LINES = {
    { "11 or lower", "2 treasures on offer" },
    { "12 - 16", "3 treasures on offer" },
    { "17 or higher", "4 treasures on offer" },
    { "Natural 19 - 20", "4 treasures on offer, and buy one extra" },
}

local function Portrait(tok, width, height)
    local portrait = nil
    if tok ~= nil then
        pcall(function() portrait = tok.offTokenPortrait end)
    end
    if type(portrait) ~= "string" or portrait == "" then
        return gui.Panel{
            interactable = false,
            width = width,
            height = height,
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff10",
            cornerRadius = 6,
        }
    end
    local rect = nil
    pcall(function() rect = tok:GetPortraitRectForAspect(width / height, portrait) end)
    return gui.Panel{
        interactable = false,
        width = width,
        height = height,
        valign = "center",
        bgimage = portrait,
        bgcolor = "white",
        cornerRadius = 6,
        borderWidth = 1,
        borderColor = "#8c7a55",
        imageRect = rect,
    }
end

--The codex's own item card as a tooltip, or just the name.
---@param element Panel
---@param item equipment|nil
---@param name string
local function ItemTooltip(element, item, name)
    local tooltipFn = rawget(_G, "CreateItemTooltip")
    if item ~= nil and tooltipFn ~= nil then
        local ok = pcall(function()
            element.tooltip = tooltipFn(item, { valign = "center", width = 360 }, nil)
        end)
        if ok then
            return
        end
    end
    gui.Tooltip(name)(element)
end

--A small item icon.
---@param itemid string
---@param size number
---@param faded boolean
local function ItemIcon(itemid, size, faded)
    local item = (dmhub.GetTable("tbl_Gear") or {})[itemid]
    local icon = item ~= nil and item:try_get("iconid", "") or ""
    local name = item ~= nil and item.name or "Treasure"
    return gui.Panel{
        width = size,
        height = size,
        hmargin = 2,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        borderWidth = 1,
        borderColor = cond(faded, "#5a4b33", GOLD),
        cornerRadius = 4,
        opacity = cond(faded, 0.45, 1),
        linger = function(element)
            ItemTooltip(element, item, name)
        end,
        gui.Panel{
            interactable = false,
            width = "84%",
            height = "84%",
            halign = "center",
            valign = "center",
            bgimage = cond(icon ~= "", icon, "phosphor/flask-fill.png"),
            bgcolor = "white",
        },
    }
end

--A treasure's short text for its stall card: its description, else its flavor.
---@param item equipment
---@return string
local function ShortText(item)
    local text = item:try_get("description", "")
    if type(text) ~= "string" or string.match(text, "^%s*$") then
        text = item:try_get("flavor", "")
    end
    text = string.gsub(tostring(text or ""), "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    if #text > 150 then
        text = string.sub(text, 1, 147) .. "..."
    end
    return text
end

--- the stall dialog -----------------------------------------------------------

--One hero's visit: the Presence test (with 3D dice resting at the bottom,
--rolled by a click or a throw), then the treasures it found, to buy.
---@param host Panel|nil
---@param heroid string
function EotwMarket.ShowShopDialog(host, heroid)
    if host == nil or not host.valid then
        return
    end
    local state = {
        skill = nil,
        rolling = false,
        message = "",
        buying = false,
    }
    do
        local tok = dmhub.GetCharacterById(heroid)
        if tok ~= nil then
            state.skill = EotwMarket.TrainedSkills(tok)[1]
        end
    end

    local dlg = nil
    local body = nil
    local hintLabel = nil
    local cageHolder = nil
    local closeButton = nil
    local cage = nil
    local armedSignature = nil

    local Render

    local function Disarm()
        armedSignature = nil
        if cage ~= nil and cage.valid then
            pcall(function() cage:CancelDicePreviewRoll() end)
        end
    end

    local function Close()
        if state.rolling then
            return
        end
        Disarm()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local function ArmDice(signature)
        Disarm()
        if cage == nil or not cage.valid then
            return
        end
        armedSignature = signature
        EotwMarket.Roll{
            previewPanel = cage,
            heroid = heroid,
            skill = state.skill,
            begin = function(rollInfo, bonus)
                armedSignature = nil
                state.rolling = true
                state.message = ""
                Render()
            end,
            cancel = function()
                armedSignature = nil
                Render()
            end,
            done = function(ok, result)
                if mod.unloaded then
                    return
                end
                state.rolling = false
                if not ok then
                    state.message = tostring(result)
                end
                Render()
            end,
        }
    end

    --The found treasures as cards, each with Buy (or why not).
    local function StallCards(tok, visit)
        local gear = dmhub.GetTable("tbl_Gear") or {}
        local cards = {}
        for _, itemid in ipairs(EotwMarket.Offer(visit)) do
            local item = gear[itemid]
            local name = item ~= nil and item.name or "A treasure"
            local bought = type(visit.bought) == "table" and visit.bought[itemid] == true
            local blocked = EotwMarket.BuyBlocked(heroid, itemid)
            local icon = item ~= nil and item:try_get("iconid", "") or ""
            local buyButton
            if bought then
                buyButton = gui.Label{
                    text = "Bought",
                    fontSize = 18,
                    bold = true,
                    color = GREEN,
                    width = "auto",
                    height = 34,
                    halign = "center",
                    valign = "bottom",
                    bmargin = 4,
                }
            else
                buyButton = gui.Button{
                    text = "Buy",
                    fontSize = 18,
                    width = 130,
                    height = 34,
                    halign = "center",
                    valign = "bottom",
                    bmargin = 4,
                    opacity = cond(blocked == nil and not state.buying, 1, 0.4),
                    linger = function(element)
                        if blocked ~= nil then
                            gui.Tooltip(blocked)(element)
                        end
                    end,
                    click = function()
                        if blocked ~= nil or state.buying then
                            return
                        end
                        audio.FireSoundEvent("Mouse.Click")
                        state.buying = true
                        state.message = ""
                        EotwMarket.Buy(heroid, itemid, function(okBuy, message)
                            state.buying = false
                            if not okBuy then
                                state.message = tostring(message or "The purchase did not go through.")
                            end
                            if not mod.unloaded then
                                Render()
                            end
                        end)
                        Render()
                    end,
                }
            end
            cards[#cards+1] = gui.Panel{
                width = 190,
                height = 300,
                hmargin = 5,
                vmargin = 5,
                flow = "vertical",
                pad = 10,
                borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = cond(bought, "#1f2a18", "#1d1913"),
                borderWidth = cond(bought, 2, 1),
                borderColor = cond(bought, GREEN, "#5a4b33"),
                cornerRadius = 8,
                opacity = cond(not bought and blocked ~= nil, 0.6, 1),
                linger = function(element)
                    ItemTooltip(element, item, name)
                end,
                gui.Panel{
                    interactable = false,
                    width = 84,
                    height = 84,
                    halign = "center",
                    bgimage = cond(icon ~= "", icon, "phosphor/flask-fill.png"),
                    bgcolor = "white",
                },
                gui.Label{
                    interactable = false,
                    text = name,
                    fontSize = 17,
                    bold = true,
                    color = TEXT,
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    vmargin = 6,
                },
                gui.Label{
                    interactable = false,
                    text = item ~= nil and ShortText(item) or "",
                    fontSize = 13,
                    color = DIM,
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
                buyButton,
            }
        end
        return cards
    end

    Render = function()
        if body == nil or not body.valid then
            return
        end
        local tok = dmhub.GetCharacterById(heroid)
        local children = {}
        local visit = tok ~= nil and EotwMarket.Visit(tok) or nil
        local blocked = EotwMarket.Blocked(heroid)
        local canRoll = tok ~= nil and visit == nil and blocked == nil and not state.rolling

        if tok == nil then
            children[#children+1] = gui.Label{ text = "This hero is not here.", fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto" }
        elseif visit == nil then
            --before the test: the skill, the formula, what each tier finds.
            local trained = EotwMarket.TrainedSkills(tok)
            local skillOptions = { { id = "", text = "No skill" } }
            for _, name in ipairs(trained) do
                skillOptions[#skillOptions+1] = { id = name, text = string.format("%s (+2)", name) }
            end
            children[#children+1] = gui.Label{
                text = "Make a Presence test to find the stalls worth your coin.",
                fontSize = 17,
                color = TEXT,
                width = "100%",
                height = "auto",
                tmargin = 10,
            }
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 12,
                gui.Label{
                    text = "Skill",
                    fontSize = 15,
                    color = DIM,
                    width = 100,
                    height = "auto",
                    valign = "center",
                },
                gui.Dropdown{
                    width = 240,
                    height = 34,
                    fontSize = 16,
                    styles = ThemeEngine.GetStyles(),
                    options = skillOptions,
                    idChosen = state.skill or "",
                    change = function(element)
                        ---@cast element Dropdown
                        local id = element.idChosen
                        state.skill = cond(id ~= nil and id ~= "", id, nil)
                        Render()
                    end,
                },
                gui.Label{
                    text = cond(#trained == 0, "Alchemy or Magic would help (this hero has neither)", "Alchemy or Magic"),
                    fontSize = 13,
                    italics = true,
                    color = DIM,
                    width = 360,
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                },
            }
            local _, formula = EotwMarket.RollBonus(tok, state.skill)
            children[#children+1] = gui.Label{
                text = formula,
                fontSize = 20,
                color = TEXT,
                width = "100%",
                height = "auto",
                tmargin = 12,
                bmargin = 8,
            }
            for _, line in ipairs(TIER_LINES) do
                children[#children+1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 2,
                    gui.Label{
                        text = line[1],
                        fontSize = 16,
                        bold = true,
                        color = GOLD,
                        width = 180,
                        height = "auto",
                    },
                    gui.Label{
                        text = line[2],
                        fontSize = 16,
                        color = TEXT,
                        width = "auto",
                        height = "auto",
                    },
                }
            end
            children[#children+1] = gui.Label{
                text = string.format("%s can buy up to %d (Wealth %d).", tostring(tok.name), EotwMarket.Wealth(tok), EotwMarket.Wealth(tok)),
                fontSize = 15,
                italics = true,
                color = DIM,
                width = "100%",
                height = "auto",
                tmargin = 10,
            }
        else
            --after the test: what it found, and buying.
            local limit = EotwMarket.PurchaseLimit(tok, visit)
            local boughtCount = EotwMarket.BoughtCount(visit)
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 8,
                gui.Label{
                    text = cond(visit.critical == true, "Critical!", string.format("Tier %d", tonumber(visit.tier) or 1)),
                    fontFace = "display",
                    fontSize = 30,
                    color = cond(visit.critical == true, AMBER, GOLD),
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
                gui.Label{
                    text = string.format("Rolled %d (natural %d)%s", tonumber(visit.total) or 0, tonumber(visit.natural) or 0,
                        cond(type(visit.skill) == "string" and visit.skill ~= "", string.format(" with %s", tostring(visit.skill)), "")),
                    fontSize = 15,
                    color = DIM,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 14,
                },
            }
            children[#children+1] = gui.Label{
                text = string.format("%d %s on offer.  Bought %d of %d%s.",
                    #EotwMarket.Offer(visit), cond(#EotwMarket.Offer(visit) == 1, "treasure", "treasures"),
                    boughtCount, limit,
                    cond(visit.critical == true, string.format(" (Wealth %d, +1 for the critical)", EotwMarket.Wealth(tok)), string.format(" (Wealth %d)", EotwMarket.Wealth(tok)))),
                fontSize = 17,
                color = TEXT,
                width = "100%",
                height = "auto",
                vmargin = 8,
            }
            local cards = StallCards(tok, visit)
            if #cards == 0 then
                cards[1] = gui.Label{ text = "The stalls had nothing in stock.", fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto" }
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                halign = "center",
                children = cards,
            }
        end

        children[#children+1] = gui.Label{
            text = state.message,
            fontSize = 15,
            color = RED,
            width = "100%",
            height = 22,
            tmargin = 6,
            textAlignment = "center",
        }
        body.children = children

        --the bottom: dice while a roll is possible, else a Close button.
        local hint = ""
        if state.rolling then
            hint = ""
        elseif canRoll then
            hint = "Click or throw the dice to make the test."
        elseif blocked ~= nil then
            hint = blocked
        elseif visit ~= nil then
            hint = "The stalls change after this hero's next encounter."
        end
        if hintLabel ~= nil and hintLabel.valid then
            hintLabel.text = hint
        end
        if cageHolder ~= nil and cageHolder.valid then
            cageHolder:SetClass("collapsed", visit ~= nil)
        end
        if closeButton ~= nil and closeButton.valid then
            closeButton:SetClass("collapsed", visit == nil or state.rolling)
        end
        if not state.rolling then
            if canRoll then
                local signature = tostring(state.skill)
                if signature ~= armedSignature then
                    ArmDice(signature)
                end
            elseif armedSignature ~= nil then
                Disarm()
            end
        end
    end

    local name = "Your hero"
    do
        local tok = dmhub.GetCharacterById(heroid)
        if tok ~= nil and tok.name ~= nil then
            name = tok.name
        end
    end

    dlg = gui.Panel{
        floating = true,
        width = 860,
        height = 820,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "none",
        pad = 24,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwMarket.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev and not state.rolling then
                element.data.seen = rev
                Render()
            end
        end,

        --the top: title, then the test or the stalls.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "top",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 4,
                gui.Panel{
                    width = 30,
                    height = 30,
                    valign = "center",
                    rmargin = 10,
                    bgimage = "phosphor/storefront-fill.png",
                    bgcolor = GOLD,
                },
                gui.Label{
                    text = string.format("The Arcane Market: %s", name),
                    fontSize = 28,
                    bold = true,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            },
            gui.Label{
                text = "Potions, powders and stranger things, sold from carts and back rooms to those who know whom to ask.",
                fontSize = 16,
                italics = true,
                color = DIM,
                width = "100%",
                height = "auto",
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    body = element
                end,
            },
        },

        --the bottom: the hint over the dice, or a Close once the test is made.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                text = "",
                fontSize = 16,
                italics = true,
                color = AMBER,
                width = "100%",
                height = 46,
                textAlignment = "center",
                create = function(element)
                    hintLabel = element
                end,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                create = function(element)
                    cageHolder = element
                end,
                --the same dice cage the project roll dialog has (EotwDowntime):
                --built once, since a rebuild would drop the armed roll.
                gui.DicePreview{
                    width = "70%",
                    height = 120,
                    halign = "center",
                    bgimage = true,
                    bgcolor = "white",
                    styles = { gui.Style{ opacity = 0 } },
                    draggable = true,
                    dragMove = false,
                    create = function(element)
                        ---@cast element DicePreview
                        cage = element
                        element:SetAsDicePreviewPanel(true)
                        pcall(function() element.dicePreviewScreenBounds = true end)
                        Render()
                    end,
                    destroy = function(element)
                        ---@cast element DicePreview
                        pcall(function() element:CancelDicePreviewRoll() end)
                        element:SetAsDicePreviewPanel(false)
                    end,
                    hover = function(element)
                        ---@cast element DicePreview
                        pcall(function() element:DicePreviewMouseEnter() end)
                    end,
                    dehover = function(element)
                        ---@cast element DicePreview
                        pcall(function() element:DicePreviewMouseLeave() end)
                    end,
                    click = function(element)
                        ---@cast element DicePreview
                        if armedSignature ~= nil then
                            pcall(function() element:DicePreviewClick() end)
                        end
                    end,
                    dragging = function(element)
                        ---@cast element DicePreview
                        pcall(function() element:DicePreviewDragThink() end)
                    end,
                    drag = function(element)
                        ---@cast element DicePreview
                        pcall(function() element:DicePreviewDragEnd() end)
                    end,
                },
            },
            gui.Button{
                classes = { "collapsed" },
                halign = "center",
                bmargin = 10,
                text = "Close",
                fontSize = 22,
                width = 240,
                height = 50,
                create = function(element)
                    closeButton = element
                    Render()
                end,
                click = function()
                    Close()
                end,
            },
        },

        --close: an X in the top-right corner (not while dice are in the air).
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "top",
            x = 10,
            y = -10,
            width = 22,
            height = 22,
            bgimage = "phosphor/x-bold.png",
            styles = {
                { selectors = { "eotwDialogClose" }, bgcolor = DIM },
                { selectors = { "eotwDialogClose", "hover" }, bgcolor = "#ffffff", scale = 1.15 },
            },
            classes = { "eotwDialogClose" },
            linger = gui.Tooltip("Close"),
            press = function()
                if state.rolling then
                    return
                end
                audio.FireSoundEvent("UI.WindowClose")
                Close()
            end,
        },
    }
    host:AddChild(dlg)
end

--- the market's card -----------------------------------------------------------

--One hero's row: portrait, name and Wealth, what they found and bought on
--this visit, and Shop / Browse.
local function MarketRow(host, hero)
    local tok = dmhub.GetCharacterById(hero.heroid)
    local name = (tok ~= nil and tok.name) or (hero.summary or {}).name or "Hero"
    local blocked = EotwMarket.Blocked(hero.heroid)
    local visit = tok ~= nil and EotwMarket.Visit(tok) or nil

    local status
    local icons = {}
    if blocked ~= nil or tok == nil then
        status = blocked or "Loading..."
    elseif visit == nil then
        status = string.format("Wealth %d  -  has not shopped since their last encounter", EotwMarket.Wealth(tok))
    else
        local limit = EotwMarket.PurchaseLimit(tok, visit)
        local boughtCount = EotwMarket.BoughtCount(visit)
        status = string.format("%s: %d on offer  -  bought %d of %d",
            cond(visit.critical == true, "Critical", string.format("Tier %d", tonumber(visit.tier) or 1)),
            #EotwMarket.Offer(visit), boughtCount, limit)
        for _, itemid in ipairs(EotwMarket.Offer(visit)) do
            local bought = type(visit.bought) == "table" and visit.bought[itemid] == true
            icons[#icons+1] = ItemIcon(itemid, 30, not bought)
        end
    end

    local buttonText = cond(visit == nil, "Shop", "Browse")
    return gui.Panel{
        width = "100%",
        height = 72,
        flow = "horizontal",
        vmargin = 2,
        hpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        cornerRadius = 6,
        opacity = cond(blocked ~= nil, 0.5, 1),
        Portrait(tok, 44, 58),
        gui.Panel{
            width = "100%-200",
            height = "auto",
            flow = "vertical",
            valign = "center",
            lmargin = 10,
            gui.Label{
                text = name,
                fontSize = 18,
                bold = true,
                color = TEXT,
                width = "100%",
                height = "auto",
                textWrap = false,
                minFontSize = 12,
            },
            gui.Label{
                text = status,
                fontSize = 13,
                color = cond(visit ~= nil, AMBER, DIM),
                width = "100%",
                height = "auto",
            },
            gui.Panel{
                classes = { cond(#icons > 0, "visible", "collapsed") },
                width = "auto",
                height = "auto",
                flow = "horizontal",
                tmargin = 3,
                children = icons,
            },
        },
        gui.Button{
            text = buttonText,
            fontSize = 16,
            width = 120,
            height = 34,
            halign = "right",
            valign = "center",
            opacity = cond(blocked == nil, 1, 0.4),
            linger = function(element)
                if blocked ~= nil then
                    gui.Tooltip(blocked)(element)
                elseif visit == nil then
                    gui.Tooltip("Make a Presence test to find what is on offer.")(element)
                end
            end,
            click = function()
                if blocked ~= nil then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                EotwMarket.ShowShopDialog(host, hero.heroid)
            end,
        },
    }
end

--The Arcane Market's card: every hero, what they have found and bought, and
--a way into the stalls for each. host mounts the shop dialog.
---@param host Panel|nil
---@return Panel
function EotwMarket.MarketPanel(host)
    local listPanel = nil

    local function Rebuild()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {}
        for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
            rows[#rows+1] = MarketRow(host, hero)
        end
        if EotwRoster.GetHeroes() == nil then
            rows[1] = gui.Label{ text = "The traders are sizing you up...", fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        elseif #rows == 0 then
            rows[1] = gui.Label{ text = "You have no heroes. Visit the Hero's Guild.", fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        end
        listPanel.children = rows
    end

    --what the market sells today, as icons.
    local stockIcons = {}
    for _, entry in ipairs(EotwMarket.Stock()) do
        stockIcons[#stockIcons+1] = ItemIcon(entry.itemid, 34, false)
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwMarket.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Rebuild()
            end
        end,

        gui.Label{
            text = "Shop the Stalls",
            fontSize = 26,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
        },
        gui.Label{
            text = "Each hero makes a Presence test (Alchemy or Magic help) to find what is on offer, then buys as many treasures as their Wealth. The stalls change after that hero's next encounter.",
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 8,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 10,
            gui.Label{
                text = "In stock:",
                fontSize = 14,
                color = DIM,
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 6,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                children = stockIcons,
            },
        },
        gui.Panel{
            width = "100%",
            height = "100%-200",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            create = function(element)
                listPanel = element
                Rebuild()
            end,
        },
    }
end

--- dev commands ---------------------------------------------------------------

local DEV_USAGE = [[Usage: /eotwmarket <command> (open the town first)
  critical         the next market roll counts as a natural 20
  reset [hero]     forget the hero's market visit (or every hero's), so they can shop again
  stock            list what the market sells
  state            print each hero's visit
[hero] matches the start of a hero's name, case-insensitive.]]

pcall(function()
    Commands.RegisterMacro{
        name = "eotwmarket",
        summary = "dev: the Encounter of the Week Arcane Market",
        doc = DEV_USAGE,
        command = function(str)
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then
                print("EotW town: /eotwmarket is a developer command")
                return
            end
            local arg = string.gsub(str or "", "^%s*(.-)%s*$", "%1")
            local verb, rest = string.match(arg, "^(%S+)%s*(.*)$")
            verb = string.lower(verb or "")
            rest = string.lower(rest or "")

            if verb == "critical" then
                EotwMarket.forceCritical = not EotwMarket.forceCritical
                printf("EotW town (dev): next market roll is %s", cond(EotwMarket.forceCritical, "a natural 20", "rolled normally"))
                return
            end
            if verb == "stock" then
                for _, entry in ipairs(EotwMarket.Stock()) do
                    printf("  %s (%s)", tostring(entry.item.name), entry.itemid)
                end
                return
            end
            if verb ~= "reset" and verb ~= "state" then
                print(DEV_USAGE)
                return
            end
            for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
                local tok = dmhub.GetCharacterById(hero.heroid)
                local heroName = (tok ~= nil and tok.name) or (hero.summary or {}).name or hero.heroid
                if tok ~= nil and (rest == "" or string.sub(string.lower(heroName), 1, #rest) == rest) then
                    if verb == "state" then
                        local visit = EotwMarket.Visit(tok)
                        if visit == nil then
                            printf("  %s: Wealth %d, epoch %d, not shopped", heroName, EotwMarket.Wealth(tok), EotwMarket.Epoch(tok))
                        else
                            printf("  %s: Wealth %d, epoch %d, tier %s%s, rolled %s, offer %d, bought %d of %d", heroName,
                                EotwMarket.Wealth(tok), EotwMarket.Epoch(tok), tostring(visit.tier), cond(visit.critical == true, " (critical)", ""),
                                tostring(visit.total), #EotwMarket.Offer(visit), EotwMarket.BoughtCount(visit), EotwMarket.PurchaseLimit(tok, visit))
                        end
                    elseif EotwRoster.IsInStep(hero.heroid) then
                        tok:ModifyProperties{
                            description = "Dev: reset the market visit",
                            undoable = false,
                            execute = function()
                                tok.properties.eotwMarket = false
                            end,
                        }
                        dmhub.Schedule(0.3, function()
                            if not mod.unloaded then
                                EotwRoster.PushHero(hero.heroid)
                                Bump()
                            end
                        end)
                        printf("EotW town (dev): %s can shop again", heroName)
                    end
                end
            end
        end,
    }
end)

local mod = dmhub.GetModLoading()

--- The Tackle table
--- Opens once casting has stopped and any event has fully resolved, because an
--- event can hand over points and those are spendable. Purchases happen one at
--- a time and the total is re-read after each, since buying the Fishing event
--- can produce an event that awards more.
--- @class FSHShop
FSHShop = RegisterGameType("FSHShop")

--- What the Tackle table sells, in the order the rules list it.
FSHShop.REWARDS = {
    {
        id = "hearty",
        cost = 50,
        name = "Hearty meal",
        detail = "One serving. Recoveries +1 until the end of the next respite.",
        kind = "item"
    },
    {
        id = "great",
        cost = 100,
        name = "Great meal",
        detail = "One serving. Recoveries +1 and 10 temporary Stamina.",
        kind = "item"
    },
    {
        id = "tackle",
        cost = 120,
        name = "Better tackle",
        detail = "The Angler title: an edge on Fishing rolls.",
        kind = "title"
    },
    {
        id = "event",
        cost = 200,
        name = "Fishing event",
        detail = "Roll on the Fishing Events table.",
        kind = "event"
    },
    {
        id = "legendary",
        cost = 300,
        name = "Legendary fisher",
        detail = "The Goldenrod title: reroll one cast per trip.",
        kind = "title"
    }
}

--- The reward matching an id
--- @param rewardId string The reward id
--- @return table|nil reward The reward
function FSHShop.Reward(rewardId)
    for _, reward in ipairs(FSHShop.REWARDS) do
        if reward.id == rewardId then
            return reward
        end
    end
    return nil
end

--- What a reward hands over, resolved at purchase time so the constants stay
--- in one place.
--- @param rewardId string The reward id
--- @return string|nil guid The item or title guid
local function RewardGuid(rewardId)
    if rewardId == "hearty" then
        return FSHConstants.itemHeartyMeal
    elseif rewardId == "great" then
        return FSHConstants.itemGreatMeal
    elseif rewardId == "tackle" then
        return FSHConstants.titleAngler
    elseif rewardId == "legendary" then
        return FSHConstants.titleGoldenrod
    end
    return nil
end

--- Whether a Trip can buy a reward right now
--- @param charid string The hero's token id
--- @param rewardId string The reward id
--- @return boolean affordable True when it can be bought
function FSHShop.CanBuy(charid, rewardId)
    local trip = FSHTrip.Get(charid)
    local reward = FSHShop.Reward(rewardId)

    if trip == nil or reward == nil then
        return false
    end

    if trip.status ~= FSHTrip.STATUS.SHOPPING.key then
        return false
    end

    if not FSHTrip.IsOwnedByThisClient(charid) then
        return false
    end

    return (trip.points or 0) >= reward.cost
end

--- Buys one reward
--- Nothing is bundled: each press is one purchase, so the total can be re-read
--- before the next one and a reward that awards points is spendable.
--- @param charid string The hero's token id
--- @param rewardId string The reward id
--- @return boolean bought True when the purchase went through
--- @return string reason Why not, when it did not
function FSHShop.Buy(charid, rewardId)
    if not FSHShop.CanBuy(charid, rewardId) then
        return false, "You cannot afford that."
    end

    local reward = FSHShop.Reward(rewardId)
    local token = dmhub.GetCharacterById(charid)
    if token == nil or not token.valid then
        return false, "That hero is not available."
    end

    FSHTrip.AddPurchase(charid, reward.name, reward.cost)

    local guid = RewardGuid(rewardId)

    if reward.kind == "item" and guid ~= nil and guid ~= "" then
        token:ModifyProperties{
            description = "Buy fishing reward",
            undoable = false,
            execute = function()
                token.properties:GiveItem(guid, 1)
            end
        }
    elseif reward.kind == "title" and guid ~= nil and guid ~= "" then
        token:ModifyProperties{
            description = "Buy fishing reward",
            undoable = false,
            execute = function()
                token.properties:AddTitle(guid)
            end
        }
    elseif reward.kind == "event" then
        --The shop closes behind the event and reopens once it is settled, so
        --anything the event awards can still be spent.
        FSHTrip.SetStatus(charid, FSHTrip.STATUS.EVENT.key)
    end

    return true, ""
end

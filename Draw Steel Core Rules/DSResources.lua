local mod = dmhub.GetModLoading()

CharacterResource.heroicResourceId = "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"
CharacterResource.epicResourceId = "e7b04a7e-61fc-4e17-b999-d95d7e751abb"
CharacterResource.maliceResourceId = "101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8"
CharacterResource.surgeResourceId = "8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d"
CharacterResource.triggerResourceId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"
CharacterResource.freeTriggeredActionResourceId = "5e551b7d-17fb-4099-a303-bafb3c146f98"
CharacterResource.actionResourceId = "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
CharacterResource.maneuverResourceId = "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b"
CharacterResource.heroTokenId = "2166c5fe-260e-4691-9743-06cf097a59f3"
CharacterResource.villainActionId = "67f15a17-523c-4a30-8f1a-a27e4f122605"
CharacterResource.recoveryResourceId = "5bd90f9b-46be-4cf2-8ca6-a96430d62949"
CharacterResource.freeManeuverResourceId = "d81ce1e9-96a3-4705-9180-1c80f72a86cf"
CharacterResource.respiteActivityId = "5758da29-8660-47d3-805b-7c6038f476a1"
CharacterResource.rampageId = "9f418676-96be-402b-92da-0f50294146b3"

--Whether this ability is a Draw Steel triggered action or free triggered action,
--as declared by its "Action" field in the ability editor. Only these two are
--suppressed by "Cannot Use Triggered Abilities" (the Dazed / Surprised rule).
--A TriggeredAbility whose action is "No Action" is not an action the creature
--takes: automatic effects, and prompt plumbing such as the "Spend Recovery"
--trigger that Healing Grace and similar abilities fire on their targets.
--- @return boolean
function ActivatedAbility:IsTriggeredAction()
    local resource = self:ActionResource()
    return resource == CharacterResource.triggerResourceId or resource == CharacterResource.freeTriggeredActionResourceId
end

monster.resourceid = CharacterResource.maliceResourceId
character.resourceid = CharacterResource.heroicResourceId

monster.resourceRefresh = "global"
creature.resourceRefresh = "unbounded"

function creature:GetHeroicOrMaliceResourcesAvailableToSpend()
    return self:GetHeroicOrMaliceResourcesAvailable()
end

function character:GetHeroicOrMaliceResourcesAvailableToSpend()
    return self:GetHeroicOrMaliceResourcesAvailable() + self:CalculateNamedCustomAttribute("Negative Heroic Resource") + self:ExtraHeroicResource()
end

function creature:GetHeroicOrMaliceResourcesAvailable()
    return self:GetHeroicOrMaliceResources()
end

function creature:GetHeroicOrMaliceResources()
    local resources = self:GetResources()
    return resources[self.resourceid] or 0
end

function character:GetHeroicOrMaliceResources()
    local resources = self:try_get("resources")
    if resources ~= nil then
        local heroicResource = resources[CharacterResource.heroicResourceId]
        if heroicResource ~= nil then
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden or q.guid ~= heroicResource.combatid then
                return 0
            end

            return heroicResource.unbounded or 0
        end
    end

    return 0
end

function creature:ResourceName()
    local t = dmhub.GetTable(CharacterResource.tableName)
    return t[self.resourceid].name
end

function CharacterResource.GetMalice()
    return CharacterResource.GetGlobalResource(CharacterResource.maliceResourceId)
end

function CharacterResource.SetMalice(amount, message)
    print("SetMalice::", amount)
    CharacterResource.SetGlobalResource(CharacterResource.maliceResourceId, amount, message)
end

function CharacterResource.CanSpendMalice(cost)
    cost = tonumber(cost) or 0
    return cost <= 0 or CharacterResource.GetMalice() >= cost
end

function CharacterResource.SpendMalice(cost, message)
    cost = tonumber(cost) or 0
    if cost <= 0 then
        return true
    end

    if not CharacterResource.CanSpendMalice(cost) then
        return false
    end

    CharacterResource.SetMalice(CharacterResource.GetMalice() - cost, message)
    return true
end

--- Action Log card posted whenever an ability spends Malice: a monster ability with a
--- Malice cost, a Malice feature, or a Malice-paid enhancement. Shows the Malice
--- diamond with the amount spent; hovering the card shows the full ability card, so
--- players can see what the Director's Malice bought.
--- @class MaliceSpentChatMessage: GameType
--- @field new fun(o?: table): MaliceSpentChatMessage
--- @field tokenid string Charid of the creature that used the ability.
--- @field cost number Malice actually deducted.
--- @field ability ActivatedAbility
MaliceSpentChatMessage = RegisterGameType("MaliceSpentChatMessage")

MaliceSpentChatMessage.tokenid = ""
MaliceSpentChatMessage.cost = 0

--- @param token CharacterToken the creature that used the ability
--- @param ability ActivatedAbility
--- @param cost number
function MaliceSpentChatMessage.Post(token, ability, cost)
    if token == nil or (not token.valid) or cost <= 0 then
        return
    end

    --Same shallow clone the cast card stores: the invoker chain is live game
    --state that must not be serialized into the chat message.
    local abilityClone = table.shallow_copy(ability)
    setmetatable(abilityClone, getmetatable(ability))
    abilityClone.invoker = nil

    chat.SendCustom(MaliceSpentChatMessage.new{
        tokenid = token.charid,
        cost = cost,
        ability = abilityClone,
    })
end

--The action bar's red Malice cost diamond (a rotated square with a red inner
--diamond), with the number counter-rotated so it stays upright. The outer panel
--reserves room for the rotated square's bounding box.
local function MaliceCostDiamond(cost)
    return gui.Panel{
        width = 30,
        height = 30,
        valign = "center",
        rmargin = 4,
        interactable = false,
        gui.Panel{
            width = 21,
            height = 21,
            halign = "center",
            valign = "center",
            rotate = 135,
            interactable = false,
            bgimage = true,
            bgcolor = "white",
            gradient = Styles.Ability.maliceDiamondGradient,
            border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
            borderColor = "grey",
            gui.Panel{
                width = "65%",
                height = "65%",
                halign = "center",
                valign = "center",
                interactable = false,
                bgimage = true,
                bgcolor = "#DE1E47",
                borderWidth = 2,
                borderColor = "#FF5076",
                gui.Label{
                    text = string.format("%d", cost),
                    rotate = -135,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    fontSize = 12,
                    bold = true,
                    color = "white",
                    interactable = false,
                },
            },
        },
    }
end

function MaliceSpentChatMessage.Render(selfInput, message)
    local token = dmhub.GetCharacterById(selfInput.tokenid)
    local ability = selfInput:try_get("ability")
    if token == nil or (not token.valid) or ability == nil then
        return gui.Panel{
            width = 0, height = 0,
        }
    end
    ---@cast ability ActivatedAbility

    local cost = tonumber(selfInput.cost) or 0

    local card = CreateActionLogCard{
        token = token,
        content = {
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                MaliceCostDiamond(cost),
                gui.Panel{
                    flow = "vertical",
                    width = "100%-34",
                    height = "auto",
                    valign = "center",
                    gui.Label{
                        classes = {"action-log-detail", "sizeXs", "fg"},
                        text = ability.name,
                    },
                    gui.Label{
                        classes = {"action-log-subtext", "sizeXxs", "fgMuted"},
                        text = string.format("Spent %d Malice", cost),
                    },
                },
            },
        },
    }

    return gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message)
        end,

        --The whole card shows the ability tooltip (everyone, players included).
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            hover = function(element)
                local tok = dmhub.GetCharacterById(selfInput.tokenid)
                if tok == nil or (not tok.valid) then
                    return
                end
                local args = {token = tok, width = 540}
                local dock = element:FindParentWithClass("dock")
                if dock ~= nil then
                    element.tooltipParent = dock
                    args.halign = dock.data.TooltipAlignment()
                end
                element.tooltip = CreateAbilityTooltip(ability, args)
            end,
            card,
        },
    }
end

--Every ability's resource payment funnels through ConsumeResources, so Malice is
--measured around it: what actually left the pool (squads, cost modifiers and the
--Monster-vs-Monster negative balance included) is what the card reports.
local g_baseConsumeResources = ActivatedAbility.ConsumeResources
function ActivatedAbility:ConsumeResources(casterToken, options)
    local maliceBefore = CharacterResource.GetMalice()
    g_baseConsumeResources(self, casterToken, options)

    if mod.unloaded then
        return
    end

    local spent = maliceBefore - CharacterResource.GetMalice()
    if spent > 0 then
        --a broken log card must never break the cast that paid for it.
        local ok, err = pcall(MaliceSpentChatMessage.Post, casterToken, self, spent)
        if not ok then
            print("MaliceSpentChatMessage:: post failed:", err)
        end
    end
end

function CharacterResource.GetVillainActions()
    return CharacterResource.GetGlobalResource(CharacterResource.villainActionId)
end

function CharacterResource.SetVillainActions(amount, note)
    CharacterResource.SetGlobalResource(CharacterResource.villainActionId, amount, note)
end

-- =====================================================================
-- VillainActionState: per-encounter tracking of which villain actions
-- have been consumed. Lives in a shared document so all clients see
-- the same state in real time. Reset on encounter start (hooked from
-- InitiativeQueue.Create in MCDMInitiativeQueue.lua).
--
-- Keys:
--   tokenid          - the charid of the Leader/Solo that owns the VA
--   villainActionKey - the ability's `villainAction` field value
--                      ("Villain Action 1" | "Villain Action 2" | ...)
-- =====================================================================
VillainActionState = {}
VillainActionState.docId = "dsVillainActions"

mod:RegisterDocumentForCheckpointBackups(VillainActionState.docId)

function VillainActionState.GetDocPath()
    return mod:GetDocumentPath(VillainActionState.docId)
end

function VillainActionState.HasUsed(tokenid, villainActionKey)
    if tokenid == nil or villainActionKey == nil then return false end
    local doc = mod:GetDocumentSnapshot(VillainActionState.docId)
    local used = doc.data.used
    if used == nil then return false end
    local entry = used[tokenid]
    if entry == nil then return false end
    return entry[villainActionKey] == true
end

function VillainActionState.MarkUsed(tokenid, villainActionKey)
    if tokenid == nil or villainActionKey == nil then return end
    local doc = mod:GetDocumentSnapshot(VillainActionState.docId)
    doc:BeginChange()
    if doc.data.used == nil then doc.data.used = {} end
    if doc.data.used[tokenid] == nil then doc.data.used[tokenid] = {} end
    doc.data.used[tokenid][villainActionKey] = true
    doc:CompleteChange("Villain Action used: " .. villainActionKey)
end

function VillainActionState.ClearUsed(tokenid, villainActionKey)
    if tokenid == nil or villainActionKey == nil then return end
    local doc = mod:GetDocumentSnapshot(VillainActionState.docId)
    if doc.data.used == nil or doc.data.used[tokenid] == nil then return end
    doc:BeginChange()
    doc.data.used[tokenid][villainActionKey] = nil
    doc:CompleteChange("Villain Action reset: " .. villainActionKey, {undoable = false})
end

function VillainActionState.ClearForToken(tokenid)
    if tokenid == nil then return end
    local doc = mod:GetDocumentSnapshot(VillainActionState.docId)
    if doc.data.used == nil or doc.data.used[tokenid] == nil then return end
    doc:BeginChange()
    doc.data.used[tokenid] = nil
    doc:CompleteChange("Villain Action state cleared for token", {undoable = false})
end

function VillainActionState.ResetAll()
    local doc = mod:GetDocumentSnapshot(VillainActionState.docId)
    if doc.data.used == nil then return end
    doc:BeginChange()
    doc.data.used = {}
    doc:CompleteChange("Villain Action state reset (new encounter)", {undoable = false})
end

function creature:GetHeroTokens()
    return 0
end

function character:GetHeroTokens()
    return CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
end

function creature:SetHeroTokens(amount, message)
    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, amount, message)
end

--- @return {color: string, when: string, who: string, value: number, note: string}
function creature:GetHeroTokenHistory()
    return CharacterResource.GetGlobalResourceHistory(CharacterResource.heroTokenId)
end

--Whether a creature has the named complication. pcall: Complications() is a
--hero-side method and a creature-typed monster may not carry it.
--- @param c creature|nil
--- @param name string
--- @return boolean
local function HasComplication(c, name)
    if c == nil then
        return false
    end
    local found = false
    pcall(function()
        for _, complication in ipairs(c:Complications()) do
            if complication.name == name then
                found = true
            end
        end
    end)
    return found
end

--Spend 1 Hero Token on a test re-roll or a saving throw. Lucky complication:
--"roll a d10. On a 6 or higher, you gain the benefit but don't spend the hero
--token." The token is taken now so the benefit never waits on the d10, and
--handed back if the d10 comes up 6+.
--Re-reads the pool rather than trusting an earlier check, so a token spent
--elsewhere in the meantime cannot take the pool negative.
--- @param c creature|nil the hero spending the token
--- @param note string the pool history entry
--- @return boolean paid
function CharacterResource.SpendHeroTokenForRoll(c, note)
    local tokens = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
    if tokens < 1 then
        return false
    end
    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, tokens - 1, note)

    if HasComplication(c, "Lucky") then
        ---@cast c creature
        dmhub.Roll{
            roll = "1d10",
            description = "Lucky",
            tokenid = dmhub.LookupTokenId(c),
            creature = c,
            complete = function(rollInfo)
                if (rollInfo.total or 0) < 6 then
                    return
                end
                local now = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
                CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, now + 1, "Lucky: Hero Token not spent")
                local send = rawget(_G, "SendTitledChatMessage")
                if send ~= nil then
                    send(string.format("%s's luck holds: the Hero Token is not spent.", c:try_get("name") or "The hero"), "Lucky", "#e0b84c")
                end
            end,
        }
    end

    return true
end

--Whether the test behind a finished roll was re-rolled with a Hero Token.
--HeroTokenTestRerollRule marks the roll's properties when it pays. Lucky's
--drawback reads this through the rollpower trigger's Hero Token Reroll symbol.
--- @param rollInfo any
--- @return boolean
function CharacterResource.RollUsedHeroTokenReroll(rollInfo)
    local used = false
    pcall(function()
        used = rollInfo.properties:try_get("heroTokenReroll", false) == true
    end)
    return used
end

--A hero may spend 1 Hero Token to re-roll a test, and must use the new roll --
--so one re-roll per test. Expressed as a roll-dialog re-roll rule (see the
--"Re-roll rules" block in DSRollDialog.lua): it replaces the dialog's free
--Re-roll button with a Hero Token one for the duration of that roll.
--RollDialog.GetDefaultRerollRule hands this to every test a hero makes; a roll
--can also ask for it by name via its own `rerollRule` option.
--- @return table
function CharacterResource.HeroTokenTestRerollRule()
    return {
        text = "Re-roll",
        icon = "drawsteel/hero-token.png",
        tooltip = "1 Hero Token: Re-roll. You must use the new roll.",
        maxRerolls = 1,
        spentTooltip = "You have already re-rolled this test. You must use the new roll.",

        CanReroll = function(state)
            if CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) < 1 then
                return false, "You have no Hero Tokens to spend."
            end
            return true
        end,

        --Also marks the roll as Hero-Token re-rolled for Lucky's drawback. The
        --roll's chat message keeps the properties uploaded with the first roll
        --and a re-roll does not refresh them, so upload the mark explicitly.
        Pay = function(state)
            if not CharacterResource.SpendHeroTokenForRoll(state.creature, "Re-rolled a test") then
                return false
            end
            local props = state.options ~= nil and state.options.rollProperties or nil
            if props ~= nil then
                props.heroTokenReroll = true
                if state.rollInfo ~= nil then
                    pcall(function() state.rollInfo:UploadProperties(props) end)
                end
            end
            return true
        end,
    }
end

--A hero may spend 1 Hero Token to succeed on a saving throw they failed. A
--re-roll rule (see "Re-roll rules" in DSRollDialog.lua) that takes over the
--roll dialog's Re-roll button only while the save on screen is a failure.
--  args.IsFailed(state) -> boolean  whether the save as rolled has failed.
--  args.Succeed(state)              called once the token is paid; makes the
--                                   save succeed and accepts the result.
--- @param args {IsFailed: (fun(state: table): boolean), Succeed: (fun(state: table))}
--- @return table
function CharacterResource.HeroTokenSaveSucceedRule(args)
    return {
        text = "Succeed Instead",
        fontSize = 16,
        icon = "drawsteel/hero-token.png",
        tooltip = "1 Hero Token: Succeed on this saving throw instead.",

        Applies = function(state)
            return args.IsFailed(state) and CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) >= 1
        end,

        CanReroll = function(state)
            if CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) < 1 then
                return false, "You have no Hero Tokens to spend."
            end
            return true
        end,

        Pay = function(state)
            return CharacterResource.SpendHeroTokenForRoll(state.creature, "Succeeded on a saving throw")
        end,

        Perform = function(state)
            args.Succeed(state)
        end,
    }
end

--- One way to spend Hero Tokens outside a roll (the roll-time spends are the
--- re-roll rules above).
--- @class HeroTokenSpendOption
--- @field id "surges"|"stamina"
--- @field text string menu caption, cost included
--- @field cost number Hero Tokens it takes from the pool
--- @field available boolean whether it can be bought right now
--- @field reason string|nil why not, when it can't
--- @field Spend fun(): boolean pays and applies it; false if it could not

--Report a pool change to analytics, the same event the character panel sends.
--- @param token CharacterToken
--- @param change number
--- @param source string
local function TrackHeroTokenSpend(token, change, source)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    local className = "unknown"
    pcall(function()
        if token.properties:IsHero() then
            local hero = token.properties --[[@as character]]
            local classInfo = hero:GetClass()
            if classInfo ~= nil then
                className = classInfo.name
            end
        end
    end)
    analytics.Event{
        type = "hero_token_change",
        userid = dmhub.userid,
        gameid = dmhub.gameid,
        version = dmhub.version,
        change = change,
        source = source,
        class = className,
        dailyLimit = 30,
    }
end

--The spends a hero can make from the party's Hero Token pool at will:
--  * 1 Hero Token: gain 2 surges (combat only; surges do not exist outside it).
--  * 2 Hero Tokens: regain Stamina equal to the Recovery value, without
--    spending a Recovery. The rules allow it "on your turn or when you take
--    damage"; only the on-your-turn half can be offered from a button.
--Under "Strictly Enforce Action Economy and Resource Costs" (strict:resources,
--which Encounter of the Week forces) only the spends the hero can make right
--now are listed: affordable, in combat, on the hero's own turn. Otherwise every
--spend is listed, the unusable ones with available = false and a reason, and
--the turn is not checked (the table polices it, as with the rest of the sheet).
--- @param token CharacterToken|nil the hero spending
--- @return HeroTokenSpendOption[]
function CharacterResource.HeroTokenSpendOptions(token)
    local result = {}
    if token == nil or not token.valid or token.properties == nil then
        return result
    end

    local c = token.properties
    local hero = c:IsHero()
    if not hero then
        pcall(function() hero = c:IsCompanion() end)
    end
    if not hero then
        return result
    end

    local strict = StrictActionEconomyEnforced()
    local pool = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
    local q = dmhub.initiativeQueue
    local inCombat = q ~= nil and not q.hidden

    --- @param option HeroTokenSpendOption
    local function Add(option)
        if option.available or not strict then
            result[#result+1] = option
        end
    end

    --The first reason the hero can't buy something costing `cost` right now.
    --- @param cost number
    --- @return string|nil
    local function CommonReason(cost)
        if pool < cost then
            return "not enough Hero Tokens"
        end
        if c:IsDead() then
            return "dead"
        end
        return nil
    end

    local surgeReason = CommonReason(1)
    if surgeReason == nil and not inCombat then
        surgeReason = "only in combat"
    end
    if surgeReason == nil and strict and not c:IsOurTurn() then
        surgeReason = "only on your turn"
    end
    Add{
        id = "surges",
        text = "Gain 2 Surges (1 Hero Token)",
        cost = 1,
        available = surgeReason == nil,
        reason = surgeReason,
        Spend = function()
            --not SpendHeroTokenForRoll: Lucky's refund covers saves and
            --re-rolls only. Re-read the pool, it may have moved since.
            local now = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
            if now < 1 then
                return false
            end
            CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, now - 1, "Gained 2 surges")
            token:ModifyProperties{
                description = "Spend Hero Token for Surges",
                execute = function()
                    --a negative consume is a gain, and follows the hero's
                    --surge sharing (a retainer's mentor, a summoner).
                    token.properties:ConsumeSurges(-2, "Hero Token")
                end,
            }
            TrackHeroTokenSpend(token, -1, "surges")
            return true
        end,
    }

    local amount = c:RecoveryAmount()
    local staminaReason = CommonReason(2)
    if staminaReason == nil and c:CurrentHitpoints() >= c:MaxHitpoints() then
        staminaReason = "already at full Stamina"
    end
    if staminaReason == nil and strict and not c:IsOurTurn() then
        staminaReason = "only on your turn"
    end
    Add{
        id = "stamina",
        text = string.format("Regain %d Stamina (2 Hero Tokens)", amount),
        cost = 2,
        available = staminaReason == nil,
        reason = staminaReason,
        Spend = function()
            local now = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)
            if now < 2 then
                return false
            end
            CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, now - 2, "Regained Stamina")
            token:ModifyProperties{
                description = "Spend Hero Tokens for Stamina",
                execute = function()
                    token.properties:Heal(token.properties:RecoveryAmount(), "Hero Tokens")
                end,
            }
            TrackHeroTokenSpend(token, -2, "stamina")
            return true
        end,
    }

    return result
end

--Context-menu entries for HeroTokenSpendOptions. Unusable spends (listed only
--outside strict mode) are greyed out with their reason in the caption, since a
--disabled menu row shows no tooltip.
--- @param token CharacterToken|nil
--- @param onSpend? fun() called after a spend goes through (e.g. close the menu)
--- @return ContextMenuEntry[]
function CharacterResource.HeroTokenSpendMenuEntries(token, onSpend)
    local entries = {}
    for _, option in ipairs(CharacterResource.HeroTokenSpendOptions(token)) do
        local text = option.text
        if not option.available and option.reason ~= nil then
            text = string.format("%s: %s", text, option.reason)
        end
        entries[#entries+1] = {
            text = text,
            icon = "drawsteel/hero-token.png",
            disabled = not option.available,
            click = function()
                option.Spend()
                if onSpend ~= nil then
                    onSpend()
                end
            end,
        }
    end
    return entries
end

function creature:GetEpicResources()
    local resources = self:try_get("resources")
    if resources ~= nil then
        local epicResource = resources[CharacterResource.epicResourceId]
        if epicResource ~= nil then
            return epicResource.unbounded or 0
        end
    end
    return 0
end

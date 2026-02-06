local mod = dmhub.GetModLoading()

local g_animateTiers = setting{
    id = "animate_tiers",
    description = "Animate Power Table During Rolls",
    default = true,
    editor = "check",
    section = "General",
    storage = "preference",
}

--register the ability to modify power roll damage during spell casting.
ActivatedAbilityModifyCastBehavior.RegisterParam{
    id = "ability_damage",
    text = "Ability Damage",
}

ActivatedAbilityModifyCastBehavior.RegisterParam{
    id = "ability_boon",
    text = "Number of Edges",
}

ActivatedAbilityModifyCastBehavior.RegisterParam{
    id = "ability_bane",
    text = "Number of Banes",
}

ActivatedAbilityModifyCastBehavior.RegisterParam{
    id = "ability_surges",
    text = "Number of Surges",
}

ActivatedAbilityModifyCastBehavior.RegisterParam{
    id = "ability_ignore_immunity",
    text = "Ignore Damage Immunity",
}


--- @class ActivatedAbilityModifyPowerRollBehavior : ActivatedAbilityBehavior
ActivatedAbilityPowerRollBehavior = RegisterGameType("ActivatedAbilityPowerRollBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityPowerRollBehavior.summary = 'Roll on Power Table'
ActivatedAbilityPowerRollBehavior.rule = ''


function ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(edges, banes)
    edges = edges or 0
    banes = banes or 0

    local bonus = 0
    if banes == 0 then
        if edges == 1 then
            bonus = 2
        end
    elseif edges == 0 then
        if banes == 1 then
            bonus = -2
        end
    elseif edges > banes then
        bonus = 2
    elseif edges < banes then
        bonus = -2
    else
        bonus = 2*math.max(-1, math.min(1, edges - banes))
    end

    return bonus
end


local function FormatTierText(text, skipValidation)
    if not skipValidation then
        text = ActivatedAbilityDrawSteelCommandBehavior.FormatRuleValidation(text)
    end
    local damageGroups = regex.MatchGroups(text, "^(?<damage>[0-9]+).*?damage")
    if damageGroups ~= nil then
        text = string.format("<b>%s</b>%s", damageGroups.damage, string.sub(text, string.len(damageGroups.damage)+1))
    end

    text = MarkdownDocument.FormatRichText(text, {player = not dmhub.isDM})

    return text
end

local function BoonsAndBanesToMod(boons, banes)
    if boons >= 2 and banes == 0 then
        return 0
    elseif banes >= 2 and boons == 0 then
        return 0
    end

    if boons > 0 and banes > 0 then
        if boons > banes then
            return 2
        elseif boons < banes then
            return -2
        else
            return 0
        end
    end

    return (min(2, boons) - min(2, banes))*2
end

--result has {total = number, boons = nil|number, banes = nil|number, autosuccess = bool?, autofailure = bool?, nottierone = bool?, nottierthree = bool?, tiers = nil|number}
local function DiceResultToTier(result)
    if result.autosuccess then
        return 3
    end

    if result.autofailure then
        return 1
    end

    local tier = 1
    if result.total >= 17 then
        tier = 3
    elseif result.total >= 12 then
        tier = 2
    end

    if (result.boons or 0) >= 2 and (result.banes or 0) == 0 then
        tier = tier + 1
    elseif (result.banes or 0) >= 2 and (result.boons or 0) == 0 then
        tier = tier - 1
    end

    tier = tier + (result.tiers or 0)
    if tier > 3 then
        tier = 3
    elseif tier < 1 then
        tier = 1
    end

    if tier == 3 and result.nottierthree then
        tier = 2
    end

    if tier == 1 and result.nottierone then
        tier = 2
    end

    return tier
end

local g_TierNames = GameSystem.TierNames

ActivatedAbilityPowerRollBehavior.tierNames = g_TierNames

ActivatedAbility.RegisterType
{
    id = 'power_roll',
    text = 'Ability Power Roll',
    createBehavior = function()
        return ActivatedAbilityPowerRollBehavior.new{
            tiers = {"", "", ""},
            roll = "2d10 + Might or Agility",
        }
    end,
}

function ActivatedAbilityPowerRollBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Ability Power Roll"
end

--if we have targets, the actual tier should be equal to one of the tiers found among the targets.
--- @param tier number
--- @param multitargets nil|({token: CharacterToken, tier: number}[])
--- @return number
local function NormalizeTierBasedOnMultitargets(tier, multitargets)
    if multitargets == nil or #multitargets == 0 then
        return tier
    end

    for _,target in ipairs(multitargets) do
        if target.tier == tier then
            return tier
        end
    end

    return multitargets[1].tier
end

--- @return nil|({token: CharacterToken, tier: number}[])
local function CalculateMultitargetsFromRollProperties(rollMessage, rollResult)

    rollResult = rollResult or rollMessage

    if not rollMessage.properties:has_key("multitargets") then
        return nil
    end

    local multitargets = {}
    for i,target in ipairs(rollMessage.properties.multitargets) do
        if target.tokenid then
            local rollInfo = {
                total = rollResult.total,
                boons = rollResult.boons,
                banes = rollResult.banes,
                autosuccess = rollResult.autosuccess,
                autofailure = rollResult.autofailure,
                nottierone = rollResult.nottierone,
                nottierthree = rollResult.nottierthree,
                tiers = rollResult.tiers,
            }

            --the multitargets give boons relative to the base roll, so we apply any different in boons.
            if (target.boons or 0) ~= 0 or (target.banes or 0) ~= 0 then

                local baseBonusFromBoonsAndBanes = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(rollInfo.boons, rollInfo.banes)

                rollInfo.boons = math.min(rollInfo.boons + target.boons, 2)
                rollInfo.banes = math.min(rollInfo.banes + (target.banes or 0), 2)

                local targetBonusFromBoonsAndBanes = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(rollInfo.boons, rollInfo.banes)

                rollInfo.total = rollInfo.total + (targetBonusFromBoonsAndBanes - baseBonusFromBoonsAndBanes)
            end

            local tier = rollMessage.properties:try_get("overrideTier") or DiceResultToTier(rollInfo)

            multitargets[#multitargets+1] = {
                token = dmhub.GetCharacterById(target.tokenid),
                tier = tier,
            }
        end
    end
    return multitargets
end

--- Note: rollProperties MAY be a typed object, or just a raw table.
ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom = function(rollProperties, caster, options)

    local m_fullyImplemented = false
    if (options ~= nil and options.ability ~= nil) then
        m_fullyImplemented = options.ability:try_get("implementation", 1) == 3
    end

    if rollProperties ~= nil and rawget(rollProperties, "fullyImplemented") then
        m_fullyImplemented = true
    end

    return function(parentPanel)
        local m_diceFaces = {}
        local m_numDice = 0
        local m_endTime = nil
        local m_mod = 0
        local m_rollInfo
        local m_rollInfoKey
        local m_finished = false
        local m_tierFinished = nil
        local m_multitargetResults = nil
        local tbl = gui.Table{
            width = "100%",
            height = "auto",
            flow = "vertical",
            styles = {
                {
                    selectors = {"row", "highlight"},
                    bgcolor = Styles.textColor,
                },
                {
                    selectors = {"label", "highlight"},
                    color = "black",
                },
                {
                    selectors = {"row", "flash"},
                    brightness = 3,
                    transitionTime = 1,
                },
                {
                    selectors = {"row", "selectable", "hover"},
                    bgcolor = "#ff7777",
                    brightness = 2,
                    transitionTime = 0.1,
                }
            },
            think = function(element)
                if m_rollInfo ~= nil then
                    --check if we have an update to the message.

                    local message
                    for _,msg in ipairs(chat.messages) do
                        if msg.key == m_rollInfoKey then
                            message = msg
                            break
                        end
                    end

                    if message ~= nil then
                        m_rollInfo = message

                        local tier = DiceResultToTier(m_rollInfo)

                        tier = m_rollInfo.properties:try_get("overrideTier") or tier

                        local multitargetsChanged = false
                        local multitargets = nil
                        if m_finished then
                            multitargets = CalculateMultitargetsFromRollProperties(m_rollInfo)
                            tier = NormalizeTierBasedOnMultitargets(tier, multitargets)
                            if multitargets ~= nil and m_multitargetResults ~= nil then
                                if #multitargets ~= #m_multitargetResults then
                                    multitargetsChanged = true
                                else
                                    for i=1,#multitargets do
                                        if multitargets[i].token.charid ~= m_multitargetResults[i].token.charid or multitargets[i].tier ~= m_multitargetResults[i].tier then
                                            multitargetsChanged = true
                                        end
                                    end
                                end
                            elseif multitargets ~= nil then
                                multitargetsChanged = true
                            end

                            m_multitargetResults = multitargets
                        end

                        if m_tierFinished ~= nil and (tier ~= m_tierFinished or multitargetsChanged) then
                            m_tierFinished = tier
                            element:FireEventTree("tier", m_tierFinished, true, multitargets)
                        end
                    end
                end

                if m_endTime ~= nil and dmhub.Time() > m_endTime then
                    element:FireEvent("diceend")
                    m_endTime = nil
                    m_finished = true

                    local tier = DiceResultToTier(m_rollInfo)

                    local multitargets = CalculateMultitargetsFromRollProperties(m_rollInfo, nil)
                    tier = NormalizeTierBasedOnMultitargets(tier, multitargets)

                    tier = m_rollInfo.properties:try_get("overrideTier") or tier

                    m_tierFinished = tier
                    element:FireEventTree("tier", tier, true, multitargets)


                    local critEligible = false
                    if options.ability ~= nil then
                        critEligible = options.ability:HasKeyword("Strike") or options.ability:IsAction()
                    end

                    local eventName = string.format("UI.PowerRoll_Tier%d", tier)
                    if critEligible and m_rollInfo.naturalRoll == 19 or m_rollInfo.naturalRoll == 20 then
                        eventName = "UI.PowerRoll_Crit"
                    end

                    audio.DispatchSoundEvent(eventName)
                end
            end,

            recalculatedMultiTargets = function(element, multiTargets, rollProperties)
                if not m_finished then
                    return
                end

                local message
                for _,msg in ipairs(chat.messages) do
                    if msg.key == m_rollInfoKey then
                        message = msg
                        break
                    end
                end

                if message ~= nil then
                    message:UploadProperties(rollProperties)
                end
            end,

            beginRoll = function(element, rollInfo, rollid)

                m_diceFaces = {}
                m_numDice = 0
                m_endTime = nil
                m_finished = false
                m_tierFinished = nil

                element.thinkTime = 0.1
                m_rollInfo = rollInfo
                m_rollInfoKey = rollid
                m_mod = rollInfo.total
                for _,roll in ipairs(rollInfo.rolls) do
                    m_mod = m_mod - roll.result
					local events = chat.DiceEvents(roll.guid)
					if events ~= nil then
						events:Listen(element)
                        m_numDice = m_numDice + 1
					end
                end

                if #rollInfo.rolls == 0 then
                    element:FireEvent("diceface", "none", 0, 0)
                end
            end,
            diceend = function(element)
            end,

            diceface = function(element, diceguid, num, timeRemaining)
                if m_finished then
                    return
                end

                local endTime = dmhub.Time() + timeRemaining
                m_diceFaces[diceguid] = num
                if m_endTime == nil or endTime > m_endTime then
                    m_endTime = endTime
                end

                local total = m_mod
                local count = 0
                for _,value in pairs(m_diceFaces) do
                    count = count + 1
                    total = total + value
                end

                if count == m_numDice then
                    local tier = DiceResultToTier{
                        total = total,
                        boons = m_rollInfo.surges,
                        banes = m_rollInfo.shields,
                        autofailure = m_rollInfo.autofailure,
                        autosuccess = m_rollInfo.autosuccess,
                        nottierone = m_rollInfo.nottierone,
                        nottierthree = m_rollInfo.nottierthree,
                        tiers = m_rollInfo.tiers,
                    }

                    element:FireEventTree("tier", tier)
                end
            end,
        }

        local children = {}
        for i=1,#g_TierNames do
            local tier = g_TierNames[i]
            local tierText = rollProperties.tiers[i]
            print("TIER:: tierText =", tierText)

            if caster ~= nil then
                tierText = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(caster, tierText, nil, m_fullyImplemented)
            end

            local row = gui.TableRow{
                width = "100%",
                height = "auto",
                press = function(element)
                    if (not element:HasClass("selectable")) or element:HasClass("highlight") then
                        return
                    end

                    m_tierFinished = i
                    rollProperties.overrideTier = i
                    rollProperties.overrideMessage = string.format("%s overrode the result", dmhub.userDisplayName)
                    m_rollInfo:UploadProperties(rollProperties)

                    element.parent:FireEventTree("tier", i, true)
                end,
                tier = function(element, tierNumber, finish, multitargets)
                    if (not finish) and (not g_animateTiers:Get()) then
                        return
                    end
                    if finish then
                        element:FireEventTree("finishRoll", tierNumber)
                    end
                    element:SetClassTree("highlight", tierNumber == i)
                    if tierNumber == i and finish then
                        element:PulseClass("flash")
                    end

                    if finish then
                        element:SetClass("selectable", true)
                    end
                end,
                gui.Label{ hpad = 0, textAlignment = "left", fontFace = "DrawSteelGlyphs", text = string.format("%d", i), width = "16%", fontSize = 34, height = 20, valign = "center", },
                gui.Panel{
                    vpad = 2,
                    width = "54%",
                    halign = "left",
                    height = "auto",
                    valign = "center",
                    hpad = 0,
                    gui.Label{
                        text = FormatTierText(tierText, m_fullyImplemented),
                        fontSize = 15,
                        width = 500,
                        height = "auto",
                        vpad = 0,
                        refreshMods = function(element)
                            local tierText = rollProperties.tiers[i]
                            if caster ~= nil then
                                tierText = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(caster, tierText, nil, m_fullyImplemented)
                            end
                            element.text = FormatTierText(tierText, m_fullyImplemented)
                        end,
                        finishRoll = function(element, tierNumber)
                            if i >= tierNumber then
                                rollProperties.tiers[i] = string.gsub(rollProperties.tiers[i], "{#", "{!")
                            end
                        end,
                    },
                },

                gui.Panel{
                    vpad = 4,
                    width = "17%",
                    height = "auto",
                    halign = "right",
                    valign = "center",
                    flow = "horizontal",
                    wrap = true,
                    tier = function(element, tierNumber, finish, multitargets)
                        if multitargets == nil then
                            element.children = {}
                        end

                        local children = {}

                        for _,target in ipairs(multitargets or {}) do
                            if target.tier == i then
                                children[#children+1] = gui.CreateTokenImage(target.token, {
                                    width = 32,
                                    height = 32,
                                    halign = "right",
                                    valign = "center",
                                    bgcolor = "white",
                                })
                            end
                        end

                        element.children = children
                    end,
                },
            }

            children[#children+1] = row
        end

        tbl.children = children

        

        parentPanel.children = {tbl}
    end
end

function ActivatedAbility:HasPotency()
    for i,behavior in ipairs(self.behaviors) do
        if behavior:HasPotency() then
            return true
        end
    end

    return false
end

function ActivatedAbilityBehavior:HasPotency()
end

function ActivatedAbilityPowerRollBehavior:HasPotency()
    local pattern = "\\b[a-zA-Z]\\s*<\\s*([0-9]+|weak|average|strong)"
    for _,tier in ipairs(self.tiers) do
        if regex.MatchGroups(tier, pattern) ~= nil then
            return true
        end
    end

    return false
end

RegisterGoblinScriptSymbol(ActivatedAbility, {
	name = "Has Potency",
	type = "boolean",
	desc = "Whether this ability includes potency.",
	examples = {"Ability has Potency"},
	calculate = function(c)
        return c:HasPotency()
	end,
})


--placed here for easy reference. Tells us if a generic melee free strike
--would have banes applied to it.
--- @param targetToken CharacterToken
--- @return boolean
function creature:HasBanesOnGenericFreeStrike(targetToken)
    local modifiersOnCaster = self:GetActiveModifiers()
    local ability = MCDMUtils.GetStandardAbility("Generic Opportunity Attack")

    local roll = "2d10"
    local targetCreature = targetToken.properties

    for _,mod in ipairs(modifiersOnCaster) do
        local m = mod.mod:DescribeModifyPowerRoll(mod, self, "ability_power_roll", {ability = ability, caster = self, target = targetCreature, attribute = self:try_get("attrid"), skills = {self:try_get("skillid")}})

        if m ~= nil and m.modifier.name ~= "Cover" then
            m.hint = m.modifier:HintModifyPowerRolls(mod, self, "ability_power_roll", {
                ability = ability,
                target = targetCreature,
                --attribute = self:try_get("attrid"),
                --skills = {self:try_get("skillid")}
            })
            if m.hint ~= nil and m.hint.result then
                roll = m.modifier:ModifyPowerRolls(mod, self, "ability_power_roll", roll, {
                    ability = ability,
                    target = targetCreature,
                })
            end
        end

    end

    local modifiersOnTarget = targetCreature:GetActiveModifiers()
    for _,mod in ipairs(modifiersOnTarget) do
        local m = mod.mod:DescribeModifyPowerRoll(mod, targetCreature, "enemy_ability_power_roll", {ability = ability, caster = self, target = targetCreature})

        if m ~= nil then
            m.hint = m.modifier:HintModifyPowerRolls(mod, self, "enemy_ability_power_roll", {
                ability = ability,
                target = targetCreature,
                --attribute = self:try_get("attrid"),
                --skills = {self:try_get("skillid")}
            })
            if m.hint ~= nil and m.hint.result then
                roll = m.modifier:ModifyPowerRolls(mod, self, "enemy_ability_power_roll", roll, {
                    ability = ability,
                    target = targetCreature,
                })
            end
        end
    end

    return string.find(string.lower(roll), "bane") ~= nil
end


local g_activeRoll = nil --the active roll object of the roll we are currently doing.
local g_activeRollPanel = nil --the panel showing the roll that is currently active.

function ActivatedAbilityPowerRollBehavior:Cast(ability, casterToken, targets, options)


    if #targets == 0 then
        --don't roll if there are no targets.
        return
    end

    local rollType = cond(self:try_get("isTest"), "test_power_roll", "ability_power_roll")

    if self:try_get("resistanceRoll", false) then
        return self:CastResistance(ability, casterToken, targets, options)
    end

    local caster = casterToken.properties
    local roll = dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols), "Power table roll")

	local modifiersApplied = nil
    local appliedTargetCreature = nil

    local modifiersOnCaster = caster:GetActiveModifiers()

    if rollType == "ability_power_roll" then
        local paramModifications = options.symbols.cast:GetParamModifications("ability_damage")

        for _,damageMod in ipairs(paramModifications) do
            local mod = CharacterModifier.new{
                behavior = "power",
                rollType = "ability_power_roll",
                activationCondition = true,
                keywords = {},
                modtype = "none",
                guid = dmhub.GenerateGuid(),
                name = damageMod.name,
                description = damageMod.description,
                damageModifier = damageMod.value,
            }

            modifiersOnCaster[#modifiersOnCaster+1] = {
                mod = mod,
            }
        end

        local paramSurges = options.symbols.cast:GetParamModifications("ability_surges")
        for _,surgeMod in ipairs(paramSurges) do
            local mod = CharacterModifier.new{
                behavior = "power",
                rollType = "ability_power_roll",
                activationCondition = true,
                keywords = {},
                modtype = "none",
                guid = dmhub.GenerateGuid(),
                name = surgeMod.name,
                description = surgeMod.description,
                surges = surgeMod.value,
                damageModifier = 0,
            }

            modifiersOnCaster[#modifiersOnCaster+1] = {
                mod = mod,
            }
        end

        for i,boonbane in ipairs({"ability_boon", "ability_bane"}) do
            local mult = cond(i == 1, 1, -1)

            local paramModifications = options.symbols.cast:GetParamModifications(boonbane)
            for _,boonMod in ipairs(paramModifications) do
                local modtype = "none"
                for _,option in ipairs(ActivatedAbilityPowerRollBehavior.s_modificationTypes) do
                    if option.value == boonMod.value*mult then
                        modtype = option.id
                    end
                end

                local mod = CharacterModifier.new{
                    behavior = "power",
                    rollType = "ability_power_roll",
                    activationCondition = true,
                    keywords = {},
                    modtype = modtype,
                    guid = dmhub.GenerateGuid(),
                    name = boonMod.name,
                    description = boonMod.description,
                    damageModifier = 0,
                }

                modifiersOnCaster[#modifiersOnCaster+1] = {
                    mod = mod,
                }
            end
        end

        --our behavior-builtin modifiers
        for _,modInfo in ipairs(self:try_get("modifiers", {})) do
            local mod = CharacterModifier.new{
                behavior = "power",
                rollType = "ability_power_roll",
                activationCondition = modInfo.condition,
                keywords = {},
                modtype = modInfo.type,
                guid = dmhub.GenerateGuid(),
                name = modInfo.text,
                description = modInfo.details,
            }

            modifiersOnCaster[#modifiersOnCaster+1] = {
                mod = mod,
            }
        end
    end


    for _,behavior in ipairs(ability.behaviors) do
        if behavior.typeName == "ActivatedAbilityModifyPowerRollBehavior" and behavior:IsFiltered(ability, casterToken, options) == false then
            local filterCondition = trim(behavior.modifier:try_get("filterCondition", ""))
            if filterCondition == "" or dmhub.EvalGoblinScript(filterCondition, caster:LookupSymbol(options.symbols), "Filter condition for power roll modifier") then
                modifiersOnCaster[#modifiersOnCaster+1] = {
                    mod = behavior.modifier,
                }
            end
        end
    end

    local multitargetsByTokenId = {}

    local multitargets = {}

    local baseBoons = nil
    local baseBanes = nil

    local CalculateMultitargets = function()
        while #multitargets > 0 do
            table.remove(multitargets, #multitargets)
        end

        --respect any target redirecting occurring.
        for i,target in ipairs(targets or {}) do
            targets[i] = options.symbols.cast:RedirectTarget(target)
        end

        for i,target in ipairs(targets or {}) do
            if target.token == nil then
                goto continue
            end
            local cached = multitargetsByTokenId[target.token.charid]
            if cached ~= nil then
                --this target has already been processed.
                multitargets[#multitargets+1] = cached
                goto continue
            end

            local boons = 0
            local banes = 0
            local targetCreature = target.token.properties

            if appliedTargetCreature == nil then
                appliedTargetCreature = targetCreature
            end

            local modifiersOnTarget = {}
            
            if target.token.charid ~= casterToken.charid then
                --if this is not the caster, we need to check for modifiers on the target.
                modifiersOnTarget = targetCreature:GetActiveModifiers()
            end

            local candidateModifiers = {}

            --the attacker's modifiers.
            for _,mod in ipairs(modifiersOnCaster) do
                local m = mod.mod:DescribeModifyPowerRoll(mod, caster, rollType, {ability = ability, caster = caster, target = targetCreature, attribute = self:try_get("attrid"), skills = {self:try_get("skillid")}})
                if m ~= nil then
                    if options.symbols ~= nil then
                        m.modifier:InstallSymbolsFromContext(options.symbols)
                    end

                    m.hint = m.modifier:HintModifyPowerRolls(mod, caster, rollType, {
                        ability = ability,
                        target = targetCreature,
                        attribute = self:try_get("attrid"),
                        skills = {self:try_get("skillid")}
                    })
                    if m.hint ~= nil then
                        candidateModifiers[#candidateModifiers+1] = m
                    end
                end
            end

            --the defender's modifiers.
            for _,mod in ipairs(modifiersOnTarget) do
                --this is run from the defender's perspective.
                local m = mod.mod:DescribeModifyPowerRoll(mod, targetCreature, "enemy_ability_power_roll", {ability = ability, caster = caster, target = targetCreature})
                if m ~= nil then
                    if options.symbols ~= nil then
                        m.modifier:InstallSymbolsFromContext(options.symbols)
                    end

                    --this is told from the caster's perspective.
                    m.hint = m.modifier:HintModifyPowerRolls(mod, caster, "enemy_ability_power_roll", {
                        ability = ability,
                        target = targetCreature,
                    })

                    if m.hint ~= nil then
                        candidateModifiers[#candidateModifiers+1] = m
                    end
                end
            end

            --modifiers from attached triggers.
            --HACK: For now attached triggers are only used for non-primary targets.
            --work out a way to control which targets attached triggers are used for when
            --we have attached triggers that need to be used for different purposes.
            if options.attachedTriggers ~= nil and i > 1 then
                for _,trigger in ipairs(options.attachedTriggers) do
                    if trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier then
                        candidateModifiers[#candidateModifiers+1] = {
                            modifier = trigger.powerRollModifier.powerRollModifier,
                            context = {
                                mod = trigger.powerRollModifier.powerRollModifier,
                            },
                            hint = {
                                result = true,
                                justification = {},
                            }
                        }
                    end
                end
            end

            --if we are attacking as part of a minion squad signature, any excess targeting
            --gets to do free strikes against the targets.
            if options.symbols.targetPairs ~= nil and ability.categorization == "Signature Ability" and casterToken.properties.minion then
                local numAttackers = 0

                for i,pair in ipairs(options.symbols.targetPairs) do
                    if pair.b == target.token.charid then
                        numAttackers = numAttackers + 1
                    end
                end

                if numAttackers > 1 then

                    local mod = CharacterModifier.new{
                        behavior = "power",
                        rollType = "ability_power_roll",
                        activationCondition = true,
                        keywords = {},
                        modtype = "none",
                        guid = dmhub.GenerateGuid(),
                        name = cond(numAttackers-1 == 1, "Extra Attacker", "Extra Attackers"),
                        description = string.format("There %s %d extra minion attacker%s, each of which does free strike against the target.", cond(numAttackers-1 == 1, "is", "are"), numAttackers-1, cond(numAttackers-1 > 1, "s", "")),
                        damageModifier = casterToken.properties:OpportunityAttack()*(numAttackers-1),
                    }
                    
                    candidateModifiers[#candidateModifiers+1] = {
                        modifier = mod,
                        hint = mod:HintModifyPowerRolls(mod, caster, "ability_power_roll", {
                            ability = ability,
                            target = targetCreature,
                        })
                    }

                end
            end



            local candidateRoll = roll
            for _,mod in ipairs(candidateModifiers) do
                if mod.hint ~= nil and mod.hint.result then
                    candidateRoll = mod.modifier:ModifyPowerRolls(mod.context, caster, "ability_power_roll", candidateRoll, {
                        ability = ability,
                        target = targetCreature,
                    })
                end
            end

            local rollInfo = dmhub.ParseRoll(candidateRoll)

            candidateModifiers = DeepCopy(candidateModifiers)

            if modifiersApplied == nil then
                modifiersApplied = candidateModifiers
                if baseBoons == nil then
                    baseBoons = boons
                end
                if baseBanes == nil then
                    baseBanes = banes
                end
            end


            multitargets[#multitargets+1] = {
                token = target.token,
                boons = boons - baseBoons,
                banes = banes - baseBanes,
                modifiers = candidateModifiers,
                triggers = {},
            }

            multitargetsByTokenId[target.token.charid] = multitargets[#multitargets]

            ::continue::

        end

        return multitargets
    end

    CalculateMultitargets()

    if rollType == "test_power_roll" then
        local skillid = self:try_get("skillid", "none")
        local skill = dmhub.GetTable(Skill.tableName)[skillid]
        if skill ~= nil and caster:ProficientInSkill(skill) then
            for _,mod in ipairs(modifiersApplied) do
                if mod.modifier.name == "Skilled" then
                    mod.hint.result = true
                end
            end
        end
    end




    local m_result = {
        total = nil,
        boons = nil,
        banes = nil,
    }

    local m_canceled = false

    local tiers = DeepCopy(self.tiers)
    if ability.description ~= "" and ability.effectImplemented == false and ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(ability.description) == true then
        --append the rule to the tiers if it is a valid rule that could
        --appear on a power roll.
        for i=1,#tiers do
            tiers[i] = trim(tiers[i])
            if string.ends_with(tiers[i], ".") then
                tiers[i] = trim(string.sub(tiers[i], 1, string.len(tiers[i])-1))
            end
            tiers[i] = string.format("%s; %s", tiers[i], ability.description)
        end
    end

    for i,tier in ipairs(tiers) do
        tiers[i] = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(caster, tiers[i], nil, ability:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze)
    end

    local multitargetProperties = nil

    local rollProperties = RollPropertiesPowerTable.new{
        tiers = tiers,
    }

    for _,token in ipairs(dmhub.allTokens) do
        for _,mod in ipairs(token.properties:GetActiveModifiers()) do
            for _,target in ipairs(multitargets) do
                if target.token ~= nil then
                    mod.mod:TriggerModsPowerRoll(mod, token, casterToken, target.token, ability, rollProperties, target.triggers, options)
                end
            end
        end
    end

    for _,target in ipairs(multitargets) do
        table.sort(target.triggers, function(a,b) return cond(a.hostile, 1, 0) < cond(b.hostile, 1, 0) end)
    end

    local m_rollInfo = nil

    local rollKey
    rollKey = GameHud.instance.rollDialog.data.ShowDialog{
        description = ability.name .. ": Power Roll",
        title = ability.name,
        type = "ability_power_roll",
        ability = ability,
        roll = roll,
        showDialogDuringRoll = true,
        amendable = true,
        modifiers = modifiersApplied,
        multitargets = multitargets,
        RecalculateMultitargets = CalculateMultitargets,
        creature = caster,
        targetCreature = appliedTargetCreature,
        symbols = options.symbols,

        rollProperties = rollProperties,

        PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(rollProperties, caster, {
            ability = ability,
        }),

        rollActive = function(activeRoll)
            g_activeRoll = activeRoll
        end,

        beginRoll = function(rollInfo)
            if #targets > 0 and targets[1].token ~= nil and ability.keywords["Strike"] and ability.keywords["Melee"] then

                local damage = 5
                local tier = DiceResultToTier(rollInfo)
                local command = rollProperties.tiers[tier]

                local damageMatch = regex.MatchGroups(roll, "(?<damage>[0-9]+).*?damage")
                if damageMatch ~= nil then
                    damage = tonumber(damageMatch.damage)
                end

                local outcome = "Hit"
                if tier == 1 then
                    outcome = "Block"
                elseif tier == 3 then
                    outcome = "Critical"
                end
               --[[]
                casterToken:AnimateAttack{
                    targetid = targets[1].token.charid,
                    rollid = "none",
                    damage = damage,
                    outcome = outcome,
                }]]
            end
        end,

        completeRoll = function(rollInfo)
            m_rollInfo = rollInfo
            m_result = {
                total = rollInfo.total,
                boons = rollInfo.boons,
                banes = rollInfo.banes,
                tiers = rollInfo.tiers,
                nottierone = rollInfo.nottierone,
                nottierthree = rollInfo.nottierthree,
                autofailure = rollInfo.autofailure,
                autosuccess = rollInfo.autosuccess,
            }
            options.symbols.cast.boonsApplied = rollInfo.boons
            options.symbols.cast.banesApplied = rollInfo.banes
            options.symbols.cast.casterid = casterToken.id
        end,

        cancelRoll = function()
            m_canceled = true
        end,
    }

    local holdOpenRefreshAt = nil
    local refreshAtPanel = nil

    while m_canceled == false and m_result.total == nil do
        coroutine.yield(0.1)

        if g_activeRollPanel ~= nil and g_activeRollPanel.valid and g_activeRoll.guid == rollKey and dmhub.HoldAmendableRollOpen ~= nil and dmhub.HoldAmendableRollOpen() and (holdOpenRefreshAt == nil or holdOpenRefreshAt < dmhub.Time()-2) then
            holdOpenRefreshAt = dmhub.Time()
            refreshAtPanel = g_activeRollPanel
            g_activeRollPanel:FireEvent("recordInteracting")
        elseif refreshAtPanel ~= nil and refreshAtPanel.valid and (not dmhub.HoldAmendableRollOpen()) then
            refreshAtPanel:FireEvent("clearInteracting")
            refreshAtPanel = nil
            holdOpenRefreshAt = nil
        end
    end

    if refreshAtPanel ~= nil and refreshAtPanel.valid then
        refreshAtPanel:FireEvent("clearInteracting")
    end

    if m_canceled then
        options.abort = true
        return
    end

    --Allow modifiers to modify the casting of the power roll.
    --Limited to cost changes
    for _, mod in ipairs(modifiersApplied or {}) do
        mod.modifier:ModifyPowerRollCasting(mod.context, caster, ability, options)
    end

    ability:CommitToPaying(casterToken, options)

    if ability.keywords["Strike"] then
        --trigger the attack trigger when attacking.

        for _,target in ipairs(targets or {}) do
            local targetToken = target.token
            if targetToken ~= nil then
                local args = {
                    outcome = string.format("tier%d", rollProperties:try_get("overrideTier") or DiceResultToTier(m_result)),
                    degree = rollProperties:try_get("overrideTier") or DiceResultToTier(m_result),
                    target = GenerateSymbols(targetToken.properties),
                    ability = GenerateSymbols(ability),
                }

                casterToken.properties:TriggerEvent("attack", args)
            end
        end
    end

    --handle any targets that have had the target altered.
    if targets ~= nil then
        for i=1,#targets do
            targets[i] = options.symbols.cast:RedirectTarget(targets[i])
        end
    end

    local multitargetResults = CalculateMultitargetsFromRollProperties(m_rollInfo, m_result)

    local triggerInfo = {
        surges = 0,
        tierone = false,
        tiertwo = false,
        tierthree = false,
    }

    local highestTier = 0
    local casterCommand = nil

    local promptWhenResolving = self:try_get("promptWhenResolving", false)

    local targetChoices = {}
    if promptWhenResolving then
        for _,target in ipairs(targets or {}) do
            local targetToken = target.token
            targetChoices[#targetChoices+1] = targetToken
        end
    end

    repeat

        if promptWhenResolving then

            print("ChooseTarget:: prompting...")
            targets = nil
            GameHud.instance.actionBarPanel:FireEventTree("chooseTargetToken", {
                sourceToken = casterToken,
                targets = table.shallow_copy(targetChoices),
                prompt = self:try_get("promptWhenResolvingText", "Choose Target"),
                choose = function(targetToken)
                    print("ChooseTarget:: chosen")
                    targets = {
                        {
                            token = targetToken,
                        }
                    }

                    for i=1,#targetChoices do
                        if targetChoices[i].charid == targetToken.charid then
                            table.remove(targetChoices, i)
                            break
                        end
                    end
                end,
                cancel = function()
                    targets = {}
                    targetChoices = {}
                end,
            })

            while targets == nil do
                coroutine.yield(0.1)
            end
        end

        for numTarget,target in ipairs(targets or {}) do

            local targetToken = target.token
            local tier = rollProperties:try_get("overrideTier") or DiceResultToTier(m_result)
            local modifiersUsed = rollProperties:try_get("modifiersUsed", {})

            if targetToken ~= nil then
                if rollProperties:try_get("tierSuppressed") then
                    --this means that the caster is 'silenced' and results based on tier won't apply.
                    options.symbols.cast:SetTierResult(targetToken, -1)
                else
                    options.symbols.cast:SetTierResult(targetToken, tier)
                end
            end

            local targetRollProperties = rollProperties

            options.symbols.cast.total = m_result.total

            if targetToken ~= nil then
                if multitargetResults ~= nil then
                    for i,multitarget in ipairs(multitargetResults) do
                        if multitarget.token.charid == targetToken.charid then
                            tier = multitarget.tier
                            if multitargets[i].rollProperties ~= nil then
                                targetRollProperties = multitargets[i].rollProperties
                            end
                            break
                        end
                    end
                end

                local command = targetRollProperties.tiers[tier]

                local surges = 0
                local potencyApplied = 0
                if m_rollInfo.properties ~= nil and m_rollInfo.properties:try_get("multitargets") ~= nil and m_rollInfo.properties.multitargets[numTarget] ~= nil then
                    surges = m_rollInfo.properties.multitargets[numTarget].surges or 0

                    --Check modifiers actually applied to roll for this target
                    for _, mod in ipairs(m_rollInfo.properties.multitargets[numTarget].modifiersUsed or {}) do
                        potencyApplied = potencyApplied + mod:try_get("potencymod", 0)
                    end

                    options.symbols.cast:SetPotencyApplied(targetToken, potencyApplied)
                end

                options.surges = surges
                triggerInfo.surges = triggerInfo.surges + surges
                triggerInfo.tierone = triggerInfo.tierone or tier == 1
                triggerInfo.tiertwo = triggerInfo.tiertwo or tier == 2
                triggerInfo.tierthree = triggerInfo.tierthree or tier == 3


                triggerInfo.keywords = StringSet.new{
                    strings = table.keys(ability.keywords)
                }

                local casterTokenForCommand = casterToken


                options.powerRollPass = "target"

                --if we have targetPairs that indicate a minion squad attack with a different caster,
                --we substitute the casterToken.
                if options.symbols.targetPairs ~= nil then
                    for i, pair in ipairs(options.symbols.targetPairs) do
                        if pair.b == targetToken.charid then
                            local attackerTok = dmhub.GetTokenById(pair.a)
                            if attackerTok ~= nil then
                                casterTokenForCommand = attackerTok
                                options.powerRollPass = nil
                            end
                        end
                    end
                end

                ability.RecordTokenMessage(targetToken, options, string.format("Tier %d (%s)", tier, command))

                print("Execute::", command)
                self:ExecuteCommand(ability, casterTokenForCommand, targetToken, options, command)
                print("Execute:: DONE", command)

                if tier > highestTier and options.powerRollPass == "target" then
                    highestTier = tier
                    casterCommand = function ()
                        options.powerRollPass = "caster"
                        self:ExecuteCommand(ability, casterTokenForCommand, targetToken, options, command)
                    end
                end
            end
        end
    until promptWhenResolving == false or #targetChoices == 0

    --execute any per-caster tier commands.
    if casterCommand ~= nil then
        casterCommand()
    end

    options.powerRollPass = nil

    triggerInfo.naturalroll = m_rollInfo.naturalRoll

    triggerInfo.ability = ability

    casterToken.properties:DispatchEvent("rollpower", triggerInfo)

    casterToken.properties:ClearMomentaryOngoingEffects()
    for _,target in ipairs(multitargets) do
        if target.token ~= nil and target.token.valid then
            target.token.properties:ClearMomentaryOngoingEffects()
        end
    end

end

ActivatedAbilityPowerRollBehavior.ExecuteCommand = ActivatedAbilityDrawSteelCommandBehavior.ExecuteCommand
ActivatedAbilityPowerRollBehavior.ExecuteCommandInternal = ActivatedAbilityDrawSteelCommandBehavior.ExecuteCommandInternal

ActivatedAbilityPowerRollBehavior.s_modificationTypes = {
{text = "None", id = "none", mod = "", value = 0, hideText = true},
{text = "Edge", id = "edge", mod = "1 edge", value = 1},
{text = "Double Edge", id = "double_edge", mod = "2 edge", value = 2},
{text = "Bane", id = "bane", mod = "1 bane", value = -1},
{text = "Double Bane", id = "double_bane", mod = "2 banes", value = -2},
{text = "Edge becomes Bane", id = "edge_bane", mod = "1 bane", value = -2, remove_edge = true},
{text = "Bane becomes Edge", id = "bane_edge", mod = "1 edge", value = 2, remove_bane = true},
{text = "Bane becomes Double Edge", id = "bane_double_edge", mod = "2 edges", value = 4, remove_bane = true},
{text = "Remove Edge", id = "remove_edge", mod = "", value = -1, remove_edge = true, lateness = 100},
{text = "Remove Bane", id = "remove_bane", mod = "", value = 1, remove_bane = true, lateness = 100},
{text = "Ignore Edges", id = "ignore_edges", mod = "", value = -2, ignore_edges = true, lateness = 100},
{text = "Ignore Banes", id = "ignore_banes", mod = "", value = 2, ignore_banes = true, lateness = 100},
{text = "Tier 3", id = "tier3", mod = "autosuccess", value = 0},
{text = "Tier 1", id = "tier1", mod = "autofailure", value = 0},
{text = "Not Tier 3", id = "nottierthree", mod = "nottierthree", value = 0},
{text = "Not Tier 1", id = "nottierone", mod = "nottierone", value = 0},
{text = "Tier Up", id = "tierup", mod = "tierup", value = 0},
{text = "Tier Down", id = "tierdown", mod = "tierdown", value = 0},
{text = "+1", id = "plusone", mod = "+1", value = 1},
{text = "+2", id = "plustwo", mod = "+2", value = 2},
{text = "+3", id = "plusthree", mod = "+3", value = 3},
{text = "-1", id = "minusone", mod = "-1", value = -1},
{text = "-2", id = "minustwo", mod = "-2", value = -2},
{text = "-3", id = "minusthree", mod = "-3", value = -3},
{text = "-3", id = "minusthree", mod = "-3", value = -3},
{text = "Suppress Effects", id = "suppresseffects", mod = "suppresseffects", value = -3},
{text = "Append to Roll", id = "appendroll", hideText = true},
{text = "Replace Roll", id = "replaceroll", hideText = true},
}

ActivatedAbilityPowerRollBehavior.s_modificationTypesById = {}

local g_modificationIdToText = {}
for _,option in ipairs(ActivatedAbilityPowerRollBehavior.s_modificationTypes) do
    g_modificationIdToText[option.id] = option.text
    ActivatedAbilityPowerRollBehavior.s_modificationTypesById[option.id] = option
end

function ActivatedAbilityBehavior:GetPowerRollDisplay()
    return nil
end

function ActivatedAbilityPowerRollBehavior:GetPowerRollDisplay()
    local roll = self.roll
    return string.gsub(roll, "2d10", "<b>Power Roll</b>")
end

function ActivatedAbility:GetPowerRollDisplay()
    for _,behavior in ipairs(self.behaviors) do
        local result = behavior:GetPowerRollDisplay()
        if result ~= nil then
            return result
        end
    end

    return ""
end

function ActivatedAbilityPowerRollBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    local rollPanel = gui.Panel{
        classes = {"formPanel", cond(self:try_get("resistanceRoll", false), "collapsed")},
        gui.Label{
            classes = {"formLabel"},
            text = "Roll:",
        },

        gui.GoblinScriptInput{
            halign = "right",
            value = self.roll,
            events = {
                change = function(element)
                    self.roll = element.value
                end,
            },

			documentation = {
				help = string.format("This GoblinScript determines the roll to use for the power table."),
				output = "roll",
				examples = {
					{
						script = "2d10 + Might or Agility",
						text = "2d10 + Might or Agility is used for the roll. Whichever is higher out of Might or Agility will be used.",
					},
					{
						script = "2d10 + 4",
						text = "2d10 + 4 is used for the roll.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is casting the spell.",
				symbols = ActivatedAbility.helpCasting,
			},
        },
    }

    local testPanel
    local resistanceTypePanel

    local rollType = "ability"
    if self:try_get("resistanceRoll", false) then
        rollType = "resistance"
    elseif self:try_get("isTest", false) then
        rollType = "test"
    end
    local rollTypeDropdown = gui.Dropdown{
        options = {
            {id = "ability", text = "Ability"},
            {id = "test", text = "Test"},
            {id = "resistance", text = "Reactive Test"},
        },
        idChosen = rollType,
        change = function(element)
            self.isTest = (element.idChosen == "test")
            self.resistanceRoll = (element.idChosen == "resistance")
            rollPanel:SetClass("collapsed", self:try_get("resistanceRoll", false))
            resistanceTypePanel:SetClass("collapsed", not self:try_get("resistanceRoll", false))
            testPanel:SetClass("collapsed", not self:try_get("isTest", false))
        end,
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Roll Type:",
        },
        rollTypeDropdown,
    }

    local skillOptions = {
        {
            id = "none",
            text = "None",
        }
    }

    local skillsTable = dmhub.GetTable(Skill.tableName)
    for k,skill in pairs(skillsTable) do
        skillOptions[#skillOptions+1] = {
            id = skill.id,
            text = skill.name,
        }
    end

    testPanel = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        classes = {cond(self:try_get("isTest", false), nil, "collapsed")},

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Characteristic:",
            },

            gui.Dropdown{
                classes = {"formDropdown"},
                options = creature.attributeDropdownOptionsWithNone,
                idChosen = self:try_get("attrid", "none"),
                change = function(element)
                    self.attrid = element.idChosen
                end,
            },
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Skill:",
            },

            gui.Dropdown{
                classes = {"formDropdown"},
                options = skillOptions,
                sort = true,
                hasSearch = true,
                idChosen = self:try_get("skillid", "none"),
                change = function(element)
                    self.skillid = element.idChosen
                end,
            },
        },

    }

    result[#result+1] = testPanel

    resistanceTypePanel = gui.Panel{
        classes = {"formPanel", cond(self:try_get("resistanceRoll", false), nil, "collapsed")},

        gui.Label{
            classes = {"formLabel"},
            text = "Attribute:",
        },

        gui.Dropdown{
            classes = {"formDropdown"},
            idChosen = self:ResistanceAttr(),
            options = creature.attributeDropdownOptions,
            change = function(element)
                self.resistanceAttr = element.idChosen
            end,
        },
    }

    result[#result+1] = resistanceTypePanel

    result[#result+1] = rollPanel

    result[#result+1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        create = function(element)
            if #element.children == 1 and self:has_key("modifiers") then
                element:FireEvent("refreshBehavior")
            end
        end,

        refreshBehavior = function(element)
            local children = {}
            for i,modifier in ipairs(self:try_get("modifiers", {})) do
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        width = 120,
                        text = g_modificationIdToText[modifier.type],
                        lmargin = 20,
                    },

                    gui.GoblinScriptInput{
                        halign = "right",
                        width = 300,
                        value = modifier.condition,
                        events = {
                            change = function(element)
                                modifier.condition = element.value
                            end,
                        },

                        documentation = {
                            help = string.format("This GoblinScript determines whether the modifier will apply."),
                            output = "boolean",
                            examples = {
                                {
                                    script = "Might > 4",
                                    text = "The modifier will apply if the caster's Might is greater than 4.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature that is casting the ability.",
                            symbols = ActivatedAbility.helpCasting,
                        },

                    },

                    gui.DeleteItemButton{
                        width = 12,
                        height = 12,
                        hmargin = 8,
                        click = function(element)
                            local modifiers = self:try_get("modifiers", {})
                            table.remove(modifiers, i)
                            parentPanel:FireEvent("refreshBehavior")
                        end,
                    },
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        width = 120,
                        text = "Name:",
                        lmargin = 20,
                    },
                    gui.Input{
                        width = 280,
                        fontSize = 14,
                        hmargin = 0,
                        text = modifier.text,
                        characterLimit = 80,
                        change = function(element)
                            modifier.text = element.text
                        end,
                    }
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        width = 120,
                        text = "Details:",
                        lmargin = 20,
                    },
                    gui.Input{
                        width = 280,
                        fontSize = 14,
                        hmargin = 0,
                        text = modifier.details,
                        characterLimit = 240,
                        change = function(element)
                            modifier.details = element.text
                        end,
                    }
                }

            end

            children[#children+1] = element.children[#element.children]

            element.children = children
        end,

        gui.Panel{
            classes = {"formPanel"},

            gui.Dropdown{
                textOverride = "Add Modifier...",
                classes = {"formDropdown"},

                options = {
                    {text = "Edge", id = "edge"},
                    {text = "Double Edge", id = "double_edge"},
                    {text = "Bane", id = "bane"},
                    {text = "Double Bane", id = "double_bane"},
                },
                idChosen = "none",
                change = function(element)
                    local modifiers = self:get_or_add("modifiers", {})
                    modifiers[#modifiers+1] = {
                        type = element.idChosen,
                        condition = "",
                        text = "",
                    }

                    parentPanel:FireEvent("refreshBehavior")
                end,
            }
        },
    }

    local rows = {}

    for i=1,#g_TierNames do
        local tier = g_TierNames[i]
        rows[#rows+1] = gui.TableRow{
            gui.Label{ text = tier },
            gui.Input{
                text = self.tiers[i],
                characterLimit = 160,
                halign = "right",
                change = function(element)
                    self.tiers[i] = element.text
                end
            },
        }
    end

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Table{
            width = 400,
            height = "auto",
            flow = "vertical",
            minHeight = 30,
            halign = "left",
            styles = {
                Styles.Table,
                {
                    classes = {"input"},
                    width = 300,
                },

            },

            children = rows,
        }
    }

    result[#result+1] = gui.Check{
        text = "Prompt When Resolving",
        value = self:try_get("promptWhenResolving", false),
        change = function(element)
            self.promptWhenResolving = element.value
            parentPanel:FireEvent("refreshBehavior")
        end,
    }

    if self:try_get("promptWhenResolving", false) then
        result[#result+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Prompt:",
            },
            gui.Input{
                classes = {"formInput"},
                text = self:try_get("promptWhenResolvingText", ""),
                placeholderText = "Choose Target",
                characterLimit = 240,
                change = function(element)
                    self.promptWhenResolvingText = element.text
                end
            }
        }
    end


    return result
end

function RollProperties:GetSymbols(rollInfo, targetCreature)
    return nil
end

RegisterGameType("RollPropertiesPowerTable", "RollProperties")

RegisterGameType("TierSymbols")

TierSymbols.tier = ""

TierSymbols.lookupSymbols = {
	debuginfo = function(c)
		return "TIER: " .. c.tier
	end,

    includesforcedmovement = function(c)
        local match = regex.MatchGroups(c.tier, "(push|pull|slide) +(?<value>[0-9]+)")
        return match ~= nil
    end,

    push = function(c)
        local match = regex.MatchGroups(c.tier, "push +(?<value>[0-9]+)")
        return (match ~= nil and tonumber(match.value)) or 0
    end,
    pull = function(c)
        local match = regex.MatchGroups(c.tier, "pull +(?<value>[0-9]+)")
        return (match ~= nil and tonumber(match.value)) or 0
    end,
    slide = function(c)
        local match = regex.MatchGroups(c.tier, "slide +(?<value>[0-9]+)")
        return (match ~= nil and tonumber(match.value)) or 0
    end,
}

function RollPropertiesPowerTable:GetSymbols(rollInfo, targetCreature)
    local multitargets = CalculateMultitargetsFromRollProperties(rollInfo)
    local token = dmhub.LookupToken(targetCreature)
    if token == nil or multitargets == nil then
        return nil
    end

    for i,entry in ipairs(multitargets) do
        if entry.token.charid == token.charid then
            local tier = self.tiers[entry.tier]
            return GenerateSymbols(TierSymbols.new{tier = tier})
        end
    end
end

function RollPropertiesPowerTable:HasDamage()
    for i,tier in ipairs(self.tiers) do
        local match = regex.MatchGroups(tier, "(?<damage>\\d+)\\s+([a-zA-Z]+\\s+)?damage", {indexes = true})
        if match ~= nil then
            return true
        end
    end

    return false
end

function RollPropertiesPowerTable:GetDamageTypes()
    local result = {}
    for i,tier in ipairs(self.tiers) do
        local match = regex.MatchGroups(tier, "(?<damage>\\d+)\\s+(?<type>[a-zA-Z]+\\s+)?damage")
        if match ~= nil then
            local t = string.lower(match.type or "untyped")
            if not table.contains(result, t) then
                result[#result+1] = t
            end
        end
    end


    if #result == 0 then
        return nil
    end

    return result
end

function RollPropertiesPowerTable:HasForcedMovement()
    for _,tier in ipairs(self.tiers) do
        local t = string.lower(tier)
        if string.find(t, "%f[%w]push%f[%W]") or string.find(t, "%f[%w]pull%f[%W]") or string.find(t, "%f[%w]slide%f[%W]") then
            return true
        end
    end

    return false
end

function RollPropertiesPowerTable:ResetMods()
    self.surges = nil
    self.shields = nil
    self.tierSuppressed = nil
    if self:has_key("baseTiers") == false then
        self.baseTiers = DeepCopy(self.tiers)
    else
        self.tiers = DeepCopy(self.baseTiers)
    end
end

function RollPropertiesPowerTable:GetOutcome(rollInfo)
    local tier = DiceResultToTier(rollInfo)
    return {
        outcome = string.format("Tier %d", tier),
        color = "white",
    }
end

--@param delta number
--@return nil
function RollPropertiesPowerTable:ModifyDamage(damage)
    if damage == 0 then
        return
    end

    for i,tier in ipairs(self.tiers) do
        --account for damage dice possibility as well as damage type.
        local match = regex.MatchGroups(tier, "(?<damage>\\d+)\\s+(\\+\\s*\\d+d\\d+\\s+)?([a-zA-Z]+\\s+)?damage", {indexes = true})
        if match ~= nil then
            local index = match.damage.index
            local length = match.damage.length

            local before = string.sub(tier, 1, index-1)
            local after = string.sub(tier, index+length)

            local damageValue = round(tonumber(match.damage.value))
            damageValue = max(0, round(damageValue + damage))

            local valueBefore = self.tiers[i]
            self.tiers[i] = string.format("%s%d%s", before, damageValue, after)
        end
    end
end

--Add damage of a specific type to all tiers
--@param damage number The amount of damage to add
--@param damageType string The type of damage (e.g., "fire", "cold", "untyped")
function RollPropertiesPowerTable:ModifyDamageWithType(damage, damageType)
    if damage == 0 then
        return
    end
    
    damageType = damageType or "untyped"
    
    for i, tier in ipairs(self.tiers) do
        -- First, try to find existing damage of the same type and add to it
        local pattern = "(?<damage>\\d+)\\s+" .. damageType .. "\\s+damage"
        local match = regex.MatchGroups(tier, pattern, {indexes = true})
        
        if match ~= nil then
            -- Found existing damage of this type, add to it
            local index = match.damage.index
            local length = match.damage.length
            
            local before = string.sub(tier, 1, index-1)
            local after = string.sub(tier, index+length)
            
            local damageValue = round(tonumber(match.damage.value))
            damageValue = max(0, round(damageValue + damage))
            
            self.tiers[i] = string.format("%s%d%s", before, damageValue, after)
        else
            -- No existing damage of this type found, append new damage
            local extraDamage = string.format("%d %s damage", damage, damageType)
            extraDamage = trim(extraDamage)
            
            -- Try to find any existing damage and place after it
            local anyDamageMatch = regex.MatchGroups(tier, "^(?<prefix>.*?)(?<damage>\\d+\\s+([a-zA-Z]+\\s+)?damage)(?<suffix>.*)$")
            if anyDamageMatch ~= nil then
                self.tiers[i] = string.format("%s%s; %s%s", anyDamageMatch.prefix, anyDamageMatch.damage, extraDamage, anyDamageMatch.suffix)
            else
                -- Just put damage at the front
                self.tiers[i] = string.format("%s; %s", extraDamage, tier)
            end
        end
    end
end

local g_tableStyles = {
    gui.Style{
        selectors = {"label"},
        color = "#cccccc",
        valign = "center",
    },
    gui.Style{
        selectors = {"row", "highlighted"},
        transitionTime = 1.0,
        bgcolor = Styles.textColor,
    },
    gui.Style{
        selectors = {"label", "parent:highlighted"},
        transitionTime = 1.0,
        color = "black",
    },
	gui.Style{
		selectors = {"row", "flash"},
		brightness = 3,
		transitionTime = 0.3,
	},
    gui.Style{
        selectors = {"label", "parent:collapsedAnim"},
        transitionTime = 0.5,
        uiscale = {x = 1, y = 0.001},
    },
    gui.Style{
        selectors = {"amendable", "row", "hover"},
        bgcolor = "#ff7777",
    },
}

local g_boonsBanesStyles = {
    gui.Style{
        selectors = {"collapsedAnim"},
        transitionTime = 0.5,
        uiscale = {x = 1, y = 0.001},
    },
    gui.Style{
        selectors = {"label"},
        color = Styles.textColor,
        valign = "center",
        width = "20%",
        height = "100%",
        bgimage = "panels/square.png",
        fontSize = 16,
        textAlignment = "center",
        borderWidth = 1,
        borderColor = Styles.textColor,
    },
    gui.Style{
        selectors = {"label", "selected"},
        bgcolor = Styles.textColor,
        color = "black",
        bold = true,
    },
    gui.Style{
        selectors = {"label", "hover", "~selected", "parent:active"},
        bgcolor = Styles.textColor,
        color = "black",
        brightness = 0.9,
    },
}

local g_RollModifierStyles = {
    gui.Style{
        selectors = {"modifierPanel"},
        bgcolor = "#888888",
    },
    gui.Style{
        selectors = {"modifierPanel", "~good", "~bad"},
        gradient = Styles.dialogGradient,
    },
    gui.Style{
        selectors = {"modifierPanel", "good"},
        gradient = Styles.healthGradient,
    },
    gui.Style{
        selectors = {"modifierPanel", "bad"},
        gradient = Styles.bloodiedGradient,
    },
}

local g_boonsLabels = {"Bane x 2", "Bane", "None", "Edge", "Edge x 2"}

function RollPropertiesPowerTable:CustomPanel(message)

    local m_resultPanel = nil

    local messageGuid = message.key

    local m_endAt = {}

    local m_activeAmendableRoll = false

    local m_rows = nil

    local m_lastKnownTotal = nil

    local m_listening = {}
    local m_mod = 0
    local m_complete = false

    local m_boons = 0
    local m_banes = 0
    local m_tiers = 0

    local m_multitargetPanels = {}
    local m_selectedMultitarget = 1
    local m_multitargetsPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        flow = "horizontal",
        height = "auto",

        refreshRollInfo = function(element, rollInfo)
            if rollInfo.properties ~= nil and rollInfo.properties:has_key("multitargetsDISABLED") then
                element:SetClass("collapsed", false)
                local multitargets = rollInfo.properties.multitargets

                for i, target in ipairs(multitargets) do
                    if m_multitargetPanels[i] == nil and target.tokenid then
                        local targetToken = dmhub.LookupToken(target.tokenid)
                        if targetToken ~= nil then
                            m_multitargetPanels[i] = gui.CreateTokenImage(targetToken, {
                                width = 24,
                                height = 24,
                            })
                        end
                    end

                    local targetPanel = gui.Panel{
                        classes = {"multitarget"},
                        width = "100%",
                        height = "auto",
                    }

                    m_multitargetPanels[#m_multitargetPanels+1] = targetPanel
                end

            else
                element:SetClass("collapsed", true)
            end
        end,
    }

    local m_boonsBanesPanel = nil
    local boonsBanesLabels = nil

    if not message.isComplete then
        boonsBanesLabels = {}
        for i,text in ipairs(g_boonsLabels) do
            boonsBanesLabels[#boonsBanesLabels+1] = gui.Label{
                text = text,
                fontSize = 14,

                press = function(element)
                    local isActive = g_activeRoll ~= nil and g_activeRoll.amendable and g_activeRoll.guid == messageGuid
                    if isActive  then
                        local oldMod = BoonsAndBanesToMod(m_boons, m_banes)
                        local currentValue = m_boons - m_banes

                        if m_boons > 0 and m_banes > 0 then
                            if m_boons > m_banes then
                                currentValue = 1
                            elseif m_banes > m_boons then
                                currentValue = -1
                            end
                        end

                        local newValue = i - 3

                        local delta = newValue - currentValue
                        if delta ~= 0 then
                            if delta < 0 then
                                m_banes = m_banes - delta
                            else
                                m_boons = m_boons + delta
                            end

                            if m_banes > 2 then
                                m_boons = m_boons - (m_banes - 2)
                                m_banes = 2
                            end

                            if m_boons > 2 then
                                m_banes = m_banes - (m_boons - 2)
                                m_boons = 2
                            end

                            g_activeRoll = g_activeRoll:Amend{
                                categories = {},
                                amendable = true,
                                boons = m_boons,
                                banes = m_banes,
                            }
                            messageGuid = g_activeRoll.guid

                            if m_lastKnownTotal ~= nil then
                                local newMod = BoonsAndBanesToMod(m_boons, m_banes)

                                local total = m_lastKnownTotal + newMod - oldMod

                                local index = self:try_get("overrideTier") or DiceResultToTier{ total = total, boons = m_boons, banes = m_banes, tiers = m_tiers }
                                if m_rows ~= nil then
                                    for i,row in ipairs(m_rows) do
                                        if row ~=nil and row.valid then
                                            row:SetClassImmediate("highlighted", i == index)
                                        end
                                    end
                                end
                            end

                        end
                    end

                end,
            }
        end

        m_boonsBanesPanel = gui.Panel{
            styles = g_boonsBanesStyles,
            classes = {"boonbanePanel"},
            width = "100%",
            height = 22,
            flow = "horizontal",
            children = boonsBanesLabels,

            collapse = function(element)
                element:SetClass("collapsedAnim", true)
                element:ScheduleEvent("die", 0.5)
                m_boonsBanesPanel = nil
                boonsBanesLabels = nil
            end,

            die = function(element)
                element:DestroySelf()
            end,
        }
    end

    local m_diceFinished = false

    local tbl = gui.Table{
        width = "100%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        styles = {
            Styles.Table,
            g_tableStyles,
        },

        recordInteracting = function(element)
            message:UploadRealtimeInteraction(dmhub.userid, { guid = dmhub.GenerateGuid(), message = dmhub.userDisplayName .. " is reviewing the roll", timestamp = dmhub.serverTime })
        end,

        clearInteracting = function(element)
            message:UploadRealtimeInteraction(dmhub.userid, nil)
        end,

		refreshInfo = function(element, info, diceStyle, complete, rollInfo)
            m_multitargetsPanel:FireEvent("refreshRollInfo", rollInfo)
            if m_complete then
                return
            end

            local isActive = g_activeRoll ~= nil and g_activeRoll.amendable and g_activeRoll.guid == messageGuid

            m_tiers = info.tiers or 0
            m_boons = info.boons or 0
            m_banes = info.banes or 0

            if boonsBanesLabels ~= nil then
                local selectedIndex = 3 + m_boons - m_banes
                if m_boons > 0 and m_banes > 0 then
                    if m_boons > m_banes then
                        selectedIndex = 4
                    elseif m_banes > m_boons then
                        selectedIndex = 2
                    end
                end
                for i,label in ipairs(boonsBanesLabels) do
                    label:SetClassImmediate("selected", i == selectedIndex)
                end
                m_boonsBanesPanel:SetClass("active", isActive)
            end

            local refreshAmendable = false
            if m_activeAmendableRoll ~= isActive then
                m_activeAmendableRoll = isActive
                refreshAmendable = true

                --make the active roll panel point at this, to record the panel that is doing the roll.
                if isActive then
                    g_activeRollPanel = element
                elseif g_activeRollPanel == element then
                    g_activeRollPanel = nil
                end
            end

            if m_rows == nil then
                m_rows = {}

                m_lastKnownTotal = info.total
                local index = self:try_get("overrideTier") or DiceResultToTier(rollInfo)

                for i, tier in ipairs(self.tiers) do
                    if index == i or (not complete) then
                        m_rows[#m_rows+1] = gui.TableRow{
                            height = "auto",
                            gui.Label{ text = g_TierNames[i], width = 90, height = "auto", },
                            gui.Label{
                                text = FormatTierText(tier),
                                width = 240,
                                height = "auto",
                                refreshTiers = function(element)
                                    element.text = FormatTierText(self.tiers[i])
                                end,
                                revealTier = function(element)
                                    local text = self.tiers[i]
                                    text = string.gsub(text, "{#", "{!")
                                    self.tiers[i] = text
                                    element:FireEvent("refreshTiers")
                                end,
                            },
                            width = "100%",
                            press = function(element)
                                if element:HasClass("amendable") then
                                    self.overrideTier = i
                                    self.overrideMessage = string.format("%s overrode the result", dmhub.userDisplayName)
                                    message:UploadProperties(self)

                                    for j,row in ipairs(m_rows) do
                                        if row ~=nil and row.valid then
                                            row:SetClassImmediate("highlighted", i == j)
                                        end
                                    end
                                end
                            end,
                            collapse = function(element)
                                element:FireEvent("remove")
                                element:SetClass("collapsedAnim", true)
                                element:ScheduleEvent("destroy", 0.5)
                            end,
                            fade = function(element)
                                element:SetClass("highlighted", false)
                            end,
                            destroy = function(element)
                                element:FireEvent("remove")
                                element:DestroySelf()
                            end,
                            remove = function(element)
                                for i,row in ipairs(m_rows) do
                                    if row == element then
                                        table.remove(m_rows, i)
                                    end
                                end
                            end,
                        }

                        if complete then
                            m_rows[#m_rows]:FireEventTree("revealTier")
                        end
                    end
                end

                element.children = m_rows
            end

            element:FireEventTree("refreshTiers")


            m_mod = info.mod or 0

            if complete or m_diceFinished then
                m_complete = complete
                m_lastKnownTotal = info.total
                local index = self:try_get("overrideTier") or DiceResultToTier(rollInfo)
                if self:has_key("overrideTier") == false then
                    local multitargets = CalculateMultitargetsFromRollProperties(rollInfo)
                    index = NormalizeTierBasedOnMultitargets(index, multitargets)
                end

                if #m_rows == 3 then
                    for i,row in ipairs(m_rows) do
                        if row ~= nil and row.valid then
                            row:SetClassImmediate("highlighted", i == index)
                            if complete then
                                if i <= index then
                                    row:FireEventTree("revealTier")
                                end
                                if i == index then
                                    row:PulseClass("flash")
                                    row:ScheduleEvent("fade", 3)
                                else
                                    row:ScheduleEvent("collapse", 1)
                                end
                            end
                        end
                    end
                end

                if complete and m_boonsBanesPanel ~= nil then
                    m_boonsBanesPanel:ScheduleEvent("collapse", 1)
                end

                if complete then
                    for k,v in pairs(m_listening) do
                        local events = chat.DiceEvents(k)
                        if events ~= nil then
                            events:Unlisten(element)
                        end
                    end
                end
            elseif not m_complete then

                if #info.rolls == 0 then
                    local total = m_mod
                    local index = DiceResultToTier{ total = total, boons = m_boons, banes = m_banes, tiers = m_tiers }
                    for i,row in ipairs(m_rows) do
                        if row ~=nil and row.valid then
                            row:SetClassImmediate("highlighted", i == index)
                        end
                    end
                end

                for i,roll in ipairs(info.rolls) do
                    if roll.guid ~= nil and roll.guid ~= '' and m_listening[roll.guid] == nil and (not roll.dropped) then
                        m_listening[roll.guid] = true

						local events = chat.DiceEvents(roll.guid)
						if events ~= nil then
							events:Listen(element)
						end
                    end
                end
            end

            if refreshAmendable then
                element:SetClassTree("amendable", m_activeAmendableRoll)
            end
        end,

        diceend = function(element)
            m_diceFinished = true
            element:FireEventOnParents("forceShowResult")
        end,

		diceface = function(element, diceguid, num, timeRemaining)

            if m_complete or self:has_key("overrideTier") then
                return
            end
            
            if m_endAt ~= nil then
                local endAt = dmhub.Time() + timeRemaining
                m_endAt[diceguid] = endAt
                local count = 0
                for k,v in pairs(m_endAt) do
                    count = count + 1
                    if m_endAt[diceguid] > endAt then
                        endAt = m_endAt[diceguid]
                    end
                end

                if count == 2 then
                    m_endAt = nil
                    element:ScheduleEvent("diceend", endAt - dmhub.Time())
                end
            end

            m_listening[diceguid] = num

            local total = m_mod
            for k,v in pairs(m_listening) do
                if type(v) == "number" then
                    total = total + v
                end
            end

            m_lastKnownTotal = total

            if not g_animateTiers:Get() then
                return
            end

            local index = DiceResultToTier{ total = total, boons = m_boons, banes = m_banes, tiers = m_tiers }
            for i,row in ipairs(m_rows) do
                if row ~=nil and row.valid then
                    row:SetClassImmediate("highlighted", i == index)
                end
            end
        end,
    }

    local m_modifiersPanelCache = {}
    local m_modifiersPanel = gui.Panel{
        classes = {"collapsed-anim"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        vmargin = 2,
		refreshInfo = function(element, info, diceStyle, complete, rollInfo)
            if complete then
                element:SetClass("collapsed-anim", true)
                m_modifiersPanelCache = {}
                return
            end

            local newCache = {}
            local children = {}
            local counts = {}

            for _,target in ipairs(rollInfo.properties:try_get("multitargets", {})) do
                for _,modifier in ipairs(target.modifiersUsed or {}) do
                    if rawget(modifier, "guid") == nil then
                        print("COULD NOT FIND GUID FOR MODIFIER", json(modifier))
                        return
                    end
                    local key = modifier.name .. "-" .. modifier.guid
                    if modifier:HasRenderOnRoll() and counts[key] == nil then
                        counts[key] = (counts[key] or 0) + 1

                        --if this modifier is associated with a trigger,
                        --then fish out the information about the trigger and pass it also.
                        local triggerInfo = nil
                        for _,trigger in ipairs(target.triggers or {}) do
							if trigger.triggered and trigger.modifier.powerRollModifier.guid == modifier.guid then
                                triggerInfo = trigger
                                break
                            end
                        end

                        local panel = m_modifiersPanelCache[key] or gui.Panel{
                            styles = g_RollModifierStyles,
                            classes = {"modifierPanel"},
                            width = 60,
                            height = 40,
                            bgimage = true,
                            borderColor = "white",
                            borderWidth = 1,
                            cornerRadius = 4,
                            hmargin = 2,
                            halign = "left",
                        }

                        newCache[key] = panel

                        modifier:RenderOnRoll(rollInfo, triggerInfo, panel)

                        children[#children+1] = panel
                    end
                end
            end

            m_modifiersPanelCache = newCache

            element.children = children
            element:SetClass("collapsed-anim", #children == 0)
        end,
    }

    local m_label = nil
    local m_showingInteraction = false

    m_resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
		refreshInfo = function(element, info, diceStyle, complete, rollInfo)

            m_modifiersPanel:FireEvent("refreshInfo", info, diceStyle, complete, rollInfo)

            tbl:FireEvent("refreshInfo", info, diceStyle, complete, rollInfo)

            local text = self:try_get("overrideMessage")

            if text ~= nil then
                m_showingInteraction = false
            else
                local interactions = message.realtimeInteractions
                if interactions ~= nil or m_showingInteraction then
                    if complete or interactions == nil then
                        text = nil
                        m_showingInteraction = false
                    else
                        local mostRecent = nil
                        for k,v in pairs(interactions) do
                            if mostRecent == nil or mostRecent.timestamp < v.timestamp then
                                mostRecent = v
                            end
                        end

                        if mostRecent ~= nil and mostRecent.timestamp < dmhub.serverTime - 5 then
                            mostRecent = nil
                        end

                        if mostRecent ~= nil then
                            text = mostRecent.message
                            m_showingInteraction = true
                        else
                            m_showingInteraction = false
                        end
                    end
                end
            end


            if text ~= nil then
                if m_label == nil then
                    m_label = gui.Label{
                        color = Styles.textColor,
                        width = "100%",
                        height = "auto",
                        fontSize = 16,
                        text = text,
                        
                        data = {
                            interacting = false,
                            text = "",
                            count = 0,
                        },

                        updateLabel = function(element, text, interacting)
                            element.data.text = text
                            if interacting ~= element.data.interacting or interacting == false then
                                element.text = text
                            end
                            element.data.interacting = interacting
                            if interacting then
                                element.thinkTime = 0.5
                            else
                                element.thinkTime = nil
                            end
                        end,

                        think = function(element)
                            element.data.count = element.data.count + 1
                            local text = element.data.text
                            for i=1,element.data.count%4 do
                                text = text .. "."
                            end

                            element.text = text
                        end,
                    }
                    local items = {m_label}
                    for _,child in ipairs(element.children) do
                        items[#items+1] = child
                    end

                    element.children = items

                    element:FireEventOnParents("moveToBottomNowAndDelayed")
                    --local chatPanel = element:Get("chat-panel")
                    --chatPanel:FireEvent("keepAtBottom")
                end

                m_label:FireEvent("updateLabel", text, m_showingInteraction)
                m_label:SetClass("collapsed", false)
            elseif m_label ~= nil then
                m_label:SetClass("collapsed", true)
            end
        end,
        tbl,
        m_boonsBanesPanel,
        m_multitargetsPanel,
        m_modifiersPanel,
    }

    return m_resultPanel
end


RollCheck.RegisterCustom{
    id = "resistance_power_roll",
    rollType = "resistance_power_roll",
	Describe = function(check, isplayer)
        local attrName = check.info.attrid
        local attrInfo = creature.attributesInfo[check.info.attrid]
        attrName = attrInfo and attrInfo.description or attrName
        return "Roll Resistance vs " .. attrName
    end,
	GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,
	GetModifiers = function(check, creature)
        local options = check.options or {}
        options.attribute = check.info.attrid
        return creature:GetModifiersForPowerRoll(check:GetRoll(creature), "resistance_power_roll" , options)
    end,
	ShowDialog = function(check, dialogOptions)
        dialogOptions.rollProperties = RollPropertiesPowerTable.new{
            tiers = DeepCopy(check.info.tiers)
        }
        dialogOptions.PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(dialogOptions.rollProperties, dialogOptions.creature)
        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

function ActivatedAbilityPowerRollBehavior:ResistanceAttr()
    return self:try_get("resistanceAttr", "inu")
end

--cast vs resistance.
function ActivatedAbilityPowerRollBehavior:CastResistance(ability, casterToken, targets, options)
    options = options or {}
	local tokenids = ActivatedAbility.GetTokenIds(targets)
    local dcaction = ability:RequireSavingThrowsCo(self, casterToken, tokenids, {
        id = "resistance_power_roll",
        rollType = "resistance_power_roll",
        text = "Resistance",
        explanation = "Roll Resistance vs " .. ability.name,
        targets = targets,
        info = {
            attrid = self:ResistanceAttr(),
            tiers = DeepCopy(self.tiers),
        },
    })

    if dcaction == nil then
        --the roll was canceled.
        return
    end

    ability:CommitToPaying(casterToken, options)

    for i,target in ipairs(targets) do
        if target.token ~= nil then
		    local dcinfo = dcaction.info.tokens[target.token.charid]
            if dcinfo ~= nil then
                local tier = DiceResultToTier{ total = dcinfo.result, boons = dcinfo.boons, banes = dcinfo.banes }
                options.symbols.cast:SetTierResult(target.token, tier)
                local command = self.tiers[tier]
                self:ExecuteCommand(ability, casterToken, target.token, options, command)
            end
        end
    end
end

RollCheck.RegisterCustom{
    id = "power_roll_custom",
    rollType = "power_roll_custom",
	Describe = function(check, isplayer)
        return check.info.explanation
    end,
	GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,
	GetModifiers = function(check, creature)
        return {}
    end,
	ShowDialog = function(check, dialogOptions)
        dialogOptions.rollProperties = RollPropertiesPowerTable.new{
            tiers = DeepCopy(check.info.tiers)
        }
        dialogOptions.PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(dialogOptions.rollProperties, dialogOptions.creature)
        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

--cast custom.
function ActivatedAbilityPowerRollBehavior:CastCustom(ability, casterToken, targets, options)
	local tokenids = ActivatedAbility.GetTokenIds(targets)
    local dcaction = ability:RequireSavingThrowsCo(self, casterToken, tokenids, {
        id = "power_roll_custom",
        rollType = "power_roll_custom",
        text = "Custom Roll",
        explanation = ability.explanation,
        targets = targets,
        info = {
            attrid = self:ResistanceAttr(),
            tiers = DeepCopy(self.tiers),
            explanation = ability.explanation,
        },
    })

    if dcaction == nil then
        --the roll was canceled.
        return
    end

    ability:CommitToPaying(casterToken, options)

    for i,target in ipairs(targets) do
        if target.token ~= nil then
		    local dcinfo = dcaction.info.tokens[target.token.charid]
            if dcinfo ~= nil then
                local tier = DiceResultToTier{ total = dcinfo.result, boons = dcinfo.boons, banes = dcinfo.banes }
                if self:has_key("callback") then
                    self.callback(target.token, tier)
                end
            end
        end
    end
end

function ActivatedAbilityPowerRollBehavior.CustomRoll(options)
    local ability = DeepCopy(MCDMUtils.GetStandardAbility("Ability Power Roll"))
    local explanation = options.explanation or "Custom Power Roll"
    for i,behavior in ipairs(ability.behaviors) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            behavior.tiers = options.tiers
            behavior.resistanceAttr = options.resistanceAttr or behavior.resistanceAttr
            behavior.callback = options.callback
        end
    end

    local targets = {}
    for _,target in ipairs(options.targets) do
        targets[#targets+1] = {
            token = target,
        }
    end

    ability:Cast(options.caster, targets, {
        symbols = {}
    })
end
local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCustomTriggerBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
ActivatedAbilityCustomTriggerBehavior = RegisterGameType("ActivatedAbilityCustomTriggerBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCustomTriggerBehavior.summary = 'Custom Trigger'

--If true, the cast holds at this behavior until the triggered ability this
--fired has been taken or declined. Off by default: firing a custom trigger is
--normally fire-and-forget, and most abilities put the trigger last.
ActivatedAbilityCustomTriggerBehavior.waitForResolution = false

--How long to wait for the trigger prompt to show up before concluding it was
--never offered. The dispatch is asynchronous even locally -- DispatchEvent
--queues onto the creature's triggeredEvents, which RefreshToken drains a frame
--or more later -- so some window is needed in the happy path too. A trigger
--that never appears (already used this turn, no legal target, condition
--failed) must not park the cast, hence the bound.
local g_triggerAppearTimeout = 3

--Upper bound on holding the cast while the player decides. ActiveTrigger
--entries age out of GetAvailableTriggers after 60s, so this only has to
--outlast that.
local g_triggerResolveTimeout = 90

ActivatedAbility.RegisterType
{
    id = "customtrigger",
    text = "Custom Trigger",
    createBehavior = function()
        return ActivatedAbilityCustomTriggerBehavior.new{
            triggerName = "",
            value = "",
        }
    end,
}

--The trigger panel labels a trigger with the ability's name, suffixed with its
--resource cost when it has one ("Burning Ash (2 Insight)").
local function TriggerMatchesName(triggerInfo, name)
    local text = triggerInfo:try_get("text", "")
    return text == name or string.starts_with(text, name .. " (")
end

local function FindTriggerByName(token, name)
    if token == nil or (not token.valid) or token.properties == nil then
        return nil
    end

    for _,triggerInfo in pairs(token.properties:GetAvailableTriggers() or {}) do
        if TriggerMatchesName(triggerInfo, name) then
            return triggerInfo
        end
    end

    return nil
end

local function FindTriggerById(token, id)
    if token == nil or (not token.valid) or token.properties == nil then
        return nil
    end

    for _,triggerInfo in pairs(token.properties:GetAvailableTriggers() or {}) do
        if triggerInfo.id == id then
            return triggerInfo
        end
    end

    return nil
end

--Hold the casting coroutine until the triggered ability we just fired has been
--resolved. Without this the trigger is served from its own coroutine while the
--cast marches on, so any behavior sequenced *after* the trigger actually
--resolves *before* it. That inverts abilities whose later behaviors the
--trigger is meant to precede -- e.g. Black Ash Teleport fires Burning Ash and
--then offers the Hide, and the deferred Burning Ash damage was stripping the
--hidden the player had just gained.
function ActivatedAbilityCustomTriggerBehavior:WaitForTriggerResolution(token)
    local name = self.triggerName
    if name == nil or name == "" then
        return
    end

    local snapshot = ActivatedAbility.GetActiveCastSnapshot()

    local deadline = dmhub.Time() + g_triggerAppearTimeout
    local trigger = FindTriggerByName(token, name)
    while trigger == nil and dmhub.Time() < deadline do
        coroutine.yield(0.1)
        trigger = FindTriggerByName(token, name)
    end

    if trigger == nil then
        --Never offered. Nothing to wait for.
        return
    end

    local triggerid = trigger.id

    local dismissed = false

    deadline = dmhub.Time() + g_triggerResolveTimeout
    while dmhub.Time() < deadline do
        local t = FindTriggerById(token, triggerid)
        if t == nil then
            break
        elseif t.dismissed then
            dismissed = true
            break
        elseif t.triggered then
            break
        end

        coroutine.yield(0.1)
    end

    if dismissed then
        --Declined: nothing was cast, so don't sit on unrelated casts.
        return
    end

    --An accepted trigger casts in its own coroutine. Give it a beat to register
    --itself, then wait for it (and anything it invokes) to finish.
    coroutine.yield(0.1)
    coroutine.yield(0.1)

    deadline = dmhub.Time() + g_triggerResolveTimeout
    while ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot) and dmhub.Time() < deadline do
        coroutine.yield(0.1)
    end
end

function ActivatedAbilityCustomTriggerBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Custom Trigger"
end

function ActivatedAbilityCustomTriggerBehavior:Cast(ability, casterToken, targets, options)
    for _,target in ipairs(targets) do
        if target.token ~= nil then
            options.symbols.target = target.token.properties
            local value = ExecuteGoblinScript(self.value, target.token.properties:LookupSymbol(options.symbols), 0, "Determine custom trigger value")
            print("GoblinScript:: symbols", options.symbols, "self.value =", self.value, "result =", value)

            target.token.properties:DispatchEvent("custom", {
                triggername = self.triggerName,
                triggervalue = value,
            })

            if self:try_get("waitForResolution", false) then
                self:WaitForTriggerResolution(target.token)
            end
        end
    end
end

function ActivatedAbilityCustomTriggerBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Trigger Name:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.triggerName,
            change = function(element)
                self.triggerName = element.text
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Value:",
        },
        gui.GoblinScriptInput{
            value = self.value,
            change = function(element)
                self.value = element.value
            end,
            documentation = {
				domains = parentPanel.data.parentAbility.domains,
                help = string.format("This GoblinScript is used to determine the value passed with the custom trigger being fired."),
                output = "number",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is casting the ability causing the trigger.",
                symbols = ActivatedAbility.helpCasting,
            }
        }
    }

    result[#result+1] = gui.Check{
        text = "Wait for trigger to resolve",
        value = self:try_get("waitForResolution", false),
        change = function(element)
            self.waitForResolution = element.value
        end,
    }

	return result
end
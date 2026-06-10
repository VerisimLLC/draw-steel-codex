local mod = dmhub.GetModLoading()

--Acolyte class plumbing. Glue between the action bar (Invoke toggle), the rules
--engine (Patron's Gaze risk roll + Patron's Spite trigger), and YAML-authored
--ability content (which reads Cast.Invoked).
--
--Pipeline summary for an "Invoke"-able ability:
--   1. Action bar renders an "Invoke <cost>" toggle next to the cast button
--      (via DrawSteelActionBar.RegisterCastControl).
--   2. On cast commit:
--        - sets symbols.cast.invoked = true (Cast.Invoked -> 1 in GoblinScript)
--        - deals Presence damage to the caster
--        - adds <cost> to the caster's Patron's Gaze resource
--   3. After the invoked cast finishes resolving (GameSystem.OnEndCastActivatedAbility),
--      the `patronsgazerisk` event is dispatched on the caster. A YAML-authored
--      `behavior: trigger` modifier queues a "Patron's Gaze: Risk Roll" prompt.
--   4. The player resolves the prompt: a TriggeredAbility rolls a visible 1d10
--      (ActivatedAbilityRollBehavior) then ActivatedAbilityPatronGazeResolveBehavior
--      compares the roll to current Patron's Gaze. If roll <= gaze, it fires the
--      `patronspitetriggered` event with GazeCleared = (pre-reset gaze), clears
--      Patron's Gaze, and grants 2 Zeal.
--Patron subclasses (Noctule Courtier, Von Glauer, etc.) declare a trigger
--modifier listening for `patronspitetriggered` in YAML and provide their own
--Spite content.

----------------------------------------------------------------------
-- 1. Cast.Invoked GoblinScript symbol
----------------------------------------------------------------------
-- Lets YAML formulas branch on whether the caster invoked. Stored as a plain
-- field on ActivatedAbilityCast so it serializes alongside the cast and survives
-- across the commit -> resolve boundary.

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "Invoked",
    type = "number",
    desc = "1 if the caster invoked their patron for this ability (Acolyte mechanic), 0 otherwise.",
    seealso = {},
    examples = {"Cast.Invoked = 1", "1 + Cast.Invoked"},
    calculate = function(c)
        if c:try_get("invoked", false) then
            return 1
        end
        return 0
    end,
}

----------------------------------------------------------------------
-- 2. patronspitetriggered trigger
----------------------------------------------------------------------
-- Fired on the caster after an invoked ability resolves and the d10 risk roll
-- fails (roll <= current Patron's Gaze). Patron subclasses register a
-- TriggeredAbility against this id to spawn their patron-specific Spite.
--
-- Exposes GazeCleared as a top-level symbol (matches the codebase convention --
-- gainresource exposes Quantity/Resource the same way, NOT under Triggerer).
-- In YAML formulas reference it bare: `GazeCleared >= 1`. The proposal called
-- for `Triggerer.GazeCleared`, but the codebase pattern puts trigger payload
-- symbols at top level, so it's `GazeCleared` here.

TriggeredAbility.RegisterTrigger{
    id = "patronspitetriggered",
    text = "Patron's Spite Triggered",
    symbols = {
        gazecleared = {
            name = "GazeCleared",
            type = "number",
            desc = "The amount of Patron's Gaze that was cleared when Patron's Spite triggered.",
        },
    },
}

----------------------------------------------------------------------
-- 2b. patronsgazerisk trigger
----------------------------------------------------------------------
-- Fired on the caster after an invoked ability finishes resolving. A
-- YAML-authored `behavior: trigger` modifier on the Acolyte class listens for
-- this id and queues a prompt ("Patron's Gaze: Risk Roll"). When the player
-- resolves the prompt, the triggered ability rolls a visible 1d10
-- (ActivatedAbilityRollBehavior) and ActivatedAbilityPatronGazeResolveBehavior
-- compares the roll to the caster's current Patron's Gaze.
--
-- No payload symbols: the risk roll reads Patron's Gaze fresh at resolve time.

TriggeredAbility.RegisterTrigger{
    id = "patronsgazerisk",
    text = "Patron's Gaze Risk Roll",
    symbols = {},
}

----------------------------------------------------------------------
-- 3. Patron damage type (custom attribute + GoblinScript symbols)
----------------------------------------------------------------------
-- The Acolyte's patron determines the elemental flavour of their damage
-- (Goxomoc=lightning, Unicorn=holy, Von Glauer=corruption, ...). YAML
-- subclass content sets a creature's patron_damage_type via:
--    behavior: attribute
--    attribute: a7c01b7e-d4af-4dba-9ad0-7a17ed4ace1d
--    value: "corruption"
--    operation: set
--
-- The damage parser then translates the literal token "patron" in tier
-- text / DrawSteelCommand rule strings into this string, AND marks the
-- damage event with patrondamage=true so triggers can react.

ACOLYTE_PATRON_DAMAGE_TYPE_ATTRIBUTE_ID = "a7c01b7e-d4af-4dba-9ad0-7a17ed4ace1d"

--Returns the caster's patron damage type as a lowercase string, or "" if not
--set. Handles both stringset (set via add operation -> StringSet object with
--.strings[1]) and raw-string (set via set operation -> plain string) storage.
function creature:PatronDamageType()
    --attributeInfoById entries for database-backed attributes have the shape
    --{ id, attr = CustomAttribute, attributeType, ... }; we need the .attr.
    --Static/builtin attributes don't have .attr -- guard for that too.
    local rec = CustomAttribute.attributeInfoById and CustomAttribute.attributeInfoById[ACOLYTE_PATRON_DAMAGE_TYPE_ATTRIBUTE_ID]
    if rec == nil then
        return ""
    end
    local attrInfo = rec.attr or rec
    if attrInfo == nil or type(attrInfo.CalculateBaseValue) ~= "function" then
        return ""
    end

    local value = self:GetCustomAttribute(attrInfo)
    if type(value) == "string" then
        return string.lower(value)
    end
    if type(value) == "table" then
        --StringSet shape: { strings = { "corruption" } }
        local strings = rawget(value, "strings")
        if type(strings) == "table" and strings[1] ~= nil then
            return string.lower(tostring(strings[1]))
        end
    end
    return ""
end

--Register the GoblinScript symbol now AND re-register after refreshTables. The
--customAttributes table auto-registers a fallback lookupSymbol for every
--attribute -- which for stringset-type returns the raw StringSet object. We
--want our string-returning version to win. CustomAttribute.lua loads before
--this file so its refreshTables handler fires after ours; re-registering
--inline doesn't help (gets overwritten). Defer via dmhub.Schedule so our
--override runs after the auto-binding settles.
local function RegisterPatronDamageTypeSymbol()
    GameSystem.RegisterGoblinScriptField{
        target = creature,
        name = "PatronDamageType",
        type = "text",
        desc = "The caster's patron damage type (corruption / holy / lightning / ...). Empty string if not set. Used by Acolyte tier text and patron damage triggers.",
        seealso = {},
        examples = {'Self.PatronDamageType = "corruption"'},
        calculate = function(c)
            return c:PatronDamageType()
        end,
    }
end

RegisterPatronDamageTypeSymbol()

dmhub.RegisterEventHandler("refreshTables", function(keys)
    dmhub.Schedule(0.01, function()
        if mod.unloaded then return end
        RegisterPatronDamageTypeSymbol()
    end)
end)

----------------------------------------------------------------------
-- 4. Cast.DealsPatronDamage GoblinScript symbol
----------------------------------------------------------------------
-- True if ANY damage event during the cast was patron-tagged. Useful for
-- modifier activation conditions like "Cast.Tier >= 2 and Cast.DealsPatronDamage = 1".

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "DealsPatronDamage",
    type = "number",
    desc = "1 if any damage event during this cast was patron-tagged (Acolyte mechanic), 0 otherwise.",
    seealso = {},
    examples = {"Cast.DealsPatronDamage = 1", "Cast.Tier >= 2 and Cast.DealsPatronDamage = 1"},
    calculate = function(c)
        if c:try_get("dealsPatronDamage", false) then
            return 1
        end
        return 0
    end,
}

----------------------------------------------------------------------
-- 5. Invoke cast control (action bar UI + lifecycle hooks)
----------------------------------------------------------------------

-- Bootstrap the registry locally so this file can register even though
-- DrawSteelActionBar.lua loads later in main.lua. DMHub's Lua runtime is strict
-- (reading an uninitialized global errors), so we use rawget(_G, ...) to safely
-- create the table. The action bar module does the same dance, so order of load
-- doesn't matter.
DrawSteelActionBar = rawget(_G, "DrawSteelActionBar") or {}
_G.DrawSteelActionBar = DrawSteelActionBar
DrawSteelActionBar._castControls = DrawSteelActionBar._castControls or {}
if type(DrawSteelActionBar.RegisterCastControl) ~= "function" then
    --Lightweight fallback registration so module-load ordering can't lose entries.
    --The DrawSteelActionBar module overwrites this once it loads and reads
    --_castControls at render time; the entries appended here survive.
    function DrawSteelActionBar.RegisterCastControl(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" then return end
        for i,existing in ipairs(DrawSteelActionBar._castControls) do
            if existing.id == spec.id then
                DrawSteelActionBar._castControls[i] = spec
                return
            end
        end
        DrawSteelActionBar._castControls[#DrawSteelActionBar._castControls+1] = spec
    end
end

-- Lookup the Patron's Gaze resource id (CharacterResource UUID). Done lazily
-- because CharacterResource.nameToId isn't populated until the resource table
-- has loaded, which can be later than this file at module load time.
local function GetPatronsGazeResourceId()
    return CharacterResource.nameToId and CharacterResource.nameToId["Patron's Gaze"]
end

-- Apply the cost of Invoking the patron for a single cast: mark the cast object
-- as invoked (so Cast.Invoked = 1 in GoblinScript), deal Presence patron damage
-- to the caster, and add the invoke cost to the caster's Patron's Gaze resource.
--
-- This is the SINGLE source of truth for the Invoke cost. It is called from two
-- places:
--   * the action-bar Invoke cast control's onCommit (abilities cast normally);
--   * the triggered-ability Invoke prompt (abilities that fire as triggers).
--
-- `cast` is the ActivatedAbilityCast the ability's behaviors will see
-- (options.symbols.cast). It may be nil for callers that have not built one yet;
-- in that case only the damage / Patron's Gaze side effects are applied.
function AcolyteApplyInvoke(casterToken, ability, cast)
    if casterToken == nil or not casterToken.valid then return end

    local invoke = ability ~= nil and ability:try_get("invoke")
    local cost = (invoke and tonumber(invoke.cost)) or 0

    --Mark the cast as invoked so Cast.Invoked = 1 in GoblinScript. ability:Cast
    --respects an existing options.symbols.cast, so this flag flows through to all
    --behaviors and tier-text formulas.
    if cast ~= nil then
        cast.invoked = true
    end

    --Apply self damage (Presence) and Patron's Gaze increment as part of the
    --same ModifyProperties transaction so they undo together.
    casterToken:ModifyProperties{
        description = "Invoke Patron",
        execute = function()
            --Read the caster's Presence score (in Draw Steel the score IS the
            --bonus; AttributeMod is the right call). Use prs for Presence per
            --the Draw Steel attribute id convention.
            local presenceValue = casterToken.properties:AttributeMod("prs") or 0
            if presenceValue < 0 then presenceValue = 0 end

            if presenceValue > 0 then
                --Resolve the patron damage type at commit-time so subclass
                --selection (Goxomoc / Unicorn / Von Glauer / ...) drives the
                --damage type. If no patron is configured, fall back to untyped.
                --This damage is patron damage by definition, so we always set
                --patrondamage=true.
                local patronType = casterToken.properties:PatronDamageType()
                if patronType == "" then
                    patronType = "untyped"
                    print(string.format(
                        "PATRON DAMAGE:: Invoke self-damage: caster '%s' has no patron_damage_type set; emitting untyped.",
                        creature.GetTokenDescription(casterToken)
                    ))
                end
                casterToken.properties:TakeDamage(presenceValue, "Invoked patron", {
                    damagetype = patronType,
                    patrondamage = true,
                })
            end

            --Add to Patron's Gaze (unbounded resource).
            local pgId = GetPatronsGazeResourceId()
            if pgId ~= nil and cost > 0 then
                casterToken.properties:RefreshResource(pgId, "unbounded", cost, "Invoked patron")
            end
        end,
    }
end

DrawSteelActionBar.RegisterCastControl{
    id = "acolyte-invoke",
    priority = 10,

    appliesTo = function(ability)
        --The ability has an `invoke` table -> { cost = number, description = string }.
        --YAML authors set this on Acolyte abilities that support Invocation.
        return ability ~= nil and ability:try_get("invoke") ~= nil
    end,

    render = function(parent, ability, castState, ctx)
        local invoke = ability:try_get("invoke")
        if invoke == nil then return end

        local cost = tonumber(invoke.cost) or 0
        local desc = invoke.description or ""
        castState.invoked = false

        --Mirror the toggle state onto the cast object so GoblinScript formulas
        --(e.g. `numTargets: 1 + Cast.Invoked` on Elder's Fury / Patronizing
        --Dismissal) resolve correctly during targeting setup -- not just at cast
        --resolve. The action bar guarantees ctx.cast is a fresh ActivatedAbilityCast
        --by the time render runs. onCommit re-sets cast.invoked, so this is the
        --pre-commit (targeting-flow) source of truth.
        local cast = ctx and ctx.cast
        if cast ~= nil then
            cast.invoked = false
        end

        local refreshTargeting = ctx and ctx.refreshTargeting

        local labelOff = string.format("Invoke %d", cost)
        local labelOn = string.format("Invoking %d", cost)

        local toggle
        toggle = gui.Button{
            classes = {"sizeM"},
            width = 140,
            text = labelOff,
            classes = {},

            hover = function(element)
                if desc ~= "" then
                    gui.Tooltip{
                        valign = "top",
                        text = desc,
                    }(element)
                end
            end,

            press = function(element)
                castState.invoked = not castState.invoked
                --Visual toggle: change label and add a "selected" class so any
                --theme styles keyed off it kick in. We also flip the text so
                --the state is visible even without theme support for "selected".
                element:SetClass("selected", castState.invoked)
                element.text = castState.invoked and labelOn or labelOff

                --Live-update the cast object so GoblinScript formulas referencing
                --Cast.Invoked (numTargets, range, prompts, etc.) re-evaluate against
                --the new state. Then trigger targeting recompute so the player sees
                --the prompt count update (e.g. "Choose Target 1/2" -> "Choose Target 1/1").
                if cast ~= nil then
                    cast.invoked = castState.invoked
                end
                if type(refreshTargeting) == "function" then
                    refreshTargeting()
                end
            end,
        }

        parent.children = { toggle }
    end,

    onCommit = function(ability, cast, castState, casterToken, symbols)
        if not castState.invoked then return end
        if casterToken == nil or not casterToken.valid then return end

        --Apply the Invoke cost via the shared helper. FireCastControlsOnCommit
        --pre-builds the cast object (assigning it to symbols.cast) before
        --invoking us when one doesn't already exist, so `cast` is guaranteed
        --non-nil here. ability:Cast respects an existing options.symbols.cast
        --(see ActivatedAbility.lua:2500-2516), so cast.invoked flows through to
        --all behaviors and tier-text formulas.
        AcolyteApplyInvoke(casterToken, ability, cast)

        --The post-resolution risk roll is no longer driven from a cast-control
        --hook (the old onResolve d10 logic). Instead, GameSystem.OnEndCastActivatedAbility
        --(wrapped below) dispatches the `patronsgazerisk` event after the invoked
        --cast finishes resolving, which queues a player-resolved trigger prompt.
    end,
}

----------------------------------------------------------------------
-- 6. Fire patronsgazerisk after an invoked cast resolves
----------------------------------------------------------------------
-- GameSystem.OnEndCastActivatedAbility is invoked from ActivatedAbility:FinishCast
-- once per cast, AFTER all of the cast's behaviors have finished. We wrap it so
-- that whenever an invoked Acolyte ability resolves we dispatch `patronsgazerisk`
-- on the caster. cast.invoked is set by the Invoke cast control's onCommit and
-- rides on options.symbols.cast through to here.
--
-- ROOT CAUSE of the original "risk roll never fires" bug, and the trap that the
-- first fix attempt fell into -- both confirmed by live instrumentation:
--
--   (a) GameSystem.OnEndCastActivatedAbility is a single shared function pointer.
--       MCDMRules.lua assigns it at module-load time. A one-shot Schedule(0)
--       install captures whatever base is current at that instant; any later
--       reassignment (another mod, a partial hot-reload, runOnController re-init)
--       silently replaces the pointer and detaches the Acolyte hook. Invoke's
--       onCommit still ran (damage + Patron's Gaze are independent of this hook),
--       the cast still reached FinishCast, but the patronsgazerisk dispatch --
--       which lived ONLY in the detached wrap -- never fired.
--
--   (b) A naive "re-assert on refreshTables" fix is far WORSE: every Lua reload
--       leaves the previous module instance's refreshTables event handler still
--       registered (DMHub does not auto-unregister them). Each stale handler
--       wraps OnEndCast again on the next refresh, so the function nests N deep
--       after N reloads -- observed live as patronsgazerisk dispatching 9x for a
--       single cast.
--
-- FIX: install ONE permanent thin shim, exactly once per process, recorded in a
-- _G slot so it survives module reloads and cannot be installed twice. The shim
-- is never re-wrapped. The actual hook logic lives in another _G slot that a
-- module reload simply OVERWRITES (never appends). So:
--   * no nesting, ever (the shim is installed once and only once);
--   * no staleness (reload replaces the logic in place);
--   * clobber-resilient (Section 6b below re-asserts the shim into the
--     OnEndCast slot on refreshTables -- safe now because re-asserting a
--     single stable shim is idempotent and can never nest).

--Slot holding the current hook logic. A module reload overwrites this; the
--permanent shim always reads the latest value.
_G.AcolytePatronsGazeRiskLogic = function(casterToken, ability, options)
    if casterToken == nil or not casterToken.valid then return end
    if options == nil or options.abort then return end

    --cast.invoked is set by the Invoke cast control's onCommit and rides on
    --options.symbols.cast (verified by live instrumentation to survive
    --commit -> FinishCast with object identity intact).
    local cast = options.symbols and options.symbols.cast
    if cast == nil or not cast:try_get("invoked", false) then
        return
    end

    --Dispatch exactly once per cast. The shim is single-installed so this is
    --belt-and-suspenders, but it also protects against the same options table
    --reaching the shim twice for any reason.
    if options._acolytePatronsGazeRiskDispatched then
        return
    end
    options._acolytePatronsGazeRiskDispatched = true

    --Dispatch the risk-roll trigger event on the caster. A YAML `behavior: trigger`
    --modifier on the Acolyte class listens for `patronsgazerisk` and queues the
    --"Patron's Gaze: Risk Roll" prompt. No payload symbols -- the resolve behavior
    --reads Patron's Gaze fresh.
    casterToken.properties:DispatchEvent("patronsgazerisk", {})
end

--Install the permanent shim into GameSystem.OnEndCastActivatedAbility. Idempotent
--at the process level: the shim is created and stored in _G.AcolytePatronsGazeRiskShim
--exactly once and reused forever after, so module reloads never create a second one.
local function InstallPatronsGazeRiskHook()
    if rawget(_G, "AcolytePatronsGazeRiskShim") == nil then
        --First install in this process. Capture the current OnEndCast as the
        --base to chain into.
        local baseOnEndCast = GameSystem.OnEndCastActivatedAbility
        _G.AcolytePatronsGazeRiskShim = function(casterToken, ability, options)
            if type(baseOnEndCast) == "function" then
                baseOnEndCast(casterToken, ability, options)
            end
            local logic = rawget(_G, "AcolytePatronsGazeRiskLogic")
            if type(logic) == "function" then
                logic(casterToken, ability, options)
            end
        end
    end

    --Point the OnEndCast slot at our shim if it is not already there. This both
    --performs the initial install and heals a later clobber -- and because the
    --shim is a single stable object, re-pointing at it can never nest.
    if GameSystem.OnEndCastActivatedAbility ~= _G.AcolytePatronsGazeRiskShim then
        GameSystem.OnEndCastActivatedAbility = _G.AcolytePatronsGazeRiskShim
    end
end

--Install once the current load pass settles (so it lands after MCDMRules.lua's
--assignment), then re-assert on every refreshTables so any later clobber is
--healed. Both calls are fully idempotent (single shim, see above), so the
--recurring call is cheap and can never nest.
dmhub.Schedule(0, function()
    if mod.unloaded then return end
    InstallPatronsGazeRiskHook()
end)

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then return end
    InstallPatronsGazeRiskHook()
end)

----------------------------------------------------------------------
-- 7. PatronsGazeChatMessage -- bespoke Action Log card for the risk roll
----------------------------------------------------------------------
-- A custom chat message (chat.SendCustom) that renders the *only* Action Log
-- entry for the Patron's Gaze d10 risk roll -- the normal roll dialog's own
-- standard roll card is suppressed (see section 8b). It reuses the standard
-- action-log card chrome (CreateActionLogCard: portrait, colour bar, name).
--
-- The card moves through three states, driven by chat.UpdateCustom from the
-- resolve behavior; each push re-fires `pgRefresh` via the card's
-- refreshMessage handler:
--   * offered  -- sent the instant the roll dialog opens (no dieguid/result):
--                 shows the Gaze meter and "awaiting the roll".
--   * rolling  -- dieguid set: the card subscribes to chat.DiceEvents and a
--                 marker tracks the d10's face live as it tumbles.
--   * resolved -- result set: one big word, "PATRON'S SPITE" or "appeased".
-- The verbose explanation lives in the card's hover tooltip.

PatronsGazeChatMessage = RegisterGameType("PatronsGazeChatMessage")

--Spite severity tier from the amount of Gaze at stake. Mirrors the 3 / 4-9 /
--10+ breakpoints every patron's Spite table uses.
local function PatronsGazeSpiteTier(gaze)
    if gaze >= 10 then return "catastrophic" end
    if gaze >= 4 then return "greater" end
    return "lesser"
end

--Pip count for the meter. Patron's Gaze is uncapped, but the d10 risk roll
--makes 10 the meaningful ceiling.
local PATRONS_GAZE_PIP_COUNT = 10

--Verbose explanation for the card's hover tooltip, derived from the message
--props (handles the offered/rolling state where `result` is still nil).
local function PatronsGazeCardDetail(props)
    if props == nil then
        return "Patron's Gaze Roll."
    end
    local gaze = tonumber(props:try_get("gaze", 0)) or 0
    local result = props:try_get("result")
    if result == nil then
        return string.format(
            "Patron's Gaze Roll: a d10 against your Patron's Gaze of %d.\n\nOn %d or lower, your Patron's Gaze clears -- you gain 2 Zeal, and your patron's Spite (%s) sweeps the encounter.",
            gaze, gaze, PatronsGazeSpiteTier(gaze))
    end
    local r = tonumber(result) or 0
    if props:try_get("triggered", false) then
        return string.format(
            "Patron's Gaze Roll: rolled %d, equal to or under your Patron's Gaze of %d.\n\nYour Patron's Gaze clears -- you gain 2 Zeal, and your patron's Spite (%s) sweeps the encounter.",
            r, gaze, PatronsGazeSpiteTier(gaze))
    end
    return string.format(
        "Patron's Gaze Roll: rolled %d, above your Patron's Gaze of %d.\n\nYour patron is appeased -- no Spite this time.",
        r, gaze)
end

--Ominous-purple card styling, kept local to this file (component-specific, not
--part of the shared action-log vocabulary). The action-log card chrome around
--it comes from CreateActionLogCard + the action log panel's own styles.
local g_patronsGazeCardStyles = {
    { selectors = {"pg-card"}, flow = "vertical", width = "100%", height = "auto" },
    { selectors = {"pg-card-titlerow"}, flow = "horizontal", width = "100%", height = "auto", vmargin = 1 },
    { selectors = {"pg-eye"}, width = 16, height = 16, bgimage = "ui-icons/eye.png",
      bgcolor = "#a974d6", valign = "center", rmargin = 5 },
    { selectors = {"pg-title"}, width = "auto", height = "auto", valign = "center",
      fontSize = 12, bold = true, color = "#c9a8e8" },
    { selectors = {"pg-meterrow"}, flow = "horizontal", width = "100%", height = "auto",
      valign = "center", vmargin = 3 },
    { selectors = {"pg-pips"}, flow = "horizontal", width = "auto", height = "auto", valign = "center" },
    { selectors = {"pg-pip"}, width = 13, height = 11, hmargin = 1, bgimage = "panels/square.png",
      bgcolor = "#43285f", cornerRadius = 2, borderWidth = 2, borderColor = "#1d0a2e" },
    { selectors = {"pg-pip", "filled"}, bgcolor = "#d6b8f5" },
    { selectors = {"pg-pip", "marker"}, borderColor = "#fff2b0" },
    { selectors = {"pg-pip", "marker", "hit"}, borderColor = "#ff6a6a" },
    { selectors = {"pg-die"}, width = 32, height = 32, halign = "right", valign = "center",
      hmargin = 8, bgimage = "ui-icons/d10-filled.png", bgcolor = "#7a52a8" },
    { selectors = {"pg-die-label"}, width = "100%", height = "100%", bgimage = "ui-icons/d10.png",
      bgcolor = "#e8d4f7", color = "#2a1040", fontSize = 15, bold = true, textAlignment = "center" },
    { selectors = {"pg-status"}, width = "100%", height = "auto", fontSize = 16, bold = true,
      color = "#c9a8e8", textAlignment = "left", tmargin = 1 },
    { selectors = {"pg-status", "triggered"}, color = "#ff7a7a" },
    { selectors = {"pg-status", "safe"}, color = "#9adf9a" },
    --Offered / rolling: a quieter, smaller status line.
    { selectors = {"pg-status", "pending"}, fontSize = 12, bold = false, color = "#9a86b8" },
}

--Render the card skeleton. Dynamic state (gaze / dieguid / result) is applied
--through the `pgRefresh` event, fired by refreshMessage every action-log
--refresh -- so chat.UpdateCustom moves the card offered -> rolling -> resolved.
function PatronsGazeChatMessage:Render(message)
    local token = nil
    local tid = self:try_get("tokenid")
    if tid ~= nil then
        token = dmhub.GetCharacterById(tid)
    end

    --Ten pips, left = die value 1. `pgFace` marks the live/landing face.
    local pips = {}
    for i = 1, PATRONS_GAZE_PIP_COUNT do
        pips[i] = gui.Panel{
            classes = {"pg-pip"},
            data = { pipIndex = i },
            pgFace = function(element, num)
                element:SetClass("marker", element.data.pipIndex == num)
            end,
            pgLand = function(element, info)
                local landed = element.data.pipIndex == info.result
                element:SetClass("marker", landed)
                element:SetClass("hit", landed and info.triggered)
            end,
        }
    end

    local dieLabel = gui.Label{
        classes = {"pg-die-label"},
        text = "?",
        pgFace = function(element, num)
            element.text = tostring(num)
        end,
    }

    local statusLabel = gui.Label{ classes = {"pg-status", "pending"}, text = "" }

    local contentRoot = gui.Panel{
        classes = {"pg-card"},
        styles = g_patronsGazeCardStyles,
        data = { subscribed = false, lastFace = nil },

        gui.Panel{
            classes = {"pg-card-titlerow"},
            gui.Panel{ classes = {"pg-eye"} },
            gui.Label{ classes = {"pg-title"}, text = "PATRON'S GAZE" },
        },
        gui.Panel{
            classes = {"pg-meterrow"},
            gui.Panel{ classes = {"pg-pips"}, children = pips },
            gui.Panel{ classes = {"pg-die"}, dieLabel },
        },
        statusLabel,

        --Physical d10 feed while the dice tumble (rolling state).
        diceface = function(element, diceguid, num, timeRemaining)
            element.data.lastFace = num
            element:FireEventTree("pgFace", num)
        end,

        --Apply all dynamic state from the (possibly updated) message props.
        pgRefresh = function(element, props)
            local gaze = tonumber(props:try_get("gaze", 0)) or 0
            local result = props:try_get("result")
            local triggered = props:try_get("triggered", false)
            local dieguid = props:try_get("dieguid")

            --Base meter: light pips 1..gaze (the Patron's Gaze at stake).
            for _,pip in ipairs(pips) do
                pip:SetClass("filled", pip.data.pipIndex <= gaze)
            end

            if result ~= nil then
                --Resolved: one big word, marker on the landing pip.
                local r = tonumber(result) or 0
                dieLabel.text = tostring(r)
                element:FireEventTree("pgLand", { result = r, triggered = triggered })
                statusLabel:SetClass("pending", false)
                statusLabel:SetClass("triggered", triggered)
                statusLabel:SetClass("safe", not triggered)
                statusLabel.text = triggered and "PATRON'S SPITE" or "appeased"
            elseif dieguid ~= nil and dieguid ~= "" then
                --Rolling: subscribe to the physical die, track it live.
                statusLabel:SetClass("triggered", false)
                statusLabel:SetClass("safe", false)
                statusLabel:SetClass("pending", true)
                statusLabel.text = "the dice are cast..."
                if element.data.lastFace ~= nil then
                    dieLabel.text = tostring(element.data.lastFace)
                end
                if not element.data.subscribed then
                    local events = chat.DiceEvents(dieguid)
                    if events ~= nil then
                        events:Listen(element)
                        element.data.subscribed = true
                    end
                end
            else
                --Offered: the roll dialog is up, awaiting the player.
                statusLabel:SetClass("triggered", false)
                statusLabel:SetClass("safe", false)
                statusLabel:SetClass("pending", true)
                statusLabel.text = "awaiting the roll..."
                dieLabel.text = "?"
            end
        end,
    }

    --Latest props, captured by refreshMessage so the hover tooltip is current.
    local m_props = nil

    local card = CreateActionLogCard{
        token = token,
        classes = {"patrons-gaze-card"},
        nameOverride = (token == nil) and "Patron's Gaze" or nil,
        content = { contentRoot },
    }

    --The action log fires refreshMessage on the cached card every refresh (and
    --after chat.UpdateCustom). Fan it to pgRefresh and keep props for the tooltip.
    card.events = card.events or {}
    card.events.refreshMessage = function(element, msg)
        if msg ~= nil and msg.properties ~= nil then
            m_props = msg.properties
            element:FireEventTree("pgRefresh", msg.properties)
        end
    end
    --Verbose text on hover (CreateCustomMessagePanel only adds its own linger
    --if we don't set one, so this wins).
    card.events.linger = function(element)
        gui.Tooltip(PatronsGazeCardDetail(m_props))(element)
    end

    return card
end

----------------------------------------------------------------------
-- 8. ActivatedAbilityPatronGazeResolveBehavior
----------------------------------------------------------------------
-- The sole behavior on the Patron's Gaze risk-roll triggered ability. It opens
-- the normal roll dialog ("Patron's Gaze Roll") for the d10 itself -- the
-- player still chooses when to roll -- and drives the bespoke card alongside:
--   * before the dialog opens : post the card in its "offered" state
--   * beginRoll (dice thrown) : push the die's guid so the card tracks it live
--   * completeRoll (settled)  : push the result; if roll <= Gaze, pause 1s,
--                               then clear Patron's Gaze, grant 2 Zeal, and
--                               fire patronspitetriggered (-> Spite banner)
--   * cancelRoll              : delete the offered card; nothing resolves
-- The dialog's own standard roll card is suppressed in section 8b.

RegisterGameType("ActivatedAbilityPatronGazeResolveBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityPatronGazeResolveBehavior.summary = "Patron's Gaze Risk Resolve"

--Distinctive description string -- also the marker section 8b matches on to
--silence this roll's standard Action Log card.
local PATRONS_GAZE_ROLL_DESC = "Patron's Gaze Roll"

ActivatedAbility.RegisterType{
    id = "patron_gaze_resolve",
    text = "Patron's Gaze Risk Resolve",
    createBehavior = function()
        return ActivatedAbilityPatronGazeResolveBehavior.new{}
    end,
}

function ActivatedAbilityPatronGazeResolveBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Roll the Patron's Gaze d10 and resolve Patron's Spite"
end

function ActivatedAbilityPatronGazeResolveBehavior:Cast(ability, casterToken, targets, options)
    if casterToken == nil or not casterToken.valid then return end

    local pgId = GetPatronsGazeResourceId()
    if pgId == nil then
        return
    end

    --Read current Patron's Gaze (unbounded resource).
    local resources = casterToken.properties:GetResources() or {}
    local gaze = tonumber(resources[pgId]) or 0

    --Post the card in its "offered" state the instant the roll is presented.
    local msgGuid = chat.SendCustom(PatronsGazeChatMessage.new{
        tokenid = casterToken.charid,
        gaze = gaze,
    })

    local complete = false
    local cancelled = false
    local rollTotal = nil

    --Open the normal roll dialog. Its standard roll card is suppressed by the
    --RollDialog.OnBeforeRoll hook in section 8b (keyed on this description).
    local rollDialog = GameHud.instance and GameHud.instance.rollDialog
    if rollDialog == nil or rollDialog.data == nil then
        return
    end

    rollDialog.data.ShowDialog{
        title = PATRONS_GAZE_ROLL_DESC,
        description = PATRONS_GAZE_ROLL_DESC,
        roll = "1d10",
        creature = casterToken.properties,

        beginRoll = function(rollInfo)
            --Dice thrown: hand the die's guid to the card so it watches live.
            local dieguid = nil
            if rollInfo ~= nil and rollInfo.rolls ~= nil and rollInfo.rolls[1] ~= nil then
                dieguid = rollInfo.rolls[1].guid
            end
            if msgGuid ~= nil then
                chat.UpdateCustom(msgGuid, PatronsGazeChatMessage.new{
                    tokenid = casterToken.charid,
                    gaze = gaze,
                    dieguid = dieguid,
                })
            end
        end,

        completeRoll = function(rollInfo)
            rollTotal = tonumber(rollInfo and rollInfo.total) or 0
            complete = true
        end,

        cancelRoll = function()
            cancelled = true
            complete = true
        end,
    }

    --Yield the cast coroutine until the player resolves the dialog.
    while not complete do
        coroutine.yield(0.1)
    end

    if cancelled then
        --Roll cancelled: drop the offered card so nothing dangling is left.
        if msgGuid ~= nil then
            for _,m in ipairs(chat.messages or {}) do
                if m.key == msgGuid then
                    m:Delete()
                    break
                end
            end
        end
        return
    end

    local roll = rollTotal or 0
    local triggered = roll <= gaze and gaze > 0

    --Push the final result onto the card (offered/rolling -> resolved).
    if msgGuid ~= nil then
        chat.UpdateCustom(msgGuid, PatronsGazeChatMessage.new{
            tokenid = casterToken.charid,
            gaze = gaze,
            result = roll,
            triggered = triggered,
        })
    end

    if not triggered then
        return
    end

    --Patron's Spite triggered. Pause 1 second so the resolved card has a beat
    --to land before the patron subclass's dramatic banner fires.
    coroutine.yield(1)

    --Clear Patron's Gaze, grant 2 Zeal, and fire patronspitetriggered -- all in
    --one ModifyProperties so they network atomically. Patron subclasses declare
    --a trigger listening for the event (which raises the Spite banner).
    local zealId = CharacterResource.heroicResourceId

    casterToken:ModifyProperties{
        description = "Patron's Spite",
        execute = function()
            local props = casterToken.properties

            --Zero out unbounded Patron's Gaze (no direct "set" helper exists).
            local rt = props:GetResourceTable("unbounded")
            if rt ~= nil and rt[pgId] ~= nil then
                rt[pgId].unbounded = 0
            end
            props:InvalidateResources()

            --Grant 2 Zeal (heroic resource is unbounded for Draw Steel).
            if zealId ~= nil then
                props:RefreshResource(zealId, "unbounded", 2, "Cleared Patron's Gaze")
            end

            --Fire patronspitetriggered on the caster; gazecleared = pre-clear gaze.
            props:DispatchEvent("patronspitetriggered", {
                gazecleared = gaze,
            })
        end,
    }
end

----------------------------------------------------------------------
-- 8b. Suppress the Patron's Gaze roll's standard Action Log card
----------------------------------------------------------------------
-- The roll above goes through the normal roll dialog, which would normally log
-- a standard roll card -- but the bespoke PatronsGazeChatMessage card is meant
-- to be the only entry. RollDialog.OnBeforeRoll lets a mod adjust a roll just
-- before it is thrown; we flip `silent` on for our roll (identified by its
-- description) so no standard card is logged. The physical dice still roll, so
-- the bespoke card can still watch them live via chat.DiceEvents.
--
-- Installed deferred (DSRollDialog defines RollDialog later than this file) and
-- re-asserted on refreshTables. Any pre-existing foreign hook is captured once
-- into a _G slot and chained, so module reloads can neither nest nor lose it.

local function InstallPatronsGazeRollHook()
    local rd = rawget(_G, "RollDialog")
    if rd == nil then
        return
    end

    --Capture a genuinely-foreign hook once; never capture our own shim.
    local current = rd.OnBeforeRoll
    if type(current) == "function" and current ~= rawget(_G, "AcolyteOnBeforeRollShim") then
        _G.AcolyteOnBeforeRollPrev = current
    end

    if rawget(_G, "AcolyteOnBeforeRollShim") == nil then
        _G.AcolyteOnBeforeRollShim = function(info)
            if info ~= nil and info.description == PATRONS_GAZE_ROLL_DESC
                and info.rollArgs ~= nil then
                --Suppress the standard roll card for our roll only.
                info.rollArgs.silent = true
            end
            local prev = rawget(_G, "AcolyteOnBeforeRollPrev")
            if type(prev) == "function" then
                return prev(info)
            end
            return nil
        end
    end

    if rd.OnBeforeRoll ~= _G.AcolyteOnBeforeRollShim then
        rd.OnBeforeRoll = _G.AcolyteOnBeforeRollShim
    end
end

dmhub.Schedule(0, function()
    if mod.unloaded then return end
    InstallPatronsGazeRollHook()
end)

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then return end
    InstallPatronsGazeRollHook()
end)

----------------------------------------------------------------------
-- 9. Patron's Gaze heroic-resource display box
----------------------------------------------------------------------
-- Mirrors the Beastheart's Rampage box (DSCompanion.lua CreateRampageBox): a
-- "tokenbox" panel registered with TacPanel.RegisterHeroicResourceDisplay so it
-- appears in the character panel's HEROIC RESOURCES section. It shows the
-- caster's current Patron's Gaze and lets the player edit it directly. Visible
-- only for creatures that have at least one level in the Acolyte class.
--
-- Registration is DEFERRED via dmhub.Schedule because Acolyte.lua loads before
-- MCDMCharacterPanel.lua (which defines TacPanel.RegisterHeroicResourceDisplay).
-- TacPanel.HeroicResources() re-reads the display registry every time the panel
-- is built, so a registration added after load is still picked up. We also
-- re-register on refreshTables so a later hot-reload of MCDMCharacterPanel
-- (which resets its registry) doesn't drop our box; the registry is keyed by
-- id, so re-registering is idempotent.

ACOLYTE_CLASS_ID = "6e1d3a8c-1b2f-4a9e-bdac-01a7e6c1a55e"

--Patron's Gaze CharacterResource id (see compendium/import/acolyte.yaml). An
--unbounded resource, read/written via the GetUnboundedResource* API.
local g_patronsGazeResourceId = "8a5e3c1d-2b7f-4e0a-9c5d-6b8a4e1f3c7d"

--True if this creature has levels in the Acolyte class.
local function IsAcolyte(creatureObj)
    if creatureObj == nil then return false end
    return creatureObj:GetLevelInClass(ACOLYTE_CLASS_ID) > 0
end

--Component-specific "ominous purple" theming for the Patron's Gaze box. Layered
--ON TOP of the shared TacPanelStyles.TokenBox rather than added into it -- the
--styling belongs to the Acolyte feature, not the shared TokenBox vocabulary, so
--it stays local to this file. Each entry's selector chain ends in "patronsgaze"
--so it only overrides this box (the base TokenBox rules supply layout/sizing).
local g_patronsGazeStyles = {
    --Box: dark purple fill (tints the inherited panels/square.png bgimage) with
    --a brighter purple border.
    {
        selectors = {"panel", "tokenbox", "patronsgaze"},
        bgcolor = "#1d0a2ee6",
        borderColor = "#8b4fc4",
    },
    --Title: pale eerie violet.
    {
        selectors = {"label", "tokenbox", "title", "patronsgaze"},
        color = "#c9a8e8",
    },
    --Icon: the eye, tinted ominous purple (ui-icons glyphs are monochrome, so
    --bgcolor acts as a tint). Sizing/positioning comes from the base "icon" rule.
    {
        selectors = {"panel", "icon", "patronsgaze"},
        bgimage = "ui-icons/eye.png",
        bgcolor = "#a974d6",
    },
    --Value readout: light purple instead of the default cream.
    {
        selectors = {"input", "tokenbox", "value", "patronsgaze"},
        color = "#dcc2f0",
    },
    --Gaze meter: ten little horizontal pips stacked on the right edge. Dark
    --purple when empty, light purple when filled.
    {
        selectors = {"panel", "gaze-pip"},
        width = 12,
        height = 2,
        vmargin = 1,
        bgimage = "panels/square.png",
        bgcolor = "#43285f",
        cornerRadius = 1,
    },
    {
        selectors = {"panel", "gaze-pip", "filled"},
        bgcolor = "#d6b8f5",
    },
}

local function CreatePatronsGazeBox()
    --Ten pip panels for the gaze meter, built fresh per box. Index 1 is the
    --topmost pip, index 10 the bottom -- the meter fills from the bottom up.
    local gazePips = {}
    for i = 1, 10 do
        gazePips[i] = gui.Panel{ classes = {"gaze-pip"} }
    end

    return gui.Panel{
        styles = { TacPanelStyles.TokenBox, g_patronsGazeStyles },
        classes = {"tokenbox", "patronsgaze"},
        data = { displayToken = nil },

        refreshCharacter = function(element, token)
            local show = token ~= nil and token.valid and token.properties ~= nil
                and IsAcolyte(token.properties)
            element.data.displayToken = show and token or nil
            element:SetClass("collapsed", not show)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        refreshValue = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        linger = function(element)
            local displayToken = element.data.displayToken
            if displayToken == nil then return end
            element.tooltip = gui.StatsHistoryTooltip{
                description = "Patron's Gaze",
                entries = displayToken.properties:GetStatHistory(g_patronsGazeResourceId):GetHistory(),
            }
        end,

        gui.Label{
            classes = {"tokenbox", "title", "patronsgaze"},
            text = "PATRON'S GAZE",
        },

        gui.Panel{
            classes = {"container"},
            halign = "center",
            flow = "horizontal",
            --Eye icon, mirroring the heroic-resources box's icon panel. The
            --bgimage + tint are supplied by g_patronsGazeStyles; sizing comes
            --from the base TokenBox "icon" rule.
            gui.Panel{
                classes = {"icon", "patronsgaze"},
            },
            gui.Input{
                classes = {"tokenbox", "value", "patronsgaze"},
                text = "0",
                characterLimit = 3,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                refreshCharacter = function(element, token)
                    if token == nil or not token.valid or token.properties == nil
                        or not IsAcolyte(token.properties) then
                        return
                    end
                    local quantity = token.properties:GetUnboundedResourceQuantity(g_patronsGazeResourceId)
                    element.textNoNotify = string.format("%d", quantity)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                refreshValue = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local displayToken = element.parent.parent.data.displayToken
                    if displayToken == nil then return end
                    local n = tonumber(element.text) or 0
                    if n < 0 then n = 0 end
                    local current = displayToken.properties:GetUnboundedResourceQuantity(g_patronsGazeResourceId)
                    if n ~= current then
                        displayToken:ModifyProperties{
                            description = "Set Patron's Gaze",
                            execute = function()
                                displayToken.properties:AddUnboundedResource(g_patronsGazeResourceId, n - current, "Patron's Gaze")
                            end,
                        }
                    end
                    element.textNoNotify = string.format("%d", n)
                end,
            },
        },

        --Gaze meter: ten pips down the right edge. Floating so it overlays the
        --right strip without disturbing the centered icon/value layout. The
        --bottom `gaze` pips light up (gaze is clamped to the 0-10 display range).
        gui.Panel{
            classes = {"gaze-pips"},
            floating = true,
            halign = "right",
            valign = "bottom",
            rmargin = 5,
            bmargin = 2,
            width = "auto",
            height = "auto",
            flow = "vertical",
            children = gazePips,

            refreshCharacter = function(element, token)
                local gaze = 0
                if token ~= nil and token.valid and token.properties ~= nil
                    and IsAcolyte(token.properties) then
                    gaze = token.properties:GetUnboundedResourceQuantity(g_patronsGazeResourceId) or 0
                end
                if gaze < 0 then gaze = 0 end
                if gaze > 10 then gaze = 10 end
                --children are pips 1..10 top-to-bottom; light the bottom `gaze`.
                for i, pip in ipairs(element.children) do
                    pip:SetClass("filled", (11 - i) <= gaze)
                end
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            refreshValue = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

local function RegisterPatronsGazeDisplay()
    local tac = rawget(_G, "TacPanel")
    if tac == nil or type(tac.RegisterHeroicResourceDisplay) ~= "function" then
        return
    end
    tac.RegisterHeroicResourceDisplay{
        id = "patronsgaze",
        create = CreatePatronsGazeBox,
        ord = 3,
    }
end

dmhub.Schedule(0, function()
    if mod.unloaded then return end
    RegisterPatronsGazeDisplay()
end)

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if mod.unloaded then return end
    RegisterPatronsGazeDisplay()
end)

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

--Set true once the attribute is confirmed present (or successfully uploaded), so
--we stop touching the table on every subsequent refreshTables. This also stops
--the redundant re-uploads the unguarded version produced each refresh.
local g_patronDamageTypeAttributeReady = false

local function EnsurePatronDamageTypeAttribute()
    --Idempotently bootstrap the customAttributes table entry. Uses a stable
    --UUID so YAML references resolve across all instances. The attribute is a
    --stringset under the hood (the closest match in the existing type system
    --to "a single text value"); we read attr.strings[1] to recover the value.
    if g_patronDamageTypeAttributeReady then
        return
    end

    --GetTable can return a non-nil-but-not-yet-upload-ready table during early
    --refreshTables passes; in that window SetAndUploadTableItem dereferences a
    --null backing store inside the engine and throws a NullReferenceException.
    --Guard on the table being a populated table before attempting any upload.
    local attrTable = dmhub.GetTable(CustomAttribute.tableName)
    if type(attrTable) ~= "table" then
        return
    end

    local existing = attrTable[ACOLYTE_PATRON_DAMAGE_TYPE_ATTRIBUTE_ID]
    if existing ~= nil and not existing:try_get("hidden", false) then
        --Already present in the database -- nothing to create, and never
        --re-upload it on later refreshes.
        g_patronDamageTypeAttributeReady = true
        return
    end

    --The attribute is missing. Defer the create+upload via dmhub.Schedule so it
    --runs after the current load/refresh pass settles, when the customAttributes
    --table's backing store is fully initialized and SetAndUploadTableItem is
    --safe to call. (Same deferral trick used for the symbol re-registration and
    --the OnEndCast hook install below.)
    dmhub.Schedule(0.01, function()
        if mod.unloaded then return end
        if g_patronDamageTypeAttributeReady then return end

        local t = dmhub.GetTable(CustomAttribute.tableName)
        if type(t) ~= "table" then
            --Table still not ready; a later refreshTables will retry.
            return
        end

        local present = t[ACOLYTE_PATRON_DAMAGE_TYPE_ATTRIBUTE_ID]
        if present ~= nil and not present:try_get("hidden", false) then
            g_patronDamageTypeAttributeReady = true
            return
        end

        local attr = CustomAttribute.new{
            id = ACOLYTE_PATRON_DAMAGE_TYPE_ATTRIBUTE_ID,
            name = "Patron Damage Type",
            category = "Acolyte",
            classid = "global",
            attributeType = "stringset",
            baseValue = "",
        }

        local ok, err = pcall(dmhub.SetAndUploadTableItem, CustomAttribute.tableName, attr)
        if ok then
            g_patronDamageTypeAttributeReady = true
        else
            --Upload still not safe; leave the flag clear so a future
            --refreshTables retries. Log so the failure isn't silent.
            printf("PATRON DAMAGE:: Deferred customAttributes bootstrap not ready yet: %s", tostring(err))
        end
    end)
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
    EnsurePatronDamageTypeAttribute()
end)

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
        toggle = gui.PrettyButton{
            width = 140,
            height = 40,
            fontSize = 14,
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

        local invoke = ability:try_get("invoke")
        local cost = (invoke and tonumber(invoke.cost)) or 0

        --Mark the cast as invoked so Cast.Invoked = 1 in GoblinScript.
        --FireCastControlsOnCommit pre-builds the cast object (assigning it to
        --symbols.cast) before invoking us when one doesn't already exist, so
        --`cast` is guaranteed non-nil here. ability:Cast respects an existing
        --options.symbols.cast (see ActivatedAbility.lua:2498-2514), so this
        --flag flows through to all behaviors and tier-text formulas.
        if cast ~= nil then
            cast.invoked = true
        end

        --Apply self damage (Presence) and Patron's Gaze increment as part of
        --the same ModifyProperties transaction so they undo together.
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
-- 7. ActivatedAbilityPatronGazeResolveBehavior
----------------------------------------------------------------------
-- Custom ActivatedAbility behavior used inside the Patron's Gaze risk-roll
-- triggered ability. It runs AFTER an ActivatedAbilityRollBehavior in the same
-- triggered ability's behavior list, reads that roll from Cast.Roll
-- (options.symbols.cast.roll), and compares it to the caster's current Patron's
-- Gaze:
--   roll <= gaze : clear Patron's Gaze, grant 2 Zeal, fire patronspitetriggered
--                  (gazecleared = pre-clear gaze), chat "Patron's Spite activates!"
--   roll  > gaze : chat "your patron is appeased."

RegisterGameType("ActivatedAbilityPatronGazeResolveBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityPatronGazeResolveBehavior.summary = "Patron's Gaze Risk Resolve"

ActivatedAbility.RegisterType{
    id = "patron_gaze_resolve",
    text = "Patron's Gaze Risk Resolve",
    createBehavior = function()
        return ActivatedAbilityPatronGazeResolveBehavior.new{}
    end,
}

function ActivatedAbilityPatronGazeResolveBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Resolve Patron's Gaze risk roll"
end

function ActivatedAbilityPatronGazeResolveBehavior:Cast(ability, casterToken, targets, options)
    if casterToken == nil or not casterToken.valid then return end

    local pgId = GetPatronsGazeResourceId()
    if pgId == nil then
        return
    end

    --The d10 result lands on the cast object (Cast.Roll) via the preceding
    --ActivatedAbilityRollBehavior, which writes options.symbols.cast.roll.
    local cast = options and options.symbols and options.symbols.cast
    local roll = 0
    if cast ~= nil then
        roll = tonumber(cast:try_get("roll", 0)) or 0
    end

    --Read current Patron's Gaze. Unbounded resource: stored on the resource
    --entry's .unbounded field.
    local resources = casterToken.properties:GetResources() or {}
    local gaze = tonumber(resources[pgId]) or 0

    local triggered = roll <= gaze and gaze > 0

    if triggered then
        chat.Send(string.format("Patron's Gaze risk roll: rolled %d vs %d - Patron's Spite activates!", roll, gaze))
    else
        chat.Send(string.format("Patron's Gaze risk roll: rolled %d vs %d - your patron is appeased.", roll, gaze))
        return
    end

    --Clear Patron's Gaze and grant 2 Zeal (Clear Patron's Gaze rule).
    --All three side effects (clear, grant, fire trigger) flow through
    --ModifyProperties so they network atomically.
    local zealId = CharacterResource.heroicResourceId

    casterToken:ModifyProperties{
        description = "Patron's Spite",
        execute = function()
            --Zero out unbounded Patron's Gaze.
            --The Resource API doesn't have a direct "set unbounded to N"
            --helper, but RefreshResource with unbounded type adds to the
            --current value. To clear, we read and zero it.
            local props = casterToken.properties
            local rt = props:GetResourceTable("unbounded")
            if rt ~= nil and rt[pgId] ~= nil then
                rt[pgId].unbounded = 0
            end
            props:InvalidateResources()

            --Grant 2 Zeal (heroic resource is unbounded for Draw Steel).
            if zealId ~= nil then
                props:RefreshResource(zealId, "unbounded", 2, "Cleared Patron's Gaze")
            end

            --Fire the patronspitetriggered event on the caster. Patron
            --subclasses declare a triggered ability listening for this id.
            props:DispatchEvent("patronspitetriggered", {
                gazecleared = gaze,
            })
        end,
    }
end

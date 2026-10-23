local mod = dmhub.GetModLoading()

--- @class TargetableObject : creature
--- @field new fun(o?: table): TargetableObject
--- @field custom_collision? ActivatedAbility Custom Collision Behavior cast when something collides with the object; replaces collision damage.
TargetableObject = RegisterGameType("TargetableObject", "creature")
TargetableObject.resourceid = CharacterResource.maliceResourceId

--GoblinScript evaluated with the "ability" symbol bound to an ability that
--does not normally target objects; if it passes, the ability can target this
--object anyway. Empty = normal targeting rules only. Consumed by
--ActivatedAbility:ObjectGrantsTargeting.
TargetableObject.additionalTargetFilter = ""

--When true this object is exempt from the standard collision damage exchange in
--both directions: the creature knocked into it takes no damage from the Collision
--global rule, and the object itself takes none either. Collision triggers still
--fire on both sides, so the object's Custom Collision Behavior (custom_collision)
--is the sole source of damage and effects for the crash. Consumed by
--TargetableObject.TokenSuppressesCollisionDamage.
TargetableObject.no_collision_damage = false

--True if the given token is an object flagged to skip standard collision damage.
--Safe to call with any token: nil, non-objects and plain creatures return false.
function TargetableObject.TokenSuppressesCollisionDamage(token)
    if token == nil or not token.isObject or token.properties == nil then
        return false
    end

    return token.properties:try_get("no_collision_damage", false) == true
end

--Custom banner text for hidden traps, keyed by the object's lower-cased
--name; any other hidden object with "trap" in its name gets "<Name>!".
--Only a trap the players cannot see gets one: a visible trap was walked
--into knowingly. bannerType defaults to "malice", the Director's menace.
TargetableObject.hiddenTrapBanners = {
    ["snare trap"] = { text = "Snare Trap!", subtitle = "You have stepped into a trap!" },
}

--The engine dispatches "pressureplate" on the mover's own client only, so
--each springing shows the (game-wide) banner once.
local function ShowHiddenTrapBanner(self, args)
    local token = dmhub.LookupToken(self)
    if token == nil or not token.objectInvisibleToPlayers then
        return
    end
    local name = nil
    pcall(function() name = token.objectInstance.description end)
    if type(name) ~= "string" or name == "" then
        name = token.name
    end
    local banner = TargetableObject.hiddenTrapBanners[string.lower(tostring(name or ""))]
    if banner == nil then
        --an unlisted hidden trap still announces itself, by its own name.
        --Objects have no trap flag, and hidden teleporters and switches are
        --pressure plates too, so only a name with "trap" in it counts.
        if type(name) ~= "string" or not string.find(string.lower(name), "trap", 1, true) then
            return
        end
        banner = { text = name .. "!", subtitle = "You have stepped into a trap!" }
    end
    local victim = args ~= nil and args.target ~= nil and dmhub.LookupToken(args.target) or nil
    DramaticBanner.Show{
        tokenid = victim ~= nil and victim.charid or nil,
        text = banner.text,
        subtitle = banner.subtitle,
        bannerType = banner.bannerType or "malice",
    }
end

--Hooked on creature.DispatchEvent, not TargetableObject:DispatchEvent: the
--engine's pressure plate looks DispatchEvent up on the MOVER's properties and
--calls it with the object's properties as self, so the object's own
--override never runs. Chained like every other DispatchEvent wrapper.
local g_baseDispatchEvent = creature.DispatchEvent
function creature:DispatchEvent(eventName, args)
    if eventName == "pressureplate" and self.isMapObject then
        local ok, err = pcall(ShowHiddenTrapBanner, self, args)
        if not ok then
            printf("TargetableObject: hidden trap banner failed: %s", tostring(err))
        end
    end
    return g_baseDispatchEvent(self, eventName, args)
end

function TargetableObject:DispatchEvent(eventName, args)
    creature.DispatchEvent(self, eventName, args)
end

--Lets the shared creature damage path tell objects apart (see creature.isMapObject).
TargetableObject.isMapObject = true

--- Fires a table-wide moment (a new round, the end of combat) on every map
--- object that has a trigger for it. Objects have no initiative entry, so the
--- round and combat code that walks the initiative queue never reaches them.
--- Only objects with a matching trigger are dispatched to: a map can hold
--- hundreds of targetable objects, and each dispatch also notifies every token.
--- @param eventName string a trigger id, e.g. "beginround" or "endcombat"
--- @param info nil|table event arguments (copied per object)
function TargetableObject.DispatchToObjects(eventName, info)
    for _, tok in ipairs(dmhub.allObjectTokens or {}) do
        local props = tok.valid and tok.properties or nil
        if props ~= nil then
            for _, entry in ipairs(props:GetActiveModifiers()) do
                if entry.mod:HasTriggeredEvent(props, eventName, false) then
                    props:DispatchEvent(eventName, info ~= nil and shallow_copy_table(info) or {})
                    break
                end
            end
        end
    end
end

--True if any of this object's modifiers has a triggered ability for eventName.
--- @param eventName string
--- @return boolean
function TargetableObject:HasTriggerFor(eventName)
    for _, entry in ipairs(self:GetActiveModifiers()) do
        if entry.mod:HasTriggeredEvent(self, eventName) then
            return true
        end
    end
    return false
end

--At 0 Stamina the object fires "objectdestroyed" (the Destroyed trigger), and only
--then runs the engine's onDeath (delete/disable/open). With a Destroyed trigger the
--onDeath waits until that cast has finished, so a pillar is still on the map while
--its Toppling Pillar resolves. The wait is a detached coroutine: the attack that
--broke the object carries on without waiting for the object's own ability.
function TargetableObject.TakeDamage(self, amount, note, info)
    local staminaBefore = self:CurrentHitpoints()
    creature.TakeDamage(self, amount, note, info)
    local staminaAfter = self:CurrentHitpoints()
    if staminaBefore > 0 and staminaAfter <= 0 then
        local token = dmhub.LookupToken(self)
        --Damage is only dealt to properties that belong to a live object token.
        ---@cast token -nil

        if not self:HasTriggerFor("objectdestroyed") then
            token.objectComponent:OnDeath()
            return
        end

        info = info or {}
        local args = {
            damage = cond(type(amount) == "number", amount, staminaBefore - staminaAfter),
            damagetype = info.damagetype or "untyped",
            attacker = info.attacker,
            hasattacker = info.attacker ~= nil,
        }

        local charid = token.charid
        dmhub.Coroutine(function()
            self:DispatchEventAndWait("objectdestroyed", args, {ignoreTurn = true})

            --Re-resolve: the token may have been replaced by a synced write while we waited.
            local tok = dmhub.GetTokenById(charid) or dmhub.LookupToken(self)
            if tok ~= nil and tok.valid and tok.objectComponent ~= nil then
                tok.objectComponent:OnDeath()
            end
        end)
    end
end

--Engine hook (ObjectComponentTargetable.GenerateOperateCommand), asked while the
--object is hovered: can `token` operate this object (a Field Ballista with
--adjacent-creature abilities)? Returns the hover text and cursor to show, or
--nil for no command. Clicking runs TargetableObject:Operate.
--- @param token CharacterToken the local user's current token
--- @param objectToken CharacterToken this object's token
--- @return nil|{text: string, cursor: string}
function TargetableObject:GetOperateCommand(token, objectToken)
    local actionBar = rawget(_G, "DrawSteelActionBar")
    if actionBar == nil or token == nil or not token.canControlAsUser then
        return nil
    end

    local operation = actionBar.GetOperation()
    if operation ~= nil and operation.object.charid == objectToken.charid then
        return nil
    end

    if not ActivatedAbility.CanOperate(token, objectToken) then
        return nil
    end

    --An object with just one ability (a Candelabra's Throw) names it: the
    --click casts it directly. When the rules won't allow it right now, the
    --hover says why and the click does nothing.
    local single = ActivatedAbility.GetSingleAdjacentAbility(objectToken, token)
    if single ~= nil then
        local reason = ActivatedAbility.AdjacentAbilityBlockedReason(single, token, objectToken)
        return {
            text = cond(reason == nil, single.name, string.format("%s (%s)", single.name, reason)),
            cursor = "hand",
        }
    end

    --"Use" for an object that only grants abilities (a Candelabra to throw).
    local verb = cond(ActivatedAbility.HasOperatedAbilities(objectToken), "Operate", "Use")
    return {
        text = string.format("%s %s", verb, creature.GetTokenDescription(objectToken)),
        cursor = "hand",
    }
end

--Engine hook: the Operate command was clicked. An object with one ability
--casts it straight away (Escape cancels; the action bar is never taken
--over); one with several switches the action bar to them, operated by `token`.
--- @param token CharacterToken
--- @param objectToken CharacterToken
function TargetableObject:Operate(token, objectToken)
    local actionBar = rawget(_G, "DrawSteelActionBar")
    if actionBar == nil then
        return
    end

    local single = ActivatedAbility.GetSingleAdjacentAbility(objectToken, token)
    if single ~= nil then
        if ActivatedAbility.AdjacentAbilityBlockedReason(single, token, objectToken) == nil then
            actionBar.CastAdjacentAbility(token, objectToken, single)
        end
        return
    end

    actionBar.BeginOperating(token, objectToken)
end

dmhub.CreateTargetableComponent = function()
    return TargetableObject.new{
        attributes = creature.CreateAttributes(),
    }
end

--True when this "creature" is really a map object (a Targetable component on a
--LevelObject: a hazard, destructible prop, wall voxel...) rather than an actual
--creature. Objects bind as creature-typed properties and are indistinguishable
--from creatures in GoblinScript otherwise, which matters for effects that
--should treat the battlefield's furniture differently from its combatants.
--
--The motivating case: an area hazard that grants its allies cover via an aura.
--The aura's "friends" filter with no caster means "everything not aligned with
--the players", which includes the hazard object itself, so the hazard was
--granting itself cover. Putting `not IsObject` on the granting modifier's
--filterCondition withholds it from the object while leaving the aura otherwise
--untouched. Filtering the MODIFIER rather than narrowing the aura matters:
--scripts that watch their own object's auras to detect that the registration
--is still live rely on the aura continuing to apply to the object.
--
--Fails safe: a creature whose token cannot be resolved reads as NOT an object,
--so filters written against this keep applying to real creatures.
GameSystem.RegisterGoblinScriptField{
    name = "Is Object",

    type = "boolean",
    desc = "True if this is a map object (such as a hazard, destructible prop, or wall voxel) rather than a real creature.",
    examples = {"not IsObject"},

    calculate = function(c)
        local token = dmhub.LookupToken(c)
        return token ~= nil and token.valid and token.objectInstance ~= nil
    end,
}

--Wall voxels spawned by abilities are stamped with the creating creature's
--charid in the "wallcreator" property (see AbilityBuildWall.lua). Expose it to
--GoblinScript hashed the same way as creature ids, so targeting filters can
--say e.g. "Target.WallCreator = Caster.ID" (the Wallmaster targeting only
--walls made by its own Living Labyrinth trait). Registered on creature (the
--base type of TargetableObject); non-walls return 0, which never matches an id.
GameSystem.RegisterGoblinScriptField{
    name = "Wall Creator",

    type = "number",
    desc = "The id of the creature that created this wall object, or 0 if it was not created by a creature. Compare against a creature's ID field.",
    examples = {"Target.WallCreator = Caster.ID"},

    calculate = function(c)
        return Utils.HashGuidToNumber(c:try_get("wallcreator", ""))
    end,
}

--The creature whose ability made this object, or nil if none did.
local function GetObjectCreator(c)
    local creatorid = c:try_get("objectcreator") or c:try_get("wallcreator")
    if creatorid == nil then
        return nil
    end

    local creatorToken = dmhub.GetCharacterById(creatorid)
    if creatorToken == nil then
        return nil
    end

    return creatorToken.properties
end

--Lets an object's formulas use its creator's stats, such as
--Caster.Creator.Reason for extra damage when something hits a wall.
GameSystem.RegisterGoblinScriptField{
    name = "Creator",

    type = "creature",
    desc = "The creature that created this object with an ability.\n\n<color=#ffaaaa><i>This field is only available for objects created by a creature's ability.</i></color>",
    examples = {"Caster.Creator.Reason", "Target.Creator.ID = Caster.ID"},

    calculate = GetObjectCreator,
}

--True for the topmost wall voxel of its tile's column. Wall abilities that
--detach/topple "a square of wall" (e.g. the Wallmaster's Wall Slam) use this
--to only offer the exposed top cube of a stacked column as a target.
GameSystem.RegisterGoblinScriptField{
    name = "Wall Top",

    type = "boolean",
    desc = "True if this object is the topmost wall voxel on its tile. Also true for anything that is not a wall voxel.",
    examples = {"Target.WallCreator = Caster.ID and Target.WallTop"},

    calculate = function(c)
        local token = dmhub.LookupToken(c)
        if token == nil or not token.valid or token.objectInstance == nil then
            return true
        end

        local loc = token.loc
        local voxelFloor = game.currentMap:GetFloorFromLoc(loc)
        if voxelFloor == nil then
            return true
        end

        local voxels = voxelFloor:GetWallVoxelsAt(loc)
        if voxels == nil or #voxels == 0 then
            return true
        end

        local top = voxels[#voxels]
        return top ~= nil and top.objid == token.objectInstance.objid
    end,
}

--The custom behavior runs alongside the standard damage rather than replacing it:
--only "No Collision Damage" opts the object out of taking collision damage.
function TargetableObject:OnCollide(collidingToken, symbols)
    local token = dmhub.LookupToken(self)
    if token == nil then
        return
    end

    if self:has_key("custom_collision") then
        --Collision formulas can write Creator as a short form of Caster.Creator.
        local castSymbols = {
            creator = GetObjectCreator(self),
        }

        self.custom_collision:Cast(token, { { token = collidingToken } }, { symbols = castSymbols })
    end

    if symbols.speed and not self:try_get("no_collision_damage", false) then
        token:ModifyProperties{
            description = "Collision",
            undoable = false,
            execute = function()
                token.properties:InflictDamageInstance(symbols.speed, "untyped", {}, "Collision", {})
            end,
        }
    end
end

function TargetableObject.CreatePropertiesEditor(component)
    return TargetableObject.CreateMultiPropertiesEditor{component}
end

function TargetableObject.CreateMultiPropertiesEditor(components)
    --local self = component.properties
    print("Target:: CreatePropertiesEditor", components)
    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = {
            {
                classes = {"field-editor-label"},
                fontSize = 12,
                minFontSize = 10,
                width = "auto",
                height = "auto",
                maxWidth = 120,
            },
            {
                classes = {"field-editor-panel"},
                flow = "horizontal",
            },
            {
                classes = {"field-editor-input"},
                fontSize = 12,
            },
        },
        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "horizontal",
            minHeight = 0,
            gui.Label{
                classes = {"field-editor-label"},
                text = "Stamina",
                halign = "left",
                valign = "center",
            },
            gui.Input{
                classes = {"field-editor-input"},
                halign = "right",
                valign = "center",
                text = tostring((components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0)),
                width = 30,
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        local stamina = (components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0)
                        element.text = tostring(stamina)
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil then
                            element:FireEvent("refresh")
                            return
                        end
                        local damage_taken = (components[1].properties.max_hitpoints or 1) - n
                        if damage_taken < 0 then
                            damage_taken = 0
                        end
                        for _, component in ipairs(components) do
                            component:BeginChanges()
                            component.properties.damage_taken = damage_taken
                            component:CompleteChanges("Change object stamina")
                        end
                        resultPanel:FireEventTree("refresh")
                    end,
                },
            },
            gui.Label{
                text = "/",
                fontSize = 14,
                height = "auto",
                width = "auto",
                halign = "right",
                valign = "center",
                hmargin = 8,
            },
            gui.Input{
                classes = {"field-editor-input"},
                text = tostring(components[1].properties.max_hitpoints or 1),
                width = 30,
                halign = "right",
                valign = "center",
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        element.text = tostring(components[1].properties.max_hitpoints or 1)
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil then
                            element:FireEvent("refresh")
                            return
                        end
                        for _, component in ipairs(components) do
                            component:BeginChanges()
                            component.properties.max_hitpoints = n
                            component:CompleteChanges("Change object stamina")
                        end
                        resultPanel:FireEventTree("refresh")
                    end,
                },
            }
        },

        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "vertical",
            minHeight = 0,
            gui.Label{
                classes = {"field-editor-label"},
                text = "Also Targetable By:",
                halign = "left",
            },
            gui.GoblinScriptInput{
                width = 250,
                halign = "left",
                value = components[1].properties:try_get("additionalTargetFilter", ""),
                change = function(element)
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        component.properties.additionalTargetFilter = element.value
                        component:CompleteChanges("Change additional targeting filter")
                    end
                end,
                documentation = {
                    help = "Abilities that do not normally target objects can target this object if this GoblinScript passes. Leave blank to use normal targeting rules only.",
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "This object",
                    symbols = {
                        ability = {
                            name = "Ability",
                            type = "ability",
                            desc = "The ability being checked against this object.",
                            examples = {
                                'Ability.Keywords has "Strike"',
                                'Ability.Keywords has "Melee"',
                            },
                        },
                        caster = {
                            name = "Caster",
                            type = "creature",
                            desc = "The creature using the ability.",
                            examples = {
                                "Caster.Level > 2",
                            },
                        },
                    },
                },
            },
        },

        gui.Panel{
            classes = {"field-editor-panel"},
            flow = "vertical",
            minHeight = 0,
            gui.Check{
                text = "No Collision Damage",
                value = components[1].properties:try_get("no_collision_damage", false),
                fontSize = 14,
                change = function(element)
                    local val = element.value
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        component.properties.no_collision_damage = val
                        component:CompleteChanges("Change collision damage")
                    end
                end,
            },

            gui.Check{
                text = "Custom Collision Behavior",
                value = components[1].properties:try_get("custom_collision", false) ~= false,
                fontSize = 14,
                change = function(element)
                    local val = element.value
                    for _, component in ipairs(components) do
                        component:BeginChanges()
                        if val == false then
                            component.properties.custom_collision = nil
                        else
                            component.properties.custom_collision = ActivatedAbility.Create{
                                name = "Custom Collision Behavior",
                                behaviors = {},
                            }
                        end
                        component:CompleteChanges("Change custom collision behavior")
                    end
                    resultPanel:FireEventTree("refresh")
                end,
            },

            gui.Button{
                text = "Edit Behavior",
                width = 200,
                height = 22,
                fontSize = 16,
                refresh = function(element)
                    element:SetClass("collapsed", components[1].properties:try_get("custom_collision", false) == false)
                end,
                press = function(element)
                    element.root:AddChild(components[1].properties.custom_collision:ShowEditActivatedAbilityDialog{
                        close = function()
                            components[1]:Upload()
                            resultPanel:FireEventTree("refresh")
                        end,
                    })
                end,
            },

            gui.Button{
                text = "Object Sheet",
                width = 200,
                height = 22,
                fontSize = 16,
                press = function(element)
                    local token = dmhub.LookupToken(components[1].properties)
                    if token ~= nil then
                        token:ShowSheet()
                    end
                end,
            },
        }
    }

    return resultPanel
end
local mod = dmhub.GetModLoading()

--- @class TargetableObject : creature
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

function TargetableObject:DispatchEvent(eventName, args)
    creature.DispatchEvent(self, eventName, args)
end

function TargetableObject.TakeDamage(self, amount, note, info)
    local staminaBefore = self:CurrentHitpoints()
    creature.TakeDamage(self, amount, note, info)
    local staminaAfter = self:CurrentHitpoints()
    if staminaBefore > 0 and staminaAfter <= 0 then
        local token = dmhub.LookupToken(self)
        token.objectComponent:OnDeath()
    end
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

function TargetableObject:OnCollide(collidingToken, symbols)
    if self:has_key("custom_collision") then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            self.custom_collision:Cast(token, { { token = collidingToken } }, symbols)
        end
    else
        if symbols.speed and not self:try_get("no_collision_damage", false) then
            local token = dmhub.LookupToken(self)
            if token ~= nil then
                token:ModifyProperties{
                    description = "Collision",
                    undoable = false,
                    execute = function()
                        token.properties:InflictDamageInstance(symbols.speed, "untyped", {}, "Collision", {})
                    end,
                }
            end
        end
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
                text = (components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0),
                width = 30,
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        local stamina = (components[1].properties.max_hitpoints or 1) - (components[1].properties.damage_taken or 0)
                        element.text = stamina
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
                text = components[1].properties.max_hitpoints or 1,
                width = 30,
                halign = "right",
                valign = "center",
                characterLimit = 3,
                events = {
                    refresh = function(element)
                        element.text = components[1].properties.max_hitpoints or 1
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
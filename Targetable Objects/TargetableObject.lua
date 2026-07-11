local mod = dmhub.GetModLoading()

--- @class TargetableObject : creature
TargetableObject = RegisterGameType("TargetableObject", "creature")
TargetableObject.resourceid = CharacterResource.maliceResourceId

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
        if symbols.speed then
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
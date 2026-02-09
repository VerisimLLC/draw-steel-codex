local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCreateObjectBehavior:ActivatedAbilityBehavior
ActivatedAbilityCreateObjectBehavior = RegisterGameType("ActivatedAbilityCreateObjectBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCreateObjectBehavior.summary = 'Create Object'
ActivatedAbilityCreateObjectBehavior.randomize = false
ActivatedAbilityCreateObjectBehavior.targetFloor = 0

ActivatedAbility.RegisterType
{
	id = 'create_object',
	text = 'Create Object',
	createBehavior = function()
		return ActivatedAbilityCreateObjectBehavior.new{
            objectid = false
		}
	end
}

function ActivatedAbilityCreateObjectBehavior:Cast(ability, casterToken, targets, options)
    local targetArea = options.targetArea
    local locations = nil
    print("CAST:: AREA:", targetArea)
    if targetArea ~= nil then
        locations = targetArea.locations
    else
        locations = {}

        for _,target in ipairs(targets or {}) do
            if target.loc ~= nil then
                locations[#locations+1] = target.loc
            end
        end
    end

    if locations == nil or #locations == 0 then
        print("CAST:: NO LOCATIONS")
        return
    end

    print("CAST:: LOCATIONS:", #locations)

    --make sure we do the top locations first so their zorder is behind.
    table.sort(locations, function(a, b) return a.y > b.y end)
    for _,loc in ipairs(locations) do
        local targetFloor = game.currentMap:GetFloorFromLoc(loc)
        print("CAST:: TARGET FLOOR:", targetFloor)
        if targetFloor ~= nil then
            local spawnOptions = {
                spawnChildren = true,
                outChildren = {},
            }

            local xdelta = 0
            local ydelta = 0
            if options.symbols.cast.auraObject then
                spawnOptions.parentid = options.symbols.cast.auraObject.objid
                xdelta = -options.symbols.cast.auraObject.x
                ydelta = -options.symbols.cast.auraObject.y
            end
            local obj = targetFloor:SpawnObjectLocal(self.objectid, spawnOptions)
            if obj ~= nil then
                obj.x = loc.x + xdelta
                obj.y = loc.y + ydelta
                for _,child in ipairs(spawnOptions.outChildren) do
                    if self.randomize then
                        for _,component in pairs(child.components) do
                            component:Randomize{
                                hue = 0.2,
                                playbackSpeed = 0.1,
                                xflip = true,
                            }
                        end
                    end

                    child:Upload()
                end
            end
        end
    end
end

function ActivatedAbilityCreateObjectBehavior:EditorItems(parentPanel)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local objectOptions = {}
    for _,object in pairs(assets.allObjects) do
        local keywords = nil
        if object.components ~= nil then
            local core = object.components["CORE"]
            if core ~= nil then
                for _,field in ipairs(core.fields) do
                    if field.id == "keywords" then
                        keywords = field.currentValue
                        break
                    end
                end
            end
        end

        if keywords ~= nil and #keywords ~= 0 then
            print("KEYWORDS::", keywords)
        end
        if keywords ~= nil and table.contains(keywords, "summonable") then
            print("KEYWORDS:: SELECT", object, object.description)
            objectOptions[#objectOptions+1] = { id = object.id, text = object.description }
        end
    end

    local Refresh
    Refresh = function()
        local children = {}

    	self:ApplyToEditor(parentPanel, children)

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Object:",
            },
            gui.Dropdown{
                options = objectOptions,
                textDefault = "Choose Object...",
                idChosen = self.objectid,
                change = function(element)
                    self.objectid = element.idChosen
                    Refresh()
                end,
            }
        }

        children[#children+1] = gui.Check{
            text = "Randomize Objects",
            value = self.randomize,
            change = function(element)
                self.randomize = element.value
                Refresh()
            end,
        }

        panel.children = children
    end

    Refresh()

    return {panel}


end
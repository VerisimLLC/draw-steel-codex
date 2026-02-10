local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityManipulateTargetLocs:ActivatedAbilityBehavior
ActivatedAbilityManipulateTargetLocs = RegisterGameType("ActivatedAbilityManipulateTargetLocs", "ActivatedAbilityBehavior")

ActivatedAbilityManipulateTargetLocs.summary = 'Manipulate Target Locations'
ActivatedAbilityManipulateTargetLocs.mode = "floor_down"

ActivatedAbility.RegisterType
{
	id = 'manipulate_target_locs',
	text = 'Manipulate Target Locations',
	createBehavior = function()
		return ActivatedAbilityManipulateTargetLocs.new{
		}
	end
}

function ActivatedAbilityManipulateTargetLocs:Cast(ability, casterToken, targets, options)
    for i=#targets,1,-1 do
        local target = targets[i]
        if target.loc ~= nil then
            local floorid = game.currentMap:GetFloorFromLoc(target.loc).actualFloor
            local floor = nil
            for i,f in ipairs(game.currentMap.floors) do
                if f.floorid == floorid then
                    floor = i
                    break
                end
            end

            if floor ~= nil then

                local dir = 1
                if self.mode == "floor_down" then
                    dir = -1
                end

                local targetFloor = floor + dir
                local floors = game.currentMap.floors
                while floors[targetFloor] ~= nil and not floors[targetFloor].isPrimaryLayerOnFloor do
                    targetFloor = targetFloor + dir
                end

                if floors[targetFloor] ~= nil then
                    local newLoc = target.loc:WithDifferentFloor(targetFloor-1)
                    target.loc = newLoc
                else
                    table.remove(targets,i)
                end
            end
        end
    end
end

function ActivatedAbilityManipulateTargetLocs:EditorItems(parentPanel)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local Refresh
    Refresh = function()
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Mode:",
            },
            gui.Dropdown{
                options = {
                    {id = "floor_down", text = "Floor Down"},
                    {id = "floor_up", text = "Floor Up"},
                },
                idChosen = self.mode,
                change = function(element)
                    self.mode = element.idChosen
                    Refresh()
                end,
            }
        }

        panel.children = children
    end

    Refresh()

    return {panel}
end
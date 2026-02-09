local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityChangeElevationBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'terraform_elevation',
	text = 'Terraform Elevation',
	createBehavior = function()
		return ActivatedAbilityChangeElevationBehavior.new{
		}
	end
}

ActivatedAbilityChangeElevationBehavior.summary = 'Terraform Elevation'
ActivatedAbilityChangeElevationBehavior.shape = 'circle'
ActivatedAbilityChangeElevationBehavior.radius = 1
ActivatedAbilityChangeElevationBehavior.height = "2"
ActivatedAbilityChangeElevationBehavior.recalculateElevation = true
ActivatedAbilityChangeElevationBehavior.testFalling = false

function ActivatedAbilityChangeElevationBehavior:Cast(ability, casterToken, targets, options)
    local height = dmhub.EvalGoblinScript(self.height, casterToken.properties:LookupSymbol(options.symbols), string.format("Height for %s", ability.name))
    local hasChanges = false

    if options.targetArea ~= nil and options.targetArea.shape == "Cube" then

        game.currentFloor:ChangeElevation{
            type = "rectangle",
            p1 = { x = options.targetArea.origin.x - options.targetArea.radius/2, y = options.targetArea.origin.y - options.targetArea.radius/2 },
            p2 = { x = options.targetArea.origin.x + options.targetArea.radius/2, y = options.targetArea.origin.y + options.targetArea.radius/2 },
            opacity = 1,
            height = height,
            add = true,
        }

    else
        if options.targetArea ~= nil then
            print("TARGET::", options.targetArea, "->", #options.targetArea.perimeter)
            game.currentFloor:ChangeElevation{
                type = "polygon",
                points = options.targetArea.perimeter,
                opacity = 1,
                height = height,
                add = true,
                recalculateTokenElevation = self.recalculateElevation,
            }
        else
            local targetLocs = {}
            for _,target in ipairs(targets) do
                if target.loc ~= nil then
                    targetLocs[#targetLocs + 1] = target.loc
                end
            end

            for _,loc in ipairs(targetLocs) do
                if self.shape == "circle" then
                    game.currentFloor:ChangeElevation{
                        type = "ellipse",
                        center = { x = loc.x, y = loc.y },
                        radius = self.radius,
                        opacity = 1,
                        height = height,
                        add = true,
                        recalculateTokenElevation = self.recalculateElevation,
                    }
                else
                    game.currentFloor:ChangeElevation{
                        type = "rectangle",
                        p1 = { x = loc.x - self.radius/2, y = loc.y - self.radius/2 },
                        p2 = { x = loc.x + self.radius/2, y = loc.y + self.radius/2 },
                        opacity = 1,
                        height = height,
                        add = true,
                        recalculateTokenElevation = self.recalculateElevation,
                    }
                end
                
                ability:CommitToPaying(casterToken, options)
                hasChanges = true
            end
        end
    end

    if hasChanges and self.testFalling then
        for _,token in ipairs(dmhub.allTokens) do
            token:TryFall()
        end
    end
end

function ActivatedAbilityChangeElevationBehavior:EditorItems(parentPanel)
    local result = {}

    print("SHAPE:: XX", self.shape)
    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Shape:",
        },

        gui.Dropdown{
            idChosen = self.shape,
            options = {
                {id = 'circle', text = 'Circle'},
                {id = 'square', text = 'Square'},
            },
            change = function(element)
                print("SHAPE:: SET", self.shape, "->", element.idChosen)
                self.shape = element.idChosen
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Radius:",
        },

        gui.Input{
            classes = {"formInput"},
            width = 100,
            text = tostring(self.radius),
            characterLimit = 16,
            change = function(element)
                self.radius = tonumber(element.text) or self.radius
                element.text = tostring(self.radius)
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Height:",
        },

        gui.GoblinScriptInput{
            value = self.height,
            change = function(element)
                self.height = element.value
            end,
            documentation = {
                help = "This GoblinScript determines the height of the terrain change. Positive values will make terrain higher, negative values will make the terrain lower.",
                output = "number",
                subject = creature.helpSymbols,
				subjectDescription = "The creature invoking the ability",
            },
        }
    }

    result[#result+1] = gui.Check{
        text = "Recalculate creature elevation",
        value = self.recalculateElevation,
        change = function(element)
            self.recalculateElevation = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Test creature falling",
        value = self.testFalling,
        change = function(element)
            self.testFalling = element.value
        end,
    }

    return result
end

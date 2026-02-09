local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityChangeTerrainBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
    id = 'terraform_terrain',
    text = 'Terraform Terrain',
    createBehavior = function()
        return ActivatedAbilityChangeTerrainBehavior.new {
        }
    end
}

ActivatedAbilityChangeTerrainBehavior.summary = 'Terraform Terrain'
ActivatedAbilityChangeTerrainBehavior.shape = 'circle'
ActivatedAbilityChangeTerrainBehavior.radius = 1
ActivatedAbilityChangeTerrainBehavior.tileid = "none"

function ActivatedAbilityChangeTerrainBehavior:Cast(ability, casterToken, targets, options)
    if self.tileid == "none" then
        return
    end

    if options.targetArea ~= nil then
        local points = {}
        local perim = options.targetArea.perimeter
        for i=1,#perim do
            local pt = perim[i]
            points[#points + 1] = pt.x
            points[#points + 1] = pt.y
        end

        print("TARGET:: EXECUTE WITH", #points / 2, "points")

        game.currentFloor:ExecutePolygonOperation {
            points = { points },
            closed = true,
            tileid = self.tileid,
            terrain = true,
            fade = 0.2,
        }

        ability:CommitToPaying(casterToken, options)

        return
    end

    for _, target in ipairs(targets) do
        if target.loc ~= nil then
            local points = {}
            if self.shape == "circle" then
                local radius = self.radius
                for i = 0, 350, 10 do
                    local angle = math.rad(i)
                    points[#points + 1] = target.loc.x + radius * math.cos(angle)
                    points[#points + 1] = target.loc.y + radius * math.sin(angle)
                end
            else
                points[#points + 1] = target.loc.x - self.radius / 2
                points[#points + 1] = target.loc.y - self.radius / 2
                points[#points + 1] = target.loc.x + self.radius / 2
                points[#points + 1] = target.loc.y - self.radius / 2
                points[#points + 1] = target.loc.x + self.radius / 2
                points[#points + 1] = target.loc.y + self.radius / 2
                points[#points + 1] = target.loc.x - self.radius / 2
                points[#points + 1] = target.loc.y + self.radius / 2
            end

            game.currentFloor:ExecutePolygonOperation {
                points = { points },
                closed = true,
                tileid = self.tileid,
                terrain = true,
                fade = 0.2,
            }

            ability:CommitToPaying(casterToken, options)
        end
    end
end

function ActivatedAbilityChangeTerrainBehavior:EditorItems(parentPanel)
    local result = {}

    result[#result + 1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Shape:",
        },

        gui.Dropdown {
            idChosen = self.shape,
            options = {
                { id = 'circle', text = 'Circle' },
                { id = 'square', text = 'Square' },
            },
            change = function(element)
                self.shape = element.idChosen
            end,
        }
    }

    result[#result + 1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Radius:",
        },

        gui.Input {
            classes = { "formInput" },
            width = 100,
            text = tostring(self.radius),
            characterLimit = 16,
            change = function(element)
                self.radius = tonumber(element.text) or self.radius
                element.text = tostring(self.radius)
            end,
        }
    }

    local terrainOptions = {
        {
            id = "none",
            text = "None",
        }
    }

    for key, tilesheet in pairs(assets.tilesheets) do
        if not tilesheet.hidden then
            terrainOptions[#terrainOptions + 1] = {
                id = key,
                text = tilesheet.description,
            }
        end
    end

    result[#result + 1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Terrain:",
        },

        gui.Dropdown {
            idChosen = self.tileid,
            hasSearch = true,
            sort = true,
            options = terrainOptions,
            change = function(element)
                self.tileid = element.idChosen
            end,
        }
    }

    return result
end

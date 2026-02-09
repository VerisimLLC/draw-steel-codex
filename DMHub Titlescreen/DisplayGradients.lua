local mod = dmhub.GetModLoading()

local GradientRegistry = {}

DisplayGradients = {}

DisplayGradients.Register = function(info)
    GradientRegistry[info.id] = info
end

DisplayGradients.GetOptions = function()
    local result = {}

    result[#result+1] = {
        id = "none",
        text = "None",
    }

    for k,entry in pairs(GradientRegistry) do
        result[#result+1] = {
            id = entry.id,
            text = entry.id,
        }
    end

    return result
end

DisplayGradients.GetGradient = function(id)
    local entry = GradientRegistry[id]
    if entry ~= nil then
        return entry.gradient
    end
end

DisplayGradients.Register{
    id = "Red",
    gradient = gui.Gradient{
        point_a = {x = 0},
        point_b = {x = 1},
        stops = {
            {
                position = 0,
                color = "#ff000000",
            },
            {
                position = 0.05,
                color = "#ff0000ff",
            },
            {
                position = 1,
                color = "#000000ff",
            },
        }
    }
}
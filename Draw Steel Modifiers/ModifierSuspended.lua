local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('suspended', "Suspended In Air")

CharacterModifier.TypeInfo.suspended = {
    init = function(modifier)
        modifier.altitude = 1
    end,

    onTokenRefresh = function(modifier, creature, token)
        creature._tmp_suspended = modifier.altitude
    end,

    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Altitude:",
                },
                gui.Input{
                    text = tostring(modifier.altitude),
                    change = function(element)
                        local val = tonumber(element.text) or 1
                        modifier.altitude = val
                        Refresh()
                    end,
                }
            }

            element.children = children
        end

        Refresh()
    end,

}
local mod = dmhub.GetModLoading()

local g_interactives = {}

Interactive = {
    Register = function(args)
        local modRegistering = dmhub.GetModLoading()
        local modid = "none"
        if modRegistering ~= nil then
            modid = modRegistering.modid
        end

        local id = string.format("%s.%s", modid, args.id)

        g_interactives[id] = args
    end,

}

dmhub.GetObjectInteractives = function()
    local result = {}

    for k,v in pairs(g_interactives) do
        result[#result+1] = {
            id = k,
            info = v,
            text = v.name,
        }
    end

    table.sort(result, function(a,b) return a.name < b.name end)
    return result
end

dmhub.ShowObjectInteractive = function(objid, interactiveid)

    local mainPanel

    local info = g_interactives[interactiveid]
    if info == nil then
        return
    end

    local currentMode = "PlayerView"

    local modeSelection = nil
    if dmhub.isDM and info.EditView ~= nil then
        local press = function(element)
            for _,item in ipairs(element.parents) do
                item:SetClass("selected", item == element)
            end

            currentMode = element.data.mode
            mainPanel:FireEvent("refreshView")
        end

        modeSelection = gui.Panel{
            styles = {
                Styles.AdvantageBar,
            },
            classes = {"advantage-bar"},

            gui.Label{
                classes = {"advantage-element", "selected"},
                text = "Player View",
                press = press,
                data = {mode = "PlayerView"},
            },
            gui.Label{
                classes = {"advantage-element"},
                text = "Edit View",
                press = press,
                data = {mode = "EditView"},
            },
        }
    end

    local CreateView = function()
        local fn = info[currentMode]
        if fn == nil then
            return nil
        end

        return fn(objid)
    end

    mainPanel = gui.Panel{
        width = 1600,
        height = 900,

        CreateView(),

        modeSelection,

        refreshView = function(element)
            local children = element.children
            children[1] = CreateView()
            element.children = children
        end,
    }

    local parentPanel = gui.Panel{
        width = "100%",
        height = "!00%",
        bgimage = "panels/square.png",
        bgcolor = "#000000f2",
        styles = {
            {
                selectors = {"create"},
                transitionTime = 0.2,
                opacity = 0,
            },
        },

        press = function(element)
            gui.CloseModal()
        end,

        escapeActivates = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,

        mainPanel,
    }

    return parentPanel
end
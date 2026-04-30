local mod = dmhub.GetModLoading()

--- gui.EnumeratedSliderControl -- a horizontal row of selectable options.
function gui.EnumeratedSliderControl(args)
    local m_resultPanel = nil

    local options = args.options
    args.options = nil

    local m_value = args.value
    args.value = nil

    local optionWidth = args.optionWidth or (100/#options .. "%")
    args.optionWidth = nil

    local callerStyles = args.styles
    args.styles = nil

    local children = {}

    local SetValue = function(value, suppressEvent)
        m_value = value
        for _, child in ipairs(children) do
            child.SetClass(child, "selected", child.data.id == value)
        end
        if not suppressEvent then
            m_resultPanel:FireEvent("change")
        end
    end

    for _, option in ipairs(options) do
        children[#children+1] = gui.Label{
            classes = {"enumSliderOption", cond(m_value == option.id, "selected")},
            data = { id = option.id },
            text = option.text,
            width = optionWidth,
            press = function()
                SetValue(option.id)
            end,
        }
    end

    local params = {
        styles = callerStyles,
        classes = {"enumSlider"},
        children = children,
    }

    params.GetValue = function()
        return m_value
    end

    params.SetValue = function(_, val, firechange)
        SetValue(val, not firechange)
    end

    for k, v in pairs(args) do
        params[k] = v
    end

    m_resultPanel = gui.Panel(params)
    return m_resultPanel
end

local mod = dmhub.GetModLoading()

local enumSliderStyles = {
    {
        selectors = {"enumSlider"},
        width = "100%",
        height = 24,
        flow = "horizontal",
    },
    {
        selectors = {"enumSliderOption"},
        bgimage = "panels/square.png",
        bgcolor = "black",
        color = Styles.textColor,
        fontSize = 12,
        bold = true,
        halign = "center",
        valign = "center",
        borderWidth = 2,
        borderColor = Styles.textColor,
        textAlignment = "center",
        height = "100%",
    },
    {
        selectors = {"enumSliderOption", "selected"},
        bgcolor = Styles.textColor,
        color = "black",
        transitionTime = 0.2,
    },
    {
        selectors = {"enumSliderOption", "hover"},
        bgcolor = Styles.textColor,
        color = "black",
        brightness = 1.5,
        transitionTime = 0.2,
    },
}

function gui.EnumeratedSliderControl(args)

    local m_resultPanel = nil

    local options = args.options
    args.options = nil

    local m_value = args.value
    args.value = nil

    local optionWidth = args.optionWidth or (100/#options .. "%")
    args.optionWidth = nil

    local children = {}

    local SetValue = function(value, suppressEvent)
        m_value = value
        for _,child in ipairs(children) do
            child.SetClass(child, "selected", child.data.id == value)
        end

        if not suppressEvent then
            m_resultPanel:FireEvent("change")
        end
    end

    for _,option in ipairs(options) do
        local optionPanel = gui.Label{
            classes = {"enumSliderOption", cond(m_value == option.id, "selected")},
            data = {
                id = option.id,
            },
            text = option.text,
            width = optionWidth,
            press = function(element)
                SetValue(option.id)
            end,
        }

        children[#children+1] = optionPanel
    end

    local params = {
        styles = enumSliderStyles,
        classes = {"enumSlider"},

        children = children,
    }

    params.GetValue = function(element, val)
        return m_value
	end

	params.SetValue = function(element, val, firechange)
        SetValue(val, not firechange)
	end

    for k,v in pairs(args) do
        if k == "styles" then
            params.styles = table.shallow_copy(params.styles)
            for _,style in ipairs(v) do
                params.styles[#params.styles+1] = style
            end
        else
            params[k] = v
        end

    end

    m_resultPanel = gui.Panel(params)
    return m_resultPanel
end

local mod = dmhub.GetModLoading()

--- Component-private styles for the enumerated slider. Uses @-refs that get
--- resolved against the active theme via ThemeEngine.MergeStyles. Caller-passed
--- `styles` (if any) are appended after these, preserving caller-override semantics.
local function getEnumSliderStyles()
    return {
        {
            selectors = {"enumSlider"},
            width = "100%",
            height = 24,
            flow = "horizontal",
        },
        {
            selectors = {"enumSliderOption"},
            bgimage = "panels/square.png",
            bgcolor = "@background",
            color = "@text",
            fontSize = 12,
            bold = true,
            halign = "center",
            valign = "center",
            borderWidth = 2,
            borderColor = "@text",
            textAlignment = "center",
            height = "100%",
        },
        {
            selectors = {"enumSliderOption", "selected"},
            bgcolor = "@text",
            color = "@background",
            transitionTime = 0.2,
        },
        {
            selectors = {"enumSliderOption", "hover"},
            bgcolor = "@text",
            color = "@background",
            brightness = 1.5,
            transitionTime = 0.2,
        },
    }
end

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

    local function buildMergedStyles()
        local merged = ThemeEngine.MergeStyles(getEnumSliderStyles())
        if callerStyles then
            for _, s in ipairs(callerStyles) do
                merged[#merged + 1] = s
            end
        end
        return merged
    end

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
        styles = buildMergedStyles(),
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
        params[k] = v
    end

    m_resultPanel = gui.Panel(params)

    -- Refresh styles on theme/scheme changes so existing sliders follow the active scheme.
    ThemeEngine.OnThemeChanged(mod, function()
        if m_resultPanel and m_resultPanel.valid then
            m_resultPanel.styles = buildMergedStyles()
        end
    end)

    return m_resultPanel
end

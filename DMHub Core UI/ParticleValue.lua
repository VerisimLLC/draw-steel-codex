local mod = dmhub.GetModLoading()

function gui.FloatInput(args)

    local m_dragAnchorValue = nil
    local m_value = args.value or 0
    args.value = nil

    local m_allowNegative = args.allowNegative
    args.allowNegative = nil

    local resultPanel

    local EnsurePositive = function(val)
        if (not m_allowNegative) then
            return math.max(0, val)
        end

        return val
    end


    local m_label = gui.Label{
        classes = {"sizeXs"},
        halign = "center",
        valign = "center",
        width = "100%",
        height = "100%",
        refreshValue = function(element)
            local magnitude = math.abs(m_value)
            if magnitude < 1 then
                element.text = string.format("%.3f", m_value)
            elseif magnitude < 10 then
                element.text = string.format("%.2f", m_value)
            elseif magnitude < 100 then
                element.text = string.format("%.1f", m_value)
            else
                element.text = string.format("%.0f", m_value)
            end
        end,

        editable = true,
        characterLimit = 10,

        dragThreshold = 1,

        draggable = true,
        dragMove = false,
        beginDrag = function(element)
            m_dragAnchorValue = m_value
            element.thinkTime = 0.05
        end,
        drag = function(element)
            element.thinkTime = nil
            resultPanel:FireEvent("confirm", m_value)
        end,
        dragging = function(element, target)
            if m_dragAnchorValue == nil then
                return
            end

            m_value = m_dragAnchorValue + element.dragDelta.x*0.05
            resultPanel.data.setValue(resultPanel, m_value, true)
        end,

        think = function(element)
            if element.dragging then
                dmhub.OverrideMouseCursor("horizontal-expand", 0.2)
            end
        end,

        change = function(element)
            local n = tonumber(element.text)
            print("CONFIRM:: confirming value", element.text, n)
            if n == nil then
                element:FireEvent("refreshValue")
                return
            end

            resultPanel.data.setValue(resultPanel, n, true)
            resultPanel:FireEvent("confirm", m_value)
        end,
    }

    local params = {

        data = {
            getValue = function(element)
                return m_value
            end,
            setValue = function(element, val, fireevent)
                if val == nil then
                    return
                end

                val = EnsurePositive(val)

                m_value = val
                resultPanel:FireEventTree("refreshValue")
                if fireevent then
                    element:FireEvent("change", val)
                end
            end,

            setValueNoEvent = function(val)
                if val == nil then
                    return
                end

                val = EnsurePositive(val)
                m_value = val
                resultPanel:FireEventTree("refreshValue")
            end,
        },

        halign = "center",
        valign = "center",
        width = 50,
        height = 20,

        m_label,
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)

    resultPanel.GetValue = resultPanel.data.getValue
    resultPanel.SetValue = resultPanel.data.setValue

    resultPanel:FireEventTree("refreshValue")

    return resultPanel
end

function gui.ParticleValue(args)

    local resultPanel

    local m_value = args.value
    args.value = nil

    local GetSubValue = function(n)
        if n == 1 then
            if type(m_value) == "table" then
                return m_value.val
            else
                return m_value
            end
        else
            if type(m_value) == "table" then
                return m_value.maxVal
            else
                return nil
            end
        end
    end

    local SetSubValue = function(n, val)
        if n == 1 then
            if type(m_value) == "table" then
                m_value.val = val
            else
                m_value = val
            end
        else
            if type(m_value) == "table" then
                m_value.maxVal = val
            else
                m_value = {val = m_value, maxVal = val}
            end
        end
    end

    local m_allowNegative = args.allowNegative
    args.allowNegative = nil


    local CreateValueLabel = function(index)
        return gui.FloatInput{
            halign = "center",
            value = GetSubValue(index),
            allowNegative = m_allowNegative,
            change = function(element)
                SetSubValue(index, element.value)

                resultPanel.data.setValue(resultPanel, m_value, true)
            end,

            confirm = function(element)
                print("CONFIRM::", m_value)
                resultPanel:FireEvent("confirm", m_value)
            end,

            refreshValue = function(element)
                local val = GetSubValue(index)
                if val == nil then
                    element:SetClass("collapsed", true)
                    return
                end
                element:SetClass("collapsed", false)
            end,
        }
    end

    local m_valueLabel = CreateValueLabel(1)
    local m_maxValueLabel = CreateValueLabel(2)

    local m_modeButton = gui.Button{
        width = 32,
        height = 14,
        vmargin = 0,
        valign = "center",
        halign = "right",
        fontSize = 10,
        rmargin = 2,
        borderWidth = 1,
        refreshValue = function(element)
            print("REFRESH::", m_value)
            if type(m_value) == "table" then
                element.text = "Range"
            else
                element.text = "Fixed"
            end
        end,
        click = function(element)
            local val
            if type(m_value) == "number" then
                val = {val = m_value, maxVal = m_value}
            else
                val = m_value.val
            end

            resultPanel.data.setValue(resultPanel, val, true)
            resultPanel:FireEvent("confirm")
        end,
    }

    local EnsurePositive = function(val)
        if (not m_allowNegative) then
            if type(val) == "number" and val < 0 then
                val = 0
            elseif type(val) == "table" then
                val.val = math.max(0, val.val)
                val.maxVal = math.max(0, val.maxVal)
            end
        end

        return val
    end

    local callerStyles = (args and args.styles) or nil
    if args then args.styles = nil end

    local panelParams = {
        styles = callerStyles,
        width = 140,
        height = 20,
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "black",
        cornerRadius = 4,
        opacity = 0.5,
        wrap = false,

        data = {
            getValue = function(element)
                return m_value
            end,
            setValue = function(element, val, fireevent)
                val = EnsurePositive(val)

                m_value = val
                resultPanel:FireEventTree("refreshValue")
                if fireevent then
                    element:FireEvent("change", val)
                end
            end,

            setValueNoEvent = function(val)
                val = EnsurePositive(val)
                m_value = val
                resultPanel:FireEventTree("refreshValue")
            end,
        },

        m_valueLabel,
        m_maxValueLabel,

        m_modeButton,
    }

    for k,v in pairs(args or {}) do
        panelParams[k] = v
    end

    resultPanel = gui.Panel(panelParams)

	resultPanel.GetValue = resultPanel.data.getValue
	resultPanel.SetValue = resultPanel.data.setValue

    resultPanel.data.setValue(resultPanel, m_value, false)

    return resultPanel
end
local mod = dmhub.GetModLoading()

function TextSearch(haystack, needle)
	if string.find(string.lower(haystack), needle, 1, true) or string.find(string.lower(tr(haystack)), needle, 1, true) then
		return true
	else
		return false
	end
end

function TransitionStyle(panel, time, attributes)
    local finish = function()
		if not panel.valid then 
			return
		end
        for key,val in pairs(attributes) do
            panel.selfStyle[key] = val
        end
    end

    if time <= 0 then
        finish()
        return
    end

    local startingAttributes = {}
    for key,val in pairs(attributes) do
        if panel.selfStyle[key] == nil then
            panel.selfStyle[key] = val
        end
        startingAttributes[key] = panel.selfStyle[key]
    end

    local startTime = dmhub.Time()
    local endTime = startTime + time

    local tickFunction

    tickFunction = function()
		if not panel.valid then 
			return
		end
        local r = (dmhub.Time() - startTime) / time
        if r >= 1 then
            finish()
            return
        end

        for key,val in pairs(attributes) do
            panel.selfStyle[key] = startingAttributes[key] + (val - startingAttributes[key]) * r
        end

        dmhub.Schedule(0.01, tickFunction)
    end

    dmhub.Schedule(0.01, tickFunction)
end
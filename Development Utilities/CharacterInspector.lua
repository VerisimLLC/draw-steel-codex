local mod = dmhub.GetModLoading()


local CreateInspectorPanel

DockablePanel.Register{
	name = "Character Inspector",
	icon = mod.images.chatIcon,
	minHeight = 200,
	vscroll = true,
    devonly = true,
	folder = "Development Tools",
	content = function()
		return CreateInspectorPanel()
	end,
}


local g_customScriptsSetting = setting{
    id = "dev:customScripts",
    default = {},
    storage = "preference",
}

CreateInspectorPanel = function()

    local inspectorPanel

    local tokenPanel = gui.CreateTokenImage(nil, {
        width = 32,
        height = 32,
    })

    local customEntriesList = g_customScriptsSetting:Get()
    print("INSPECTOR:: LOAD", customEntriesList)

    local SaveEntries = function()
        local entries = {}
        for i,entry in ipairs(customEntriesList) do
            entries[#entries+1] = {
                text = entry.text,
            }
        end
        g_customScriptsSetting:Set(entries)
    end

    local customEntriesPanel = gui.Panel{
        flow = "vertical",
        width = "95%",
        height = "auto",
        halign = "left",
        thinkTime = 0.2,
        think = function(element)
            local selectedTokens = dmhub.selectedTokens or {}
            local token = selectedTokens[1]
            if token == nil then
                return
            end

            local children = {}
            for i,entry in ipairs(customEntriesList) do
                entry.panel = entry.panel or gui.Panel{
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    bgimage = true,

                    gui.Label {
                        halign = "left",
                        width = "50%",
                        height = "auto",
                        fontSize = 12,
                        text = entry.text,
                        editable = true,

                        change = function(element)
                            entry.text = string.trim(element.text)
                            element.text = entry.text
                            SaveEntries()
                        end,
                    },
                    gui.Label {
                        width = "45%",
                        height = "auto",
                        fontSize = 12,
                        minFontSize = 8,
                        halign = "right",
                        valign = "center",
                        updateValue = function(element, val)
                            if tonumber(val) ~= nil and round(tonumber(val)) == tonumber(val) then
                                val = string.format("%d", round(tonumber(val)))
                            end
                            element.text = val
                        end,

                        gui.DeleteItemButton{
                            halign = "right",
                            width = 12,
                            height = 12,
                            valign = "center",
                            click = function(element)
                                for i=1, #customEntriesList do
                                    if customEntriesList[i] == entry then
                                        table.remove(customEntriesList, i)
                                        break
                                    end
                                end
                                SaveEntries()
                            end,
                        },
                    }
                }

                local value = ExecuteGoblinScript(entry.text, token.properties:LookupSymbol{}, 0, "custom entry")
                entry.panel:FireEventTree("updateValue", value)
                children[#children+1] = entry.panel
            end

            element.children = children
        end,
    }

    local goblinScriptInput = gui.GoblinScriptInput{
        width = 272,
        value = "",
        multiline = false,
        placeholderText = "Enter Custom Goblin Script...",
        change = function(element)
            local text = string.trim(element.value)
            customEntriesList[#customEntriesList+1] = {text = text}
            SaveEntries()
            element.value = ""
        end,
        documentation = {
            help = "Enter a goblin script here to evaluate in the character inspector.",
            output = "roll",
            subject = creature.helpSymbols,
            subjectDescription = "The creature that is selected.",
        }
    }

    local searchInput = gui.SearchInput{
        vmargin = 4,
        edit = function(element)
            local s = trim(string.lower(element.text))
            if s == "" then
                s = nil
            end
            inspectorPanel:FireEventTree("search", s)
        end,
    }

    local panelsCache = {}

    local AddEntry = function(token, k, name, value, docs, newPanelsCache, children)

            if type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" and type(value) ~= "table" then
                return
            end
                local newPanel = panelsCache[k] or gui.Panel{
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    bgimage = true,

                    search = function(element, s)
                        if s == nil then
                            element:SetClass("collapsed", false)
                            return
                        end

                        local match = false
                        if string.find(string.lower(name), s) ~= nil then
                            match = true
                        elseif string.find(string.lower(k), s) ~= nil then
                            match = true
                        end

                        element:SetClass("collapsed", not match)
                    end,

                    hover = function(element)
                        local customInfo = CustomAttribute.attributeInfoByLookupSymbol[k]
                        print("INFO::", customInfo)
                        if customInfo ~= nil then
                            local baseValue = customInfo:CalculateBaseValue(token.properties)
                            local modifications = token.properties:DescribeModifications(customInfo.id, 0)
                            local panels = {}
                            local text
                            if type(baseValue) == "number" then
                                text = string.format("Base Value: %d", round(baseValue))
                            else
                                text = "--"
                            end
                            panels[#panels+1] = gui.Label{
                                text = text,
                                fontSize = 12,
                                halign = "left",
                                width = "auto",
                                height = "auto",
                            }
                            for _,modification in ipairs(modifications) do
                                panels[#panels+1] = gui.Label{
                                    text = string.format("%s: %s", modification.key, modification.value),
                                    fontSize = 12,
                                    halign = "left",
                                    width = "auto",
                                    height = "auto",
                                }
                            end

                            local container = gui.Panel{
                                width = "auto",
                                height = "auto",
                                flow = "vertical",
                                children = panels,
                            }

                            element.tooltip = gui.TooltipFrame(container)
                            print("INFO:: TOOLTIP")

                        end
                    end,

                    gui.Label {
                        halign = "left",
                        width = "50%",
                        height = "auto",
                        fontSize = 14,
                        minFontSize = 8,
                        text = docs.name .. ":",
                    },
                    gui.Label {
                        width = "45%",
                        height = "auto",
                        fontSize = 14,
                        minFontSize = 8,
                        halign = "right",
                        updateValue = function(element, val, newToken)
                            if newToken ~= nil then
                                token = newToken
                            end
                            if type(val) == "table" then
                                if val.typeName == "StringSet" then
                                    if #val.strings == 0 then
                                        element.text = "(none)"
                                    else
                                        element.text = string.format("%s", string.join(val.strings, "\n"))
                                    end
                                else
                                    element.text = string.format("(%s)", tostring(val.typeName))
                                end
                            else
                                element.text = tostring(val)
                                
                            end
                        end,
                    }
                }

                newPanelsCache[k] = newPanel
                newPanel:FireEventTree("updateValue", value, token)
                children[#children+1] = newPanel

                local index = #children
                if index%2 == 0 then
                    newPanel.selfStyle.bgcolor = "#000000"
                else
                    newPanel.selfStyle.bgcolor = "#222222"
                end

    end


	inspectorPanel = gui.Panel{
		id = 'inspector-panel',
		hpad = 6,
        width = "100%",
		height = "auto",
        flow = "vertical",
        thinkTime = 0.2,

        think = function(element)
            local selectedTokens = dmhub.selectedTokens or {}
            local token = selectedTokens[1]
            if token == nil then
                return
            end

            tokenPanel:FireEventTree("token", token)

            local children = { tokenPanel, goblinScriptInput, customEntriesPanel, searchInput }
            local newPanelsCache = {}

            local index = 1
            local creatureInfo = token.properties
            for k, fn in sorted_pairs(creature.lookupSymbols) do
                local docs = creature.helpSymbols[k]
                if docs ~= nil and type(fn) == "function" then
                    local value = fn(creatureInfo)
                    AddEntry(token, k, docs.name, value, docs, newPanelsCache, children)
                end
            end

            panelsCache = newPanelsCache
            element.children = children
        end,


        tokenPanel,
        goblinScriptInput,
        customEntriesPanel,
        searchInput,

	}


	return inspectorPanel
end


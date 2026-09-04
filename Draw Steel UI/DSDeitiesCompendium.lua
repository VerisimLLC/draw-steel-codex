local mod = dmhub.GetModLoading()

local SetDeity = function(tableName, deityPanel, deityId)
    local deityTable = dmhub.GetTable(tableName) or {}
    local deity = deityTable[deityId]
    
    if not deity then
        deityPanel.children = {}
        return
    end
    
    local UploadDeity = function()
        dmhub.SetAndUploadTableItem(tableName, deity)
    end

    local children = {}

    -- Name Input
    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Name:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = deity.name or "",
            change = function(element)
                deity.name = element.text
                UploadDeity()
            end,
        },
    }

    -- Group Input
    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Group:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = deity.group or "",
            change = function(element)
                deity.group = element.text
                UploadDeity()
            end,
        },
    }

    -- Description Input
    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Description:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = deity.description or "",
            multiline = true,
            height = 60,
            textAlignment = "topLeft",
            characterLimit = 4096,
            change = function(element)
                deity.description = element.text
                UploadDeity()
            end,
        }
    }

    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Domains:",
        },
        gui.Multiselect{
            classes = {"formStacked"},
            addItemText = "Add Domain...",
            value = (function()
                local v = {}
                for _,id in ipairs(deity:GetDomains()) do
                    v[id] = true
                end
                return v
            end)(),
            options = DeityDomain.GetDropdownList(),
            change = function(element, val)
                local newDomains = {}
                for id,_ in pairs(val) do
                    newDomains[#newDomains+1] = id
                end
                deity.domainList = newDomains
                UploadDeity()
            end,
        },
    }

    deityPanel.children = children
end

local CreateDeityEditor = function()
    local deityEditor
    deityEditor = gui.Panel{
        data = {
            SetDeity = function(tableName, deityId)
                SetDeity(tableName, deityEditor, deityId)
            end,
        },
        vscroll = true,
        width = 1200,
        height = "90%",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return deityEditor
end

--- @param contentPanel Panel
ShowDeities = function(contentPanel)
    local selectedDeityId = nil
    local deityPanel = CreateDeityEditor()
    local dataItems = {}

    local itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        create = function(element)
            element:FireEvent("refreshAssets")
        end,
        refreshAssets = function(element)
            local t = dmhub.GetTable(Deity.tableName) or {}
            local newDataItems = {}
            local children = {}

            for k, item in pairs(t) do
                newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = Deity.tableName,
                    key = k,
                    select = element.aliveTime > 0.2,
                    click = function()
                        selectedDeityId = k
                        deityPanel.data.SetDeity(Deity.tableName, k)
                    end,
                }

                newDataItems[k].text = item.name

                children[#children+1] = newDataItems[k]
            end

            table.sort(children, function(a,b) return a.text < b.text end)
            dataItems = newDataItems
            element.children = children
        end,
    }

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = 'vertical',
            height = '100%',
            width = 'auto',
        },
        itemsListPanel,
        Compendium.AddButton{
            click = function()
                dmhub.SetAndUploadTableItem(Deity.tableName, Deity.CreateNew{})
            end,
        }
    }

    contentPanel.children = {leftPanel, deityPanel}
end

Compendium.Register{
    section = "Rules",
    text = "Deities",
    click = function(contentPanel)
        ShowDeities(contentPanel)
    end,
}

local SetDomain = function(tableName, domainPanel, domainId)
    local domainTable = dmhub.GetTable(tableName) or {}
    local domain = domainTable[domainId]

    if not domain then
        domainPanel.children = {}
        return
    end
    
    local UploadDomain = function()
        dmhub.SetAndUploadTableItem(tableName, domain)
    end

    local children = {}

    -- Name Input
    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Name:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = domain.name or "",
            change = function(element)
                domain.name = element.text
                UploadDomain()
            end,
        },
    }

    domainPanel.children = children
end

local CreateDomainEditor = function()
    local domainEditor
    domainEditor = gui.Panel{
        data = {
            SetDomain = function(tableName, domainId)
                SetDomain(tableName, domainEditor, domainId)
            end,
        },
        vscroll = true,
        width = 1200,
        height = "90%",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return domainEditor
end

--- @param contentPanel Panel
ShowDomains = function(contentPanel)
    local selectedDomainId = nil
    local domainPanel = CreateDomainEditor()
    local dataItems = {}

    local itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        create = function(element)
            element:FireEvent("refreshAssets")
        end,
        refreshAssets = function(element)
            local t = dmhub.GetTable(DeityDomain.tableName) or {}
            local newDataItems = {}
            local children = {}

            for k, item in pairs(t) do
                newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = DeityDomain.tableName,
                    key = k,
                    select = element.aliveTime > 0.2,
                    click = function()
                        selectedDomainId = k
                        domainPanel.data.SetDomain(DeityDomain.tableName, k)
                    end,
                }

                newDataItems[k].text = item.name

                children[#children+1] = newDataItems[k]
            end

            table.sort(children, function(a,b) return a.text < b.text end)
            dataItems = newDataItems
            element.children = children
        end,
    }

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = 'vertical',
            height = '100%',
            width = 'auto',
        },
        itemsListPanel,
        Compendium.AddButton{
            click = function()
                dmhub.SetAndUploadTableItem(DeityDomain.tableName, DeityDomain.CreateNew())
            end,
        }
    }

    contentPanel.children = {leftPanel, domainPanel}
end

Compendium.Register{
    section = "Rules",
    text = "Domains",
    click = function(contentPanel)
        ShowDomains(contentPanel)
    end,
}
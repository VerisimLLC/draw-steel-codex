local mod = dmhub.GetModLoading()

local AddButton = function(options)
    local args = {
        style = {
            width = 32,
            height = 32,
            halign = 'right',
            valign = 'top',
        },
    }

    for k,v in pairs(options) do
        args[k] = v
    end

    return gui.AddButton(args)
end


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
        classes = {'formPanel'},
        gui.Label{
            text = 'Name:',
            valign = 'center',
            minWidth = 240,
        },
        gui.Input{
            text = deity.name or "",
            change = function(element)
                deity.name = element.text
                UploadDeity()
            end,
        },
    }

    -- Group Input
    children[#children+1] = gui.Panel{
        classes = {'formPanel'},
        gui.Label{
            text = 'Group:',
            valign = 'center',
            minWidth = 240,
        },
        gui.Input{
            text = deity.group or "",
            change = function(element)
                deity.group = element.text
                UploadDeity()
            end,
        },
    }

    -- Description Input
    children[#children+1] = gui.Panel{
        classes = {'formPanel'},
        height = 'auto',
        gui.Label{
            text = "Description:",
            valign = "center",
            minWidth = 240,
        },
        gui.Input{
            text = deity.description or "",
            multiline = true,
            minHeight = 50,
            maxHeight = 400,
            vscroll = true,
            height = 'auto',
            width = 400,
            textAlignment = "topleft",
            change = function(element)
                deity.description = element.text
                UploadDeity()
            end,
        }
    }

    children[#children+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Domains:",
            minWidth = 240,
        },
    }

    
    children[#children+1] = gui.Panel{
        id = "domainDropdown",
        classes = {"formPanel"},
        gui.Dropdown{
            width = 300,
            height = 32,
            valign = "center",
            fontSize = 18,
            idChosen = "none",
            options = DeityDomain.GetDropdownListWithAdd(deity:GetDomains()),
            valign = "bottom",
            change = function(element)
                if element.idChosen ~= "none" then
                    deity:AddDomain(element.idChosen)
                    dmhub.SetAndUploadTableItem(tableName, deity)
                end
                element:FireEvent("refreshList")
            end,

            refreshList = function(element)
                element.options = DeityDomain.GetDropdownListWithAdd(deity:GetDomains())
                element.idChosen = "none"
            end,
        }
    }

    -- Domains List
    children[#children+1] = gui.Panel{
        width = "auto",
        height = "auto", 
        flow = "vertical",
        monitorAssets = true,
        create = function(element)
            element:FireEvent("refreshAssets")
        end,
        refreshAssets = function(element)
            -- Always get fresh deity data
            local currentDeity = dmhub.GetTable(tableName)[deityId]
            if not currentDeity then return end
            
            local domainTable = dmhub.GetTable(DeityDomain.tableName) or {}
            local domainChildren = {}
            for i, id in ipairs(currentDeity:GetDomains()) do
                local domain = domainTable[id]
                --Will remove in future
                if domain == nil then
                    if id.typeName == "DeityDomain" then
                        currentDeity.domainList = {}
                        break
                    end
                end
                --

                domainChildren[#domainChildren+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        text = domain.name,
                        valign = "center",
                        width = 180,
                        fontSize = 16,
                    },
                    gui.CloseButton{
                        uiscale = 0.7,
                        valign = "center",
                        click = function()
                            Deity.DeleteDomainById(currentDeity, id)
                            dmhub.SetAndUploadTableItem(tableName, currentDeity)
                            element:Get('domainDropdown').children[1]:FireEvent("refreshList")
                        end
                    }
                }
            end

            element.children = domainChildren
        end,
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
        classes = 'class-panel',
        styles = {
            {
                halign = "left",
            },
            {
                classes = {'class-panel'},
                width = 1200,
                height = '90%',
                halign = 'left',
                flow = 'vertical',
                pad = 20,
            },
            {
                classes = {'label'},
                color = 'white',
                fontSize = 22,
                width = 'auto',
                height = 'auto',
            },
            {
                classes = {'input'},
                width = 200,
                height = 26,
                fontSize = 18,
                color = 'white',
            },
            {
                classes = {'formPanel'},
                flow = 'horizontal',
                width = 'auto',
                height = 'auto',
                halign = 'left',
                vmargin = 2,
            },
        },
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
        classes = {'formPanel'},
        gui.Label{
            text = 'Name:',
            valign = 'center',
            minWidth = 240,
        },
        gui.Input{
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
        classes = 'class-panel',
        styles = {
            {
                halign = "left",
            },
            {
                classes = {'class-panel'},
            },
        },
        vscroll = true,
        classes = 'class-panel',
        styles = {
            {
                halign = "left",
            },
            {
                classes = {'class-panel'},
                width = 1200,
                height = '90%',
                halign = 'left',
                flow = 'vertical',
                pad = 20,
            },
            {
                classes = {'label'},
                color = 'white',
                fontSize = 22,
                width = 'auto',
                height = 'auto',
            },
            {
                classes = {'input'},
                width = 200,
                height = 26,
                fontSize = 18,
                color = 'white',
            },
            {
                classes = {'formPanel'},
                flow = 'horizontal',
                width = 'auto',
                height = 'auto',
                halign = 'left',
                vmargin = 2,
            },
        },
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
local mod = dmhub.GetModLoading()

RegisterGameType("Culture")

Culture.tableName = "cultures"

Culture.name = "Culture"
Culture.description = ""
Culture.group = "Custom"

Culture.languageid = ""
Culture.init = true

function Culture.CreateNew()
    local aspects = {}
    for i,cat in ipairs(CultureAspect.categories) do
        aspects[cat.id] = ""
    end
    local result = Culture.new{
        aspects = aspects,
    }

    return result
end

function Culture:Describe()
    return "Culture"
end

local cultureLanguageChoice = CharacterLanguageChoice.Create{
    guid = "cultureLanguageChoice",
    name = "Cultural Language",
    description = "Choose the language of your culture.",
}

local cultureLoreBenefit = nil
dmhub.RegisterEventHandler("refreshTables", function(keys)
    if cultureLoreBenefit == nil then
        cultureLoreBenefit = DeepCopy(MCDMImporter.GetStandardFeature("Culture Lore Benefit"))
        if cultureLoreBenefit ~= nil then
            cultureLoreBenefit.description = "You gain an edge on tests made to recall lore about your culture, and on tests made to influence and interact with people of your culture."
        end
    end
end)

function Culture:FillFeatureDetails(choices, result)
    local langFeatures = {}
    cultureLanguageChoice:FillFeaturesRecursive(choices, langFeatures)
    for _,f in ipairs(langFeatures) do
        result[#result+1] = {
            culture = self,
            feature = f,
        }
    end

    if cultureLoreBenefit ~= nil then
        result[#result+1] = {
            culture = self,
            feature = cultureLoreBenefit,
        }
    end

    local t = GetTableCached(CultureAspect.tableName)
    for k,v in pairs(self.aspects) do
        if v ~= "" then
            local entry = t[v]
            if entry ~= nil then
                entry:FillFeatureDetails(choices, result)
            end
        end
    end
end

function Culture:FillClassFeatures(choices, result)
    cultureLanguageChoice:FillChoice(choices, result)
    if cultureLoreBenefit ~= nil then
        cultureLoreBenefit:FillChoice(choices, result)
    end
    local t = dmhub.GetTable(CultureAspect.tableName)
    for k,v in pairs(self.aspects) do
        if v ~= "" then
            local entry = t[v]
            if entry ~= nil then
                entry:FillClassFeatures(choices, result)
            end
        end
    end
end

creature.culture = Culture.CreateNew()
creature.culture.init = false


function creature:GetCulture()
    return self.culture
end

--- @param tableName string
--- @param culturePanel Panel
--- @param cultureid string
local SetCulture = function(tableName, culturePanel, cultureid)
    local cultures = GetTableCached(tableName) or {}
    local culture = cultures[cultureid]

    if not culture then
        culturePanel.children = {}
        return
    end
    
    local UploadCulture = function()
        dmhub.SetAndUploadTableItem(tableName, culture)
    end

    local children = {}

    --the ID of the Culture.
    if dmhub.GetSettingValue("dev") then
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = 'ID:',
                valign = 'center',
                minWidth = 100,
            },
            gui.Label{
                text = culture.id,
            },
        }
    end

    --the name of the Culture.
    children[#children+1] = gui.Panel{
        classes = {'formPanel'},
        gui.Label{
            text = 'Name:',
            valign = 'center',
            minWidth = 100,
        },
        gui.Input{
            text = culture.name,
            change = function(element)
                culture.name = element.text
                UploadCulture()
            end,
        },
    }

    --the group of the Culture.
    children[#children+1] = gui.Panel{
        classes = {'formPanel'},
        gui.Label{
            text = 'Group:',
            valign = 'center',
            minWidth = 100,
        },
        gui.Input{
            text = culture.group,
            change = function(element)
                culture.group = element.text
                UploadCulture()
            end,
        },
    }

    --Culture description..
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        height = 'auto',
        gui.Label {
            text = "Description:",
            valign = "center",
            width = 135,
        },
        gui.Input {
            text = culture.description or "",
            multiline = true,
            minHeight = 50,
            height = 'auto',
            width = 400,
            textAlignment = "topleft",
            change = function(element)
                culture.description = element.text
                UploadCulture()
            end,
        }
    }

    --Language choice
    local languageChoices = cultureLanguageChoice:Choices(1, culture.languageid ~= "" and {culture.languageid} or {}, {})
    if languageChoices ~= nil and #languageChoices > 0 then
        table.sort(languageChoices, function(a, b) return a.text < b.text end)
        
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = 'Language:',
                valign = 'center',
                minWidth = 145,
            },
            gui.Dropdown{
                width = 300,
                height = 32,
                textDefault = "Choose Language...",
                options = languageChoices,
                idChosen = culture.languageid ~= "" and culture.languageid or 'none',
                change = function(element)
                    local choice = element.idChosen
                    if choice == 'none' then
                        culture.languageid = ""
                    else
                        culture.languageid = choice
                    end
                    
                    UploadCulture()
                end,
            },
        }
    end

    --Create dropdowns for each culture aspect category. Pulled from DSCultureAspect.lua
    for _, cat in ipairs(CultureAspect.categories) do
        local aspectId = culture.aspects[cat.id] or ""
        local aspectEntry = GetTableCached(CultureAspect.tableName)[aspectId]

        local aspectOptions = { { id = 'none', text = "None" } }
        local aspectEntries = {}
        for _,v in pairs(GetTableCached(CultureAspect.tableName) or {}) do
            if v.category == cat.id then
                aspectEntries[v.id] = v
                table.insert(aspectOptions, { id = v.id, text = v.name })
            end
        end

        table.sort(aspectOptions, function(a, b) return a.text < b.text end)

        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = cat.text .. ":",
                valign = 'center',
                minWidth = 145,
            },
            gui.Dropdown{
                width = 300,
                height = 32,
                textDefault = "Choose Aspect...",
                options = aspectOptions,
                idChosen = aspectId ~= "" and aspectId or 'none',
                change = function(element)
                    local choice = element.idChosen
                    if choice == 'none' then
                        culture.aspects[cat.id] = ""
                    else
                        culture.aspects[cat.id] = choice
                    end
                    
                    UploadCulture()
                end,
            },
        }
    end


    culturePanel.children = children
end

local CreateCultureEditor = function()
    local cultureEditor
    cultureEditor = gui.Panel{
        data = {
            SetCulture = function(tableName, cultureid)
                SetCulture(tableName, cultureEditor, cultureid)
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

    return cultureEditor
end

--- @param contentPanel Panel
local ShowCulturesPanel = function(contentPanel)
    local selectedCultureId = nil
    local culturesPanel = CreateCultureEditor()
    local dataItems = {}
    local sectionHeadings = {}

    local itemListPanel = gui.Panel{
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        create = function(element)
            element:FireEvent("refreshAssets")
        end,
        refreshAssets = function(element)
            local culturesTable = dmhub.GetTable(Culture.tableName) or {}
            local children = {}
            local newDataItems = {}
            local newHeadings = {}

            for k,culture in unhidden_pairs(culturesTable) do
                local group = culture.group or "Custom"

                if newHeadings[group] == nil then
                    newHeadings[group] = sectionHeadings[group] or gui.Label{
                        data = {
                            ord = group,
                        },
                        text = group,
                        fontSize = 20,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        lmargin = 4,
                    }

                    children[#children+1] = newHeadings[group]
                end

                newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = Culture.tableName,
                    key = k,
                    select = element.aliveTime > 0.2,
                    click = function()
                        selectedCultureId = k
                        culturesPanel.data.SetCulture(Culture.tableName, k)
                    end,
                }
            
                newDataItems[k].data.ord = group .. "-" .. culture.name
                newDataItems[k].text = culture.name
                children[#children+1] = newDataItems[k]
            end

            table.sort(children, function(a, b)
                return a.data.ord < b.data.ord
            end)

            sectionHeadings = newHeadings
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

        itemListPanel,
        Compendium.AddButton{
            click = function()
                dmhub.SetAndUploadTableItem(Culture.tableName, Culture.CreateNew{})
            end,
        }
    }

    contentPanel.children = {leftPanel, culturesPanel}
end


Compendium.Register{
    section = "Character",
    text = "Cultures",
    contentType = "cultures",
    click = function(contentPanel)
        ShowCulturesPanel(contentPanel)
    end,
}
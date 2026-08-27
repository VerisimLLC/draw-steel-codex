local mod = dmhub.GetModLoading()

--- The Director's editor for the FishSpecies compendium table
--- Shows one water type at a time with entries grouped under their size band,
--- which is how species are actually reasoned about when authoring them.
--- @class FishSpeciesEditor
FishSpeciesEditor = RegisterGameType("FishSpeciesEditor")

--- Phosphor families offered by the icon picker.
local ICON_SEARCHES = {
    "fish",
    "shrimp",
    "waves"
}

--- Builds the icon picker options from the live phosphor set
--- @return DropdownOption[] options List of { id, text } icon options
local function IconOptions()
    local options = {}
    local seen = {}

    for _, term in ipairs(ICON_SEARCHES) do
        for _, path in ipairs(assets:GetPhosphorIcons(term, 40) or {}) do
            if not seen[path] then
                seen[path] = true
                options[#options + 1] = {
                    id = path,
                    text = path:gsub("^phosphor/", ""):gsub("%.png$", "")
                }
            end
        end
    end

    return options
end

--- Builds dropdown options from a list of DTConstant instances
--- @param constants table The DTConstant list
--- @return DropdownOption[] options List of { id, text } options
local function ConstantOptions(constants)
    local options = {}
    for _, constant in ipairs(constants) do
        options[#options + 1] = {
            id = constant.key,
            text = constant.displayText
        }
    end
    return options
end

--- Wraps a labelled control in a themed form row
--- @param labelText string The field label
--- @param control Panel The control to label
--- @return Panel row The form row
local function FormRow(labelText, control)
    return gui.Panel{
        classes = { "formRow" },
        gui.Label{
            classes = { "label", "form" },
            text = labelText
        },
        control
    }
end

--- Creates the editor pane for a single species
--- Exposes data.SetData(id), the contract the compendium's list panels use.
--- @return Panel pane The editor pane
function FishSpeciesEditor.CreateEditor()
    local m_species = nil

    local Upload = function()
        if m_species ~= nil then
            dmhub.SetAndUploadTableItem(FishSpecies.tableName, m_species)
        end
    end

    local nameInput = gui.Input{
        classes = { "input", "form" },
        text = "",
        editlag = 0.4,
        change = function(element)
            if m_species == nil then
                return
            end
            m_species:SetName(element.text)
            Upload()
        end
    }

    local waterDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = ConstantOptions(FSHConstants.WATER_TYPE),
        change = function(element)
            if m_species == nil then
                return
            end
            m_species:SetWaterType(element.idChosen)
            Upload()
        end
    }

    local bandDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = ConstantOptions(FSHConstants.BAND),
        change = function(element)
            if m_species == nil then
                return
            end
            m_species:SetBand(element.idChosen)
            Upload()
        end
    }

    --Shows the glyph and the tint together, which is the thing actually being
    --authored: neither control alone tells you how the fish will read.
    local swatch = gui.Panel{
        width = 40,
        height = 40,
        halign = "left",
        valign = "center",
        lmargin = 12,
        bgimage = FSHConstants.GENERIC_FISH.icon,
        bgcolor = FSHConstants.GENERIC_FISH.color
    }

    local iconDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        options = IconOptions(),
        change = function(element)
            if m_species == nil then
                return
            end
            m_species:SetIcon(element.idChosen)
            swatch.bgimage = element.idChosen
            Upload()
        end
    }

    local colorPicker = gui.ColorPicker{
        width = 24,
        height = 24,
        halign = "left",
        valign = "center",
        borderWidth = 2,
        borderColor = "#999999ff",
        value = FSHConstants.GENERIC_FISH.color,
        change = function(element)
            swatch.selfStyle.bgcolor = element.value
        end,
        confirm = function(element)
            if m_species == nil then
                return
            end
            m_species:SetColor(element.value)
            swatch.selfStyle.bgcolor = element.value
            Upload()
        end
    }

    local flavorInput = gui.Input{
        classes = { "input", "form" },
        text = "",
        placeholderText = "One line, optional...",
        editlag = 0.4,
        change = function(element)
            if m_species == nil then
                return
            end
            m_species:SetFlavor(element.text)
            Upload()
        end
    }

    local emptyLabel = gui.Label{
        classes = { "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "Select a species to edit it."
    }

    local formPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",

        FormRow("Name:", nameInput),
        FormRow("Water:", waterDropdown),
        FormRow("Band:", bandDropdown),
        FormRow("Flavor:", flavorInput),
        FormRow("Icon:", gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "center",

            iconDropdown,
            swatch
        }),
        FormRow("Color:", colorPicker)
    }

    local pane
    pane = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        pad = 20,

        data = {
            SetData = function(speciesId)
                local speciesTable = dmhub.GetTable(FishSpecies.tableName) or {}
                m_species = speciesTable[speciesId or ""]

                formPanel:SetClass("collapsed", m_species == nil)
                emptyLabel:SetClass("collapsed", m_species ~= nil)
                if m_species == nil then
                    return
                end

                nameInput.text = m_species:GetName()
                waterDropdown.idChosen = m_species:GetWaterType()
                bandDropdown.idChosen = m_species:GetBand()
                flavorInput.text = m_species:GetFlavor()
                iconDropdown.idChosen = m_species:GetIcon()
                colorPicker.value = m_species:GetColor()
                swatch.bgimage = m_species:GetIcon()
                swatch.selfStyle.bgcolor = m_species:GetColor()
            end
        },

        emptyLabel,
        formPanel
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if pane ~= nil and pane.valid then
            pane.styles = ThemeEngine.GetStyles()
        end
    end)

    return pane
end

--- Builds the compendium content for the FishSpecies table
--- @param parentPanel Panel The compendium content panel to populate
function FishSpeciesEditor.Show(parentPanel)
    local m_waterType = FSHConstants.WATER_TYPE.FRESH.key

    local editorPanel = FishSpeciesEditor.CreateEditor()
    local editorContainerPanel = gui.Panel{
        width = 900,
        height = "95%",
        vscroll = true,

        editorPanel
    }

    local listPanel
    listPanel = gui.Panel{
        classes = { "list-panel" },
        vscroll = true,
        monitorAssets = true,

        refreshAssets = function(element)
            local children = {}
            local grouped = FishSpecies.GroupedByBand(m_waterType)

            for _, band in ipairs(FSHConstants.BAND) do
                local entries = grouped[band.key] or {}

                children[#children + 1] = gui.Label{
                    classes = { "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    tmargin = 8,
                    text = string.format("%s (%d)", band.displayText, #entries)
                }

                for _, species in ipairs(entries) do
                    local speciesId = species:GetID()
                    local item = Compendium.CreateListItem{
                        select = false,
                        tableName = FishSpecies.tableName,
                        key = speciesId,
                        text = species:GetName(),
                        click = function()
                            editorPanel.data.SetData(speciesId)
                        end
                    }
                    children[#children + 1] = item
                end
            end

            element.children = children
        end
    }

    listPanel:FireEvent("refreshAssets")

    local waterDropdown = gui.Dropdown{
        classes = { "dropdown", "form" },
        width = 160,
        halign = "left",
        options = ConstantOptions(FSHConstants.WATER_TYPE),
        idChosen = m_waterType,
        change = function(element)
            m_waterType = element.idChosen
            --The selected species may not belong to the water now in view.
            editorPanel.data.SetData(nil)
            listPanel:FireEvent("refreshAssets")
        end
    }

    local addButton = gui.Button{
        classes = { "sizeS" },
        width = 160,
        height = 24,
        halign = "left",
        vmargin = 8,
        text = "Add Species",
        hover = gui.Tooltip("Add a species to the water currently in view"),
        click = function()
            local band = FSHConstants.BAND.TINY.key
            local index = #FishSpecies.Entries(m_waterType, band) + 1
            dmhub.SetAndUploadTableItem(FishSpecies.tableName, FishSpecies.CreateNew{
                name = "New Fish",
                waterType = m_waterType,
                band = band,
                icon = FishSpecies.IconFor(band, index),
                color = FishSpecies.ColorFor(m_waterType, band, index)
            })
        end
    }

    local leftPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "100%",
        flow = "vertical",

        waterDropdown,
        listPanel,
        addButton
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if leftPanel ~= nil and leftPanel.valid then
            leftPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    parentPanel.children = { leftPanel, editorContainerPanel }
end

Compendium.Register{
    section = "Rules",
    text = "Fish Species",
    contentType = FishSpecies.tableName,
    click = function(contentPanel)
        FishSpeciesEditor.Show(contentPanel)
    end,
}

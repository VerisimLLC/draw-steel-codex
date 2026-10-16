local mod = dmhub.GetModLoading()

local function TranslateRichTextToMarkdown(lines)
    local result = ""
    for line in lines:gmatch("([^\n]+)") do
        local text = line

        for i=1,100 do
            local match = regex.MatchGroups(text, "^(?<prefix>.*?)<b>(?<match>.*?)</b>(?<suffix>.*)$")
            if match == nil then
                break
            end

            text = match.prefix .. "**" .. match.match .. "**" .. match.suffix
        end

        --flavor lines have the entire line as italic.
        local flavorMatch = regex.MatchGroups(text, "^\\s*<i>(?<flavor>[^<]+)</i>\\s*$")

        if flavorMatch ~= nil then
            text = "*" .. flavorMatch.flavor .. "*"
        end

        text = regex.ReplaceAll(text, "</?i>", "")

        if result == "" then
            result = text
        else
            result = result .. "\n" .. text
        end
    end
    return result
end

local function TranslateMarkdownToRichText(lines)
    local result = ""
    for line in lines:gmatch("([^\n]+)") do
        local text = line
        for i=1,100 do
            local match = regex.MatchGroups(text, "^(?<prefix>.*?)\\*\\*(?<match>.*?)\\*\\*(?<suffix>.*?)$")
            if match == nil then
                break
            end

            text = match.prefix .. "<b>" .. match.match .. "</b>" .. match.suffix
        end

        local flavorMatch = regex.MatchGroups(text, "^\\s*\\*(?<flavor>[^<]+)\\*\\s*$")
        if flavorMatch ~= nil then
            text = "<i>" .. flavorMatch.flavor .. "</i>"
        end

        if result == "" then
            result = text
        else
            result = result .. "\n" .. text
        end
    end
    return result
end

local function CreateCharSheetImport()
    local m_resultPanel

    local m_leftPanel
    local m_rightPanel
    local m_monsterPanel
    local m_dataInput
    local m_overrideImportCheck

    local m_changesPanel

    local m_importedText = nil

    ---@type creature?
    local m_displayedMonsterProperties = nil
    local m_displayedMonsterLog = nil

    m_monsterPanel = gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        vscroll = true,
    }

    local reimport = function()

        import:ClearState()
        import:SetActiveImporter("mcdm")
        import.options = {
            replaceExisting = false,
        }
        import:ImportPlainText(TranslateMarkdownToRichText(m_dataInput.text))

        local monsterProperties = nil
        local monsterAsset = nil

        m_displayedMonsterLog = nil

        local imports = import:GetImports()
        for tableid,tableInfo in pairs(imports) do
            for key,asset in pairs(tableInfo) do
                monsterProperties = asset.properties
                monsterAsset = asset
                m_displayedMonsterLog = import:GetAssetLog(asset)
            end
        end

        if monsterProperties == nil then
            m_monsterPanel.children = {}
        else
            m_monsterPanel.children = {
                monsterProperties:Render({
                    width = 400,
                    noavatar = true,
                }, {
                    asset = monsterAsset,
                })
            }

        end

        m_displayedMonsterProperties = monsterProperties
        m_changesPanel:FireEvent("refreshVisibility")

    end


    m_changesPanel = gui.Panel{
        width = "100%",
        height = 30,
        vmargin = 6,
        flow = "horizontal",

        styles = {
            {
                selectors = {"hideWhenUnchanged", "unchanged"},
                hidden = 1,
            },

            {
                selectors = {"hideWhenNoLog", "nolog"},
                hidden = 1,
            }

        },
        refreshVisibility = function(element)
            element:SetClassTree("unchanged", m_dataInput.text == m_importedText or m_displayedMonsterProperties == nil)
            element:SetClassTree("nolog", m_displayedMonsterLog == nil)
        end,

        gui.Button{
            classes = {"hideWhenNoLog"},
            text = "View Log",
            halign = "left",
            width = 160,
            height = 30,
            click = function(element)
                element.popup = MCDMImporter.renderLog(m_displayedMonsterLog)
            end,
        },

        gui.Label{
            classes = {"hideWhenUnchanged"},
            text = "Text has been edited",
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "center",
        },

        gui.Button{
            classes = {"hideWhenUnchanged"},
            text = "Save Changes",
            halign = "center",
            width = 160,
            height = 30,
            click = function(element)
				local token = CharacterSheet.instance.data.info.token

                --this button is hidden (refreshVisibility) whenever no monster is displayed.
                ---@cast m_displayedMonsterProperties -nil
                if token.properties == m_displayedMonsterProperties then
                    print("ERROR: Token properties are the same as the displayed monster properties")
                    return
                end

                --completely overwrite the properties but keep the table identity.
                for key,_ in pairs(token.properties) do
                    token.properties[key] = nil
                end

                for key,value in pairs(m_displayedMonsterProperties) do
                    token.properties[key] = DeepCopy(value)
                end

                token.properties.import = {
                    type = "mcdm",
                    data = m_dataInput.text,
                }
				CharacterSheet.instance:FireEvent('refreshAll')
            end,
        },
        gui.Button{
            classes = {"hideWhenUnchanged"},
            text = "Revert Changes",
            halign = "center",
            width = 160,
            height = 30,
            click = function(element)
                m_dataInput:FireEvent("refreshToken", CharacterSheet.instance.data.info)
                reimport()
            end,
        },
    }

    m_overrideImportCheck = gui.Check{
        text = "Override Import",
        width = 160,
        height = 30,
        halign = "center",
        valign = "center",
        value = false,
        refreshToken = function(element, info)
            local c = info.token.properties
            element.value = c:try_get("import", {})["override"]
        end,
        change = function(element)
			local token = CharacterSheet.instance.data.info.token
            token.properties.import = token.properties:try_get("import", {})
            token.properties.import.override = element.value
			CharacterSheet.instance:FireEvent('refreshAll')
        end,
    }

    m_dataInput = gui.Input{
        width = "100%",
        height = "90%",
        multiline = true,
        fontSize = 16,
        textAlignment = "topleft",
        fontFace = "Courier",

        editlag = 0.2,

        edit = function(element)
            reimport()
        end,


		refreshToken = function(element, info)
            local c = info.token.properties
            if not c:has_key("import") or c.import.type ~= "mcdm" then
                element.text = ""
                return
            end


            m_importedText = TranslateRichTextToMarkdown(c.import.data)
            element.text = m_importedText

            m_changesPanel:FireEvent("refreshVisibility")
        end,
    }

    m_leftPanel = gui.Panel{
        width = "45%",
        height = "95%",
        flow = "vertical",
        halign = "center",
        valign = "center",

        m_dataInput,
        m_changesPanel,
        m_overrideImportCheck,
    }

    m_rightPanel = gui.Panel{
        width = "45%",
        height = "90%",
        flow = "vertical",
        halign = "center",
        valign = "center",
        m_monsterPanel,
    }

    m_resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        pad = 16,
        flow = "horizontal",
		refreshToken = function(element, info)
        end,

        showTab = function(element, index, id)
            if id == "Import" then
                reimport()
            end
        end,

        m_leftPanel,
        m_rightPanel,
    }

    return m_resultPanel
end

--[[
CharSheet.RegisterTab{
    id = "Import",
    text = "Import",
    panel = CreateCharSheetImport,
}
]]
local mod = dmhub.GetModLoading()

RegisterGameType("CharacterComplication", "CharacterFeat")

CharacterComplication.tableName = "complications"

CharacterComplication.name = "Complication"
CharacterComplication.description = ""
CharacterComplication.prerequisite = ""
CharacterComplication.tag = "complication"
CharacterComplication.benefit = ""
CharacterComplication.drawback = ""

CharacterComplication.descriptionEntries = {
    {
        text = "Overview",
        field = "description",
    },
    {
        text = "Benefit",
        field = "benefit",
    },
    {
        text = "Drawback",
        field = "drawback",
    },
}

local function ShowComplicationsPanel(contentPanel)
    local editorPanel = CharacterFeat.CreateEditor()

    local itemLabels = {}

    local itemsListPanel = nil
    itemsListPanel = gui.Panel{
        classes = {'list-panel'},
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local newItemLabels = {}
            local children = {}
            local complicationsTable = dmhub.GetTable(CharacterComplication.tableName) or {}
            for k,complication in pairs(complicationsTable) do
                if not complication:try_get("hidden", false) then
                    children[#children+1] = itemLabels[k] or Compendium.CreateListItem{
                        select = element.aliveTime > 0.2,
                        tableName = CharacterComplication.tableName,
                        key = k,
                        click = function()
                            editorPanel.data.SetFeat(CharacterComplication.tableName, k)
                        end,
                    }

                    children[#children].data.ord = complication.name
                    children[#children].text = complication.name

                    newItemLabels[k] = children[#children]
                end
            end

            table.sort(children, function(a, b)
                return a.data.ord < b.data.ord
            end)
            itemLabels = newItemLabels
            element.children = children
        end,
    }

    itemsListPanel:FireEvent("refreshAssets")

    local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
        gui.AddButton{
            click = function(element)
                local newComplication = CharacterComplication.new{}
                dmhub.SetAndUploadTableItem(CharacterComplication.tableName, newComplication)
            end,
        }
    }

	contentPanel.children = {leftPanel, editorPanel}
end

creature.complications = {}

function creature:Complications()
    local results = {}
    local t = dmhub.GetTable(CharacterComplication.tableName) or {}
    for complicationid, _ in pairs(self.complications) do
        local complication = t[complicationid]
        if complication ~= nil then
            results[#results+1] = complication
        end
    end

    
    return results
end

function creature:AddComplication(complicationid)
    self.complications[complicationid] = true
end

Compendium.Register{
    section = "Character",
    text = "Complications",
    contentType = "complications",
    click = function(contentPanel)
        ShowComplicationsPanel(contentPanel)
    end,
}

function CharacterComplication:Render(args)
    args = args or {}
    local resultPanel

    local benefitLabel
    local drawbackLabel

    if trim(self.drawback) == "" then
        benefitLabel = gui.Label{
            classes = {"benefit"},
            text = string.format("<b>Benefit and Drawback:</b> %s", self.benefit),
        }
        drawbackLabel = nil
    else
        benefitLabel = gui.Label{
            classes = {"benefit"},
            text = string.format("<b>Benefit:</b> %s", self.benefit),
        }
        drawbackLabel = gui.Label{
            classes = {"drawback"},
            text = string.format("<b>Drawback:</b> %s", self.drawback),
        }
    end

    resultPanel = {
        flow = "vertical",
        width = "100%",
        height = "auto",

        styles = {
            {
                selectors = {"label"},
                fontSize = 14,
                bold = false,
                width = "100%-20",
                height = "auto",
                halign = "center",
                textAlignment = "topleft",
                vmargin = 6,
            },
            {
                selectors = {"title"},
                fontFace = 28,
                fontSize = 24,
                bold = true,
            },
        },

        --I think we don't need this since it's redundant with the dropdown triangle.
        --gui.Label{
        --    classes = {"title"},
        --    text = self.name,
        --},
        gui.Label{
            text = self.description,
        },

        benefitLabel,
        drawbackLabel,
    }

    for k,v in pairs(args) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel
end
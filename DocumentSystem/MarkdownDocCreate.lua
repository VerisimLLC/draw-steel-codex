local mod = dmhub.GetModLoading()

function MarkdownDocument:ShowCreateDialog()

    local m_originalContent = self:GetTextContent()
    local m_originalAnnotations = self.annotations

    local dialogWidth = 1100
    local dialogHeight = 940

    local loc = {
        x = 1920 * 0.5 * ((dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y) / (1920 / 1080)) - dialogWidth / 2,
        y = 1080 * 0.5 - dialogHeight / 2,
        width = dialogWidth,
        height = dialogHeight,
    }


    local m_templatePanel = nil
    local previewPanel

    local labels = {}
    
    local foldersTable = assets.documentFoldersTable
    for id,template in unhidden_pairs(dmhub.GetTable(CustomDocument.tableName) or {}) do
        local parentFolder = template.parentFolder
        local maxcount = 0
        while maxcount < 10 and parentFolder ~= nil and foldersTable[parentFolder] ~= nil do
            if foldersTable[parentFolder].hidden then
                break
            end
            parentFolder = foldersTable[parentFolder].parentFolder
            maxcount = maxcount + 1
        end
        if parentFolder == "templates" then
            labels[#labels+1] = gui.Label{
                data = {
                    template = template,
                },
                text = template.description,
                press = function(element)
                    for _,child in ipairs(element.parent.children) do
                        child:SetClass("selected", child == element)
                    end

                    self:SetTextContent(template:GetTextContent())
                    self.annotations = DeepCopy(rawget(template, "annotations") or {})
                    previewPanel:FireEvent("doc", self)
                end,
            }
        end
    end

    table.sort(labels, function(a, b)
        return a.text < b.text
    end)

    table.insert(labels, 1, gui.Label{
        text = "Blank Document",
        classes = {"selected"},
        data = {
            template = false,
        },
        press = function(element)
            for _,child in ipairs(element.parent.children) do
                child:SetClass("selected", child == element)
            end
            
            self:SetTextContent(m_originalContent)
            self.annotations = m_originalAnnotations
            previewPanel:FireEvent("doc", self)
        end,
    })
    
    m_templatePanel = gui.Panel{
        flow = "vertical",
        width = 200,
        height = "100%",
        halign = "left",
        hmargin = 12,
        gui.Label{
            text = "Choose Template",
            fontSize = 16,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 8,
        },

        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "vertical",
            vscroll = true,
            children = labels,
            styles = ThemeEngine.MergeTokens({
                {
                    selectors = {"label"},
                    fontSize = 16,
                    color = "@fg",
                    bgimage = true,
                    bgcolor = "clear",
                    halign = "left",
                    valign = "top",
                    textAlignment = "left",
                    textOverflow = "ellipsis",
                    textWrap = false,
                    width = "100%",
                    height = 20,
                },
                {
                    selectors = {"label", "hover"},
                    color = "@fgInverse",
                    bgcolor = "@fg",
                    brightness = 1.2,
                },
                {
                    selectors = {"label", "selected"},
                    color = "@fgInverse",
                    bgcolor = "@fg",
                },
            }),
        },
    }

    previewPanel = gui.MarkdownLabel{
        width = "100%-248",
        height = "100%",
        hmargin = 12,
        vscroll = true,
    }

    previewPanel:FireEvent("doc", self)

    local dialog

    local dialogStyles = ThemeEngine.GetStyles()
    dialogStyles[#dialogStyles + 1] = gui.Style {
        classes = { "framedPanel" },
        priority = 5,
        opacity = 0.98,
        borderWidth = 0,
        borderColor = "clear",
    }
    dialogStyles[#dialogStyles + 1] = gui.Style {
        classes = { "framedPanel", "~uiblur" },
        priority = 5,
        opacity = 1,
    }

    dialog = gui.Panel {
        styles = dialogStyles,
        classes = { "framedPanel" },
        bgimage = true,
        blurBackground = true,
        x = loc.x,
        y = loc.y,
        width = loc.width,
        height = loc.height,
        halign = "left",
        valign = "top",
        flow = "vertical",

        gui.Panel{
            width = "auto",
            height = 60,
            halign = "center",
            flow = "horizontal",

            gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 28,
                halign = "center",
                valign = "center",
                text = "Create Document:",
            },

            gui.Input{
                width = 260,
                height = 30,
                characterLimit = 48,
                fontSize = 20,
                halign = "left",
                valign = "center",
                text = self.description,
                edit = function(element)
                    self.description = element.text
                end,
                change = function(element)
                    self.description = element.text
                end,
            }
        },

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "100%-120",

            m_templatePanel,

            previewPanel,
            
        },

        gui.Panel{
            width = "100%",
            height = 60,
            flow = "horizontal",

            gui.Button{
                width = 120,
                height = 40,
                fontSize = 24,
                halign = "center",
                valign = "center",
                text = "Cancel",
                press = function(element)
                    dialog:DestroySelf()
                end,
                escapeActivates = true,
            },

            gui.Button{
                width = 120,
                height = 40,
                fontSize = 24,
                halign = "center",
                valign = "center",
                text = "Create",
                press = function(element)
                    dialog:DestroySelf()
                    self:Upload()
                    self:ShowDocument{edit = true}
                end,
            },
        },

        click = function(element)
            element:SetAsLastSibling()
        end,
    }

    GameHud.instance.documentsPanel:AddChild(dialog)
end
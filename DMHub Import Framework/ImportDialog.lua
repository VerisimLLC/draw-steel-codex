local mod = dmhub.GetModLoading()

local CreateImportAssetsDialog

LaunchablePanel.Register{
	name = "Import Assets...",
	halign = "center",
	valign = "center",
    group = "share",
	hidden = function()
		return not dmhub.isDM
	end,
	content = function(args)
        return CreateImportAssetsDialog(args)
	end,
}

local g_currentImporterSetting = setting{
    id = "importer:current",
    description = "Last used importer type",
    default = nil,
    storage = "preference",
}


CreateImportAssetsDialog = function(args)
    local dialogPanel

    local m_currentImporter = nil
    local m_currentImporterId = nil

    import:ClearState()

    local textImport
    local textImportButton = gui.Button{
        classes = {"hidden"},
        halign = "center",
        valign = "bottom",
        text = "Import",
        click = function(element)
            element:SetClass("hidden", true)
            import:ImportFromText(textImport.text)
            dialogPanel:FireEventTree("refreshImport")
        end,
    }

    textImport = gui.Input{
        width = 500,
        height = 100,
        placeholderText = "Paste JSON data...",
        textAlignment = "topleft",
        text = "",
        edit = function(element)
            textImportButton:SetClass("hidden", false)
        end,
    }

    local textImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        data = {
            type = "text",
        },

        textImport,
        textImportButton,
    }

    local plaintextImportPanel
    plaintextImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        data = {
            type = "plaintext",
        },
 
        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ReadTextFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        print("Calling ImportPlainText with data: ", json(data))
                        import:ImportPlainText(data)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"txt", "json", "ds-hero"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        plaintextImportPanel:FireEvent("openFiles", paths)
                    end,
                }
            end,
        },

    }

    local docxImportPanel
    docxImportPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",

        data = {
            type = "docx",
        },
 
        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ParseDocxFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        print("Calling ImportPlainText with data: ", json(data))
                        import:ImportPlainText(data)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"docx", "txt"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        docxImportPanel:FireEvent("openFiles", paths)
                    end,
                }
            end,
        },
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Folder...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFolderDialog{
                    id = "Import",
                    extensions = {"docx"},
                    prompt = "Choose folder to import...",
                    open = function(folderPath, files)
                        docxImportPanel:FireEvent("openFiles", files)
                    end,
                }
            end,
        },       

    }

    local filesImportPanel
    filesImportPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",

        data = {
            type = "files",
        },

        openFiles = function(element, paths)
            if paths ~= nil and #paths > 0 then
                import:ClearState()
                import:SetActiveImporter(m_currentImporterId)
                for _,path in ipairs(paths) do
                    local data = dmhub.ParseJsonFile(path, function(err)
                        import:Log(string.format("Could not open file %s: %s", path, err))
                    end)

                    if data ~= nil then
                        import:ImportFromJson(data, path)
                    end
                end
            end

            dialogPanel:FireEventTree("refreshImport")
        end,
        
        gui.Button{
            classes = {"sizeL"},
            text = "Choose Files...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFileDialog{
                    id = "Import",
                    extensions = {"json"},
                    multiFiles = true,
                    prompt = "Choose files to import...",
                    openFiles = function(paths)
                        filesImportPanel:FireEvent("openFiles", paths)

                    end,
                }
            end,
        },

        gui.Button{
            classes = {"sizeL"},
            text = "Choose Folder...",
            minWidth = 260,
            halign = "center",
            valign = "center",
            hmargin = 8,
            click = function(element)
                dmhub.OpenFolderDialog{
                    id = "Import",
                    extensions = {"json"},
                    prompt = "Choose folder to import...",
                    open = function(folderPath, files)
                        filesImportPanel:FireEvent("openFiles", files)
                    end,
                }
            end,
        },

    }

    local urlImportPanel
    urlImportPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        data = {
            type = "url",
        },

        gui.Panel{
            width = "auto",
            height = 28,
            flow = "horizontal",
            halign = "center",
            gui.Input{
                placeholderText = "Enter URL...",
                halign = "center",
                width = 600,
                height = 28,
                fontSize = 20,
                characterLimit = 1024,
                data = {
                    url = "",
                },
                importer = function(element, importer)
                    element.placeholderText = importer.urlText or "Enter URL..."
                end,

                change = function(element)
                    local url = element.data.url

                    if url ~= "" and url ~= nil then
                        element.text = ""
                        element.data.url = ""
                        element.parent:FireEventTree("url", element.data.url)

                        printf("NET:: Sent request for %s", url)
                        net.Get{
                            url = url,
                            success = function(data)
                        printf("NET:: SUCCESS %s / %s", url, json(data))
                                import:ImportFromJson(data, url)
                                dialogPanel:FireEventTree("refreshImport")
                            end,
                            error = function(err)
                        printf("NET:: FAILURE %s", err)
                                dialogPanel:FireEventTree("error", err)
                            end,
                        }
                    else
                        dialogPanel:FireEventTree("error", "URL is not valid")
                    end
                end,

                edit = function(element)
                    local url = element.text
                    if m_currentImporter.translateurl ~= nil then
                        url = m_currentImporter.translateurl(element.text)
                        if url == nil then
                            url = ""
                        end
                    end

                    element.data.url = url

                    element.parent:FireEventTree("url", url)
                end,
            },

            gui.Button{
                classes = {"sizeL", "hidden"},
                width = 160,
                text = "Submit",
                url = function(element, url)
                    element:SetClass("hidden", url == "")
                end,
                click = function(element)
                    element.parent:FireEventTree("change")
                end,
            },
        },
    }

    local importers = import.importers
    local importerOptions = {}
    for key,importer in pairs(importers) do
        importerOptions[#importerOptions+1] = {
            id = key,
            text = importer.description,
            ord = importer.priority or 0,
        }
    end

    table.sort(importerOptions, function(a,b) return a.ord > b.ord end)

    local importPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        hmargin = 32,
        halign = "center",
        valign = "top",
        vmargin = 16,
        import = function(element)
        end,

        gui.Panel{
            importer = function(element, importer)
                local children = element.children
                for _,child in ipairs(children) do
                    child:SetClass("collapsed", child.data.type ~= importer.input)
                end
            end,
            flow = "none",
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            textImportPanel,
            plaintextImportPanel,
            filesImportPanel,
            docxImportPanel,
            urlImportPanel,
        },
    }

    --read the last used importer, but also make sure it's valid.
    local importerid = importerOptions[1].id
    if g_currentImporterSetting:Get() ~= nil then
        local id = g_currentImporterSetting:Get()
        for _,option in ipairs(importerOptions) do
            if id == option.id then
                importerid = option.id
            end
        end
    end

    local importerDropdown = gui.Dropdown{
        width = 240,
        options = importerOptions,
        idChosen = importerid,
        create = function(element)
            element:FireEvent("change")
        end,
        change = function(element)
            g_currentImporterSetting:Set(element.idChosen)
            m_currentImporter = importers[element.idChosen]
            m_currentImporterId = element.idChosen
            import:SetActiveImporter(m_currentImporterId)
            importPanel:FireEventTree("importer", importers[element.idChosen])
        end,
    }

    local importerSelectionPanel = gui.Panel{
        flow = "horizontal",
        halign = "center",
        valign = "top",
        width = "auto",
        height = "auto",
        hmargin = 8,
        vmargin = 16,
        gui.Label{
            hmargin = 8,
            text = "Choose Importer:",
            height = 28,
            fontSize = 18,
            textAlignment = "center",
            width = "auto",
        },
        importerDropdown,
    }

    local contentPanel = gui.Panel{
        classes = "collapsed",
        halign = "center",
        valign = "center",
        flow = "vertical",
        hpad = 20,
        width = 500,
        height = 420,

        error = function(element)
            element:SetClass("collapsed", true)
        end,

        import = function(element)
            element:SetClass("collapsed", false)
        end,

        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            vpad = 8,
            vscroll = true,
		    hideObjectsOutOfScroll = true,

            styles = {
                {
                    selectors = {"exclude"},
                    strikethrough = true,
                    color = "#777777",
                },

                {
                    selectors = {"deleteItemButton"},
                    hidden = 1,

                },
                {
                    selectors = {"deleteItemButton", "parent:hover", "~importing"},
                    hidden = 0,
                },


            },

            import = function(element)
                local children = {}
                local imports = import:GetImports()
                local count = 0
                for _,_ in pairs(imports) do
                    count = count+1
                end
                printf("IMPORT:: IMPORT COUNT = %d", count)
                for tableid,tableInfo in pairs(imports) do
                    for key,asset in pairs(tableInfo) do


                        local outcomeIcon = gui.Panel{
                            classes = {"hidden"},
                            floating = true,
                            bgimage = "ui-icons/greend20.png",
                            bgcolor = "white",
                            width = 16,
                            height = 16,
                            vmargin = 8,
                            hmargin = 8,
                            halign = "right",
                            valign = "top",

                            data = {
                                tooltip = nil,
                            },

                            hover = function(element)
                                if element.data.tooltip ~= nil then
                                    gui.Tooltip(element.data.tooltip)(element)
                                end
                            end,

                            importing = function(element)
                                if not element:HasClass("hidden") then
                                    return
                                end

                                local result = import.importedAssets[key]
                                printf("Imported assets: %s vs %s", key, json(import.importedAssets))
                                if result ~= nil then
                                    element:SetClass("hidden", false)
                                    if type(result) == "string" then
                                        element.selfStyle.bgimage = "ui-icons/redd20.png"
                                        element.data.tooltip = result
                                    else
                                        element.data.tooltip = "Imported Successfully"
                                    end
                                end
                            end,
                        }

                        local reimportIcon

                        if import:IsReimport(asset) then
                            reimportIcon = gui.Panel{
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 64,
                                width = 16,
                                height = 16,
                                bgcolor = "white",
                                bgimage = "panels/hud/clockwise-rotation.png",
                                hover = gui.Tooltip("This asset already exists and will be re-imported."),
                            }
                        end

                        print("XXX: REIMPORT ICON = ", reimportIcon ~= nil)


                        local alertIcon

                        if import:GetAssetLog(asset) ~= nil then
                            alertIcon = gui.Label{
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 40,
                                width = 16,
                                height = 16,
                                cornerRadius = 8,
                                bgimage = "panels/square.png",
                                bgcolor = "#999900",
                                fontSize = 18,
                                bold = true,
                                color = "black",
                                opacity = 1,
                                textAlignment = "center",
                                text = "!",

                                showRenderLog = function(element, istooltip)
                                    if element.popup ~= nil then
                                        return
                                    end

                                    local panel = gui.TooltipFrame(
                                        gui.Panel{
                                            width = "auto",
                                            height = "auto",
                                            maxHeight = 900,
                                            vscroll = true,
                                            styles = {
                                                Styles.Default
                                            },

                                            gui.Panel{
                                                hpad = 8,
                                                width = "auto",
                                                height = "auto",
                                                flow = "vertical",
                                                valign = "top",
                                                import:GetCurrentImporter().renderLog(import:GetAssetLog(asset)),
                                            },
                                        }, {
                                            halign = "left",
                                            valign = "center",
                                        }
                                    )

                                    if istooltip then
                                        element.tooltip = panel
                                    else
                                        element.popup = panel
                                    end


                                end,

                                press = function(element)
                                    if import:GetCurrentImporter().renderLog ~= nil then
                                        element:FireEvent("showRenderLog", false)
                                    end
                                end,

                                hover = function(element)
                                    if import:GetCurrentImporter().renderLog ~= nil then
                                        element:FireEvent("showRenderLog", true)

                                    else
                                        local text = ""
                                        for _,log in ipairs(import:GetAssetLog(asset)) do
                                            if text ~= "" then
                                                text = text .. "\n"
                                            end

                                            text = string.format("%s%s %s", text, Styles.bullet, log)
                                        end

                                        gui.Tooltip{text = text, fontSize = 14}(element)
                                    end
                                end,
                            }
                        end

                        local panel
                        panel = gui.Panel{
                            classes = {"importItemPanel"},
                            bgimage = "panels/square.png",
                            width = "90%",
                            height = 40,
                            halign = "left",
                            hmargin = 8,
                            flow = "vertical",

                            styles = {
                                {
                                    bgcolor = "clear",
                                },
                                {
                                    selectors = {"hover"},
                                    bgcolor = "#ffffff22",
                                },
                            },

                            data = {
                                ord = {tableid, asset.name},
                            },

                            alertIcon,
                            reimportIcon,
                            outcomeIcon,

                            gui.Panel{
                                flow = "horizontal",
                                width = 250,
                                height = 40,
                                hmargin = 8,
                                hover = function(element)
                                    local tooltip = CreateCompendiumItemTooltip(asset, {halign = "right", valign = "center", width = 800})
                                    element.tooltip = tooltip
                                end,
                                gui.Panel{
                                    width = 40,
                                    height = 40,
                                    bgcolor = "white",
                                    thinkTime = 0.2,
                                    think = function(element)
                                        local img = import:GetImage(asset)
                                        if img ~= nil then
                                            element.bgimage = img
                                        end
                                    end,
                                },

                                gui.Panel{
                                    flow = "vertical",
                                    width = "auto",
                                    height = 40,
                                    gui.Label{
                                        fontSize = 16,
                                        bold = true,
                                        width = "auto",
                                        height = 20,
                                        minWidth = 200,
                                        vmargin = 1,
                                        hmargin = 4,
                                        valign = "top",
                                        text = asset.name,
                                    },

                                    gui.Label{
                                        fontSize = 14,
                                        width = 200,
                                        height = 20,
                                        vmargin = 1,
                                        hmargin = 4,
                                        valign = "top",
                                        text = tableid,
                                    },
                                },
                            },

                            gui.Button{
                                classes = {"deleteButton", "sizeS"},
                                floating = true,
                                halign = "right",
                                valign = "top",
                                click = function(element)
                                    panel:SetClassTree("exclude", not panel:HasClass("exclude"))
                                    import:SetImportRemoved(key, panel:HasClass("exclude"))
                                end,
                            },
                        }

                        children[#children+1] = panel
                    end
                end


                table.sort(children, function(a,b)
                    for i=1,#a.data.ord do
                        if a.data.ord[i] ~= b.data.ord[i] then
                            return a.data.ord[i] < b.data.ord[i]
                        end
                    end
                end)



                element.children = children
            end,
        },

    }

    local logPanel = gui.Panel{
        vscroll = true,
        height = 240,
        width = 400,
        flow = "vertical",
        floating = true,
        halign = "right",
        valign = "bottom",
        margin = 8,

        styles = {
            {
                selectors = {"label"},
                width = "90%",
                height = "auto",
                fontSize = 16,
                halign = "left",
                hmargin = 4,
                textWrap = true,
            }
        },

        import = function(element)
            local children = {}
            local imports = import:GetImports()
            for _,entry in ipairs(import:GetLog()) do

                local label = gui.Label{
                    text = entry,
                }

                children[#children+1] = label
            end

            element.children = children
        end,
    }

    local statusMessage = gui.Label{
        classes = {"collapsed"},
        halign = "left",
        valign = "center",
        hmargin = 64,
        width = "auto",
        height = "auto",
        maxWidth = 400,
        fontSize = 18,

        error = function(element, error)
            element:SetClass("collapsed", false)

            local text = error or import.error
            if m_currentImporter.translateerror ~= nil then
                text = m_currentImporter.translateerror(text) or text
            end
            element.text = text
        end,
        import = function(element)
            element:SetClass("collapsed", true)
        end,
    }

    local completeButton = gui.Button{
        classes = {"sizeL", "hidden"},
        halign = "center",
        valign = "bottom",
        text = "Finish",
        click = function(element)
            dialogPanel.parent:DestroySelf()
        end,
    }

    local importingText = gui.Label{
        classes = {"hidden"},
        halign = "center",
        valign = "bottom",
        text = "Importing",
        fontSize = 22,
        width = "auto",
        height = "auto",
        vmargin = 16,

        think = function(element)
            if element.text == "Importing" then
                element.text = "Importing."
            elseif element.text == "Importing." then
                element.text = "Importing.."
            elseif element.text == "Importing.." then
                element.text = "Importing..."
            else
                element.text = "Importing"
            end

            if import.pendingUpload == false then
                dialogPanel:SetClassTree("importing", true)
                dialogPanel:FireEventTree("importing")
                local processing = import:CompleteImportStep()
                if not processing then
                    element.thinkTime = nil

                    if import.error ~= nil then
                        element.root:FireEventTree("refreshImport")
                        element.text = "Error Importing"
                    else
                        element.text = "Complete!"
                        element:ScheduleEvent("complete", 1)
                    end
                end
            end
        end,

        complete = function(element)
            element:SetClass("hidden", true)
            completeButton:SetClass("hidden", false)
        end,
    }


    local bandwidthLabel = gui.Label{
        floating = true,
        halign = "left",
        valign = "bottom",
        hmargin = 16,
        vmargin = 64,
        fontSize = 16,
        width = 420,
        height = "auto",
        maxWidth = 420,

        refreshImport = function(element)
            local kb = import.uploadCostKB

            if kb <= 0 then
                element.text = ""
                return
            end

            local notEnough = ""
            if not import.haveEnoughBandwidth then
                notEnough = "\n<color=#ff0000>Not enough bandwidth available</color>"
            end

            element.text = string.format("Bandwidth required to import assets: %dKB\nBandwidth available this month: %dKB%s", kb, round(dmhub.uploadQuotaRemaining/1024), notEnough)
        end,
    }

    local importButton = gui.Button{
        classes = {"sizeL", "hidden"},
        halign = "center",
        valign = "bottom",
        text = "Import",
        refreshImport = function(element)
            if import.error ~= nil then
                element:SetClass("hidden", true)
            else
                local haveImports = false
                local imports = import:GetImports()
                for tableid,tableInfo in pairs(imports) do
                    for key,asset in pairs(tableInfo) do
                        haveImports = true
                    end
                end

                element:SetClass("hidden", (not haveImports) or (not import.haveEnoughBandwidth))

            end
        end,
        click = function(element)
            element:SetClass("hidden", true)
            importingText:SetClass("hidden", false)
            importingText.thinkTime = 0.1
        end,
    }



    dialogPanel = gui.Panel{
        width = 1200,
        height = 940,
        flow = "vertical",

        refreshImport = function(element)
            if import.error == nil then
                dialogPanel:FireEventTree("import")
            else
                dialogPanel:FireEventTree("error")
            end
        end,

        gui.Label{
            classes = {"title"},
            vmargin = 16,
            valign = "top",
            halign = "center",
            width = "auto",
            height = "auto",
            text = "Importer",
        },

        importerSelectionPanel,
        importPanel,
        contentPanel,

        statusMessage,
        importingText,
        completeButton,

        bandwidthLabel,
        importButton,

        logPanel,

    }

    return dialogPanel
end
local mod = dmhub.GetModLoading()

setting{
    id = "aiassistant",
    default = "",
    description = "AI Assistant",
    storage = "preference",
}

setting{
    id = "aihistory",
    default = {},
    description = "AI History",
    storage = "preference",
}

setting{
    id = "aiimages",
    default = {},
    description = "AI Images",
    storage = "preference",
}

local function GetCurrentAssistant()
    local dataTable = dmhub.GetTable(AIAssistant.tableName)
    local id = dmhub.GetSettingValue("aiassistant")
    if dataTable[id] ~= nil and dataTable[id]:try_get("hidden", false) == false then
        return id
    end

    local result = nil
    for key,entry in pairs(dataTable) do
        if result == nil or entry.isdefault then
            result = key
        end
    end

    return result
end

local function GetCurrentAssistantObject()
    local assistantid = GetCurrentAssistant()
    local assistant
    if assistantid ~= nil then
        assistant = dmhub.GetTable(AIAssistant.tableName)[assistantid]
    end

    if assistant == nil then
        assistant = AIAssistant.CreateNew()
    end

    return assistant
end


local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local CreateAIPanel

DockablePanel.Register{
	name = "AI Assistant",
	icon = mod.images.ai,
	minHeight = 200,
	vscroll = false,
	content = function()
		track("panel_open", {
			panel = "AI Assistant",
			dailyLimit = 30,
		})
		return CreateAIPanel()
	end,
}

local function TokenizeResponse(text)
    local items = string.split(text, "```")
    local result = {}

    for i,item in ipairs(items) do
        local t = cond(i%2 == 0, "json", "text")
        if t == "json" then
            if string.find(item, "{") == nil then
                t = "text"
            end
        end

        result[#result+1] = {
            content = item,
            type = t,
        }
    end

    return result
end

local function ErrorPanel(message)
    return gui.Label{
        classes = {"textResponse"},
        text = "(Could not parse)",
        hover = function(element)
            gui.Tooltip{ text = message, fontSize = 14, width = 800 }(element)
        end,
    }
end

local g_monsterFrameGuid = "98407687-be6a-4d52-a6e1-04f019cfaf6d"

local function CreateResponsePanel(token, guid)
    if token.type == "text" then
        return gui.Label{
            classes = {"textResponse"},
            text = token.content,
        }
    elseif token.type == "json" then

        local assistant = GetCurrentAssistantObject()
        if assistant.importer == "none" then
            return ErrorPanel("No importers configured for this assistant")
        end

        local text = token.content
        local beginJson = string.find(text, "{")
        if beginJson == nil then
            return ErrorPanel("Could not find start of JSON")
        end

        text = string.sub(text, beginJson, #text)

        local children = {}

        local importer = import.CreateImporter()
        importer:ClearState()
        importer:SetActiveImporter(assistant.importer)
        importer:ImportFromText(text)
        local imports = importer:GetImports()
        for tableid,tableInfo in pairs(imports) do
            for key,asset in pairs(tableInfo) do
                local assetRender = asset:Render{
                    pad = 4,
                    width = "100%",
                }

                local infoIcon
                
                if dmhub.GetSettingValue("dev") then
                    infoIcon = gui.Label{
                            hmargin = 8,
                            width = 16,
                            height = 16,
                            valign = "center",
                            cornerRadius = 8,
                            bgimage = "panels/square.png",
                            bgcolor = "#9999cc",
                            fontSize = 18,
                            bold = true,
                            color = "black",
                            opacity = 1,
                            textAlignment = "center",
                            text = "i",

                            hover = function(element)
                                gui.Tooltip{ text = text, fontSize = 12, maxWidth = 1200 }(element)
                            end,
                    }
                end

                local alertIcon

                if importer:GetAssetLog(asset) ~= nil then
                    alertIcon = gui.Label{

                        hmargin = 8,
                        width = 16,
                        height = 16,
                        valign = "center",
                        cornerRadius = 8,
                        bgimage = "panels/square.png",
                        bgcolor = "#999900",
                        fontSize = 18,
                        bold = true,
                        color = "black",
                        opacity = 1,
                        textAlignment = "center",
                        text = "!",

                        hover = function(element)
                            local text = ""
                            for _,log in ipairs(importer:GetAssetLog(asset)) do
                                if text ~= "" then
                                    text = text .. "\n"
                                end

                                text = string.format("%s%s %s", text, Styles.bullet, log)
                            end

                            gui.Tooltip(text)(element)
                        end,
                    }
                end


                local reimportIcon = nil
                if importer:IsReimport(asset) then
                    reimportIcon = gui.Panel{
                        width = 16,
                        height = 16,
                        valign = "center",
                        hmargin = 8,
                        bgcolor = "white",
                        bgimage = "panels/hud/clockwise-rotation.png",
                        hover = gui.Tooltip("This asset already exists and will be re-imported."),
                    }
                end

                local monsterAddPanel
                if tableid == "monster" then
                    monsterAddPanel = gui.Panel{
                        classes = {"selectionPanel"},
                        width = 32,
                        height = 32,
                        bgimage = "panels/square.png",

                        styles = {
                            gui.Style{
                                bgcolor = "clear",
                            },
                            gui.Style{
                                selectors = {"hover"},
                                bgcolor = "#ffffff88",
                            },
                            gui.Style{
                                selectors = {"focus"},
                                bgcolor = "#ffffffff",
                            },
                        },

                        data = {
                            monsterid = key
                        },

                        press = function(element)
                            gui.SetFocus(element)
                        end,

                        create = function(element)
                            local node = assets:GetMonsterNode(key)
                            if node ~= nil then
                                printf("CREATE:: HAS NODE")
                                local monster = node.monster.info
                                element.children = {gui.CreateMonsterImage(monster, {width = 30, height = 30, halign = "center", valign = "center"})}
                                element:SetClass("collapsed", false)
                            else
                                printf("CREATE:: NO NODE")
                                element:SetClass("collapsed", true)
                            end
                        end,

                        refreshImage = function(element)
                            element:FireEvent("create")
                        end,

                        assetImported = function(element)
                            if element:HasClass("collapsed") then
                                if assets:GetMonsterNode(key) == nil then
                                    --wait until the import completes.
                                    element:ScheduleEvent("assetImported", 0.1)
                                else
                                    element:FireEvent("create")
                                end
                            end
                        end,
                    }
                end

                local controlPanel

                controlPanel = gui.Panel{
                    halign = "right",
                    valign = "top",
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    bgcolor = "white",

                    infoIcon,
                    alertIcon,
                    reimportIcon,

                    monsterAddPanel,
                    gui.Button{
                        classes = {"tiny"},
                        text = "Add",
                        hover = gui.Tooltip(cond(reimportIcon == nil, "Add this entry to your compendium.", "Re-import this entry into your compendium")),
                        click = function(element)
                            controlPanel.children = {
                                monsterAddPanel,
                                gui.Label{
                                    width = 70,
                                    height = "auto",
                                    hmargin = 6,
                                    thinkTime = 0.1,
                                    fontSize = 16,

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

                                        if importer.pendingUpload == false then
                                            local processing = importer:CompleteImportStep()
                                            if not processing then
                                                element.thinkTime = nil
                                                element.text = "Imported."
                                                controlPanel:FireEventTree("assetImported")
                                            end
                                        end
                                    end,
                                }

                            }
                        end,
                    },
                }

                local containerPanel
                containerPanel = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    controlPanel,
                    assetRender,

                    refreshImage = function(element)
                        assetRender = asset:Render{
                            pad = 4,
                            width = "100%",
                        }
                        element.children = {controlPanel, assetRender}
                    end,


                    create = function(element)
                        if tableid ~= "monster" and tableid ~= "character" and asset.iconid ~= "" then
                            return
                        end
                        local images = dmhub.GetSettingValue("aiimages")
                        if images[guid] ~= nil then
                            printf("IMAGES:: READ %s", guid)
                            if tableid == "monster" or tableid == "character" then
                                asset.appearance.portraitId = images[guid]
                                asset.appearance.portraitFrameId = g_monsterFrameGuid
                            else
                                asset.iconid = images[guid]
                            end

                            element:FireEventTree("refreshImage")

                            return
                        else
                            printf("IMAGES:: NONE FOR %s", guid)
                        end

                        assetRender:FireEventTree("loadingImage")

                        local prompt
                        if tableid == "monster" then
                            prompt = string.format("A D&D monster portrait for a %s", asset.name)
                        elseif tableid == "character" then
                            prompt = string.format("A D&D character portrait for %s, a %s", asset.name, asset.properties:GetCharacterSummaryText())
                        elseif tableid == "tbl_Gear" then
                            prompt = string.format("An icon for a %s item in a photorealistic Dungeons & Dragons 5e style, with a solid white background.", asset.name)
                        elseif tableid == "Spells" then
                            prompt = string.format("An icon for a %s spell in a photorealistic Dungeons & Dragons 5e style", asset.name)
                        end

                        printf("GPT:: REQUEST IMAGE")
                        ai.Image{
                            prompt = prompt,
                            size = "256x256",
                            removeBackground = "#ffffffff",
                            success = function(imageid)
                                local images = dmhub.GetSettingValue("aiimages")
                                images[guid] = imageid
                                dmhub.SetSettingValue("aiimages", images)
                                printf("IMAGES:: SAVED %s", guid)

                                if tableid == "monster" or tableid == "character" then
                                    asset.appearance.portraitId = imageid
                                    asset.appearance.portraitFrameId = g_monsterFrameGuid
                                else
                                    asset.iconid = imageid
                                end

                                containerPanel:FireEventTree("refreshImage")
                            end,

                            error = function(err)
                                printf("GPT:: error retrieving image: %s", json(err))
                            end,
                        }
                    end,
                }

                children[#children+1] = containerPanel
            end
        end

        if #children == 0 then
            return ErrorPanel("Could not recognize JSON: " .. text)
        end

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = children,
        }

    else
        return nil
    end
end

CreateAIPanel = function()
	local history = {}
	local historyCursor = nil
    local pending = 0

    local chatPanel
    local inputPanel
    local previewPanel

    local assistantDropdown

    local resultPanel

    local m_context = {}

	chatPanel = gui.Panel{
		id = 'chat-panel',
		vscroll = true,
		hideObjectsOutOfScroll = true,
		hpad = 6,
		height = "100% available",

		styles = {
			{
				bgcolor = 'black',
				halign = 'center',
				valign = 'bottom',
				width = "100%",
				flow = 'vertical',
			},
			{
				selectors = 'separator',
				bgimage = 'panels/square.png',
				width = '96%',
				height = 1,
				vmargin = 4,
				bgcolor = "#aaaaaa",
			},
            {
                selectors = {"message"},
                width = "100%-16",
                height = "auto",
                halign = "center",
                vmargin = 8,
                fontSize = 16,
                bgimage = "panels/square.png",
                bgcolor = "#000000aa",
                color = "#cccccc",
                cornerRadius = 12,
                pad = 12,
                textAlignment = "left",
            },
            {
                selectors = {"message", "user"},
                x = 4,
            },
            {
                selectors = {"message", "assistant"},
                x = -4,
                bgcolor = "#000011aa",
            },
            {
                selectors = {"message", "error"},
                color = "#ff5555",
                x = -4,
            },

            {
                selectors = {"textResponse"},
                color = "#cccccc",
                width = "100%",
                height = "auto",
                fontSize = 18,
            }
		},

        message = function(element, text, messageType)
            element:AddChild(gui.Label{
                classes = {"message", messageType},
                text = text,
            })
			element.vscrollPosition = 0

        end,

        response = function(element, children)
            element:AddChild(gui.Panel{
                classes = {"message", "assistant"},
                flow = "vertical",
                children = children,
            })

			element.vscrollPosition = 0
        end,
	}


	previewPanel = gui.Label{
		width = 330,
		height = 18,
		text = "",
		fontSize = 14,
		italics = true,
		monitorGame = mod:GetDocumentSnapshot("chatEvents").path,
		thinkTime = 0.4,

		data = {
			ellipsis = "",
		},

		think = function(element)

			if pending == 0 then
				element.text = ""
				element.data.ellipsis = ""
			else
				if #element.data.ellipsis < 3 then
					element.data.ellipsis = element.data.ellipsis .. "."
				else
					element.data.ellipsis = ""
				end
				element.text = string.format(tr("Assistant is responding%s"), element.data.ellipsis)
			end
		end,
	}

    local ShowMessage = function(text, record, role)
        if record then
            local history = dmhub.GetSettingValue("aihistory")
            history[#history+1] = {
                type = "message",
                content = text,
                role = role,
            }
            dmhub.SetSettingValue("aihistory", history)
            printf("AIHISTORY:: WRITING TO %s", json(history))
        end
        chatPanel:FireEvent("message", text, role or "user")
    end

    local ShowResponse = function(content, guid)
        if guid == nil then
            local history = dmhub.GetSettingValue("aihistory")
            guid = dmhub.GenerateGuid()
            history[#history+1] = {
                type = "response",
                content = content,
                guid = guid,
            }


            local images = dmhub.GetSettingValue("aiimages")
            local updateImages = false
            while #history > 20 do
                if history[1].guid ~= nil and images[history[1].guid] ~= nil then
                    images[history[1].guid] = nil
                    updateImages = true
                end
                table.remove(history, 1)
            end

            if updateImages then
                dmhub.SetSettingValue("aiimages", images)
            end

            dmhub.SetSettingValue("aihistory", history)
            printf("AIHISTORY:: WRITING TO %s", json(history))
        end

        local items = TokenizeResponse(content)

        local panels = {}
        for _,item in ipairs(items) do
            panels[#panels+1] = CreateResponsePanel(item, guid)
        end

        chatPanel:FireEvent("response", panels)
    end

	inputPanel = gui.Input{
		placeholderText = 'Message the AI Assistant...',
		width = 270,
        minHeight = 24,
        maxHeight = 300,
        height = "auto",
		lineType = "MultiLineSubmit",
        characterLimit = 4096,
		events = {
			uparrow = function(element)
				if #history == 0 then
					return
				end

				if historyCursor == nil then
					historyCursor = #history
				else
					historyCursor = historyCursor - 1
					if historyCursor < 1 then
						historyCursor = #history
					end
				end

				element.text = history[historyCursor]
				element.caretPosition = element.text:len()
				element.selectionAnchorPosition = 0

			end,
			downarrow = function(element)
				if #history == 0  or historyCursor == nil then
					return
				end

				historyCursor = historyCursor+1
				if historyCursor > #history then
					historyCursor = 1
				end

				element.text = history[historyCursor]
				element.caretPosition = element.text:len()
				element.selectionAnchorPosition = 0

			end,
			edit = function(element)
				if historyCursor ~= nil and element.text ~= history[historyCursor] then
					historyCursor = nil
				end
			end,
			submit = function(element)

                local assistant = GetCurrentAssistantObject()

                local text = element.text
                if text == "/clear" then
                    chatPanel.children = {}
                    dmhub.SetSettingValue("aihistory", {})
                    element.text = ""
                    m_context = {}
                    resultPanel:FireEvent("refreshContent")
                    return
                elseif text == "/refresh" then
                    resultPanel:FireEvent("refreshContent")
                    element.text = ""
                    return
                end

				historyCursor = -1

				if element.text ~= '' and history[#history] ~= element.text then
					history[#history+1] = element.text
				end

				element.text = ''

				element.hasFocus = true

                ShowMessage(text, true)

                if string.starts_with(text, "!") then
                    local response = assistant:ProcessFactoid(text)

                    ShowMessage(response, false, "assistant")
                    return
                end

                pending = pending+1

                m_context[#m_context+1] = {
                    role = "user",
                    content = text,
                }

                ai.Chat{
                    messages = assistant:GenerateContext(m_context),
                    temperature = assistant.temperature,

                    success = function(response)
                        pending = pending-1

                        m_context[#m_context+1] = {
                            role = "assistant",
                            content = response,
                        }

                        ShowResponse(response)
                    end,

                    error = function(err)
                        m_context[#m_context] = nil
                        pending = pending-1
                        chatPanel:FireEvent("message", json(err), "error")
                        printf("GPT:: ERROR: %s", json(err))
                    end,
                }
			end,

		},
	}

    local bottomPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        inputPanel,
        gui.Panel{
            width = 12,
            height = 12,
            cornerRadius = 6,
            bgimage = "panels/square.png",
            bgcolor = Styles.textColor,
            hmargin = 2,
            halign = "right",
            valign = "center",
            linger = gui.Tooltip(tr("The number of AI tokens you have. Tokens are used when you use the AI. Support DMHub on Patreon to get more tokens.")),
        },
        gui.Label{
            width = 32,
            height = 24,
            textAlignment = "left",
            halign = "right",
            valign = "center",
            hmargin = 6,
            fontSize = 16,
            minFontSize = 10,
            color = Styles.textColor,

            thinkTime = 0.2,

            create = function(element)
                element:FireEvent("think")
            end,

            think = function(element)
                local tokensAvailable = round(ai.NumberOfAvailableTokens())
                element.text = string.format("%d", tokensAvailable)
            end,
        }
    }

    assistantDropdown = gui.Dropdown{
        height = 18,
        fontSize = 14,
        hmargin = 8,
        width = 140,
        valign = "center",
        monitorAssets = AIAssistant.tableName,
        refreshAssets = function(element)
            local dataTable = dmhub.GetTable(AIAssistant.tableName)
            local options = {}
            for key,assistant in pairs(dataTable) do
                if assistant:try_get("hidden", false) == false then
                    options[#options+1] = {
                        id = key,
                        text = assistant.name,
                    }
                end
            end

            element.options = options
            element.idChosen = GetCurrentAssistant()
        end,

        create = function(element)
            element:FireEvent("refreshAssets")
        end,

        change = function(element)
            dmhub.SetSettingValue("aiassistant", element.idChosen)
        end,
    }

	resultPanel = gui.Panel{
		selfStyle = {
			width = '100%',
			height = '100%',
			flow = 'vertical',
		},
		children = {
			chatPanel,
			previewPanel,
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                halign = "left",
                height = "auto",
                hmargin = 8,
                gui.Label{
                    text = "Personality:",
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
                assistantDropdown,
            },
            bottomPanel,
		},

        refreshContent = function(element)
            chatPanel.children = {}
            for _,entry in ipairs(dmhub.GetSettingValue("aihistory")) do
                if entry.type == "message" then
                    ShowMessage(entry.content)
                else
                    ShowResponse(entry.content, entry.guid)
                end
            end

            if #chatPanel.children == 0 then
                local assistant = GetCurrentAssistantObject()
                ShowMessage(assistant.welcomeMessage, false, "assistant")
            end
        end,
	}

    resultPanel:FireEvent("refreshContent")

    printf("AIHISTORY: READING %s", json(dmhub.GetSettingValue("aihistory")))

	return resultPanel
end

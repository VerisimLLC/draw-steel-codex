local mod = dmhub.GetModLoading()

local CreateChatPanel

DockablePanel.Register{
	name = "Chat",
	icon = "icons/standard/Icon_App_Chat.png",
	minHeight = 200,
	vscroll = false,
	content = function()
		return CreateChatPanel()
	end,
}

local function FormatChatMessage(message)
    local textColor = cond(message.isLocal, "#777777", "#FFFFFF")
    local text = message.message
    local nick = message.nick
    local nickColor = message.nickColor
    if nickColor.a < 0.9 then
        nickColor.r = 1
        nickColor.g = 0.8
        nickColor.b = 0.8
        nickColor.a = 1
    elseif nickColor.v < 0.6 then
        nickColor.v = 0.6
    end
    return string.format("<color=%s><b>%s:</b></color> <color=%s>%s</color>", nickColor.tostring, nick, textColor, text)
end

local CreateChatMessagePanel = function(message)
    local m_message = message
	local complete = false
	return gui.Label{
		classes = {'chat-message-panel'},
		markdown = true,
		text = FormatChatMessage(message),
        linger = function(element)
            gui.Tooltip(DescribeServerTimestamp(m_message.timestamp))(element)
        end,
		refreshMessage = function(element, message)
			if complete then
				return
			end

            m_message = message

			element.text = FormatChatMessage(message)
			if message.isComplete then
				complete = true
			end
		end
	}
end

local CreateObjectMessagePanel = function(message)
	local objectInfo = nil
	local options = {
		summary = true,
        width = 340,
        noninteractive = true,
	}
	local params = {}
	if message.properties ~= nil then
		objectInfo = message.properties.ability

		if message.properties.charid ~= nil then
			params.token = dmhub.GetTokenById(message.properties.charid)
		end
	end

	if message.tableid ~= nil and objectInfo == nil then
		local dataTable = dmhub.GetTable(message.tableid)
		objectInfo = dataTable[message.objectid]
	end

	local renderPanel = nil
	if objectInfo ~= nil then
		renderPanel = objectInfo:Render(options, params)
	end

	return gui.Panel{
		id = 'SharedObjectPanel',
		classes = {'chat-message-panel'},
		gui.Label{
			classes = {'chat-message-panel'},
			text = message.formattedText,
		},
		renderPanel,
	}
end


local CreateDataMessagePanel = function(message)

	local renderPanel = message.data:Render({summary = true}, {})

	return gui.Panel{
		idprefix = 'SharedObjectPanel',
		classes = {'chat-message-panel'},
		gui.Label{
			classes = {'chat-message-panel'},
			markdown = true,
			text = message.formattedText,
		},
		renderPanel,
	}
end

local CreateCustomMessagePanel = function(message)
    --gets refreshMessage on message update.
    local panel = message.properties:Render(message)
    if panel == nil then
        if devmode() then
            return gui.Label{
                textAlignment = "center",
                width = "100%",
                height = "auto",
                bgcolor = "black",
                bgimage = "panels/square.png",
                color = "white",
                fontSize = 16,
                text = "Failed to render custom message: " .. tostring(message.properties.typeName) .. " (devmode only message)",
            }
        else
            --just return a dummy panel so we won't try this again, since it was unable to render.
            return gui.Panel{
                width = 1,
                height = 1,
            }
        end
    end
    return panel
end

local rightClickHandler = function(element)
	if dmhub.isDM then
		local gmonly = element.data.message.gmonly
		element.popup = gui.ContextMenu{
			entries = {
				{
					text = "Delete Message",
					click = function()
						element.data.message:Delete()
						element.popup = nil
					end,
				},

                {
					text = "Clear Chat",
					click = function()
                        Commands.clear()
						element.popup = nil
					end,
                },

				{
					text = cond(gmonly, "Reveal to players", "Hide from players"),
					click = function()
						element.data.message.gmonly = not gmonly
						element.popup = nil
					end,
				}
			}
		}
	end
end

local CreateSingleChatPanel = function(message)
	local result
    if message.messageType == "chat" then
        result = CreateChatMessagePanel(message)
	elseif message.messageType == "object" then
		result = CreateObjectMessagePanel(message)
	elseif message.messageType == "data" then
		result = CreateDataMessagePanel(message)
    elseif message.messageType == "custom" then
        result = CreateCustomMessagePanel(message)
    end

	if result ~= nil then
		result.data.message = message
		if result.events == nil then
			result.events = {}
		end
		result.events.rightClick = rightClickHandler
	end

	return result
end

function creature:CurrentlySpokenLanguage(languages_known)
    local creature = self
    languages_known = languages_known or self:LanguagesKnown()
    if creature == nil or languages_known == nil then
        print("SPEECH:: NO LANG")
        return nil
    end

    local langTable = dmhub.GetTable(Language.tableName) or {}
    if creature:has_key("languageSpeaking") and langTable[creature.languageSpeaking] and not rawget(langTable[creature.languageSpeaking], "hidden") then
        print("SPEECH:: SET LANG", creature.languageSpeaking)
        return creature.languageSpeaking
    end

    local monsterBand = nil
    if self:IsMonster() then
        monsterBand = self:MonsterGroup()
        if monsterBand ~= nil then
            monsterBand = monsterBand.name
        end
    end

    local best = nil
    local bestScore = nil
    for key,_ in pairs(languages_known) do
        local langInfo = langTable[key]
        if langInfo ~= nil and (not rawget(langInfo,"hidden")) then
            local score = langInfo.commonality
            print("SPEECH:: SCORE", langInfo.name, "speakers", langInfo.speakers, "BAND", monsterBand)
            if monsterBand and string.find(langInfo.speakers, monsterBand) then
                score = score + 1000
            end
            if score >= (bestScore or 0) then
                best = key
                bestScore = score
            end
        end
    end

    return best
end

local function SetCurrentLanguage(token, langid)
    token:ModifyProperties{
        description = "Set Language",
        undoable = false,
        execute = function()
            token.properties.languageSpeaking = langid
        end
    }
end

local g_settingChatOOC = setting{
    id = "chatspeaker",
    default = true,
    storage = "pergamepreference",
}

--any chat panels that have errors we don't re-try.
local g_errorPanels = {}

CreateChatPanel = function()

	local children = {}
	local messagePanels = {}

	local chatPanel = gui.Panel{
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
				bgcolor = Styles.textColor,
				gradient = Styles.horizontalGradient,
			},
			{
				selectors = {'visibilityPanel'},
				halign = "right",
				valign = "center",
			},

			{
				selectors = {'chat-message-panel'},
				textAlignment = 'topleft',
				halign = 'left',
				width = '100%',
				height = 'auto',
				color = 'white',
				fontSize = '40%',
				vmargin = 2,
			},

			{
				selectors = {'chat-message-panel'},
				flow = 'vertical',
			},

            {
                selectors = {"unknownLanguage"},
                fontFace = "Tengwar",
            }
		},

        thinkTime = 0.6,

		events = {
            think = function(element)
                local lastLanguagesKnown = element.data.lastLanguagesKnown or {}

                local count = 0
                local equal = true
                for key,_ in pairs(creature:try_get("g_languagesKnownLocally", {})) do
                    if lastLanguagesKnown[key] == nil then
                        equal = false
                        break
                    end
                    count = count + 1
                end

                if equal then
                    for _,_ in pairs(lastLanguagesKnown) do
                        count = count-1
                    end

                    equal = (count == 0)
                end

                if not equal then
                    element.data.lastLanguagesKnown = table.shallow_copy(creature:try_get("g_languagesKnownLocally", {}))
                    element:FireEventTree("refreshLanguages")
                end
            end,

			create = 'refreshChat',
			refreshChat = function(element)
				local newMessagePanels = {}
				local children = {}
				local newMessage = false
				for i,message in ipairs(chat.messages) do
                    if message.messageType == "chat" or message.messageType == "data" or message.messageType == "object" or (message.messageType == "custom" and rawget(message.properties, "channel") == "chat") then
                        newMessage = (messagePanels[message.key] == nil)
                        local child = messagePanels[message.key]
                        
                        if child == nil and (not g_errorPanels[message.key]) then
                            --safely try to create the message panel. If it fails, we just skip it.
                            local ok, result

                            if devmode() then
                                --call unsafely as a dev. We want to get errors.
                                result = CreateSingleChatPanel(message)
                                ok = true
                            else
                                ok, result = pcall(CreateSingleChatPanel, message)
                            end

                            if ok then
                                child = result
                            else
                                dmhub.CloudError("Error creating chat panel in ChatPanel: ", message.messageType, result)
                                g_errorPanels[message.key] = true
                            end
                        end

                        if child ~= nil then
                            newMessagePanels[message.key] = child
                            child:FireEvent('refreshMessage', message)
                            children[#children+1] = child
                        end
                    end
				end

				messagePanels = newMessagePanels
				element.children = children

				--go to the bottom if we have new messages
				if newMessage then
					element.vscrollPosition = 0
					element:ScheduleEvent("moveToBottom", 0.05)
				end
			end,

			moveToBottomNowAndDelayed = function(element)
				element:FireEvent("moveToBottom")
				element:ScheduleEvent("moveToBottom", 0.05)
			end,

			moveToBottom = function(element)
				element.vscrollPosition = 0
			end,
		},
	}

	chat.events:Listen(chatPanel)

	local history = {}
	local historyCursor = nil

	local completionChildren = {}
	local EscapeCompletions = nil
	local completionsPanel = gui.Panel{
		floating = true,

		y = -32,
		selfStyle = {
			halign = 'left',
			valign = 'bottom',
		},

		style = {
			width = 200,
			height = 'auto',
			flow = 'vertical',
		},
		children = {
		},

		events = {
			escape = function(element)
				EscapeCompletions()
			end,
		},
	}

	local completionChildrenStyles = {
		gui.Style{
			bgcolor = '#82231DFF',
			width = '100%',
			height = 20,
			fontSize = '40%',
			color = 'white',
			halign = 'left',
			valign = 'top',
			flow = 'none',
		},
		gui.Style{
			selectors = 'hover',
			transitionTime = 0.1,
			brightness = 1.5,
		},
		gui.Style{
			selectors = 'pressed',
			transitionTime = 0.1,
			brightness = 1.2,
		},
		gui.Style{
			selectors = 'selected',
			transitionTime = 0.1,
			brightness = 1.5,
		},
	}

	local previewPanel = nil
    local speakerPanel = nil
	local inputPanel = nil

	local UpdateCompletions = nil
	UpdateCompletions = function(txt)
		local items = chat.GetCommandCompletions(txt or inputPanel.text) or {}
		while #completionChildren < #items do
			completionChildren[#completionChildren+1] = gui.Label{
				bgimage = 'panels/square.png',
				text = '',
				styles = completionChildrenStyles,
				events = {
					click = function(element)
						inputPanel.text = element.text .. ' '
						inputPanel.caretPosition = string.len(inputPanel.text)
						inputPanel.hasFocus = true
					end,
				},
			}
		end

		for i,element in ipairs(completionChildren) do
			element:SetClass('selected', false)
			if i <= #items then
				element.text = items[i]
				element:SetClass('collapsed', false)
			else
				element:SetClass('collapsed', true)
			end
		end

		completionsPanel.children = completionChildren
	end

	local CompletionsArrow = function(arrow)
		local startIndex = 1
		local endIndex = #completionChildren
		local delta = 1
		if arrow == 'down' then
			startIndex = #completionChildren
			endIndex = 1
			delta = -1
		end

		local ntarget = nil
		local stop = false
		for i = startIndex, endIndex, delta do
			local child = completionChildren[i]
			if child:HasClass('selected') and child:HasClass('collapsed') == false then
				child:SetClass('selected', false)
				stop = true
			elseif child:HasClass('collapsed') == false and stop == false then
				ntarget = i
			end
		end

		if ntarget then
			completionChildren[ntarget]:SetClass('selected', true)
			return true
		end

		return false
	end

	local GetAndClearCompletionSelected = function()
		for i,child in ipairs(completionChildren) do
			if child:HasClass('selected') and child:HasClass('collapsed') == false then
				child:SetClass('selected', false)
				return child.text
			end
		end

		return nil
	end

	EscapeCompletions = function()
		inputPanel.hasFocus = true
	end

	local userChatMessages = {}

	previewPanel = gui.Label{
		width = 330,
		height = 18,
		text = "preview text",
		fontSize = 14,
		italics = true,
		monitorGame = mod:GetDocumentSnapshot("chatEvents").path,
		thinkTime = 0.4,

		data = {
			ellipsis = "",
			firstThink = true,
		},

		refreshGame = function(element)
			element:FireEvent("think", true)
		end,

		think = function(element, artificial)
			local doc = mod:GetDocumentSnapshot("chatEvents")

			local newChatMessages = {}

			for userid,info in pairs(doc.data) do
				local existingInfo = userChatMessages[userid]
				if existingInfo == nil or existingInfo.guid ~= info.guid then
					newChatMessages[userid] = {
						guid = info.guid,
						time = cond(element.data.firstThink, -5, dmhub.Time()),
					}
				else
					newChatMessages[userid] = existingInfo
				end
			end

			userChatMessages = newChatMessages

			local users = {}
			for userid,info in pairs(userChatMessages) do
				if userid ~= dmhub.loginUserid and info.time > dmhub.Time()-5 then
					local name = dmhub.GetDisplayName(userid)
					users[#users+1] = name
				end
			end

			table.sort(users)
			if #users == 0 then
				element.text = ""
				element.data.ellipsis = ""
			else
				if not artificial then
					if #element.data.ellipsis < 3 then
						element.data.ellipsis = element.data.ellipsis .. "."
					else
						element.data.ellipsis = ""
					end
				end
				local names = pretty_join_list(users)
				element.text = string.format("%s %s typing%s", names, cond(#users == 1, "is", "are"), element.data.ellipsis)
			end

			element.data.firstThink = false
		end,
	}

    local m_speakingCreature = nil
    local m_languagesKnown = nil
    local m_languagesKnownUpdate = nil

    speakerPanel = gui.Panel{
        styles = {
            {
                selectors = {"speaker"},
                fontSize = 14,
                minFontSize = 6,
                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
                hpad = 4,
                height = 20,
                width = 40,
                bgimage = true,
            },
            {
                selectors = {"speaker", "hover", "~selected"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
                brightness = 1.2,
            },
            {
                selectors = {"speaker", "selected"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
            },
        },
        flow = "horizontal",
        width = 330,
        height = 20,
        create = function(element)
            element:FireEventTree("refreshSelectedTokens")
        end,
        refreshSelectedTokens = function(element)
        end,

        gui.Label{
            classes = {"speaker", "selected"},
            text = "OOC",
            press = function(element)
                g_settingChatOOC:Set(true)
                element.parent:FireEventTree("refreshSelectedTokens")
                inputPanel.hasFocus = true
            end,
            refreshSelectedTokens = function(element)
                local tokens = dmhub.selectedOrPrimaryTokens
                element:SetClass("selected", g_settingChatOOC:Get() or tokens == nil or #tokens == 0 or #tokens > 1)
            end,
            send = function(element, text)
                if element:HasClass("selected") or string.starts_with(text, "/") then
                    chat.Send(text)
                end
            end,
        },
        gui.Label{
            classes = {"speaker"},
            width = 120,
            press = function(element)
                g_settingChatOOC:Set(false)
                element.parent:FireEventTree("refreshSelectedTokens")
                inputPanel.hasFocus = true
            end,
            refreshSelectedTokens = function(element)
                local tokens = dmhub.selectedOrPrimaryTokens
                if tokens == nil or #tokens == 0 or #tokens > 1 then
                    element:SetClass("collapsed", true)
                    element:SetClass("selected", false)
                    return
                end

                element:SetClass("collapsed", false)
                element:SetClass("selected", not g_settingChatOOC:Get())

                local token = tokens[1]
                m_speakingCreature = token.properties
                m_languagesKnown = m_speakingCreature:LanguagesKnown()
                m_languagesKnownUpdate = dmhub.ngameupdate
                local name = creature.GetTokenDescription(token)
                element.text = name
            end,
            send = function(element, text)
                if element:HasClass("selected") and (not string.starts_with(text, "/")) then
                    local tokenid = nil
                    local tokens = dmhub.selectedOrPrimaryTokens
                    if #tokens > 0 then
                        tokenid = tokens[1].charid
                    end

                    if tokenid ~= nil then
                        local languagesKnown = tokens[1].properties:LanguagesKnown()
                        chat.SendCustom(
                            InCharacterChatMessage.new{
                                channel = "chat",
                                charname = creature.GetTokenDescription(tokens[1]),
                                text = text,
                                tokenid = tokenid,
                                langid = creature.CurrentlySpokenLanguage(m_speakingCreature, languagesKnown),
                            }
                        )
                    else
                        chat.Send(text)
                    end
                end
            end,
        },

        gui.Dropdown{
            width = 186,
            height = 20,
            fontSize = 12,
            sort = true,
            monitorAssets = "ObjectTables",
            refreshAssets = function(element)
                local options = {}
                for key,language in unhidden_pairs(dmhub.GetTable(Language.tableName) or {}) do
                    local text = language.name
                    if language.speakers ~= "" then
                        text = string.format("%s (%s)", text, language.speakers)
                    end
                    options[#options+1] = {
                        id = key,
                        text = text,
                        hidden = function()
                            if m_languagesKnownUpdate ~= dmhub.ngameupdate then
                                m_languagesKnownUpdate = dmhub.ngameupdate
                                m_languagesKnown = m_speakingCreature:LanguagesKnown()
                            end

                            return m_languagesKnown == nil or (not m_languagesKnown[key])
                        end,
                    }
                end
                element.options = options
                element.data.init = true
            end,

            create = function(element)
                element:FireEvent("refreshAssets")
            end,
            options = {},


            refreshSelectedTokens = function(element)
                if not element.data.init then
                    element:FireEvent("refreshAssets")
                end
                local tokens = dmhub.selectedOrPrimaryTokens
                if tokens == nil or #tokens == 0 or #tokens > 1 or g_settingChatOOC:Get() then
                    element:SetClass("collapsed", true)
                    return
                end

                element:SetClass("collapsed", false)
                element.idChosen = creature.CurrentlySpokenLanguage(m_speakingCreature, m_languagesKnown) or ""
            end,

            change = function(element)
                local tokens = dmhub.selectedOrPrimaryTokens
                if tokens == nil or #tokens == 0 or #tokens > 1 then
                    element:SetClass("collapsed", true)
                    return
                end

                SetCurrentLanguage(tokens[1], element.idChosen)
                element:FireEventTree("refreshSelectedTokens")
            end,
        },
    }

	local chatRealTimeUpdateTime = 0

	inputPanel = gui.Input{
        classes = {"inputFaded"},
		placeholderText = 'Enter Chat...',
		width = "100%-50",
        minHeight = 24,
        maxHeight = 300,
		height = "auto",
		lineType = "MultiLineSubmit",
		characterLimit = 4096,
		events = {
			deselect = function(element)
				--UpdateCompletions('')
			end,
			tab = function(element)
				local items = chat.GetCommandCompletions(inputPanel.text)
				if #items == 1 then
					inputPanel.text = items[1] .. ' '
					inputPanel.caretPosition = string.len(inputPanel.text)
					UpdateCompletions()
					element.hasFocus = true
				end
			end,
			uparrow = function(element)
				if CompletionsArrow('up') then
					return
				end

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

				UpdateCompletions()
			end,
			downarrow = function(element)
				if CompletionsArrow('down') then
					return
				end

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

				UpdateCompletions()
			end,
			edit = function(element)
				if historyCursor ~= nil and element.text ~= history[historyCursor] then
					historyCursor = nil
				end
				chat.PreviewChat(element.text)

				UpdateCompletions()

				--send real time updates here.
				if element.text == "" or string.starts_with(element.text, "/") then

					local doc = mod:GetDocumentSnapshot("chatEvents")
					if doc.data[dmhub.loginUserid] ~= nil then
						doc:BeginChange()
						doc.data[dmhub.loginUserid] = nil
						doc:CompleteChange("Preview chat", {undoable = false})
					end

				elseif dmhub.Time() > chatRealTimeUpdateTime + 1 then
					local doc = mod:GetDocumentSnapshot("chatEvents")
					doc:BeginChange()
					doc.data[dmhub.loginUserid] = {
						guid = dmhub.GenerateGuid(),
					}
					doc:CompleteChange("Preview chat", {undoable = false})

					chatRealTimeUpdateTime = dmhub.Time()
				end
			end,
			submit = function(element)

				local completionText = GetAndClearCompletionSelected()
				if completionText ~= nil then
					element.text = completionText .. ' '
					element.hasFocus = true
					element.caretPosition = string.len(element.text)
					return
				end

				local doc = mod:GetDocumentSnapshot("chatEvents")
				if doc.data[dmhub.loginUserid] ~= nil then
					doc:BeginChange()
					doc.data[dmhub.loginUserid] = nil
					doc:CompleteChange("Preview chat", {undoable = false})
				end

                speakerPanel:FireEventTree("send", element.text)

				historyCursor = -1

				if element.text ~= '' and history[#history] ~= element.text then
					history[#history+1] = element.text
				end

				element.text = ''

				element.hasFocus = true
				chat.PreviewChat('')

				UpdateCompletions()
			end,
			sendchat = function(element)
				--this includes a chat being sent by rolling dice.
				--Does not include executing a command.
			end,
			slash = function(element)
				element.hasFocus = true
				element.text = '/'
				element.caretPosition = 1
				element.selectionAnchorPosition = nil
				chat.PreviewChat('/')

				UpdateCompletions()
			end,
		},
	}

	chat.events:Listen(inputPanel)

	local resultPanel = gui.Panel{
		selfStyle = {
			width = '100%',
			height = '100%',
			flow = 'vertical',
		},
		children = {
			chatPanel,
			previewPanel,
            speakerPanel,
			inputPanel,
			completionsPanel,
		}
	}

	return resultPanel
end


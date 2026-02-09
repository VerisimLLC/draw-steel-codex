local mod = dmhub.GetModLoading()

local CreateChatPanel

DockablePanel.Register{
	name = "Action Log",
	icon = "icons/standard/Icon_App_ActivityLog.png",
	minHeight = 200,
	vscroll = false,
	content = function()
		return CreateChatPanel()
	end,
}

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

    local linger = function(element)
        local allChildren = element:GetChildrenWithClassRecursive("always")
        for i,child in ipairs(allChildren) do
            if child.tooltip ~= nil then
                return
            end
        end
        gui.Tooltip(DescribeServerTimestamp(message.timestamp))(element)
    end

    if panel.events == nil then
        panel.events = {
            linger = linger,
        }
    elseif panel.events.linger == nil then
        panel.events.linger = linger
    end

    return panel
end

local CreateRollCategoryPanel = function(cat, catInfo)

	local headingLabel = nil
	if cat ~= 'default' then
		local text = cat
	
		headingLabel = gui.Label{
			classes = {'roll-category-label'},
			text = text,
		}
	end

	local resultLabel = gui.Label{
		classes = {'roll-category-total'},
		text = tostring(catInfo.total),
		events = {
			showresult = function(element)
				element:SetClass("show", true)
			end,

			complete = function(element)
				element:SetClass('complete', true)
			end
		},
	}

	local rollsPanel = gui.Panel{
		classes = {'rolls-panel'},
	}

	local rollResultPanel = gui.Panel{
		classes = {'rolls-result-panel'},
		resultLabel,
		headingLabel,
	}

	local panelCache = {}

	return gui.Panel{
		classes = {'roll-category-panel'},
		children = {
			rollsPanel,
			rollResultPanel,
		},

		data = {
			addOutcomePanel = function(outcomePanel)
				rollResultPanel:AddChild(outcomePanel)
			end,
		},
		
		--see ChatPanel.cs GetRollInfo for structure of 'info'
		--diceStyle is from LuaInterface.cs GetDiceStyling().
		refreshInfo = function(element, info, diceStyle, complete, rollInfo)

            --see if the total has been changed by roll modifications.
            local total = info.total
            local boons = info.boons or 0
            local banes = info.banes or 0

            local modFromEdgesAndBanes = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(boons, banes)

            if rollInfo.properties ~= nil and rollInfo.properties:has_key("multitargets") and rollInfo.properties.multitargets[1] then
                --use the first multitarget as a guide as to modifying the roll.
                local targetInfo = rollInfo.properties.multitargets[1]
                if targetInfo.boons ~= 0 or targetInfo.boons ~= 0 then
                    boons = boons + (targetInfo.boons or 0)
                    banes = banes + (targetInfo.banes or 0)
                    local newMod = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(boons, banes)

                    total = total - modFromEdgesAndBanes + newMod
                end
            end

			resultLabel.text = string.format("%d", math.tointeger(total))

			local newPanelCache = {}
			local children = {}
			for i,roll in ipairs(info.rolls) do

				--table of guid key -> face value to give the current value shown
				--for the dice. We display the sum of these.
				local dicefaces = {}

                local nfaces = roll.faces
                if nfaces == 3 then
                    nfaces = 6
                end

				local panel = panelCache[i] or gui.Panel{
					classes = {'single-roll-panel', cond(complete, 'complete', 'preview')},
					bgimage = string.format('ui-icons/d%d-filled.png', nfaces),
					saturation = 0.7,
					brightness = 0.4,
					bgcolor = diceStyle.bgcolor,
					events = {

					},

					gui.Label{
						classes = {'single-roll-panel', cond(complete, 'complete', 'preview')},
						bgimage = string.format('ui-icons/d%d.png', nfaces),
						bgcolor = diceStyle.trimcolor,
						color = diceStyle.color,

						settext = function(element, text)
							element.text = text
						end,

						create = function(element)
							if roll.guid ~= nil and roll.guid ~= '' then
								local events = chat.DiceEvents(roll.guid)
								if events ~= nil then
									events:Listen(element)
								end

								if roll.partnerguid ~= nil then
									events = chat.DiceEvents(roll.partnerguid)
									if events ~= nil then
										events:Listen(element)
									end
								end
							end
						end,


						complete = function(element)
							element.parent:SetClassTree('preview', false)
							element.parent:SetClassTree('complete', true)
						end,

						diceface = function(element, diceguid, num, timeRemaining)
							if element:HasClass('complete') == false then
								element:SetClassTree('preview', true)

								dicefaces[diceguid] = num

								--we sum all the dice faces for this roll. Usually this is just one die
								--and once face, but d100 can have multiple dice.
								local sum = 0
								for k,num in pairs(dicefaces) do
									sum = sum + num
								end
								element.text = tostring(math.tointeger(sum))
							end
						end,
					},
				}

				panel:SetClassTree("dropped", roll.dropped)
				panel:SetClassTree("best", roll.roll == roll.faces)
				panel:SetClassTree("worst", roll.roll == 1)
				local text = string.format("%d", math.tointeger(roll.roll))
				if roll.explodes then
					text = text .. '!'
				end
				if roll.multiply ~= nil and roll.multiply ~= 1 then
					text = string.format("<size=80%%>%s\n<size=50%%>x%s</size></size>", text, tostring(roll.multiply))
				end
				panel:FireEventTree("settext", text)

				newPanelCache[i] = panel
				children[#children+1] = panel
			end

            local mod = info.mod or 0
            local boons = info.boons or 0
            local banes = info.banes or 0

            local modFromEdgesAndBanes = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(boons, banes)

            if rollInfo.properties ~= nil and rollInfo.properties:has_key("multitargets") and rollInfo.properties.multitargets[1] then
                --use the first multitarget as a guide as to modifying the roll.
                local targetInfo = rollInfo.properties.multitargets[1]
                if targetInfo.boons ~= 0 or targetInfo.boons ~= 0 then
                    boons = boons + (targetInfo.boons or 0)
                    banes = banes + (targetInfo.banes or 0)
                    local newMod = ActivatedAbilityPowerRollBehavior.GetRollModFromEdgesAndBanes(boons, banes)

                    mod = mod - modFromEdgesAndBanes + newMod
                end
            end

			if mod then
				local panel = panelCache['mod'] or gui.Label{
					classes = {'single-roll-panel','complete'},
				}
                if mod == 0 then
                    panel.text = ""
                else
				    panel.text = ModifierStr(mod)
                end
				newPanelCache['mod'] = panel
				children[#children+1] = panel
			end

			if boons >= 2 and banes == 0 then
				children[#children+1] = panelCache['doubleboon'] or gui.Panel{
					width = 16,
					height = 16,
                    halign = "left",
					valign = "center",
					bgimage = "panels/triangle.png",
					rotate = 180,
					bgcolor = "green",
					linger = function(element)
						gui.Tooltip("Double Edge -- +Tier")(element)
					end,
				}

				newPanelCache['doubleboon'] = children[#children]
			end

			if banes >= 2 and boons == 0 then
				children[#children+1] = panelCache['doublebane'] or gui.Panel{
					width = 16,
					height = 16,
					valign = "center",
					bgimage = "panels/triangle.png",
					bgcolor = "red",
					linger = function(element)
						gui.Tooltip("Double Bane -- -Tier")(element)
					end,
				}

				newPanelCache['doublebane'] = children[#children]
			end

			rollsPanel.children = children
			panelCache = newPanelCache
		end,
	}
end

local CreateRollMessagePanel = function(message, adoptiveParentPanel)

    local adopted = adoptiveParentPanel ~= nil

	local currentMessage = message

    local visibilityPanel

	local headingLabel = nil
    local paddingPanel = nil

    if not adopted then

        if dmhub.isDM then
            visibilityPanel = gui.VisibilityPanel{
                visible = not message.gmonly,
                hmargin = 6,
                x = 20,
                refreshMessage = function(element, newMessage)
                end,
                hover = function(element)
                    local text
                    if element:HasClass("visible") then
                        text = tr("Visible to everyone")
                    else
                        text = string.format(tr("Visible only to the player who rolled and the %s"), GameSystem.GameMasterShortName)
                    end
                    gui.Tooltip(text)(element)
                end,

                press = function(element)
                    message.gmonly = not message.gmonly
                end,
            }
        end

        headingLabel = gui.Label{
            classes = {'chat-message-panel'},
            width = "94%",
            visibilityPanel,
        }
        paddingPanel = gui.Panel{
            classes = {'roll-message-padding'},
        }
    end

	local outcomePanel = nil
	local outcomePanelAdded = false

	if message.forcedResult or (message.properties ~= nil and message.properties.typeName == "RollProperties" and message.properties:HasOutcomes()) then
		outcomePanel = gui.Label{
			classes = {'roll-message-outcome', 'hidden', 'appear'},
			text = ' ',
		}
	end

	local customPanel = nil

	if message.properties ~= nil then
		customPanel = message.properties:CustomPanel(message)
	end

	local longFormResultsLabel = gui.Label{
		classes = {"long-form-message-outcome"},
	}

	local catPanels = {}

	local complete = false
	local panel = gui.Panel{
		classes = {'roll-main-panel'},

		linger = function(element)
			if currentMessage == nil or (visibilityPanel ~= nil and visibilityPanel.tooltip ~= nil) then
				return
			end
			gui.Tooltip{
				maxWidth = 500,
				text = string.format("%s = %d\nRolled by %s %s", currentMessage.rollStr, currentMessage.total, currentMessage.playerName, DescribeServerTimestamp(currentMessage.timestamp)),
			}(element)
		end,

		refreshMessage = function(element, message)
            if visibilityPanel ~= nil then
			    visibilityPanel:FireEvent("visible", not message.gmonly)
            end

			if complete then
				--we already have this message and it was complete already so don't bother updating.
				return
			end

            if headingLabel ~= nil then
			    headingLabel.text = message.formattedText
            end


			local newCatPanels = {}

			local complete = message.isComplete
			local info = message.resultInfo
			local diceStyle = message.diceStyle

			local children = {headingLabel}

			if outcomePanel ~= nil and message.properties ~= nil then
				local outcome = message.properties:GetOutcome(message)
				if outcome ~= nil and #outcome.outcome < 14 then
					outcomePanel.selfStyle.color = outcome.color or "white"
					outcomePanel.text = outcome.outcome
				elseif outcome ~= nil then
					longFormResultsLabel.text = outcome.outcome
				end
			elseif outcomePanel ~= nil and message.autofailure then
				outcomePanel.selfStyle.color = "red"
				outcomePanel.text = "Failure"
			elseif outcomePanel ~= nil and message.autosuccess then
				outcomePanel.selfStyle.color = "green"
				outcomePanel.text = "Success"
			end

			for cat,catInfo in pairs(info) do

				local catPanel = catPanels[cat] or CreateRollCategoryPanel(cat, catInfo)
				catPanel:FireEvent('refreshInfo', catInfo, diceStyle, complete, message)

				if customPanel ~= nil then
					customPanel:FireEvent("refreshInfo", catInfo, diceStyle, complete, message)
				end

				newCatPanels[cat] = catPanel

				children[#children+1] = catPanel

				if outcomePanel ~= nil and not outcomePanelAdded then
					catPanel.data.addOutcomePanel(outcomePanel)
					outcomePanelAdded = true
				end
			end

			if outcomePanel ~= nil and not outcomePanelAdded then
				children[#children+1] = outcomePanel
			end

			children[#children+1] = paddingPanel

			catPanels = newCatPanels
			element.children = children

			element:SetClass('complete', message.isComplete)

			if message.isComplete then
				complete = true
				element:FireEventTree('complete')
				if outcomePanel ~= nil then
					outcomePanel:SetClass('hidden', false)
					outcomePanel:SetClass('appear', false)
				end
			end
		end,

		headingLabel,
	}

	local avatar = nil

	local avatarPanel = nil
    
    if not adopted then
        avatarPanel = gui.Panel{
            classes = {'roll-avatar-panel'},

            refreshMessage = function(element, message)
                if avatar == nil and message.tokenid ~= nil then
                    local token = dmhub.GetCharacterById(message.tokenid)
                    if token ~= nil then
                        avatar = gui.CreateTokenImage(token, {
                            width = 48,
                            height = 48,
                            valign = "center",
                            halign = "center",
                        })

                        element:AddChild(avatar)

                        local name = token:GetNameMaxLength(12)
                        if name ~= nil and name ~= "" and token.canLocalPlayerSeeName then
                            element:AddChild(gui.Label{
                                text = name,
                                fontSize = 14,
                                color = message.nickColor,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                maxWidth = 60,
                                textWrap = false,
                            })
                        end
                    end
                end
            end
        }
    end


    local separator = nil
    if not adopted then
	    separator = gui.Panel{
		    classes = {'separator'},
	    }
    end


    local chatMessagePanel
	chatMessagePanel = gui.Panel{
		classes = {"chat-message-panel"},
		bgimage = "panels/square.png",
		bgcolor = "clear",
		flow = "vertical",

		refreshMessage = function(element, message)
			currentMessage = message
			panel:FireEvent("refreshMessage", message)
            if avatarPanel ~= nil then
			    avatarPanel:FireEventTree("refreshMessage", message)
            end

            if adopted then
                chatMessagePanel:SetClassTree("adopted", true)
            end


		end,

        separator,

		gui.Panel{
			classes = {'chat-message-panel', 'roll-message-panel'},
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				vmargin = 0,
				hmargin = 0,
				avatarPanel,
				panel,
			},

			--force the result to show even if it's not complete yet. Useful to allow the user to see it and able to modify it.
			forceShowResult = function(element)
				element:FireEventTree("showresult")
			end,

			longFormResultsLabel,
			customPanel,
		},
	}

    if adopted then
        chatMessagePanel:SetClassTree("adopted", true)
    end

	return chatMessagePanel
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

local CreateSingleChatPanel = function(message, adoptiveParentPanel)
	local result = nil
	if message.messageType == "roll" then
		result = CreateRollMessagePanel(message, adoptiveParentPanel)
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

--any chat panels that have errors we don't re-try.
local g_errorPanels = {}

CreateChatPanel = function()

	local children = {}
	local messagePanels = {}
    local adoptedPanels = {}

	local chatPanel = gui.Panel{
		id = 'action-log-panel',
		vscroll = true,
        vscrollLockToBottom = true,
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
                selectors = {'chat-message-panel', 'adopted'},
                tmargin = -16,
            },

			{
				selectors = {'chat-message-panel', 'roll-message-panel'},
				flow = 'vertical',
			},
			{
				selectors = {'roll-avatar-panel'},
				flow = 'vertical',
				width = "14%",
				height = "auto",
				halign = "left",
				valign = "center",
			},
			{
				selectors = {'roll-main-panel'},
				flow = 'vertical',
				width = "80%",
				height = "auto",
				halign = "right",
			},
			{
				selectors = {'roll-message-outcome'},
				color = 'white',
				fontSize = 18,
				minFontSize = 10,
				halign = 'center',
				valign = 'bottom',
				width = 'auto',
				height = 'auto',
				maxWidth = 70,
			},
			{
				selectors = {'roll-message-outcome', 'appear'},
				scale = 3,
				opacity = 0,
				transitionTime = 0.25,
			},
			{
				selectors = {'long-form-message-outcome'},
				fontSize = 14,
				color = "white",
				width = "100%",
				height = "auto",
			},
			{
				selectors = {'roll-message-padding'},
				width = '100%',
				height = 8,
			},
			{
				selectors = {'rolls-panel'},
				width = '60%',
				height = 'auto',
				valign = "center",
				flow = 'horizontal',
				wrap = true,
			},
            {
                selectors = {"rolls-panel", "adopted"},
                uiscale = 0.7,
                width = "60%",
                halign = "right",
            },
			{
				selectors = {'roll-category-label'},
				halign = 'center',
				valign = 'top',
				width = 'auto',
				height = 'auto',
				maxWidth = 64,
				fontSize = 18,
				minFontSize = 8,
				color = 'white',
			},
			{
				selectors = {'roll-category-total'},
				width = 'auto',
				height = 'auto',
				halign = 'center',
				valign = 'bottom',
				bold = true,
				fontSize = 28,
				color = 'clear',
				scale = 3,
			},
			{
				selectors = {'roll-category-total', 'show'},
				scale = 1,
				color = '#ffffff55',
			},
			{
				selectors = {'roll-category-total', 'complete'},
				transitionTime = 0.25,
				scale = 1,
				color = 'white',
			},
			{
				selectors = {'rolls-result-panel'},
				valign = "center",
				width = "25%",
				height = "auto",
				halign = "right",
				flow = "vertical",
			},
            {
                selectors = {'rolls-result-panel', 'adopted'},
                width = "15%",
            },
			{
				selectors = {'roll-category-panel'},
				flow = 'horizontal',
				width = '100%',
				height = 'auto',
			},
			{
				selectors = {'single-roll-panel'},
				halign = 'left',
				textAlignment = 'center',
				textWrap = false,
				textOverflow = "overflow",
				fontSize = 24,
				color = 'clear',
				bgcolor = '#cccccc',
				bold = true,
				width = 40,
				height = 40,
			},
			{
				selectors = {'single-roll-panel','complete'},
				color = 'white',
			},
			{
				selectors = {'single-roll-panel','complete','best'},
				color = '#aaffaa',
			},
			{
				selectors = {'single-roll-panel','complete','worst'},
				color = '#ffaaaa',
			},
			{
				selectors = {'single-roll-panel','complete','dropped'},
				opacity = 0.3,
			},
			{
				selectors = {'single-roll-panel','label','preview'},
				opacity = 0.6,
			},
		},

		events = {
			create = 'refreshChat',
			refreshChat = function(element)
				local newMessagePanels = {}
				local children = {}
				local newMessage = false
				for i,message in ipairs(chat.messages) do
                    if adoptedPanels[message.key] then
                        local panel = adoptedPanels[message.key]
                        if panel.valid then
                            panel:FireEvent('refreshMessage', message)
                        end
                    elseif message.messageType ~= "chat" and message.messageType ~= "data" and message.messageType ~= "object" and (message.messageType ~= "custom" or rawget(message.properties, "channel") ~= "chat") then
                        newMessage = (messagePanels[message.key] == nil)
                        local child = messagePanels[message.key]

                        local adoptiveParentPanel = nil
                        if message.messageType == "roll" and message.properties ~= nil then
                            adoptiveParentPanel = element.data.castPanels and element.data.castPanels[message.properties:try_get("castid")]
                        end
                        
                        if child == nil and (not g_errorPanels[message.key]) then

                            local ok, result

                            --safely try to create the message panel. If it fails, we just skip it.
                            if devmode() then
                                --call unsafely as a dev. We want to get errors.
                                result = CreateSingleChatPanel(message, adoptiveParentPanel)
                                ok = true
                            else
                                ok, result = pcall(CreateSingleChatPanel, message, adoptiveParentPanel)
                            end

                            if ok then
                                child = result
                            else

                                dmhub.CloudError("Error creating chat panel in ActionLog: ", message.messageType, result)
                                g_errorPanels[message.key] = true
                            end
                        end

                        if child ~= nil then
                            newMessagePanels[message.key] = child
                            child:FireEvent('refreshMessage', message)

                            if adoptiveParentPanel ~= nil then
                                adoptiveParentPanel:AddChild(child)
                                adoptedPanels[message.key] = child
                            else
                                children[#children+1] = child

                                if child.data.castid then
                                    local castPanels = element.data.castPanels or {}
                                    castPanels[child.data.castid] = child
                                    element.data.castPanels = castPanels
                                end
                            end
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

	local resultPanel = gui.Panel{
		selfStyle = {
			width = '100%',
			height = '100%',
			flow = 'vertical',
		},
		children = {
			chatPanel,
		}
	}

	return resultPanel
end


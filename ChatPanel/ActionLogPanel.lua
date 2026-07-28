local mod = dmhub.GetModLoading()

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

local CreateChatPanel

DockablePanel.Register{
	name = "Action Log",
	icon = "icons/standard/Icon_App_ActivityLog.png",
	minHeight = 200,
	vscroll = false,
	content = function()
		track("panel_open", {
			panel = "Action Log",
			dailyLimit = 30,
		})
		return CreateChatPanel()
	end,
}

local CreateCustomMessagePanel = function(message)
    --gets refreshMessage on message update.

    --pcall: a message may come from a client running a newer mod version whose
    --message type is not registered here; reading .Render on an unknown type raises.
    local panel = nil
    pcall(function() panel = message.properties:Render(message) end)
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

-- Determines if a token is acting out of turn (e.g. triggered ability / reaction).
local function IsOutOfTurn(token)
    if token == nil then
        return false
    end
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return false
    end
    local currentId = q:CurrentInitiativeId()
    if currentId == nil then
        return false
    end
    return InitiativeQueue.GetInitiativeId(token) ~= currentId
end

-- Shared card wrapper for all action log entries.
-- options:
--   token: CharacterToken (for portrait, name, player color)
--   content: gui element or table of elements for the card body
--   classes: additional CSS classes (optional)
--   nameOverride: string to use instead of token name (optional)
--   hidePortrait: bool (optional)
--   hideName: bool (optional)
function CreateActionLogCard(options)
    local token = options.token
    local outOfTurn = IsOutOfTurn(token)

    local playerColor = "#AA0000"
    if token ~= nil and token.valid and token.playerControlled then
        playerColor = token.playerColor
    end

    local portraitPanel = nil
    if token ~= nil and token.valid and not options.hidePortrait then
        portraitPanel = gui.CreateTokenImage(token, {
            classes = {"action-log-portrait"},
        })
    end

    local nameLabel = nil
    if not options.hideName then
        local name = options.nameOverride
        if name == nil and token ~= nil and token.valid then
            name = token.name
            if not token.canLocalPlayerSeeName then
                name = "Unknown"
            end
        end
        if name ~= nil then
            nameLabel = gui.Label{
                classes = {"action-log-name", "sizeS", "bold"},
                text = name,
            }
        end
    end

    local content = options.content or {}

    local contentChildren = {}
    if nameLabel then
        contentChildren[#contentChildren+1] = nameLabel
    end
    for _,child in ipairs(content) do
        contentChildren[#contentChildren+1] = child
    end

    local cardClasses = {"action-log-card", "bgAlt", cond(outOfTurn, "out-of-turn")}
    for _,cls in ipairs(options.classes or {}) do
        cardClasses[#cardClasses+1] = cls
    end

    return gui.Panel{
        classes = cardClasses,
        --Clip the floating color bar to the card: it is height="100%" which resolves
        --against the scroll viewport (not this auto-height card), so without clipping it
        --overshoots downward and bleeds over the entries beneath this one. clip needs a
        --bgimage to use as the clip mask; the "bgAlt" class supplies one (and its visible
        --dark fill), so clip alone crops the bar without a clipHidden companion here.
        clip = true,

        -- Color accent bar (floating so it doesn't affect horizontal flow sizing)
        gui.Panel{
            classes = {"action-log-color-bar"},
            floating = true,
            bgcolor = playerColor,
        },

        gui.Panel{
            classes = {"action-log-card-header"},

            -- Portrait
            portraitPanel,

            -- Content area
            gui.Panel{
                classes = {"action-log-content"},
                children = contentChildren,
            },
        },
    }
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

			local rollType = rollInfo.properties and rollInfo.properties:try_get("type")
			if rollType ~= "project_power_roll" then 
				if boons >= 2 and banes == 0 then
					children[#children+1] = panelCache['doubleboon'] or gui.Panel{
						classes = {"bgSuccess"},
						width = 16,
						height = 16,
						halign = "left",
						valign = "center",
						bgimage = "panels/triangle.png",
						rotate = 180,
						linger = function(element)
							gui.Tooltip("Double Edge -- +Tier")(element)
						end,
					}

					newPanelCache['doubleboon'] = children[#children]
				end

				if banes >= 2 and boons == 0 then
					children[#children+1] = panelCache['doublebane'] or gui.Panel{
						classes = {"bgDanger"},
						width = 16,
						height = 16,
						valign = "center",
						bgimage = "panels/triangle.png",
						linger = function(element)
							gui.Tooltip("Double Bane -- -Tier")(element)
						end,
					}

					newPanelCache['doublebane'] = children[#children]
				end
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
				if outcome ~= nil then
					local outcomeText = outcome.outcome
					if message.tokenid ~= nil then
						local token = dmhub.GetCharacterById(message.tokenid)
						if token ~= nil then
							outcomeText = StringInterpolateGoblinScript(outcomeText, token.properties)
						end
					end
					if #outcomeText < 14 then
						-- Caller-supplied custom color stays inline; otherwise clear so
						-- the cascade's @fgStrong on {roll-message-outcome} wins reactively.
						outcomePanel.selfStyle.color = outcome.color
						outcomePanel:SetClass("success", false)
						outcomePanel:SetClass("danger", false)
						outcomePanel.text = outcomeText
					else
						longFormResultsLabel.text = outcomeText
					end
				end
			elseif outcomePanel ~= nil and message.autofailure then
				outcomePanel.selfStyle.color = nil
				outcomePanel:SetClass("success", false)
				outcomePanel:SetClass("danger", true)
				outcomePanel.text = "Failure"
			elseif outcomePanel ~= nil and message.autosuccess then
				outcomePanel.selfStyle.color = nil
				outcomePanel:SetClass("danger", false)
				outcomePanel:SetClass("success", true)
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
    local m_cardToken = nil

    if not adopted then
        avatarPanel = gui.Panel{
            classes = {"action-log-portrait"},

            refreshMessage = function(element, message)
                if avatar == nil and message.tokenid ~= nil then
                    local token = dmhub.GetCharacterById(message.tokenid)
                    if token ~= nil then
                        m_cardToken = token
                        avatar = gui.CreateTokenImage(token, {
                            width = 40,
                            height = 40,
                            valign = "center",
                            halign = "center",
                        })

                        element:AddChild(avatar)
                    end
                end
            end
        }
    end

    local rollContentPanel = gui.Panel{
        classes = {'chat-message-panel', 'roll-message-panel'},
        width = "100%-12",
        halign = "right",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 0,
            hmargin = 0,
            panel,
        },

        forceShowResult = function(element)
            element:FireEventTree("showresult")
        end,

        longFormResultsLabel,
    }


    local customPanelWrapper = nil
    if customPanel ~= nil then
        customPanelWrapper = gui.Panel{
            classes = {"action-log-card-custom"},
            customPanel,
        }
    end

    local chatMessagePanel
    if adopted then
        -- Wrap rollContentPanel in a container that matches the standalone
        -- card's action-log-content width so dice align consistently.
        local adoptedRollContent = gui.Panel{
            width = "100%-70",
            height = "auto",
            halign = "right",
            flow = "vertical",
            rollContentPanel,
        }

        chatMessagePanel = gui.Panel{
            classes = {"chat-message-panel"},
            flow = "vertical",

            refreshMessage = function(element, message)
                currentMessage = message
                panel:FireEvent("refreshMessage", message)
                chatMessagePanel:SetClassTree("adopted", true)
            end,

            adoptedRollContent,
            customPanelWrapper,
        }
        chatMessagePanel:SetClassTree("adopted", true)
    else
        -- Standalone roll: wrap in card layout
        -- We build the card container and inject content on refreshMessage
        -- since we need the token from the message.
        local colorBar = gui.Panel{
            classes = {"action-log-color-bar"},
            floating = true,
            bgcolor = "#888888",
        }

        local rollNameLabel = gui.Label{
            classes = {"action-log-name", "sizeS", "bold"},
            text = "",
        }

        chatMessagePanel = gui.Panel{
            classes = {"chat-message-panel"},
            flow = "vertical",
            width = "100%",
            height = "auto",

            refreshMessage = function(element, message)
                currentMessage = message
                panel:FireEvent("refreshMessage", message)
                rollContentPanel:SetClassTree("adopted", true)
                avatarPanel:FireEventTree("refreshMessage", message)

                if m_cardToken ~= nil then
                    if m_cardToken ~= nil and m_cardToken.valid and m_cardToken.playerControlled then
                        colorBar.selfStyle.bgcolor = m_cardToken.playerColor
                    else
                        local monsterColor = "#AA0000"
                        colorBar.selfStyle.bgcolor = monsterColor
                    end
                    element:SetClass("out-of-turn", IsOutOfTurn(m_cardToken))
                    if m_cardToken.canLocalPlayerSeeName then
                        rollNameLabel.text = m_cardToken.name
                    else
                        rollNameLabel.text = "Unknown"
                    end
                else
                    rollNameLabel.text = message.playerName or ""
                end
            end,

            gui.Panel{
                classes = {"action-log-card"},
                --Contain the floating colorBar (height 100% overshoots -- see CreateActionLogCard).
                --Unlike CreateActionLogCard this card has no "bgAlt" class, so it has no bgimage
                --for clip to use as a mask; supply an invisible one (square.png + clear + clipHidden)
                --so clip actually crops the bar without drawing a background of its own.
                clip = true,
                clipHidden = true,
                bgimage = "panels/square.png",
                bgcolor = "clear",

                colorBar,

                gui.Panel{
                    classes = {"action-log-card-header"},
                    avatarPanel,

                    gui.Panel{
                        classes = {"action-log-content"},
                        rollNameLabel,
                        rollContentPanel,
                    },
                },
                customPanelWrapper,
            },
        }
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
    --true once refreshChat has completed at least one FULL pass; the incremental path
    --can only patch an existing build.
    local m_fullRefreshDone = false

	local chatPanelStyles = {
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

            -- Round > Turn spine. Deliberately quiet: the spine is scaffolding
            -- for the cards, not content of its own. No cornerRadius here -- the
            -- active theme's squared/rounded choice owns that, not this panel.
            {
                selectors = {"actionLogRound"},
                width = "100%",
                height = "auto",
                flow = "vertical",
            },
            {
                selectors = {"actionLogRoundHeader"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                hpad = 4,
            },
            {
                selectors = {"actionLogRoundLabel"},
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 10,
                uppercase = true,
                bold = true,
                color = Styles.textColor,
                opacity = 0.7,
            },
            {
                selectors = {"actionLogTurn"},
                width = "100%",
                height = "auto",
                flow = "vertical",
            },
            {
                selectors = {"actionLogTurnHeader"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                hpad = 8,
                vmargin = 2,
            },
            {
                selectors = {"actionLogTurnActor"},
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 13,
                bold = true,
                color = Styles.textColor,
            },
            {
                selectors = {"actionLogRoundCount"},
                width = "auto",
                height = "auto",
                halign = "right",
                fontSize = 9,
                uppercase = true,
                color = Styles.textColor,
                opacity = 0.45,
            },
            -- Ally/foe dot. These two are the Draw Steel status swatches the
            -- design calls for (--hp-healthy / --hp-dying); they are role
            -- semantics owned by the system, so they are stated rather than
            -- pulled from the theme's text ramp.
            {
                selectors = {"actionLogTurnDot"},
                width = 6,
                height = 6,
                valign = "center",
                rmargin = 6,
            },
            {
                selectors = {"actionLogTurnDot", "hero"},
                bgcolor = "#2D6A4F",
            },
            {
                selectors = {"actionLogTurnDot", "foe"},
                bgcolor = "#6B2020",
            },
            -- The turn's cards indent under its header, so the spine reads as a
            -- hierarchy rather than three stacked label rows.
            {
                selectors = {"actionLogTurnBody"},
                width = "100%-10",
                height = "auto",
                halign = "right",
                flow = "vertical",
            },

            -- Collapsible child rolls under an ability cast.
            {
                selectors = {"actionLogKids"},
                width = "100%",
                height = "auto",
                flow = "vertical",
            },
            {
                selectors = {"actionLogKidsBody"},
                width = "100%-8",
                height = "auto",
                halign = "right",
                flow = "vertical",
            },
            {
                selectors = {"actionLogKidsBadge"},
                width = "auto",
                height = "auto",
                halign = "left",
                flow = "horizontal",
                hpad = 4,
                vmargin = 2,
            },
            {
                selectors = {"actionLogKidsBadgeLabel"},
                width = "auto",
                height = "auto",
                valign = "center",
                fontSize = 9,
                color = Styles.textColor,
                opacity = 0.55,
            },
            {
                selectors = {"actionLogKidsBadgeLabel", "parent:hover"},
                opacity = 1,
            },

            -- Action log card styles
            {
                selectors = {"action-log-card"},
                flow = "vertical",
                width = "100%",
                height = "auto",
                cornerRadius = 4,
                vmargin = 2,
            },
            {
                selectors = {"action-log-card", "out-of-turn"},
                lmargin = 20,
                width = "100%-20",
            },
            {
                selectors = {"action-log-color-bar"},
                width = 6,
                height = "100%",
                bgimage = "panels/square.png",
                halign = "left",
                valign = "top",
            },
            {
                selectors = {"action-log-card-header"},
                flow = "horizontal",
                width = "100%",
                height = "auto",
            },
            {
                selectors = {"action-log-portrait"},
                width = 40,
                height = 40,
                halign = "left",
                valign = "top",
                lmargin = 10,
                tmargin = 6,
                bmargin = 6,
                rmargin = 4,
            },
            {
                selectors = {"action-log-content"},
                flow = "vertical",
                width = "100%-70",
                height = "auto",
                halign = "right",
                vpad = 4,
            },
            {
                selectors = {"action-log-card-custom"},
                flow = "vertical",
                width = "100%",
                height = "auto",
                hpad = 10,
                bmargin = 4,
                borderBox = true,
            },
            {
                selectors = {"action-log-name"},
                width = "auto",
                height = "auto",
                maxWidth = "100%",
                halign = "left",
            },
            {
                selectors = {"action-log-detail"},
                width = "100%",
                height = "auto",
                halign = "left",
                textAlignment = "left",
            },
            {
                selectors = {"action-log-subtext"},
                width = "100%",
                height = "auto",
                halign = "left",
                textAlignment = "left",
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
				color = '@fgStrong',
				fontSize = '100%',
				vmargin = 2,
			},
            {
                selectors = {'chat-message-panel', 'adopted'},
                tmargin = 0,
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
				width = "100%",
				height = "auto",
				halign = "left",
			},
			{
				selectors = {'roll-message-outcome'},
				color = '@fgStrong',
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
				color = "@fgStrong",
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
				color = '@fgStrong',
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
				color = '@fgStrong',
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
				color = '@fgStrong',
			},
			{
				selectors = {'single-roll-panel','complete','best'},
				color = '@success',
			},
			{
				selectors = {'single-roll-panel','complete','worst'},
				color = '@danger',
			},
			{
				selectors = {'single-roll-panel','complete','dropped'},
				opacity = 0.3,
			},
			{
				selectors = {'single-roll-panel','label','preview'},
				opacity = 0.6,
			},

			-- Rules previously in MCDMAbilityRollBehavior.lua's g_tableStyles /
			-- g_boonsBanesStyles / g_RollModifierStyles. Lifted here so the
			-- chatPanel's reactive cascade carries them -- those packs were
			-- frozen MergeTokens snapshots that broke theme reactivity.
			{
				selectors = {'row', 'highlighted'},
				transitionTime = 1.0,
				bgcolor = "@accent",
			},
			{
				selectors = {'label', 'parent:highlighted'},
				transitionTime = 1.0,
				color = "@fgInverse",
			},
			{
				selectors = {'row', 'flash'},
				brightness = 3,
				transitionTime = 0.3,
			},
			{
				selectors = {'label', 'parent:collapsedAnim'},
				transitionTime = 0.5,
				uiscale = {x = 1, y = 0.001},
			},
			{
				selectors = {'amendable', 'row', 'hover'},
				bgcolor = "@accentHover",
			},
			{
				--Amendable rows fill with the light @accentHover gold on hover, so
				--flip the tier text to the dark inverse color to stay legible
				--(mirrors {label, parent:highlighted} above for the accent fill).
				selectors = {'label', 'parent:amendable', 'parent:hover'},
				color = "@fgInverse",
			},
			{
				selectors = {'collapsedAnim'},
				transitionTime = 0.5,
				uiscale = {x = 1, y = 0.001},
			},
			{
				selectors = {'boonsBanesLabel'},
				color = "@fgStrong",
				valign = "center",
				width = "20%",
				height = "100%",
				bgimage = "panels/square.png",
				textAlignment = "center",
				borderWidth = 1,
				borderColor = "@border",
			},
			{
				selectors = {'boonsBanesLabel', 'selected'},
				bgcolor = "@fgStrong",
				color = "@bg",
				bold = true,
			},
			{
				selectors = {'boonsBanesLabel', 'hover', '~selected', 'parent:active'},
				bgcolor = "@fgStrong",
				color = "@bg",
				brightness = 0.9,
			},
			{
				selectors = {'modifierPanel'},
				bgcolor = "@bgAlt",
			},
			{
				selectors = {'modifierPanel', 'good'},
				bgcolor = "@success",
			},
			{
				selectors = {'modifierPanel', 'bad'},
				bgcolor = "@warning",
			},
		}

	--=====================================================================
	-- Round > Turn spine
	--
	-- Messages carry the combat round and turn they were sent in
	-- (ChatMessageInfo.round/.turn, stamped engine-side on send). Instead of
	-- parenting every message panel straight into the scroll panel, they are
	-- parented into a Round > Turn > body tree, so the log reads as a spine
	-- rather than one flat stream.
	--
	-- This is layered ON TOP of the existing incremental refresh, deliberately:
	-- message panels are still created, cached, refreshed and cast-adopted
	-- exactly as before -- only their PARENT changes. The changed/structural/
	-- removed fast paths and the castPanels adoption logic are untouched, which
	-- is what keeps a dice roll's refresh storm off the frame budget.
	--
	-- round == 0 means the message was sent outside combat; those parent
	-- straight to the scroll panel, exactly as they do today.
	--=====================================================================

	--Older engine builds have no round/turn on the message wrapper, and reading
	--a property that does not exist on the C# userdata raises. Probe ONCE on the
	--first message we see rather than pcall-ing per message on the hot path; if
	--the stamp is missing the panel simply stays flat, as it is today.
	local m_haveStamp = nil

	local function StampAvailable(message)
		if m_haveStamp == nil then
			m_haveStamp = pcall(function() return message.round end)
		end
		return m_haveStamp
	end

	--Returns the panel a message's card should be parented into, creating the
	--Round and Turn containers on demand. Returns nil when the message has no
	--turn (outside combat, or a build without the stamp), meaning "parent to
	--the scroll panel as before".
	--`sink` is the full pass's children array. The full pass REPLACES
	--element.children wholesale, so a round panel created during it must land in
	--that array rather than be added to the live panel (which would be discarded
	--a moment later). Messages are iterated in order, so appending the round
	--panel at the point its first message appears keeps rounds in chronological
	--position alongside any out-of-combat messages. The incremental path passes
	--no sink and adds directly.
	local function TurnBodyFor(element, message, sink)
		if not StampAvailable(message) then
			return nil
		end

		local round = message.round or 0
		local turn = message.turn or 0
		if round == 0 then
			return nil
		end

		element.data.roundPanels = element.data.roundPanels or {}
		element.data.turnPanels = element.data.turnPanels or {}

		local roundPanel = element.data.roundPanels[round]
		if roundPanel == nil or (not roundPanel.valid) then
			local countLabel = gui.Label{
				classes = { "actionLogRoundCount" },
				width = "auto",
				height = "auto",
				halign = "right",
				text = "",
			}

			roundPanel = gui.Panel{
				classes = { "actionLogRound" },
				width = "100%",
				height = "auto",
				flow = "vertical",
				gui.Panel{
					classes = { "actionLogRoundHeader" },
					width = "100%",
					height = "auto",
					flow = "horizontal",
					--pins to the top of the log while this round's turns scroll
					--under it, and leaves with the round.
					sticky = true,
					gui.Label{
						classes = { "actionLogRoundLabel" },
						width = "auto",
						height = "auto",
						halign = "left",
						text = string.format("ROUND %d", round),
					},
					countLabel,
				},
			}
			roundPanel.data.countLabel = countLabel
			element.data.roundPanels[round] = roundPanel
			if sink ~= nil then
				sink[#sink + 1] = roundPanel
			else
				element:AddChild(roundPanel)
			end
		end

		local key = string.format("%d:%d", round, turn)
		local entry = element.data.turnPanels[key]
		if entry ~= nil and entry.body ~= nil and entry.body.valid then
			return entry.body
		end

		--Actor for the turn header comes from the first message we file under
		--it. A turn's later messages can belong to other tokens (a reaction, a
		--triggered ability), so the FIRST one is the closest thing to "whose
		--turn this is" without a separate turn-owner stamp.
		local actorName = nil
		local isHero = false
		if message.tokenid ~= nil then
			local token = dmhub.GetCharacterById(message.tokenid)
			if token ~= nil then
				actorName = token.name
				--same discriminator the cards already use for player colouring
				--(see IsOutOfTurn's caller above): player-controlled reads as an
				--ally, everything else as a foe.
				isHero = token.valid and token.playerControlled
			end
		end

		local body = gui.Panel{
			classes = { "actionLogTurnBody" },
			width = "100%",
			height = "auto",
			flow = "vertical",
		}

		local turnPanel = gui.Panel{
			classes = { "actionLogTurn" },
			width = "100%",
			height = "auto",
			flow = "vertical",
			gui.Panel{
				classes = { "actionLogTurnHeader" },
				width = "100%",
				height = "auto",
				flow = "horizontal",
				--stacks directly under the pinned round rule, so both stay
				--readable while a turn's entries scroll past.
				sticky = true,
				--ally/foe dot, the design's one spot of role colour on the spine.
				gui.Panel{
					classes = { "actionLogTurnDot", cond(isHero, "hero", "foe") },
					width = 6,
					height = 6,
					valign = "center",
					halign = "left",
					bgimage = "panels/square.png",
				},
				gui.Label{
					classes = { "actionLogTurnActor" },
					width = "auto",
					height = "auto",
					halign = "left",
					text = actorName or "Turn",
				},
			},
			body,
		}

		element.data.turnPanels[key] = { panel = turnPanel, body = body, round = round }
		roundPanel:AddChild(turnPanel)
		return body
	end

	--A cast's child rolls collapse behind a "v n" badge, per the design.
	--
	--They are NOT parented straight onto the ability card: that card is rendered
	--by whichever mod owns the message type (properties:Render), so its internals
	--are not ours to reach into. Instead they go in a container we own -- a
	--clickable badge row plus a body -- appended to the card. Collapsing hides
	--only that body, so the card itself is never touched.
	--
	--Glyphs are ASCII ("v" / ">") rather than the design's chevrons: this file,
	--like the rest of the codex, is ASCII-only.
	local function AdoptInto(castPanel, child)
		if castPanel == nil or (not castPanel.valid) then
			return
		end

		local kids = castPanel.data.kidsContainer
		if kids == nil or kids.body == nil or (not kids.body.valid) then
			local body = gui.Panel{
				classes = { "actionLogKidsBody" },
				width = "100%",
				height = "auto",
				flow = "vertical",
			}

			local badgeLabel = gui.Label{
				classes = { "actionLogKidsBadgeLabel" },
				width = "auto",
				height = "auto",
				valign = "center",
				text = "",
			}

			local badge = gui.Panel{
				classes = { "actionLogKidsBadge" },
				width = "auto",
				height = "auto",
				halign = "left",
				flow = "horizontal",
				badgeLabel,
				press = function(element)
					body:SetClass("collapsed", not body:HasClass("collapsed"))
					element:FireEvent("refreshKids")
				end,
				refreshKids = function(element)
					local n = body.children ~= nil and #body.children or 0
					badgeLabel.text = string.format("%s %d", cond(body:HasClass("collapsed"), ">", "v"), n)
					--a cast with no rolls under it shows no badge at all.
					element:SetClass("collapsed", n == 0)
				end,
			}

			local container = gui.Panel{
				classes = { "actionLogKids" },
				width = "100%",
				height = "auto",
				flow = "vertical",
				badge,
				body,
			}

			kids = { container = container, body = body, badge = badge }
			castPanel.data.kidsContainer = kids
			castPanel:AddChild(container)
		end

		kids.body:AddChild(child)
		if kids.badge.valid then
			kids.badge:FireEvent("refreshKids")
		end
	end

	--Round entry counts, DERIVED from what is actually parented under each round
	--rather than accumulated as messages arrive: the full pass re-files every
	--message, so a running counter would inflate on every structural refresh.
	--Cheap -- it walks a handful of group panels, not the message list.
	local function RefreshRoundCounts(element)
		local counts = {}
		for _, entry in pairs(element.data.turnPanels or {}) do
			if entry.body ~= nil and entry.body.valid and entry.round ~= nil then
				local kids = entry.body.children
				counts[entry.round] = (counts[entry.round] or 0) + (kids ~= nil and #kids or 0)
			end
		end

		for round, panel in pairs(element.data.roundPanels or {}) do
			local label = panel.valid and panel.data.countLabel or nil
			if label ~= nil and label.valid then
				local n = counts[round] or 0
				label.text = string.format("%d %s", n, cond(n == 1, "entry", "entries"))
			end
		end
	end

	local chatPanel = gui.Panel{
		id = 'action-log-panel',
		vscroll = true,
        vscrollLockToBottom = true,
		hideObjectsOutOfScroll = true,
		hpad = 6,
		width = "100%-12",
		height = "100% available",

		styles = ThemeEngine.MergeStyles(chatPanelStyles),

		events = {
			create = 'refreshChat',
			refreshChat = function(element, changeInfo)
				--dev:diceperf -- per-phase timing of this handler (see engine settings.txt).
				--os.clock() (CPU seconds) rather than dmhub.Time(), which is frame-quantized.
				local perfLog = dmhub.GetSettingValue("dev:diceperf")
				local perfStart = perfLog and os.clock() or 0
				local perfCreateMs, perfCreates, perfRefreshMs, perfRefreshes = 0, 0, 0, 0

				--INCREMENTAL PATH. The engine passes a change-set with refreshChat (see
				--ChatPanel.cs RefreshLua): changeInfo.changed maps the top-level message
				--keys whose content changed (new message, server echo replacing the
				--message object, amendment arrival, roll completion) to true, and
				--changeInfo.structural is true when the message SET changed shape
				--(removal / first load / chat cleared). For a non-structural change on
				--an already-built log, only the changed panels are touched: existing
				--panels get refreshMessage, brand-new messages get a panel created and
				--APPENDED. Nothing else is visited -- in particular the other ~100
				--message panels and this scroll panel's children list -- which is what
				--keeps a dice roll's refresh storm (send + echo + completion) off the
				--frame budget. A structural change, or a refresh before the first full
				--build (changeInfo == nil for the panel-create event), falls through to
				--the full pass below.
				if changeInfo ~= nil and (not changeInfo.structural) and m_fullRefreshDone then
					--Removed messages (chat is pruned past 128 messages on every send, so
					--this is routine): destroy just that message's panel.
					for key,_ in pairs(changeInfo.removed or {}) do
						local child = messagePanels[key] or adoptedPanels[key]
						messagePanels[key] = nil
						adoptedPanels[key] = nil
						if child ~= nil and child.valid then
							child:DestroySelf()
						end
					end

					local anyNew = false
					for key,_ in pairs(changeInfo.changed) do
						--chat.GetRollInfo is a by-key lookup of the same message wrappers
						--chat.messages holds (any message type, despite the name).
						local message = chat.GetRollInfo(key)
						if message ~= nil then
							local adopted = adoptedPanels[key]
							if adopted then
								if adopted.valid then
									adopted:FireEvent('refreshMessage', message)
								end
							else
								local child = messagePanels[key]
								--a panel destroyed out from under us (e.g. its adoptive
								--cast parent was removed) is treated as missing.
								if child ~= nil and (not child.valid) then
									messagePanels[key] = nil
									child = nil
								end
								if child ~= nil then
									child:FireEvent('refreshMessage', message)

									--late adoption: mirrors the full pass below.
									local adoptiveParentPanel = child.data.adoptCastid and element.data.castPanels and element.data.castPanels[child.data.adoptCastid]
									if adoptiveParentPanel ~= nil and adoptiveParentPanel.valid then
										AdoptInto(adoptiveParentPanel, child)
										adoptedPanels[key] = child
									end
								elseif message.messageType ~= "chat" and message.messageType ~= "data" and message.messageType ~= "object" and (message.messageType ~= "custom" or rawget(message.properties, "channel") ~= "chat") then
									local adoptCastid = nil
									if message.messageType == "roll" and message.properties ~= nil then
										adoptCastid = message.properties:try_get("castid")
									end
									local adoptiveParentPanel = adoptCastid and element.data.castPanels and element.data.castPanels[adoptCastid]
									if adoptiveParentPanel ~= nil and (not adoptiveParentPanel.valid) then
										adoptiveParentPanel = nil
									end

									if not g_errorPanels[key] then
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
											child.data.adoptCastid = adoptCastid
										else
											dmhub.CloudError(string.format("Error creating chat panel in ActionLog: messageType=%s error=%s", tostring(message.messageType), tostring(result)))
											g_errorPanels[key] = true
										end
									end

									if child ~= nil then
										messagePanels[key] = child
										child:FireEvent('refreshMessage', message)

										if adoptiveParentPanel ~= nil then
											AdoptInto(adoptiveParentPanel, child)
											adoptedPanels[key] = child
										else
											--cast adoption still wins; grouping only decides
											--where an UNadopted card is parented.
											local turnBody = TurnBodyFor(element, message)
											if turnBody ~= nil then
												turnBody:AddChild(child)
											else
												element:AddChild(child)
											end
											anyNew = true

											if child.data.castid then
												local castPanels = element.data.castPanels or {}
												castPanels[child.data.castid] = child
												element.data.castPanels = castPanels
											end
										end
									end
								end
							end
						end
					end

					if anyNew then
						RefreshRoundCounts(element)
					end

					--go to the bottom if we appended new messages, same as the full pass.
					if anyNew then
						element.vscrollPosition = 0
						element:ScheduleEvent("moveToBottom", 0.05)
					end

					if perfLog then
						print(string.format("DICEPERF-LUA:: ActionLog refreshChat INCREMENTAL total=%.1fms", (os.clock() - perfStart) * 1000))
					end
					return
				end

				local newMessagePanels = {}
				local children = {}
				local newMessage = false
				for i,message in ipairs(chat.messages) do
                    --This handler runs on EVERY refreshChat (a dice roll fires it several
                    --times: send, server echo patches, roll completion) over every message,
                    --so per-message bridge reads (message.key/.messageType/.properties are
                    --each a Lua->C# property call) dominated its cost. Messages that already
                    --have a panel take a fast path with a single bridge read (key); the
                    --type filtering and cast-adoption lookups only run when a panel is
                    --first created, with the roll's castid cached on the panel
                    --(data.adoptCastid) for the late-adoption check on later passes.
                    local key = message.key
                    local adopted = adoptedPanels[key]
                    if adopted then
                        if adopted.valid then
                            adopted:FireEvent('refreshMessage', message)
                        end
                    else
                        local child = messagePanels[key]
                        if child ~= nil then
                            --fast path: known message with an existing panel.
                            newMessagePanels[key] = child
                            local perfT1 = perfLog and os.clock() or 0
                            child:FireEvent('refreshMessage', message)
                            if perfLog then
                                perfRefreshMs = perfRefreshMs + (os.clock() - perfT1) * 1000
                                perfRefreshes = perfRefreshes + 1
                            end

                            --late adoption: a roll whose cast panel was created after the
                            --roll's own panel moves under it as soon as it exists.
                            local adoptiveParentPanel = child.data.adoptCastid and element.data.castPanels and element.data.castPanels[child.data.adoptCastid]
                            if adoptiveParentPanel ~= nil then
                                AdoptInto(adoptiveParentPanel, child)
                                adoptedPanels[key] = child
                            else
                                local turnBody = TurnBodyFor(element, message, children)
                                if turnBody ~= nil then
                                    turnBody:AddChild(child)
                                else
                                    children[#children+1] = child
                                end

                                if child.data.castid then
                                    local castPanels = element.data.castPanels or {}
                                    castPanels[child.data.castid] = child
                                    element.data.castPanels = castPanels
                                end
                            end
                        elseif message.messageType ~= "chat" and message.messageType ~= "data" and message.messageType ~= "object" and (message.messageType ~= "custom" or rawget(message.properties, "channel") ~= "chat") then
                            newMessage = true

                            local adoptCastid = nil
                            if message.messageType == "roll" and message.properties ~= nil then
                                adoptCastid = message.properties:try_get("castid")
                            end
                            local adoptiveParentPanel = adoptCastid and element.data.castPanels and element.data.castPanels[adoptCastid]

                            if not g_errorPanels[key] then

                                local ok, result

                                local perfT0 = perfLog and os.clock() or 0

                                --safely try to create the message panel. If it fails, we just skip it.
                                if devmode() then
                                    --call unsafely as a dev. We want to get errors.
                                    result = CreateSingleChatPanel(message, adoptiveParentPanel)
                                    ok = true
                                else
                                    ok, result = pcall(CreateSingleChatPanel, message, adoptiveParentPanel)
                                end

                                if perfLog then
                                    perfCreateMs = perfCreateMs + (os.clock() - perfT0) * 1000
                                    perfCreates = perfCreates + 1
                                end

                                if ok then
                                    child = result
                                    child.data.adoptCastid = adoptCastid
                                else

                                    dmhub.CloudError(string.format("Error creating chat panel in ActionLog: messageType=%s error=%s", tostring(message.messageType), tostring(result)))
                                    g_errorPanels[key] = true
                                end
                            end

                            if child ~= nil then
                                newMessagePanels[key] = child
                                local perfT1 = perfLog and os.clock() or 0
                                child:FireEvent('refreshMessage', message)
                                if perfLog then
                                    perfRefreshMs = perfRefreshMs + (os.clock() - perfT1) * 1000
                                    perfRefreshes = perfRefreshes + 1
                                end

                                if adoptiveParentPanel ~= nil then
                                    AdoptInto(adoptiveParentPanel, child)
                                    adoptedPanels[key] = child
                                else
                                    local turnBody = TurnBodyFor(element, message, children)
                                    if turnBody ~= nil then
                                        turnBody:AddChild(child)
                                    else
                                        children[#children+1] = child
                                    end

                                    if child.data.castid then
                                        local castPanels = element.data.castPanels or {}
                                        castPanels[child.data.castid] = child
                                        element.data.castPanels = castPanels
                                    end
                                end
                            end
                        end
                    end
				end

				messagePanels = newMessagePanels
				m_fullRefreshDone = true
				local perfT2 = perfLog and os.clock() or 0
				element.children = children
				RefreshRoundCounts(element)
				if perfLog then
					print(string.format("DICEPERF-LUA:: ActionLog refreshChat total=%.1fms msgs=%d creates=%d createMs=%.1f refreshes=%d refreshMs=%.1f childrenMs=%.1f",
						(os.clock() - perfStart) * 1000, #chat.messages, perfCreates, perfCreateMs, perfRefreshes, perfRefreshMs, (os.clock() - perfT2) * 1000))
				end

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

	ThemeEngine.OnThemeChanged(mod, function()
		if chatPanel ~= nil and chatPanel.valid then
			chatPanel.styles = ThemeEngine.MergeStyles(chatPanelStyles)
		end
	end)

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


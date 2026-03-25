local mod = dmhub.GetModLoading()

if devmode() then
LaunchablePanel.Register{
	name = "Trigger Debugger",
	icon = mod.images.goblinScriptDebuggerIcon,
	folder = "Development Tools",
	content = function()
        local dialogWidth = 800
        local dialogHeight = 600

        local m_selectedTokenIds = nil
        local m_selectedTokens = nil
        local m_locked = false

		local dialogPanel = gui.Panel{
			classes = {'document-dialog'},
			flow = "vertical",
            thinkTime = 0.2,
            think = function(element)
                if m_locked then
                    return
                end
                local tokens = dmhub.selectedTokens
                local tokenids = {}
                for _,tok in ipairs(tokens) do
                    tokenids[#tokenids+1] = tok.id
                end

                if dmhub.DeepEqual(m_selectedTokenIds, tokenids) then
                    return
                end

                m_selectedTokenIds = tokenids
                m_selectedTokens = tokens
                element:FireEventTree("tokens", tokens)
            end,
			selfStyle = {
				width = dialogWidth,
				height = dialogHeight,
			},

			styles = {
				{
					width = "100%",
					height = "100%",
					valign = 'center',
					halign = 'center',
					bgcolor = 'clear',
				},
				{
					selectors = {'document-dialog'},
					priority = 5,
					valign = 'top',
					halign = 'left',
				},
                {
                    selectors = {"label"},
                    width = "auto",
                    height = "auto",
                    color = "white",
                    fontSize = 14,
                    halign = "left",
                }
			},

            gui.Panel{
                valign = "top",
                halign = "left",
                width = 400,
                height = "auto",
                flow = "horizontal",
                vmargin = 10,
                hmargin = 10,
                tokens = function(element, tokens)
                    if #tokens == 0 then
                        element.children = {
                            gui.Label{
                                text = "No tokens selected",
                            },
                        }
                        return
                    else
                        local children = {}
                        for _,tok in ipairs(tokens) do
                            children[#children+1] = gui.CreateTokenImage(tok, {width=32, height=32, halign = "left"})
                        end
                        children[#children+1] = gui.Label{
                            text = "Showing triggers for selected tokens",
                        }

                        children[#children+1] = gui.Check{
                            text = "Lock",
                            value = m_locked,
                            change = function(element)
                                m_locked = element.value
                            end,
                        }

                        children[#children+1] = gui.Button{
                            text = "Clear",
                            width = 60,
                            height = 24,
                            halign = "right",
                            click = function()
                                element.parent.parent:FireEventTree("tokens", m_selectedTokens)
                            end,
                        }
                        element.children = children
                    end
                end,
            },

            gui.Panel{
                width = "96%",
                height = "100%-60",
                halign = "left",
                hmargin = 10,
                vmargin = 10,
                flow = "vertical",
                vscroll = true,
                styles = {
                    {
                        selectors = {"label"},
                        hmargin = 4,
                    },
					{
						selectors = {"evenRow"},
						bgcolor = "#111111",
					},
					{
						selectors = {"oddRow"},
						bgcolor = "#333333",
					},
					{
						selectors = {"evenRow","hover"},
						bgcolor = "#881111",
					},
					{
						selectors = {"oddRow","hover"},
						bgcolor = "#883333",
					},
                },

                create = function(element)
                    creature.debugTriggerHandler = function(selfCreature, eventName, info, debugLog)
                        print("CALL WITH LOG:", debugLog)
                        local token = dmhub.LookupToken(selfCreature)
                        if token == nil or m_selectedTokenIds == nil or (not table.contains(m_selectedTokenIds, token.id)) then
                            return
                        end

                        local handleLog = "Unhandled"
                        if debugLog and #debugLog > 0 then
                            handleLog = ""
                            for _,entry in ipairs(debugLog) do
                                handleLog = string.format("%s%s<b>%s</b>: (%s) %s", handleLog, cond(handleLog ~= "", "\n", ""), entry.name, cond(entry.success, "Handled", "Unhandled"), entry.reason or "")
                            end
                        end

                        local triggerName = "(Unknown)"
                        local triggerInfo = TriggeredAbility.GetTriggerById(eventName)
                        if triggerInfo ~= nil then
                            triggerName = triggerInfo.text
                        end
                        local subjectToken = token
                        if info ~= nil and info.subject then
                            subjectToken = dmhub.LookupToken(info.subject) or token
                        end
                        print("Triggered event:", info)
                        local row = gui.Panel{
                            classes = {cond(#element.children%2 == 0, "evenRow", "oddRow")},
                            flow = "horizontal",
                            width = "100%-8",
                            height = "auto",
                            vpad = 8,
                            halign = "left",
                            valign = "top",
                            vmargin = 0,
                            bgimage = true,

                            children = {

                                gui.Label{
                                    text = string.format("%s\n(%s)", triggerName, eventName),
                                    width = 140,
                                },

                                gui.Panel{
                                    flow = "vertical",
                                    width = 60,
                                    height = "auto",
                                    hmargin = 8,
                                    gui.CreateTokenImage(token, {width=24, height=24, halign="center"}),
                                    gui.Label{text = token.name, fontSize = 10, width="100%", textAlignment = "center"},
                                    gui.Label{text = "Self", fontSize = 10, width="100%", textAlignment = "center"},
                                },

                                gui.Panel{
                                    flow = "vertical",
                                    width = 60,
                                    height = "auto",
                                    hmargin = 8,
                                    gui.CreateTokenImage(subjectToken, {width=24, height=24, halign="center"}),
                                    gui.Label{text = subjectToken.name, fontSize = 10, width="100%", textAlignment = "center"},
                                    gui.Label{text = "Subject", fontSize = 10, width="100%", textAlignment = "center"},
                                },

                                gui.Label{
                                    width = 80,
                                    height = "auto",
                                    text = handleLog,
                                    fontSize = 10,
                                },

                                gui.Panel{
                                    flow = "vertical",
                                    width = 200,
                                    height = "auto",
                                    create = function(element)
                                        if info == nil then
                                            return
                                        end

                                        for k,v in sorted_pairs(info) do
                                            if k ~= "subject" then

                                                if type(v) == "function" then
                                                    v = v("self")
                                                end

                                                local valuePanel
                                                if type(v) == "table" and (v.typeName == "creature" or v.typeName == "monster" or v.typeName == "character") then
                                                    local token = dmhub.LookupToken(v)
                                                    if token then
                                                        valuePanel = gui.CreateTokenImage(token, {width=24, height=24})
                                                    end
                                                else
                                                    valuePanel = gui.Label{
                                                        text = tostring(v),
                                                        links = true,
                                                    }
                                                end
                                                local row = gui.Panel{
                                                    flow = "horizontal",
                                                    width = "100%",
                                                    height = 24,
                                                    valign = "center",
                                                    children = {
                                                        gui.Label{
                                                            text = k,
                                                            bold = true,
                                                        },
                                                        valuePanel,
                                                    }
                                                }
                                                element:AddChild(row)
                                            end
                                        end
                                    end,
                                }
                            },
                        }
                        element:AddChild(row)
                    end
                end,
                destroy = function(element)
                    creature.debugTriggerHandler = false
                end,
                tokens = function(element, tokens)

                    element.children = {}
                end,
            }
		}

		return dialogPanel
	end,
}
end

Commands.RegisterMacro{
    name = "subclass",
    summary = "show subclass info",
    doc = "Usage: /subclass\nPrints subclass information for selected tokens.",
    command = function()
        for _,tok in ipairs(dmhub.selectedTokens) do
            local subclassName = nil
            local subclasses = character:GetSubclasses()
            for _,subclass in ipairs(subclasses) do
                if subclassName == nil then
                    subclassName = subclass.name
                else
                    subclassName = string.format("%s/%s", subclassName, subclass.name)
                end
            end
        end
    end,
}
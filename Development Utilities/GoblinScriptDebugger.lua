local mod = dmhub.GetModLoading()

LaunchablePanel.Register{
	name = "Goblin Script Debugger",
	icon = mod.images.goblinScriptDebuggerIcon,
	folder = "Development Tools",
    devonly = true,
	content = function()

        local AddDebugEntries
        
        local m_orderedEntries = {}

		local dialogWidth = 1000
		local dialogHeight = 600

        local listPanel

        local filterInput = gui.Input{
            width = 140,
            height = 20,
            halign = "left",
            valign = "top",
            vmargin = 8,
            hmargin = 8,
            placeholderText = "Enter filter...",
            editlag = 0.4,
            edit = function(element)
                local prevOrderedEntries = m_orderedEntries
                m_orderedEntries = {}
				listPanel:FireEvent("clearDebugger")
                AddDebugEntries(prevOrderedEntries)
            end,
        }

		local entries = {}

		listPanel = gui.Panel{
			width = "95%",
			height = "100%-70",
			halign = "center",
			valign = "top",
            lmargin = 8,
			flow = "vertical",
			vscroll = true,
			hideObjectsOutOfScroll = true,
            debugEntries = function(element, entries)
                local counts = {}
                for i,entry in ipairs(entries) do
                    counts[entry.input] = (counts[entry.input] or 0) + 1
                end

                local keys = table.keys(counts)
                ---@cast keys -nil
                table.sort(keys, function(a,b)
                    return counts[a] > counts[b]
                end)
                print("DebugEntries::", #entries)
                for i=1,math.min(#keys,10) do
                    local key = keys[i]
                    print(string.format("  %d. %s -> %d", i, key, counts[key]))
                end
                AddDebugEntries(entries)
            end,
			clearDebugger = function(element)
				element.children = {}
				entries = {}
                m_orderedEntries = {}
			end,
			styles = {

				{
					selectors = {"label"},
					color = "white",
					fontSize = 16,
                    fontFace = "courier",
				},
				{
					selectors = {"debugEntry"},
					width = "100%",
					halign = "left",
					valign = "top",
					height = "auto",
					minHeight = 20,
					flow = "horizontal",
					vpad = 4,
				},
				{
					selectors = {"odd"},
					bgcolor = "#676767ff",
				},
				{
					selectors = {"even"},
					bgcolor = "#444444ff",
				},
				{
					selectors = {"debugEntry", "hover"},
					brightness = 1.5,

				},
				{
					selectors = {"debugTitle"},
					width = "90%",
					hmargin = 4,
					vmargin = 2,
					halign = "left",
					height = "auto",
					flow = "horizontal",
					textAlignment = "left",
					fontSize = 12,
					italics = true,
				},
				{
					selectors = {"debugHeader"},
					width = "100%",
					halign = "left",
					height = "auto",
					flow = "horizontal",
				},
				{
					selectors = {"lookupsPanel"},
					width = "90%",
					height = "auto",
					halign = "left",
                    lmargin = 16,
					flow = "vertical",
				},
				{
					selectors = {"singleLookupPanel"},
					width = "100%",
					height = "auto",
					flow = "horizontal",
                    bgimage = "panels/square.png",
                    bgcolor = "#222222",
				},
                {
                    selectors = {"singleLookupPanel", "odd"},
                    bgcolor = "#444444",
                },
				{
					selectors = {"lookupAttribute"},
					width = "50%",
					height = "auto",
					halign = "left",
				},
				{
					selectors = {"lookupValue"},
					width = "auto",
					height = "auto",
					halign = "right",
					hmargin = 4,
				},

				{
					selectors = {"formulaLabel"},
					width = "60%",
					height = "auto",
					valign = "center",
                    halign = "left",
                    lmargin = 8,
				},
				{
					selectors = {"formulaRepeat"},
					fontSize = 10,
					width = "10%",
					halign = "right",
					valign = "center",
					height = "auto",
				},
				{
					selectors = {"formulaResult"},
					width = "20%",
					height = "auto",
					halign = "center",
					valign = "center",
				},
				{
					selectors = {"error"},
					color = "red",
				},
			}
		}

		local panelOrd = 1

		local CreateDebugEntry = function(entry)
			panelOrd = panelOrd+1
			local entryKey = dmhub.GenerateGuid() --entry.input .. '::' .. (entry.reason or 'none')
			local existing = entries[entryKey]
			if existing ~= nil and existing.result == entry.result then
				existing.count = existing.count + 1
				if existing.repeatLabel ~= nil then
					existing.repeatLabel.text = string.format("(%d)", existing.count)
				end
				existing.panel.data.ord = panelOrd
				return nil
			end

			local newEntry = {
				input = entry.input,
				result = entry.result,
				count = 1,
			}

			---@type Panel
			local lookupsPanel = nil
			local lookupPanelsInit = false

			local panel = gui.Panel{
				classes = {"debugEntry"},
				bgimage = "panels/square.png",
				data = {
					ord = panelOrd,
				},
				click = function(element)
					if not lookupPanelsInit then
						lookupPanelsInit = true
						local childPanels = {}
						for k,v in pairs(entry.lookups) do
							local text
							if v == "(unknown)" then
								text = "(unknown)"
							elseif type(v) == "function" then
								text = string.format("(%s)", v("debuginfo") or "unknown")
							elseif type(v) == "table" and v.lookupSymbols ~= nil and rawget(v.lookupSymbols, "debuginfo") ~= nil then
								text = v.lookupSymbols.debuginfo(v)
							else
								text = dmhub.ToJson(v)
							end

							local lookupPanel = gui.Panel{
								classes = {"singleLookupPanel", cond(#childPanels%2 == 0, "even", "odd")},
								gui.Label{
									classes = {"lookupAttribute"},
                                    fontFace = "courier",
									text = k,
								},
								gui.Label{
									classes = {"lookupValue", cond(v == "(unknown)", "error")},
                                    fontFace = "courier",
									text = text,
									hover = function(element)
										gui.Tooltip(element.text)(element)
									end,
								},
							}

							childPanels[#childPanels+1] = lookupPanel
						end

						lookupsPanel.children = childPanels
					end

					lookupsPanel:SetClass("collapsed", not lookupsPanel:HasClass("collapsed"))
				end,

				expose = function(element)
					local repeatLabel = gui.Label{
						classes = {"formulaRepeat"},
						text = "",
						create = function(element)
							if newEntry.count > 1 then
								element.text = string.format("(%d)", newEntry.count)
							end
						end,
					}

					newEntry.repeatLabel = repeatLabel

					lookupsPanel = gui.Panel{
						classes = {"lookupsPanel", "collapsed"},
					}

					local errorPanel
					if entry.error ~= nil then
						errorPanel = gui.Label{
							text = entry.error,
							classes = {"error", "debugTitle"},
						}
					end
                    
                    local token = nil
                    local selfCreature = entry.lookupFunction("self")
                    if selfCreature ~= nil and type(selfCreature) == "table" then
                        token = dmhub.LookupToken(selfCreature)
                    end

                    local avatarPanel
                    if token ~= nil then
                        avatarPanel = gui.CreateTokenImage(token, {
                            width = 32,
                            height = 32,
                            valign = "center",
                            halign = "left",
                        })
                    else
                        avatarPanel = gui.Panel{
                            width = 32,
                            height = 32,
                        }
                    end
					element.children = {
                        avatarPanel,
                        gui.Panel{
                            flow = "vertical",
                            width = "100%-40",
                            height = "auto",
                            halign = "right",
                            gui.Panel{
                                classes = {"debugHeader"},
                                gui.Label{
                                    classes = {"formulaLabel"},
                                    fontFace = "courier",
                                    text = entry.input,
                                },
                                gui.Label{
                                    classes = {"formulaResult", cond(entry.result == nil, "error")},
                                    fontFace = "courier",
                                    text = entry.result or "(error)",
                                },
                                repeatLabel,
                            },

                            errorPanel,

                            gui.Label{
                                classes = {"debugTitle"},
                                text = entry.reason,
                            },
                            lookupsPanel,
                        },
					}
				end,
			}

			newEntry.key = entryKey
			newEntry.panel = panel
			return newEntry
		end

		AddDebugEntries = function(newEntries)

            for i,e in ipairs(newEntries) do
                m_orderedEntries[#m_orderedEntries+1] = e
            end

			if listPanel == nil or not listPanel.valid then
				return
			end

			local newChildren = listPanel.children

            local filterText = string.lower(trim(filterInput.text))
			for i = #newEntries, 1, -1 do
				local entry = newEntries[i]

                if filterText == "" or string.find(string.lower(entry.input), filterText) or string.find(string.lower(entry.reason or ""), filterText) then
                    local newEntry = CreateDebugEntry(entry)
                    if newEntry ~= nil then
                        entries[newEntry.key] = newEntry
                        newChildren[#newChildren+1] = newEntry.panel
                    end
                end
			end

			table.sort(newChildren, function(a,b)
				return a.data.ord > b.data.ord
			end)

			for j,child in ipairs(newChildren) do
				child:SetClass("odd", j%2 == 1)
				child:SetClass("even", j%2 == 0)
			end
			listPanel.children = newChildren
		end

		dmhub.RegisterGoblinScriptDebugger(AddDebugEntries)
        RegisterGoblinScriptDebugPanel(listPanel)

		local dialogPanel = gui.Panel{
			classes = {'document-dialog'},
			flow = "vertical",
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
			},
			children = {
                filterInput,
				listPanel,

				gui.Panel{
					flow = "horizontal",
					height = "auto",
					gui.GoblinScriptInput{
						width = 260,
						height = 20,
						fontSize = 18,
						placeholderText = "Evaluate...",
						halign = "left",
						value = "",
						multiline = false,
						change = function(element)
							if element.value == "" then
								gui.SetFocus(nil)
								dmhub.Schedule(0.2, function() gui.SetFocus(element) end)
								return
							end

							local tokens = dmhub.selectedTokens
							for _,tok in ipairs(tokens) do
								printf("LEVEL:: EVAL:: %s -> %s", element.value, json(tok.properties:LookupSymbol{}("level")))
								ExecuteGoblinScript(element.value, tok.properties:LookupSymbol{}, 0, "Evaluation")
							end

							element.value = ""
							gui.SetFocus(nil)
							dmhub.Schedule(0.2, function() gui.SetFocus(element.data.input) end)
						end,

						documentation = {
							domains = {},
							help = "Use this GoblinScript to test the currently selected creature.",
							output = "number",
							examples = {
								{
									script = "Hitpoints",
									text = "The hitpoints of the selected creature",
								}
							},
							subject = creature.helpSymbols,
							subjectDescription = "The creature you have selected.",
						},

					},

					gui.Button{
						text = "Clear",
						height = 24,
						width = 40,
						hmargin = 40,
						halign = "right",
						valign = "bottom",
						fontSize = 12,
						click = function(element)
							listPanel:FireEvent("clearDebugger")
						end,
					},
				},
			},
		}

		return dialogPanel
	end,
}

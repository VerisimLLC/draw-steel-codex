local mod = dmhub.GetModLoading()

local g_styles = {
    Styles.Panel,
    {
        selectors = {"framedPanel"},
        width = 1100,
        height = "auto",
        maxHeight = 900,
        minHeight = 600,
        halign = "center",
        valign = "center",
        bgcolor = "white",
        flow = "vertical",
    },
	{
		selectors = {'row'},
		bgimage = "panels/square.png",
		height = "auto",
		width = "100%",
	},
	{
		selectors = {'row', 'large'},
		height = "auto",
	},
	{
		selectors = {"row", "evenRow"},
		bgcolor = "#222222ff",
	},
	{
		selectors = {"row", "oddRow"},
		bgcolor = "#444444ff",
	},
	{
		selectors = {"row", "previewHighlight"},
		bgcolor = Styles.textColor,
		brightness = 0.4,
	},
	{
		selectors = {"row", "highlighted"},
		bgcolor = Styles.textColor,
	},
	{
		selectors = {"row", "flash"},
		brightness = 3,
		transitionTime = 0.3,
	},
    {
        selectors = {"cellLabel"},
        height = "auto",
		minHeight = 18,
		textWrap = true,
        fontSize = 14,
        textAlignment = "left",
        color = Styles.textColor,
		valign = "center",
    },
    {
        selectors = {"cellLabel", "parent:highlighted"},
		color = "black",
	},
    {
        selectors = {"cellLabel", "parent:previewHighlight"},
		color = "black",
	},
	{
		selectors = {"cellLabel", "secret"},
		color = "clear",
		transitionTime = 0.5,
	}
}

function GameHud.CreateRollOnTableDialog(self)

    local resultPanel

	local m_options = nil
    local m_guid = nil
    local m_cancelRoll = nil

	local m_shown = 0
	
	local m_table = nil

	local tablePanel

	local OnShow = function()
		--chat.events:Push()
		chat.events:Listen(resultPanel)

		m_shown = m_shown+1
	end

	local OnHide = function()
		if m_shown > 0 then
		    chat.PreviewChat('')
			chat.events:Unlisten(resultPanel)
			--chat.events:Pop()
			m_shown = m_shown-1
		end
	end

	local CancelRollDialog = function()
		if m_cancelRoll ~= nil then
			m_cancelRoll()
		end
		resultPanel:SetClass('hidden', true)
		OnHide()
	end

	local m_hasClose = false

	local proceedButton = gui.Button{
        data = {
            onclick = false
        },
		text = "Proceed",
		halign = "center",
		valign = "bottom",
		fontSize = 30,
		enter = function(element)
			element:FireEvent("click")
		end,
		click = function(element)
            if element.data.onclick then
                element.data.onclick()
            end
			if m_hasClose then
				resultPanel:SetClass('hidden', true)
				OnHide()
			else
				CancelRollDialog()
			end
		end,
	}

	local cancelButton = gui.CloseButton{
		floating = true,
		halign = "right",
		valign = "top",
		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_ROLL_DIALOG,
		click = function(element)
			if m_hasClose then
				resultPanel:SetClass('hidden', true)
				OnHide()
			else
				CancelRollDialog()
			end
		end,
	}
	
	local m_dicefaces = {}
	local m_rolls = nil

	local rollDiceButton

	rollDiceButton = gui.UserDice{
		floating = true,
		width = 64,
		height = 64,
		halign = "center",
		valign = "bottom",
		vmargin = 18,
		events = {
			click = function(element)
				rollDiceButton:SetClass("collapsed", true)

				m_hasClose = true

				local tokenid = nil
				if m_options.creature ~= nil then
					tokenid = dmhub.LookupTokenId(m_options.creature)
				end
                
                m_options.rollProperties.tableRef = m_options.tableRef
                print("ROLL PROPERTIES:", json(m_options.rollProperties))

				dmhub.Roll{
					guid = m_guid,
					description = string.format("Roll on %s", m_table.name),
					tokenid = tokenid,
					roll = m_table:CalculateRollInfo().roll,
					silent = false,
					dmonly = false,

					creature = m_options.creature,
					properties = m_options.rollProperties,

					begin = function(rollInfo)
						m_dicefaces = {}
						m_rolls = rollInfo.rolls
						for i,roll in ipairs(m_rolls) do
							local events = chat.DiceEvents(roll.guid)
							events:Listen(resultPanel)

                            if roll.partnerguid ~= nil then
                                local partnerEvents = chat.DiceEvents(roll.partnerguid)
                                partnerEvents:Listen(resultPanel)
                            end
						end
					end,
					complete = function(rollInfo)

                        local rowIndex = m_table:RowIndexFromDiceResult(rollInfo.total)

						proceedButton:SetClass("collapsed", false)
						gui.SetFocus(proceedButton)
                        proceedButton.data.onclick = function()
                            if m_options.completeRoll ~= nil then
                                m_options.completeRoll(rollInfo)
                            end

                            tablePanel:FireEvent("completeRoll", rollInfo)

                            for i,roll in ipairs(rollInfo.rolls) do
                                local events = chat.DiceEvents(roll.guid)
                                events:Unlisten(resultPanel)
                            end
                        end
					end,
				}

				chat.PreviewChat{''}
			end,
		}
	}



    tablePanel = gui.Table{
        width = "100%",
        height = "auto",
		flow = "vertical",

		data = {
			previewIndex = nil,
		},

		previewRoll = function(element, index)
			local rows = element.children
			if element.data.previewIndex ~= nil and element.data.previewIndex <= #rows then
				rows[element.data.previewIndex]:SetClass("previewHighlight", false)
			end

			if index ~= nil and index >= 1 and index <= #rows then
				rows[index]:SetClass("previewHighlight", true)
				element.data.previewIndex = index
			end

		end,

		completeRoll = function(element, rollInfo)

			local rows = element.children
			if element.data.previewIndex ~= nil and element.data.previewIndex <= #rows then
				rows[element.data.previewIndex]:SetClass("previewHighlight", false)
			end

			local total = m_table:RowIndexFromDiceResult(rollInfo.total)
			if total >= 1 and total <= #rows then
				rows[total]:SetClass("highlighted", true)
				rows[total]:PulseClass("flash")

				local t = m_options.tableRef:GetTable()
				if t.visibility == "reveal" then
					t.rows[total].revealed = true
					m_options.tableRef:TryUpload(t)

					rows[total]:FireEventTree("showSecret")
				end
			end
		end,

        show = function(element, options)
            local rows = {}

			element.data.previewIndex = nil

            local t = options.tableRef:GetTable()

            local rollInfo = t:CalculateRollInfo()

			rollDiceButton:SetClass("collapsed", false)
			proceedButton:SetClass("collapsed", true)
            proceedButton.data.onclick = false

			chat.PreviewChat(string.format("/roll %s", rollInfo.roll))

            for i,row in ipairs(t.rows) do
                local text = row.value:ToString()

                if m_options.creature then
                    text = StringInterpolateGoblinScript(text, m_options.creature)
                end

                local rollText = tostring(rollInfo.rollRanges[i].min)
                if rollInfo.rollRanges[i].min ~= rollInfo.rollRanges[i].max then
                    rollText = rollText .. "-" .. tostring(rollInfo.rollRanges[i].max)
                end

				local hideRow = t.visibility == "hidden" or (t.visibility == "reveal" and row.revealed == false)
				local secretText
				
				if hideRow then
					secretText = gui.Label{
						classes = {"cellLabel"},
						width = "auto",
						height = "auto",
						text = "???",
						showSecret = function(element)
							element:SetClass("secret", true)
						end,
					}
				end

                local rowPanel = gui.TableRow{
                    children = {
                        gui.Label{
                            classes = "cellLabel",
							hpad = 4,
                            width = 100,
                            text = rollText,
                        },
                        gui.MarkdownLabel{
                            classes = {"cellLabel", cond(hideRow, "secret")},
                            width = 920,
							height = "auto",
                            text = text,
							secretText,

							showSecret = function(element)
								element:SetClass("secret", false)
							end,
                        },
                    },
                }

                rows[#rows+1] = rowPanel
            end

            element.children = rows
        end,
    }

	local titleLabel = gui.Label{
		color = Styles.textColor,
		halign = "center",
		valign = "top",
		tmargin = 12,
		fontSize = 26,
		width = "auto",
		height = "auto",
		show = function(element, options)
			element.text = string.format("Roll on %s", options.tableRef:GetTable().name)
		end,
	}

    local selectTableRef = function(tableRef)
        m_table = tableRef:GetTable()
        m_options.tableRef = tableRef
    end

    local choicePanelPress = function(element)
        local children = element.parent.children
        for _,child in ipairs(children) do
            child:SetClass("selected", child == element)
        end

        if element.data.tableRef then
            selectTableRef(element.data.tableRef)
        end

        resultPanel.data.RefreshDialog()
    end
    local choicePanel = gui.Panel{
        styles = Styles.AdvantageBar,
        classes = {"advantage-bar"},
        valign = "top",
        halign = "center",
        tmargin = 30,
        initTable = function(element,t, tableRef)
            if t.rollType ~= "namedChoice" then
                element:SetClassTree("hidden", true)
                m_table = t
                m_options.tableRef = tableRef
                resultPanel.data.RefreshDialog()
                return
            end

            element:SetClassTree("hidden", false)

            local children = {}

            for i,row in ipairs(m_table.rows) do
                local str = row.value.items[1]:ToString()
                local ref = nil
                for _,item in ipairs(row.value.items) do
                    ref = item:TableRef()
                    if ref ~= nil then
                        break
                    end
                end

                children[#children+1] = gui.Label{
                    classes = {"advantage-element"},
                    data = {
                        tableRef = ref,
                    },
                    text = str,
                    press = choicePanelPress,
                }
            end

            element.children = children

            choicePanelPress(children[1]) -- select the first one by default
        end,
        children = {
        }
    }

	local tableContainer = gui.Panel{
		tmargin = 16,
		width = "95%",
		height = "auto",
		halign = "center",
		valign = "center",
		maxHeight = 740,
		vscroll = true,
		tablePanel,
	}
    

    resultPanel = gui.Panel{
        classes = {"framedPanel", "toplevel", "hidden"},
        styles = g_styles,

        data = {
            ShowDialog = function(options)
                print("ROLL PROPERTIES: OPTIONS =", json(options))
				m_options = DeepCopy(options)
                m_guid = dmhub.GenerateGuid()
                m_cancelRoll = options.cancelRoll
				m_table = options.tableRef:GetTable()

                choicePanel:FireEvent("initTable", m_table, options.tableRef)

                return m_guid
            end,

            RefreshDialog = function()
				rollDiceButton.hasFocus = true

                resultPanel:SetClass('hidden', false)

				OnShow()
                resultPanel:FireEventTree("show", m_options)
            end,
        },

		gui.Panel{
			flow = "vertical",
			valign = "top",
			width = "100%",
			height = 40,
			titleLabel,
			gui.Divider{},
		},

        choicePanel,

        tableContainer,

		gui.Panel{
			rollDiceButton,
			proceedButton,
			valign = "bottom",
			width = "100%",
			height = 80,
		},

		cancelButton,


        submit = function(element)
            rollDiceButton:FireEvent("click")
        end,

		diceface = function(element, guid, num)
			m_dicefaces[guid] = num
			local total = 0
			for i,roll in ipairs(m_rolls) do
				if m_dicefaces[roll.guid] == nil then
					return
				end

				total = total + m_dicefaces[roll.guid]

                if roll.partnerguid ~= nil then
                    if m_dicefaces[roll.partnerguid] == nil then
                        return
                    end

                    total = total + m_dicefaces[roll.partnerguid]
                end
			end

			tablePanel:FireEvent("previewRoll", m_table:RowIndexFromDiceResult(total))
		end,
    }

    return resultPanel
end

RegisterGameType("RollOnTableProperties", "RollProperties")

function RollOnTableProperties:GetOutcome(rollInfo)
    local total = rollInfo.total
    local tableRef = self.tableRef
    if tableRef == nil then
        return nil
    end

    local t = tableRef:GetTable()
    if t == nil then
        return nil
    end

    local rowIndex = t:RowIndexFromDiceResult(total)
    if rowIndex == nil or rowIndex < 1 or rowIndex > #t.rows then
        return nil
    end

    local str = nil
    for _,item in ipairs(t.rows[rowIndex].value.items) do
        str = item:ToString()
        if str ~= nil then
            break
        end
    end
    if str == nil then
        return nil
    end

    return {
        outcome = str,
        color = "white",
    }
end


function RollOnTableProperties:CustomPanel(message)

    local m_finished = false

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgimage = true,
        bgcolor = "#00000088",

        refreshInfo = function(element, catInfo, diceStyle, complete, message)
            if complete then
                m_finished = true
                local t = self.tableRef:GetTable()
                if t == nil then
                    return nil
                end

                local rowIndex = t:RowIndexFromDiceResult(message.total)
                if rowIndex == nil or rowIndex < 1 or rowIndex > #t.rows then
                    return nil
                end

                local row = t.rows[rowIndex]
                for _,item in ipairs(row.value.items) do
                    local s = item:ToString()
                    if s ~= nil then
                        if message.tokenid ~= nil then
                            local token = dmhub.GetCharacterById(message.tokenid)
                            if token ~= nil then
                                s = StringInterpolateGoblinScript(s, token.properties)
                            end
                        end
                        element:FireEventTree("setText", s)
                        break
                    end
                end
            end
        end,


        children = {
            gui.MarkdownLabel{
                text = "",
                width = "100%-8",
                height = "auto",
                halign = "center",
                setText = function(element, text)
                    element.value = text
                end,

            },
        },
    }
end
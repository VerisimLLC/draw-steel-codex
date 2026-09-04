local mod = dmhub.GetModLoading()


setting{
    id = "claude_api_key",
    default = "",
    description = "Claude API Key",
    storage = "preference",
}

setting{
    id = "claude_model",
    default = "claude-sonnet-4-20250514",
    description = "Claude Model",
    storage = "preference",
}

setting{
    id = "claude_agent",
    default = "",
    description = "Claude Agent",
    storage = "preference",
}

setting{
    id = "claude_history",
    default = {},
    description = "Claude Chat History",
    storage = "preference",
}

-- Tool registry
-- Each tool has: { name, description, input_schema, execute(input) -> string }
local g_tools = {}

local function RegisterTool(args)
    assert(args.name, "Tool must have a name")
    assert(args.description, "Tool must have a description")
    assert(args.input_schema, "Tool must have an input_schema")
    assert(args.execute, "Tool must have an execute function")

    g_tools[args.name] = {
        name = args.name,
        description = args.description,
        input_schema = args.input_schema,
        execute = args.execute,
    }
end

local function GetToolDefinitions()
    local defs = {}
    for _, tool in pairs(g_tools) do
        defs[#defs+1] = {
            name = tool.name,
            description = tool.description,
            input_schema = tool.input_schema,
        }
    end
    return defs
end

local function ExecuteTool(name, input)
    local tool = g_tools[name]
    if tool == nil then
        return "Unknown tool: " .. name
    end
    local ok, result = pcall(tool.execute, input)
    if not ok then
        return "Tool error: " .. tostring(result)
    end
    return result
end

-- Agent registry
-- Each agent has: { id, name, description, system, temperature, max_tokens }
local g_agents = {}

local function RegisterAgent(args)
    assert(args.id, "Agent must have an id")
    assert(args.name, "Agent must have a name")
    assert(args.system, "Agent must have a system prompt")

    g_agents[args.id] = {
        id = args.id,
        name = args.name,
        description = args.description or "",
        system = args.system,
        temperature = args.temperature or 1,
        max_tokens = args.max_tokens or 4096,
    }
end

local function GetAgent(id)
    return g_agents[id]
end

local function GetAgents()
    return g_agents
end

local function GetDefaultAgentId()
    for id, _ in pairs(g_agents) do
        return id
    end
    return nil
end

-- Claude API bridge
claude = {

    RegisterAgent = RegisterAgent,
    GetAgent = GetAgent,
    GetAgents = GetAgents,
    GetDefaultAgentId = GetDefaultAgentId,

    RegisterTool = RegisterTool,
    GetToolDefinitions = GetToolDefinitions,
    ExecuteTool = ExecuteTool,

    -- Send a chat message to Claude with automatic tool-use handling.
    -- args: {
    --   messages = {{role = "user"|"assistant", content = string}, ...},
    --   agent = string? (agent id -- uses agent's system/temperature/max_tokens as defaults),
    --   system = string? (optional system prompt, overrides agent),
    --   temperature = number? (0-1, overrides agent),
    --   max_tokens = number? (overrides agent),
    --   tools = boolean? (if true, include registered tools; default true),
    --   success = function(text: string),
    --   error = function(message: string),
    --   toolCall = function(name: string, input: table)? (optional callback when a tool is invoked),
    -- }
    Chat = function(args)
        local apiKey = dmhub.GetSettingValue("claude_api_key")
        if apiKey == "" then
            if args.error then
                args.error("No Claude API key configured. Set your key in the Claude panel settings.")
            end
            return
        end

        local agent = nil
        if args.agent then
            agent = GetAgent(args.agent)
        end

        local model = dmhub.GetSettingValue("claude_model")
        local errorfn = args.error or function() end

        local systemPrompt = args.system or (agent and agent.system) or nil
        local temperature = args.temperature or (agent and agent.temperature) or nil
        local maxTokens = args.max_tokens or (agent and agent.max_tokens) or 4096

        local includeTools = args.tools ~= false
        local toolDefs = nil
        if includeTools then
            toolDefs = GetToolDefinitions()
            if #toolDefs == 0 then
                toolDefs = nil
            end
        end

        local messages = args.messages
        local maxToolRounds = 10

        -- Debug log: records each request/response round
        local debugLog = {
            model = model,
            agent = args.agent,
            system = systemPrompt and "(system prompt present)" or nil,
            rounds = {},
        }

        local function LogRound(round, sentMessages, response, toolResults)
            local entry = {
                round = round,
                messages_sent = #sentMessages,
                response_stop_reason = response.stop_reason,
                response_content = response.content,
            }
            if toolResults and #toolResults > 0 then
                entry.tool_results = toolResults
            end
            debugLog.rounds[#debugLog.rounds+1] = entry
        end

        local function BuildDebugText()
            local parts = {}
            parts[#parts+1] = string.format("=== Claude Debug Log ===")
            parts[#parts+1] = string.format("Model: %s", model)
            if args.agent then
                parts[#parts+1] = string.format("Agent: %s", args.agent)
            end
            if systemPrompt then
                parts[#parts+1] = string.format("\n--- System Prompt ---\n%s", systemPrompt)
            end

            parts[#parts+1] = "\n--- Conversation ---"
            for _, msg in ipairs(messages) do
                if type(msg.content) == "string" then
                    parts[#parts+1] = string.format("\n[%s]\n%s", msg.role, msg.content)
                elseif type(msg.content) == "table" then
                    for _, block in ipairs(msg.content) do
                        if block.type == "text" then
                            parts[#parts+1] = string.format("\n[%s] (text)\n%s", msg.role, block.text)
                        elseif block.type == "tool_use" then
                            parts[#parts+1] = string.format("\n[%s] (tool_use: %s)\nInput: %s", msg.role, block.name, json(block.input))
                        elseif block.type == "tool_result" then
                            local content = block.content
                            if type(content) == "string" and #content > 2000 then
                                content = string.sub(content, 1, 2000) .. "\n... (truncated)"
                            end
                            parts[#parts+1] = string.format("\n[tool_result] (id: %s)\n%s", block.tool_use_id or "?", tostring(content))
                        end
                    end
                end
            end

            parts[#parts+1] = string.format("\n--- Rounds: %d ---", #debugLog.rounds)
            return table.concat(parts, "\n")
        end

        local function DoRequest(round)
            if round > maxToolRounds then
                errorfn("Too many tool-use rounds (possible loop)")
                return
            end

            local body = {
                model = model,
                max_tokens = maxTokens,
                messages = messages,
            }

            if systemPrompt then
                body.system = systemPrompt
            end

            if temperature then
                body.temperature = temperature
            end

            if toolDefs then
                body.tools = toolDefs
            end

            net.Post{
                url = "https://api.anthropic.com/v1/messages",
                headers = {
                    ["x-api-key"] = apiKey,
                    ["anthropic-version"] = "2023-06-01",
                    ["content-type"] = "application/json",
                },
                data = body,
                timeout = 120,

                success = function(response)
                    if response.error then
                        errorfn(response.error.message or json(response.error))
                        return
                    end

                    if response.content == nil or response.content[1] == nil then
                        errorfn("Invalid response from Claude API")
                        return
                    end

                    -- Check if any tool_use blocks are present
                    local hasToolUse = false
                    local toolResults = {}
                    local textParts = {}

                    for _, block in ipairs(response.content) do
                        if block.type == "tool_use" then
                            hasToolUse = true

                            if args.toolCall then
                                args.toolCall(block.name, block.input)
                            end

                            local result = ExecuteTool(block.name, block.input)
                            toolResults[#toolResults+1] = {
                                type = "tool_result",
                                tool_use_id = block.id,
                                content = result,
                            }
                        elseif block.type == "text" then
                            textParts[#textParts+1] = block.text
                        end
                    end

                    LogRound(round, messages, response, toolResults)

                    if hasToolUse then
                        -- Append assistant response and tool results, then continue
                        messages[#messages+1] = {
                            role = "assistant",
                            content = response.content,
                        }
                        messages[#messages+1] = {
                            role = "user",
                            content = toolResults,
                        }
                        DoRequest(round + 1)
                    else
                        -- Final text response
                        local text = table.concat(textParts, "\n")
                        if args.success then
                            args.success(text, BuildDebugText())
                        end
                    end
                end,

                error = function(err)
                    errorfn(tostring(err))
                end,
            }
        end

        DoRequest(1)
    end,
}

-- Claude chat panel

local CreateClaudePanel

DockablePanel.Register{
    name = "Claude",
    icon = "panels/hud/chat.png",
    minHeight = 200,
    vscroll = false,
    content = function()
        return CreateClaudePanel()
    end,
}

-- Settings panel is created inline in CreateClaudePanel and toggled via collapsed class.

CreateClaudePanel = function()
    local history = {}
    local historyCursor = nil
    local pending = 0

    local chatPanel
    local inputPanel
    local previewPanel
    local resultPanel
    local agentDropdown
    local chatArea
    local settingsArea

    local m_context = {}

    local function GetCurrentAgentId()
        local id = dmhub.GetSettingValue("claude_agent")
        if id ~= "" and GetAgent(id) ~= nil then
            return id
        end
        return GetDefaultAgentId()
    end

    chatPanel = gui.Panel{
        id = "claude-chat-panel",
        vscroll = true,
        hideObjectsOutOfScroll = true,
        hpad = 6,
        height = "100% available",

        styles = {
            {
                bgcolor = "black",
                halign = "center",
                valign = "bottom",
                width = "100%",
                flow = "vertical",
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
                bgcolor = "#110022aa",
            },
            {
                selectors = {"message", "error"},
                color = "#ff5555",
                x = -4,
            },
        },

        message = function(element, text, messageType, debugText)
            local debugIcon = nil
            if debugText then
                debugIcon = gui.Panel{
                    width = 14,
                    height = 14,
                    halign = "right",
                    valign = "top",
                    bgimage = "panels/hud/gear.png",
                    bgcolor = "#666666",
                    styles = {
                        { opacity = 0.4 },
                        { selectors = {"hover"}, opacity = 1.0 },
                    },
                    click = function(el)
                        dmhub.CopyToClipboard(debugText)
                        el.bgcolor = "#66ff66"
                        el:ScheduleEvent("resetColor", 0.5)
                    end,
                    resetColor = function(el)
                        el.bgcolor = "#666666"
                    end,
                    hover = function(el)
                        gui.Tooltip("Click to copy debug log to clipboard")(el)
                    end,
                }
            end

            local contentPanel
            if messageType == "assistant" then
                contentPanel = gui.DocumentDisplay{
                    text = text,
                    width = "100%",
                    height = "auto",
                    noninteractive = true,
                    fontSize = 16,
                }
            else
                contentPanel = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 16,
                    color = "#cccccc",
                    textAlignment = "left",
                    text = text,
                }
            end

            local msgPanel = gui.Panel{
                classes = {"message", messageType},
                flow = "vertical",
                debugIcon,
                contentPanel,
            }

            element:AddChild(msgPanel)
            element.vscrollPosition = 0
        end,
    }

    previewPanel = gui.Label{
        width = "100%",
        height = 18,
        text = "",
        fontSize = 14,
        italics = true,

        data = {
            ellipsis = "",
        },

        thinkTime = 0.4,

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
                element.text = string.format("Claude is responding%s", element.data.ellipsis)
            end
        end,
    }

    local ShowMessage = function(text, record, role, debugText)
        if record then
            local h = dmhub.GetSettingValue("claude_history")
            h[#h+1] = {
                role = role or "user",
                content = text,
            }
            -- Keep history bounded
            while #h > 40 do
                table.remove(h, 1)
            end
            dmhub.SetSettingValue("claude_history", h)
        end
        chatPanel:FireEvent("message", text, role or "user", debugText)
    end

    inputPanel = gui.Input{
        placeholderText = "Message Claude...",
        width = "100%-40",
        minHeight = 24,
        maxHeight = 300,
        height = "auto",
        lineType = "MultiLineSubmit",
        characterLimit = 8192,
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
                if #history == 0 or historyCursor == nil then
                    return
                end

                historyCursor = historyCursor + 1
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
                local text = element.text

                if text == "/clear" then
                    chatPanel.children = {}
                    dmhub.SetSettingValue("claude_history", {})
                    m_context = {}
                    element.text = ""
                    return
                elseif text == "/settings" then
                    resultPanel:FireEvent("showSettings")
                    element.text = ""
                    return
                end

                historyCursor = -1

                if element.text ~= "" and history[#history] ~= element.text then
                    history[#history+1] = element.text
                end

                element.text = ""
                element.hasFocus = true

                ShowMessage(text, true)

                pending = pending + 1

                m_context[#m_context+1] = {
                    role = "user",
                    content = text,
                }

                claude.Chat{
                    messages = m_context,
                    agent = GetCurrentAgentId(),

                    success = function(response, debugText)
                        pending = pending - 1

                        m_context[#m_context+1] = {
                            role = "assistant",
                            content = response,
                        }

                        ShowMessage(response, true, "assistant", debugText)
                    end,

                    error = function(err)
                        m_context[#m_context] = nil
                        pending = pending - 1
                        chatPanel:FireEvent("message", err, "error")
                    end,
                }
            end,
        },
    }

    local settingsButton = gui.Panel{
        width = 24,
        height = 24,
        halign = "right",
        valign = "center",
        hmargin = 4,
        bgimage = "panels/hud/gear.png",
        bgcolor = Styles.textColor,

        styles = {
            {
                opacity = 0.6,
            },
            {
                selectors = {"hover"},
                opacity = 1.0,
            },
        },

        click = function(element)
            resultPanel:FireEvent("showSettings")
        end,
    }

    agentDropdown = gui.Dropdown{
        height = 18,
        fontSize = 14,
        hmargin = 8,
        width = 160,
        valign = "center",

        create = function(element)
            local agents = GetAgents()
            local options = {}
            for id, agent in pairs(agents) do
                options[#options+1] = {
                    id = id,
                    text = agent.name,
                }
            end

            if #options == 0 then
                options[#options+1] = {
                    id = "",
                    text = "(No agents)",
                }
            end

            element.options = options
            element.idChosen = GetCurrentAgentId() or ""
        end,

        change = function(element)
            dmhub.SetSettingValue("claude_agent", element.idChosen)
        end,
    }

    local bottomPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        inputPanel,
        settingsButton,
    }

    local infoBar = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hmargin = 8,
        vmargin = 2,

        gui.Label{
            text = "Agent:",
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "center",
            color = "#888888",
        },

        agentDropdown,

        gui.Label{
            width = "auto",
            height = "auto",
            fontSize = 12,
            color = "#888888",
            halign = "right",
            valign = "center",
            text = dmhub.GetSettingValue("claude_model"),
        },
    }

    chatArea = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        chatPanel,
        previewPanel,
        infoBar,
        bottomPanel,
    }

    settingsArea = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        flow = "vertical",
        vpad = 8,
        hpad = 12,

        styles = {
            {
                selectors = {"settingLabel"},
                width = "100%",
                height = "auto",
                fontSize = 14,
                bold = true,
                color = Styles.textColor,
                vmargin = 4,
            },
            {
                selectors = {"settingInput"},
                width = "100%",
                height = 24,
                fontSize = 14,
                vmargin = 2,
            },
        },

        gui.Label{
            classes = {"settingLabel"},
            text = "Claude API Settings",
            fontSize = 18,
            vmargin = 8,
        },

        gui.Label{
            classes = {"settingLabel"},
            text = "API Key:",
        },

        gui.Input{
            classes = {"settingInput"},
            placeholderText = "sk-ant-...",
            create = function(element)
                element.text = dmhub.GetSettingValue("claude_api_key")
            end,
            change = function(element)
                dmhub.SetSettingValue("claude_api_key", element.text)
            end,
        },

        gui.Label{
            classes = {"settingLabel"},
            text = "Model:",
        },

        gui.Input{
            classes = {"settingInput"},
            placeholderText = "claude-sonnet-4-20250514",
            create = function(element)
                element.text = dmhub.GetSettingValue("claude_model")
            end,
            change = function(element)
                dmhub.SetSettingValue("claude_model", element.text)
            end,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 12,

            gui.Button{
                text = "Done",
                width = 80,
                height = 28,
                halign = "center",
                click = function(element)
                    settingsArea:SetClass("collapsed", true)
                    chatArea:SetClass("collapsed", false)
                    agentDropdown:FireEvent("create")
                end,
            },
        },
    }

    resultPanel = gui.Panel{
        selfStyle = {
            width = "100%",
            height = "100%",
            flow = "vertical",
        },

        children = {
            chatArea,
            settingsArea,
        },

        showSettings = function(element)
            chatArea:SetClass("collapsed", true)
            settingsArea:SetClass("collapsed", false)
        end,

        refreshContent = function(element)
            chatPanel.children = {}
            m_context = {}

            local h = dmhub.GetSettingValue("claude_history")
            for _, entry in ipairs(h) do
                m_context[#m_context+1] = {
                    role = entry.role,
                    content = entry.content,
                }
                chatPanel:FireEvent("message", entry.content, entry.role)
            end

            if #chatPanel.children == 0 then
                local agentId = GetCurrentAgentId()
                local agent = agentId and GetAgent(agentId)
                local welcome
                if agent then
                    welcome = string.format("Agent '%s' ready. %s\n\nType a message to start chatting, /clear to reset, or /settings to configure.", agent.name, agent.description)
                else
                    welcome = "Hello! Configure your API key with /settings, then start chatting."
                end
                chatPanel:FireEvent("message", welcome, "assistant")
            end
        end,
    }

    resultPanel:FireEvent("refreshContent")

    return resultPanel
end

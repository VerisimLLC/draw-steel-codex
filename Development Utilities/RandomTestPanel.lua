local mod = dmhub.GetModLoading()

-- Steam companion-popout handoff test framework.
--
-- Exposes buttons that exercise dmhub.RunSteamHandoffDiagnostic for each
-- variant (happy path + five anti-patterns). Results are dumped to a scrolling
-- pane below; the latest nonce is also fed to a Consume button so the browser
-- side of the handoff can be verified without opening a browser.
--
-- C# side: LoginController.RunSteamHandoffDiagnostic + RunSteamHandoffConsume.

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

local g_variants = {
    { id = 0, name = "Happy Path",            expectFail = false, hint = "Should succeed and return a nonce." },
    { id = 1, name = "Wrong Identity Casing", expectFail = true,  hint = "identity = 'drawsteelcompanion'. Steam should 101." },
    { id = 2, name = "Dashed Hex",            expectFail = true,  hint = "Ticket sent as 'AB-CD-EF...'. Steam should 101." },
    { id = 3, name = "Base64 Ticket",         expectFail = true,  hint = "Ticket sent as base64. Steam should 101." },
    { id = 4, name = "Old API No Identity",   expectFail = true,  hint = "GetAuthSessionTicket (old, unbound). Steam should 101." },
    { id = 5, name = "Wrong AppId",           expectFail = true,  hint = "Flip to the OTHER allowlisted appid. Steam should 101." },
}

-- Render a single key/value row.
local function MakeRow(key, value, valueColor)
    local valueStr
    if value == nil then
        valueStr = "(nil)"
    elseif type(value) == "boolean" then
        valueStr = value and "true" or "false"
    elseif type(value) == "string" then
        valueStr = value == "" and "(empty)" or value
    else
        valueStr = tostring(value)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 1,
        gui.Label{
            text = key,
            width = 220,
            height = "auto",
            fontSize = 12,
            color = "#bbbbbb",
            valign = "top",
        },
        gui.Label{
            text = valueStr,
            width = "100%-228",
            height = "auto",
            fontSize = 12,
            color = valueColor or "#ffffff",
            wrap = true,
            valign = "top",
        },
    }
end

-- Pretty-print a result table from dmhub.RunSteamHandoffDiagnostic.
-- Renders an ordered set of known keys first, then anything else alphabetically.
local function BuildResultRows(result)
    local rows = {}

    -- Keys in the order we want to display them.
    local ordered = {
        "variant", "ok", "errorStep", "error",
        "steamInitialized", "steamLoggedOn", "steamId", "personaName", "appId",
        "expectedIdentity", "identityRequested", "identityRequestedLength",
        "methodUsed", "ticketHandle", "callbackFired", "callbackResult",
        "callbackElapsedSeconds", "ticketSize",
        "ticketEncoding", "ticketEncodedLength", "ticketEncodedFirst16",
        "appIdSent", "mintUrl",
        "httpStatus", "httpElapsedSeconds", "responseBody",
        "nonce", "consumeUrl",
        -- Consume-only keys.
        "uid", "steamid", "tokenLength", "tokenPrefix",
        "preflightWarning",
    }
    local seen = {}

    local function ColorFor(key, value)
        if key == "ok" then
            return value and "#88ff88" or "#ff8888"
        end
        if key == "error" or key == "errorStep" then
            return "#ffbbbb"
        end
        if key == "callbackResult" then
            if value == "k_EResultOK" then return "#88ff88" else return "#ffaa66" end
        end
        if key == "httpStatus" then
            local n = tonumber(value) or 0
            if n >= 200 and n < 300 then return "#88ff88" end
            if n >= 400 then return "#ffaa66" end
        end
        return nil
    end

    for _, key in ipairs(ordered) do
        if result[key] ~= nil then
            rows[#rows+1] = MakeRow(key, result[key], ColorFor(key, result[key]))
            seen[key] = true
        end
    end

    -- Append any remaining keys we didn't pre-order.
    local extras = {}
    for k, _ in pairs(result) do
        if not seen[k] then extras[#extras+1] = k end
    end
    table.sort(extras)
    for _, key in ipairs(extras) do
        rows[#rows+1] = MakeRow(key, result[key])
    end

    return rows
end

local function ResultToText(result)
    local lines = {}
    local ordered = {
        "variant", "ok", "errorStep", "error",
        "steamInitialized", "steamLoggedOn", "steamId", "personaName", "appId",
        "expectedIdentity", "identityRequested", "identityRequestedLength",
        "methodUsed", "ticketHandle", "callbackFired", "callbackResult",
        "callbackElapsedSeconds", "ticketSize",
        "ticketEncoding", "ticketEncodedLength", "ticketEncodedFirst16",
        "appIdSent", "mintUrl",
        "httpStatus", "httpElapsedSeconds", "responseBody",
        "nonce", "consumeUrl",
        "uid", "steamid", "tokenLength", "tokenPrefix",
        "preflightWarning",
    }
    local seen = {}
    for _, key in ipairs(ordered) do
        if result[key] ~= nil then
            lines[#lines+1] = string.format("%s: %s", key, tostring(result[key]))
            seen[key] = true
        end
    end
    for k, v in pairs(result) do
        if not seen[k] then
            lines[#lines+1] = string.format("%s: %s", k, tostring(v))
        end
    end
    return table.concat(lines, "\n")
end

DockablePanel.Register{
    name = "Steam Handoff Test",
    icon = mod.images.chatIcon,
    minHeight = 400,
    vscroll = true,
    devonly = true,
    folder = "Development Tools",
    content = function()
        track("panel_open", {
            panel = "Steam Handoff Test",
            dailyLimit = 30,
        })

        local m_lastNonce = nil
        local m_running = false

        local resultsPanel
        local statusLabel
        local nonceLabel
        local consumeButton

        local function ClearResults()
            resultsPanel.children = {}
        end

        local function ShowBusy(message)
            m_running = true
            statusLabel.text = message
            statusLabel.selfStyle.color = "#ffd966"
            ClearResults()
        end

        local function ShowResult(label, result)
            m_running = false

            local ok = result.ok == true
            statusLabel.text = string.format("%s: %s", label, ok and "OK" or "FAILED")
            statusLabel.selfStyle.color = ok and "#88ff88" or "#ff8888"

            -- Stash nonce for the consume test.
            if result.nonce and result.nonce ~= "" then
                m_lastNonce = result.nonce
                nonceLabel.text = "Last nonce: " .. result.nonce
                consumeButton:SetClass("disabled", false)
            end

            local rows = BuildResultRows(result)
            -- Add a copy-to-clipboard button at the top of the result block.
            table.insert(rows, 1, gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                gui.Button{
                    text = "Copy result to clipboard",
                    width = 200,
                    height = 22,
                    fontSize = 12,
                    halign = "left",
                    click = function()
                        dmhub.CopyToClipboard(ResultToText(result))
                        gui.Tooltip("Copied")(consumeButton)
                    end,
                },
            })
            resultsPanel.children = rows
        end

        local function RunVariant(variant)
            if m_running then return end
            ShowBusy(string.format("Running [%s]...", variant.name))
            dmhub.RunSteamHandoffDiagnostic(variant.id, function(result)
                ShowResult(variant.name, result)
            end)
        end

        local function RunConsume()
            if m_running then return end
            if not m_lastNonce or m_lastNonce == "" then return end
            ShowBusy(string.format("Consuming nonce %s...", m_lastNonce))
            dmhub.RunSteamHandoffConsume(m_lastNonce, function(result)
                m_lastNonce = nil
                consumeButton:SetClass("disabled", true)
                nonceLabel.text = "Last nonce: (consumed)"
                ShowResult("Consume", result)
            end)
        end

        local variantButtons = {}
        for _, v in ipairs(g_variants) do
            local variant = v
            variantButtons[#variantButtons+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 2,
                gui.Button{
                    text = variant.name,
                    width = 200,
                    height = 24,
                    fontSize = 13,
                    halign = "left",
                    click = function() RunVariant(variant) end,
                },
                gui.Label{
                    text = variant.hint,
                    width = "100%-208",
                    height = "auto",
                    fontSize = 11,
                    color = variant.expectFail and "#999999" or "#aaccff",
                    wrap = true,
                    valign = "center",
                    lmargin = 8,
                },
            }
        end

        statusLabel = gui.Label{
            text = "Ready.",
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = "#cccccc",
            vmargin = 4,
        }

        nonceLabel = gui.Label{
            text = "Last nonce: (none)",
            width = "100%",
            height = "auto",
            fontSize = 11,
            color = "#888888",
            vmargin = 2,
        }

        consumeButton = gui.Button{
            text = "Test Consume (uses last nonce)",
            width = 260,
            height = 24,
            fontSize = 12,
            halign = "left",
            classes = {"disabled"},
            click = RunConsume,
        }

        resultsPanel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            borderBox = true,
            pad = 6,
            bgimage = "panels/square.png",
            bgcolor = "#181818",
            vmargin = 8,
        }

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 6,
            vpad = 6,
            borderBox = true,

            gui.Label{
                text = "Steam Handoff Diagnostic",
                fontSize = 16,
                bold = true,
                color = "#ffcc44",
                width = "100%",
                height = "auto",
                halign = "left",
                vmargin = 2,
            },

            -- Status + results FIRST so they are visible immediately on click,
            -- regardless of how the panel is sized or scrolled.
            statusLabel,
            resultsPanel,

            gui.Panel{
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#444444",
                vmargin = 6,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 2,
                table.unpack(variantButtons),
            },

            gui.Panel{
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#444444",
                vmargin = 6,
            },

            consumeButton,
            nonceLabel,

            gui.Label{
                text = "Tip: Happy Path should succeed; the other variants should fail with errorcode 101 from Steam.",
                fontSize = 11,
                color = "#888888",
                width = "100%",
                height = "auto",
                wrap = true,
                vmargin = 4,
            },
        }
    end,
}

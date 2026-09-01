local mod = dmhub.GetModLoading()

--- The negotiation windows. The frame they wear - heading band, working area
--- and footer band - comes from DialogShell; what stays here is which pane the
--- run's status calls for, and when a player's window has outlived the
--- negotiation it was following.
NEGDialog = RegisterGameType("NEGDialog")

--- How many negotiation windows this client has open. A board pushed to a
--- player who already opened it from the Game menu must not toggle it shut.
local m_openWindows = 0

--- @return boolean
function NEGDialog.IsOpen()
    return m_openWindows > 0
end

--- The line both windows carry in their shell header: which negotiation, who
--- it is with, and whether it is still going. The body no longer repeats any
--- of it.
--- @return string
local function RunHeaderInfo()
    local live = NEGRun.Active()
    if live == nil then
        return ""
    end

    local parts = {}

    local name = live:Name()
    if name ~= "" then
        parts[#parts + 1] = name
    end

    local npc = live:NpcName()
    if npc ~= "" then
        parts[#parts + 1] = npc
    end

    parts[#parts + 1] = cond(live:try_get("status") == NEGConstants.statusEnded,
        "Complete", "In play")

    return table.concat(parts, "  |  ")
end

--- One cell of a footer. Cells are equal thirds unless a state asks for its
--- own split, so contents land left, centre and right whichever a state fills.
--- @param slot nil|Panel
--- @param pct number cell width as a whole percentage
--- @return Panel
local function FooterCell(slot, pct)
    return gui.Panel{
        width = string.format("%d%%", pct),
        height = "100%",
        flow = "horizontal",
        valign = "center",
        children = slot ~= nil and { slot } or {},
    }
end

--- A state's row of controls. The band and the rule above it belong to the
--- DialogShell; this is only what sits inside them.
--- @param cells table[] {slot} in order
--- @return Panel
local function BuildFooter(cells)
    local row = {}
    cells = cells or {}

    for i, cell in ipairs(cells) do
        row[#row + 1] = FooterCell(cell.slot, NEGConstants.footerCells[i] or 33)
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        children = row,
    }
end

--- The Director's window: library on the left, whichever pane the run's status
--- calls for on the right, and a footer that changes with it.
--- @return Panel
function NEGDialog.Create()
    local listPanel
    local editorPanel = NEGEditorPanel.Create()
    local setupPanel = NEGRunPanel.CreateSetup()
    local runPanel = NEGRunPanel.Create{ director = true }

    --Import takes the pane rather than opening a dialog of its own, so it is a
    --sibling of the editor rather than a layer over it.
    local m_importing = false
    local rightPane
    local importPanel = NEGImportPanel.Create(function(defid)
        m_importing = false
        rightPane:FireEvent("rebuild")
        if defid ~= nil then
            listPanel:FireEvent("select", defid)
        end
    end)

    --What Start acts on. The editor keeps its own copy privately, so the
    --selection is tracked here rather than read back out of it.
    local m_selectedDefid = nil
    local resultPanel

    listPanel = NEGLibraryPanel.Create(function(defid)
        m_selectedDefid = defid
        if editorPanel.valid then
            editorPanel:FireEvent("setDefinition", defid)
        end
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel:FireEventTree("negotiationChanged")
        end
    end, function()
        m_importing = true
        importPanel:FireEvent("reset")
        rightPane:FireEvent("rebuild")
    end)

    rightPane = gui.Panel{
        width = "100% available",
        height = "100%",
        flow = "vertical",
        valign = "top",

        negotiationChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()
            local status = live ~= nil and live:try_get("status") or nil
            importPanel:SetClass("collapsed", not m_importing)
            editorPanel:SetClass("collapsed", live ~= nil or m_importing)
            setupPanel.body:SetClass("collapsed", status ~= NEGConstants.statusSetup)
            runPanel.body:SetClass("collapsed",
                status ~= NEGConstants.statusRunning
                and status ~= NEGConstants.statusEnded)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        editorPanel,
        importPanel,
        setupPanel.body,
        runPanel.body,
    }

    local dlg

    --The launchable host owns this window's lifetime, so closing is a request
    --to the parent rather than a DestroySelf.
    local function Close()
        if dlg ~= nil then
            dlg:Close()
        end
    end

    --Nothing to start until a negotiation is selected and no other one holds
    --the table.
    local startButton = gui.Button{
        classes = { "sizeL", "disabled" },
        text = "Start Negotiation",
        halign = "right",
        valign = "center",
        interactable = false,
        hover = gui.Tooltip("Put this negotiation in front of the table"),
        click = function(element)
            if not element.interactable or m_selectedDefid == nil then
                return
            end
            NEGRun.BeginSetup(m_selectedDefid)
        end,
        negotiationChanged = function(element)
            local enabled = m_selectedDefid ~= nil and NEGRun.Active() == nil
            element:SetClass("disabled", not enabled)
            element.interactable = enabled
        end,
    }

    local idleFooter = BuildFooter{
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "Close",
                halign = "left",
                valign = "center",
                click = Close,
            },
        },
        {},
        { slot = startButton },
    }

    --One button, two jobs: it says what it will do, not what is true.
    local showButton = gui.Button{
        classes = { "sizeL" },
        text = "Show to Players",
        halign = "left",
        valign = "center",
        click = function(element)
            if NEGRun.IsPresented() then
                NEGRun.HideFromPlayers()
            else
                NEGRun.PresentToPlayers(element)
            end
        end,
        negotiationChanged = function(element)
            element.text = cond(NEGRun.IsPresented(), "Hide from Players", "Show to Players")
        end,
    }

    local setupFooter = BuildFooter(setupPanel.footer)

    local runFooter = BuildFooter{
        { slot = showButton },
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "Reset",
                halign = "center",
                valign = "center",
                requireConfirm = true,
                hover = gui.Tooltip("Throw the whole negotiation away and go back to the library"),
                click = function()
                    NEGRun.Clear()
                end,
            },
        },
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "End Negotiation",
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Close the negotiation. The final offer stays on screen."),
                click = function()
                    NEGRun.End()
                end,
            },
        },
    }

    local endFooter = BuildFooter{
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "Close",
                halign = "left",
                valign = "center",
                click = Close,
            },
        },
        {},
        {
            slot = gui.Button{
                classes = { "sizeL" },
                text = "Back to Library",
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Take this negotiation off the table"),
                click = function()
                    NEGRun.Clear()
                end,
            },
        },
    }

    --Every state's row is built once and collapsed, the way the right pane's
    --bodies are, so a swap never rebuilds a live control. That is also why the
    --shell gets one full-width cell rather than having its own refilled.
    local footerPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        halign = "left",
        valign = "center",

        negotiationChanged = function()
            local live = NEGRun.Active()
            local status = live ~= nil and live:try_get("status") or nil
            idleFooter:SetClass("collapsed", live ~= nil)
            setupFooter:SetClass("collapsed", status ~= NEGConstants.statusSetup)
            runFooter:SetClass("collapsed", status ~= NEGConstants.statusRunning)
            endFooter:SetClass("collapsed", status ~= NEGConstants.statusEnded)
        end,

        create = function(element)
            element:FireEvent("negotiationChanged")
        end,

        idleFooter,
        setupFooter,
        runFooter,
        endFooter,
    }

    dlg = DialogShell.CreateNew{
        classes = { "launchablePanel" },
        title = NEGConstants.panelTitle,
        subtitle = RunHeaderInfo(),
        width = NEGConstants.windowWidth,
        height = NEGConstants.windowHeight,
        footerCells = { 100 },
        close = "host",

        monitor = NEGRun.DocPath(),
        refresh = function(shell)
            shell:Root():FireEventTree("negotiationChanged")
            shell:SetSubtitle(RunHeaderInfo())
        end,

        onCreate = function(shell)
            m_openWindows = m_openWindows + 1
            shell:Root():FireEventTree("negotiationChanged")
        end,

        onDestroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,
    }

    resultPanel = dlg:Root()

    dlg:SetWorkingContent(gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        valign = "top",

        --No vscroll here: the library panel's bordered list is the scroller,
        --so the bar belongs on the list's edge, not this column's.
        gui.Panel{
            width = NEGConstants.listWidth,
            height = "100%",
            flow = "vertical",
            valign = "top",
            rmargin = NEGConstants.listRightMargin,

            listPanel,
        },

        rightPane,
    })

    dlg:SetFooterContent("left", footerPanel)

    return resultPanel
end

--- What the table sees: whichever scales the Director has opened, and a line
--- of text when there is nothing to watch. No footer.
--- @return Panel
function NEGDialog.CreatePlayerView()
    local board = NEGRunPanel.Create{ director = false }

    --Seeded from the state this window was built on, so one opened between
    --negotiations stays put instead of closing on its first ping.
    local sawLive = NEGRun.Active() ~= nil

    --- A window that was showing a negotiation and no longer has one takes
    --- itself off the table.
    --- @param shell DialogShell
    local function Apply(shell)
        local live = NEGRun.Active()

        shell:SetSubtitle(RunHeaderInfo())

        if sawLive and live == nil then
            sawLive = false
            shell:Close()
            return
        end

        sawLive = live ~= nil
    end

    local dlg = DialogShell.CreateNew{
        classes = { "launchablePanel" },
        title = NEGConstants.playerPanelTitle,
        subtitle = RunHeaderInfo(),
        width = NEGConstants.playerWindowWidth,
        height = NEGConstants.playerWindowHeight,
        footerCells = false,
        close = "host",

        monitor = NEGRun.DocPath(),
        refresh = function(shell)
            shell:Root():FireEventTree("negotiationChanged")
            Apply(shell)
        end,

        onCreate = function(shell)
            m_openWindows = m_openWindows + 1
            Apply(shell)
        end,

        onDestroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,
    }

    local resultPanel = dlg:Root()

    dlg:SetWorkingContent{
        board.body,
    }

    return resultPanel
end

--- The Director presenting to the table, arriving on a player's client. The
--- board itself is the Game menu's window rather than one built here, so a
--- board pushed to a player is the same window in the same host they would
--- have opened themselves.
---
--- Returning nothing leaves the presentation machinery with nothing to tear
--- down, which is what lets the window decide for itself when to go.
--- @return Panel|nil
function NEGDialog.RaiseForPlayer()
    if dmhub.isDM or NEGRun.Active() == nil then
        return nil
    end

    --LaunchPanelByName toggles, so a player who already has it open would have
    --it shut in their face. Asking first is per-client.
    if not NEGDialog.IsOpen() then
        LaunchablePanel.LaunchPanelByName(NEGConstants.panelName)
    end

    return nil
end

GameHud.RegisterPresentableDialog{
    id = NEGConstants.dialogId,
    keeplocal = false,
    create = NEGDialog.RaiseForPlayer,
}

--LaunchablePanel.Register is keyed by name, so this takes over the Negotiation
--entry rather than sitting beside it. The old registration in Draw Steel V is
--switched off as well, so the outcome does not depend on load order.
LaunchablePanel.Register{
    name = NEGConstants.panelName,
    menu = "game",
    icon = NEGConstants.icon,
    halign = "center",
    valign = "center",
    content = function()
        if dmhub.isDM then
            return NEGDialog.Create()
        end
        return NEGDialog.CreatePlayerView()
    end,
}

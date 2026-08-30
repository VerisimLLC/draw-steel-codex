local mod = dmhub.GetModLoading()

--- The Respite wizard. The window frame itself - heading band, working area
--- and footer band - comes from DialogShell; what stays here is the wizard:
--- which step the session's phase calls for, and when the window has outlived
--- the Respite it was following.
RSPShell = RegisterGameType("RSPShell")

--- How many Respite windows this client has open. The Director's offer asks
--- before it raises one, so a player who already opened it from the Game menu
--- is left alone rather than having it toggled shut under them.
local m_openWindows = 0

--- @return boolean
function RSPShell.IsOpen()
    return m_openWindows > 0
end

--- @param args table Shell args; reads orientation, instructions and working
--- @return Panel
local function BuildBody(args)
    local side = args.orientation == RSPConstants.orientSide

    -- 100%, not "100% available": a step's body is a sibling of the other
    -- steps' bodies inside the working area, not of a header and a footer.
    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = side and "horizontal" or "vertical",
        halign = "left",
        valign = "top",

        RSPWidgets.Instructions{
            text = args.instructions,
            orientation = args.orientation,
        },

        gui.Panel{
            width = side and RSPConstants.workingSideWidth or "100%",
            height = side and "100%" or RSPConstants.workingTopHeight,
            flow = "vertical",
            halign = "left",
            valign = "top",

            args.working,
        },
    }
end

--- One third of the footer. The slots are equal-width cells in a horizontal
--- flow so their contents land left, centre and right regardless of which of
--- the three a step actually fills.
--- @param slot nil|Panel
--- @param pct number cell width as a whole percentage
--- @return Panel
local function FooterCell(slot, pct)
    return gui.Panel{
        width = string.format("%d%%", pct),
        height = "100%",
        flow = "horizontal",
        valign = "center",
        children = slot ~= nil and {slot} or {},
    }
end

--- A step's row of controls. The band and the rule above it belong to the
--- DialogShell; this is only what sits inside them.
--- @param args table Shell args; reads the three footer slots, and
---   footerCellWidths when a step's footer does not divide evenly
--- @return Panel
local function BuildFooter(args)
    -- Thirds suit a footer of one control per side. A step carrying something
    -- wider in the middle says so rather than having its content spill into
    -- the cells either side of it.
    local widths = args.footerCellWidths or {}

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",

        FooterCell(args.footerLeft, widths[1] or RSPConstants.footerCells[1]),
        FooterCell(args.footerCenter, widths[2] or RSPConstants.footerCells[2]),
        FooterCell(args.footerRight, widths[3] or RSPConstants.footerCells[3]),
    }
end

--- @return string the phase the session is in, or Setup when there is none
local function CurrentPhase()
    local session = RSPSession.Active()
    return session ~= nil and session.phase or RSPConstants.phaseSetup
end

--- Build the wizard. Every step is built once and lives in the tree together;
--- the phase decides which one is not collapsed. Swapping children instead
--- would destroy the event subscriptions the steps refresh through - which is
--- also why the footer is one full-width cell holding every step's row rather
--- than the shell's own cells being refilled on each change of phase.
---
--- Every Respite window is hosted by the launchable panel, whichever way it
--- was opened, so the host paints the frame and owns the close control and the
--- shell stays transparent underneath it.
--- @param args {steps: table[]} each step carries a phase plus its own step args
--- @return Panel
function RSPShell.Create(args)
    local phase = CurrentPhase()

    local steps = {}
    local bodies = {}
    local footers = {}

    for _, stepArgs in ipairs(args.steps) do
        local collapsed = stepArgs.phase ~= phase

        local body = BuildBody(stepArgs)
        body:SetClass("collapsed", collapsed)
        bodies[#bodies + 1] = body

        local footer = nil
        if not stepArgs.footerless then
            footer = BuildFooter(stepArgs)
            footer:SetClass("collapsed", collapsed)
            footers[#footers + 1] = footer
        end

        steps[#steps + 1] = {
            phase = stepArgs.phase,
            body = body,
            footer = footer,
        }
    end

    -- Whether this window has shown a Respite that was actually running, which
    -- is what earns it a dismissal when that Respite ends. A window opened from
    -- the Game menu between Respites is legitimately idle and must not be
    -- closed out from under whoever opened it. Seeded from the phase this
    -- window was built on, so one opened mid-Respite is dismissed by its end
    -- like any other.
    local sawRespite = phase == RSPConstants.phaseOffered
        or phase == RSPConstants.phaseActive

    local dlg
    dlg = DialogShell.CreateNew{
        classes = {"rspShell", "launchablePanel"},
        title = RSPConstants.panelName,
        width = RSPConstants.windowWidth,
        height = RSPConstants.windowHeight,
        footerCells = {100},
        close = "host",
        styles = RSPWidgets.CustomStyles(),

        monitor = RSPSession.DocPath(),
        refresh = function(shell)
            shell:Root():FireEventTree("respiteChanged")

            local session = RSPSession.Active()
            local current = session ~= nil and session.phase
                or RSPConstants.phaseSetup

            if current == RSPConstants.phaseOffered
                or current == RSPConstants.phaseActive then
                sawRespite = true
            end

            -- The Respite this window was following is over, so the window goes
            -- with it rather than sitting there on a step about nothing. The
            -- host owns the lifetime, so this asks rather than destroys.
            if session == nil and sawRespite then
                sawRespite = false
                shell:Close()
                return
            end

            for _, step in ipairs(steps) do
                local on = step.phase == current
                step.body:SetClass("collapsed", not on)
                if step.footer ~= nil then
                    step.footer:SetClass("collapsed", not on)
                end
                if on then
                    shell:ShowFooter(step.footer ~= nil)
                end
            end
        end,

        onCreate = function()
            m_openWindows = m_openWindows + 1
        end,

        onDestroy = function()
            m_openWindows = math.max(0, m_openWindows - 1)
        end,
    }

    dlg:SetWorkingContent(bodies)

    dlg:SetFooterContent("left", gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        halign = "left",
        valign = "center",
        children = footers,
    })

    -- The step this window opened on decides whether the band starts showing.
    for _, step in ipairs(steps) do
        if step.phase == phase then
            dlg:ShowFooter(step.footer ~= nil)
        end
    end

    return dlg:Root()
end

local mod = dmhub.GetModLoading()

--- The window frame every Respite step wears: the heading on the left of the
--- header and information about the Respite on the right, a hairline under
--- that, and an MCDM divider between the working area and the footer.
RSPShell = {}

--- Height left for the working area once the header, its hairline and, on a
--- step that has one, the footer band have taken theirs.
--- @param footerless nil|boolean true when the step ends at the working area
--- @return string
local function WorkingHeight(footerless)
    local reserved = RSPConstants.headerHeight
        + RSPConstants.headerDividerHeight
        + RSPConstants.headerDividerTopMargin
        + RSPConstants.headerDividerBottomMargin

    if not footerless then
        reserved = reserved + RSPConstants.dividerBand + RSPConstants.footerHeight
    end

    return string.format("100%%-%d", reserved)
end

--- @param args table Shell args; reads headerInfo
--- @return Panel
local function BuildHeader(args)
    -- Auto-height so the hairline below sits against the heading rather than
    -- against the bottom of a fixed band with slack in it.
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        gui.Label{
            classes = {"sizeXxl", "bold"},
            width = RSPConstants.headerTitleWidth,
            height = "auto",
            halign = "left",
            valign = "bottom",
            bmargin = RSPConstants.headerTitleBottomMargin,
            text = RSPConstants.panelName,
        },

        gui.Label{
            classes = {"sizeS", "noBold", "fgMuted"},
            width = RSPConstants.headerInfoWidth,
            height = "auto",
            halign = "right",
            rmargin = RSPConstants.headerInfoRightMargin,
            valign = "bottom",
            textAlignment = "right",
            markdown = true,
            textWrap = true,
            text = args.headerInfo ~= nil and args.headerInfo() or "",
            respiteChanged = function(element)
                element.text = args.headerInfo ~= nil and args.headerInfo() or ""
            end,
        },
    }
end

--- @param args table Shell args; reads orientation, instructions and working
--- @return Panel
local function BuildBody(args)
    local side = args.orientation == RSPConstants.orientSide

    return gui.Panel{
        width = "100%",
        height = WorkingHeight(args.footerless),
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
--- @return Panel
local function FooterCell(slot)
    return gui.Panel{
        width = RSPConstants.footerCellWidth,
        height = "100%",
        flow = "horizontal",
        valign = "center",
        children = slot ~= nil and {slot} or {},
    }
end

--- @param args table Shell args; reads the three footer slots
--- @return Panel
local function BuildFooter(args)
    return gui.Panel{
        width = "100%",
        height = RSPConstants.footerHeight,
        flow = "horizontal",
        halign = "left",
        valign = "bottom",

        FooterCell(args.footerLeft),
        FooterCell(args.footerCenter),
        FooterCell(args.footerRight),
    }
end

--- One step of a Respite wizard, filling the window.
--- @param args table the step's args
--- @param collapsed boolean whether this step starts out of view
--- @return Panel
local function BuildStep(args, collapsed)
    return gui.Panel{
        classes = {collapsed and "collapsed" or nil},
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        BuildHeader(args),
        gui.MCDMDivider{
            width = "100%",
            layout = "line",
            height = RSPConstants.headerDividerHeight,
            tmargin = RSPConstants.headerDividerTopMargin,
            bmargin = RSPConstants.headerDividerBottomMargin,
        },
        BuildBody(args),

        -- A step with nothing to say at the bottom keeps neither the rule nor
        -- the band, and its working area takes the room back.
        not args.footerless and gui.MCDMDivider{
            width = "100%",
            layout = "line",
            vmargin = RSPConstants.footerDividerMargin,
        } or nil,
        not args.footerless and BuildFooter(args) or nil,
    }
end

--- @return string the phase the session is in, or Setup when there is none
local function CurrentPhase()
    local session = RSPSession.Active()
    return session ~= nil and session.phase or RSPConstants.phaseSetup
end

--- Build the wizard. Every step is built once and lives in the tree together;
--- the phase decides which one is not collapsed. Swapping children instead
--- would destroy the event subscriptions the steps refresh through.
---
--- Set framed when the window stands on its own. A launchable host paints the
--- frame around its content, so hosted copies stay transparent to avoid
--- double-framing; a copy pushed onto the hud has no host and must draw it.
--- @param args {steps: table[], framed: nil|boolean} each step carries a phase plus its own step args
--- @return Panel
function RSPShell.Create(args)
    local phase = CurrentPhase()

    local steps = {}
    local children = {}
    for _, stepArgs in ipairs(args.steps) do
        local panel = BuildStep(stepArgs, stepArgs.phase ~= phase)
        steps[#steps + 1] = {phase = stepArgs.phase, panel = panel}
        children[#children + 1] = panel
    end

    return gui.Panel{
        classes = {"rspShell", args.framed and "dialog" or "launchablePanel"},
        styles = ThemeEngine.MergeStyles(RSPWidgets.CustomStyles()),
        width = RSPConstants.windowWidth,
        height = RSPConstants.windowHeight,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = 16,

        data = {
            themeSub = nil,
        },

        monitorGame = RSPSession.DocPath(),
        refreshGame = function(element)
            element:FireEventTree("respiteChanged")
        end,

        respiteChanged = function(element)
            local current = CurrentPhase()
            for _, step in ipairs(steps) do
                step.panel:SetClass("collapsed", step.phase ~= current)
            end
        end,

        create = function(element)
            element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(RSPWidgets.CustomStyles())
                end
            end)
        end,

        destroy = function(element)
            if element.data.themeSub ~= nil then
                element.data.themeSub:Deregister()
                element.data.themeSub = nil
            end
        end,

        children = children,
    }
end

local mod = dmhub.GetModLoading()

--- The frame a dialog wears: a heading band with the rule painted under the
--- type, a working area that belongs entirely to the caller, and a footer of
--- evenly divided cells under a second rule.
--- @class DialogShell
--- Reach the panels through Root, WorkingArea, Header and Footer rather than
--- these fields: a shell built without a footer never assigns one, and reading
--- an unset field on a game type raises where try_get returns nil.
--- @field root Panel
--- @field workingArea Panel
--- @field header Panel
--- @field footer Panel absent when built with footerCells = false
--- @field footerRow Panel absent likewise; rebuilt by SetFooterCells
--- @field titleLabel Panel
--- @field subtitleLabel Panel
--- @field footerCells Panel[] one per entry in footerCells
--- @field footerContent Panel[][] what each cell holds, in order
--- @field footerButtons table[] {button, cell, enabled} per tracked button
--- @field autoWidthButtons boolean
--- @field closeMode string|function
--- @field onClose function|boolean
--- @field customStyles table[]|boolean
--- @field themeSub table|boolean
DialogShell = RegisterGameType("DialogShell")

local PAD = 12

-- Header: fixed band, divider floats under the heading so type prints over it.
-- The title takes the whole row and the subtitle floats over it right-aligned,
-- so neither is capped by a share of the width. Both are laid out: a
-- content-sized label beside an available-sized one does not resolve at all,
-- and renders the band empty.
local HEADER_HEIGHT = 40
local HEADER_DIVIDER_HEIGHT = 12        -- weight of the rule, not spacing
local HEADER_DIVIDER_TOP_MARGIN = 22    -- where the rule crosses the band
local HEADER_TITLE_BOTTOM_MARGIN = -6   -- closes the line box's slack under the baseline
local TITLE_WIDTH = "100%"
local SUBTITLE_WIDTH = "100%"
local CLOSE_BUTTON_INSET = 4   -- how far inside the dialog edge the glyph lands


-- Footer: fixed band, divider on top, controls in cells
local FOOTER_HEIGHT = 60
local FOOTER_DIVIDER_MARGIN = 12
local DEFAULT_FOOTER_CELLS = {33, 34, 33}

local BUTTON_CLASS = "sizeL"

--- Footer buttons size to their text rather than taking the theme's width.
DialogShell.autoWidthButtons = false

--- "modal", "destroy", "host", or a function taking the shell.
DialogShell.closeMode = "modal"

DialogShell.onClose = false
DialogShell.customStyles = false
DialogShell.themeSub = false

--- @param dlg DialogShell
--- @param args table reads title, subtitle and closeButton
--- @param pad number the dialog's own padding, which the close glyph tucks into
--- @return Panel
local function BuildHeader(dlg, args, pad)
    dlg.titleLabel = gui.Label{
        classes = {"sizeXxl", "bold"},
        width = TITLE_WIDTH,
        height = "auto",
        halign = "left",
        valign = "bottom",
        bmargin = HEADER_TITLE_BOTTOM_MARGIN,
        text = args.title or "",
    }

    -- Floating, so it takes no width from the title and needs no vertical
    -- offset: the row's height is the title's either way, and bottom-aligning
    -- inside it puts the subtitle on the line it already sat on.
    dlg.subtitleLabel = gui.Label{
        classes = {"sizeS", "noBold", "fgMuted"},
        floating = true,
        width = SUBTITLE_WIDTH,
        height = "auto",
        halign = "right",
        valign = "bottom",
        textAlignment = "right",
        markdown = true,
        textWrap = true,
        text = args.subtitle or "",
    }

    return gui.Panel{
        width = "100%",
        height = HEADER_HEIGHT,
        flow = "vertical",
        halign = "left",
        valign = "top",

        -- Drawn first and floating so the heading paints over the rule rather
        -- than sitting above it.
        gui.Panel{
            floating = true,
            width = "100%",
            height = HEADER_DIVIDER_HEIGHT,
            flow = "vertical",
            halign = "left",
            valign = "top",
            tmargin = HEADER_DIVIDER_TOP_MARGIN,

            gui.MCDMDivider{
                width = "100%",
                layout = "line",
                height = HEADER_DIVIDER_HEIGHT,
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            dlg.subtitleLabel,
            dlg.titleLabel,
        },

        args.closeButton == true and gui.Button{
            classes = {"closeButton", "sizeXs"},
            floating = true,
            halign = "right",
            valign = "top",
            hmargin = -(pad - CLOSE_BUTTON_INSET),
            tmargin = -(pad - CLOSE_BUTTON_INSET),
            click = function()
                dlg:Close()
            end,
        } or nil,
    }
end

--- Builds the cells and takes them as the shell's own, discarding whatever
--- set was there before.
--- @param dlg DialogShell
--- @param cells number[] cell widths as whole percentages
--- @return Panel[] row the cells in order
local function BuildFooterCells(dlg, cells)
    local row = {}

    dlg.footerCells = {}
    dlg.footerContent = {}

    for i, pct in ipairs(cells) do
        local cell = gui.Panel{
            width = string.format("%d%%", pct),
            height = "100%",
            flow = "horizontal",
            valign = "center",
            children = {},
        }

        dlg.footerCells[i] = cell
        dlg.footerContent[i] = {}
        row[i] = cell
    end

    return row
end

--- @param dlg DialogShell
--- @param cells number[] cell widths as whole percentages
--- @return Panel
local function BuildFooter(dlg, cells)
    local row = BuildFooterCells(dlg, cells)

    dlg.footerRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        children = row,
    }

    return gui.Panel{
        width = "100%",
        height = FOOTER_HEIGHT,
        flow = "vertical",
        halign = "left",
        valign = "bottom",

        gui.MCDMDivider{
            width = "100%",
            layout = "line",
            vmargin = FOOTER_DIVIDER_MARGIN,
        },

        dlg.footerRow,
    }
end

--- Which cell a slot names. "center" takes the middle cell, rounding up when
--- the count is even.
--- @param dlg DialogShell
--- @param slot string|number "left", "center", "right", or a 1-based index
--- @return number index 0 when the shell has no footer
local function ResolveSlot(dlg, slot)
    local count = #dlg.footerCells
    if count == 0 then
        return 0
    end

    if type(slot) == "number" then
        return math.max(1, math.min(count, math.floor(slot)))
    end

    if slot == "right" then
        return count
    end

    if slot == "center" then
        return math.ceil(count / 2)
    end

    return 1
end

--- Where a cell's contents sit when the caller does not say: the outer cells
--- against the window edges, anything between them centred.
--- @param dlg DialogShell
--- @param index number
--- @return string
local function DefaultHalign(dlg, index)
    if index <= 1 then
        return "left"
    end

    if index >= #dlg.footerCells then
        return "right"
    end

    return "center"
end

--- @param dlg DialogShell
--- @param index number
local function SyncCell(dlg, index)
    local out = {}
    for i, child in ipairs(dlg.footerContent[index]) do
        out[i] = child
    end

    dlg.footerCells[index].children = out
end

--- Forgets every button tracked against a cell, so replacing that cell's
--- contents does not leave a refresh pointing at a destroyed widget.
--- @param dlg DialogShell
--- @param index number
local function ForgetButtons(dlg, index)
    local kept = {}
    for _, entry in ipairs(dlg.footerButtons) do
        if entry.cell ~= index then
            kept[#kept + 1] = entry
        end
    end

    dlg.footerButtons = kept
end

--- @param args table reads title, subtitle, closeButton, classes, width,
---   height, pad, floating, footerCells, autoWidthButtons, close, escape,
---   onClose, onCreate, onDestroy, monitor, refresh and styles
--- @return DialogShell
function DialogShell.CreateNew(args)
    args = args or {}

    local dlg = DialogShell.new{
        autoWidthButtons = args.autoWidthButtons == true,
        closeMode = args.close or "modal",
        onClose = args.onClose or false,
        customStyles = args.styles or false,
        themeSub = false,
        footerCells = {},
        footerContent = {},
        footerButtons = {},
    }

    dlg.workingArea = gui.Panel{
        width = "100%",
        height = "100% available",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }

    local pad = args.pad or PAD
    dlg.header = BuildHeader(dlg, args, pad)

    -- false, not merely absent: a window hosted inside something that paints
    -- its own controls wants no band at all, which is not the same as one it
    -- collapses and brings back.
    local children = {dlg.header, dlg.workingArea}

    if args.footerCells ~= false then
        dlg.footer = BuildFooter(dlg, args.footerCells or DEFAULT_FOOTER_CELLS)
        children[#children + 1] = dlg.footer
    end

    dlg.root = gui.Panel{
        -- Replaces rather than extends: "dialog" paints a frame, and a
        -- launchable-hosted window must not draw one inside its host's.
        classes = args.classes or {"dialog"},
        styles = ThemeEngine.MergeStyles(dlg.customStyles or nil),
        width = args.width,
        height = args.height,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = pad,
        floating = args.floating == true,
        escapePriority = args.escape == true and EscapePriority.EXIT_MODAL_DIALOG or nil,
        captureEscape = args.escape == true,

        monitorGame = args.monitor,
        refreshGame = function()
            dlg:RefreshFooter()
            if args.refresh ~= nil then
                args.refresh(dlg)
            end
        end,

        escape = function()
            dlg:Close()
        end,

        -- The caller's hooks run after the shell's own work, so a window that
        -- tracks its own lifetime cannot displace the theme subscription.
        create = function(element)
            dlg.themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(dlg.customStyles or nil)
                end
            end)

            if args.onCreate ~= nil then
                args.onCreate(dlg)
            end
        end,

        destroy = function()
            if dlg.themeSub then
                dlg.themeSub:Deregister()
                dlg.themeSub = false
            end

            if args.onDestroy ~= nil then
                args.onDestroy(dlg)
            end
        end,

        children = children,
    }

    return dlg
end

--- Re-proportions the footer. Widths are reassigned in place when the count is
--- unchanged, so contents and tracked buttons survive; a different count
--- rebuilds the cells and empties them, and the caller re-adds.
--- @param widths number[] cell widths as whole percentages
function DialogShell:SetFooterCells(widths)
    local row = self:try_get("footerRow")
    if row == nil or widths == nil or #widths == 0 then
        return
    end

    if #widths == #self.footerCells then
        for i, pct in ipairs(widths) do
            self.footerCells[i].width = string.format("%d%%", pct)
        end
        return
    end

    self.footerButtons = {}
    row.children = BuildFooterCells(self, widths)
end

--- The dialog itself, to show, add or return.
--- @return Panel|nil
function DialogShell:Root()
    return self:try_get("root")
end

--- The caller's area, in full.
--- @return Panel|nil
function DialogShell:WorkingArea()
    return self:try_get("workingArea")
end

--- @return Panel|nil
function DialogShell:Header()
    return self:try_get("header")
end

--- Nil on a shell built with footerCells = false.
--- @return Panel|nil
function DialogShell:Footer()
    return self:try_get("footer")
end

--- Fills the working area, replacing whatever was there.
--- @param content Panel|Panel[]|nil a single panel, a list, or nil to empty
function DialogShell:SetWorkingContent(content)
    local area = self:WorkingArea()
    if area == nil then
        return
    end

    if content == nil then
        area.children = {}
        return
    end

    area.children = content.valid ~= nil and {content} or content
end

--- @param visible boolean
function DialogShell:ShowHeader(visible)
    local header = self:Header()
    if header ~= nil then
        header:SetClass("collapsed", not visible)
    end
end

--- @param visible boolean
function DialogShell:ShowFooter(visible)
    local footer = self:Footer()
    if footer ~= nil then
        footer:SetClass("collapsed", not visible)
    end
end

--- @param text string|nil
function DialogShell:SetTitle(text)
    if self.titleLabel.valid then
        self.titleLabel.text = text or ""
    end
end

--- @param text string|nil
function DialogShell:SetSubtitle(text)
    if self.subtitleLabel.valid then
        self.subtitleLabel.text = text or ""
    end
end

--- Adds a button to a footer cell. Buttons added to the same cell sit in the
--- order they were added.
--- @param args table reads slot, text, tooltip, click, enabled and halign;
---   click and enabled are both called with the shell
--- @return Panel|nil button nil when the shell has no footer
function DialogShell:AddFooterButton(args)
    local index = ResolveSlot(self, args.slot or "left")
    if index == 0 then
        return nil
    end

    local button = gui.Button{
        classes = {BUTTON_CLASS},
        text = args.text or "",
        width = self.autoWidthButtons and "auto" or nil,
        halign = args.halign or DefaultHalign(self, index),
        valign = "center",
        hover = args.tooltip ~= nil and gui.Tooltip(args.tooltip) or nil,

        click = function(element)
            if not element.interactable then
                return
            end

            if args.click ~= nil then
                args.click(self)
            end
        end,
    }

    self.footerButtons[#self.footerButtons + 1] = {
        button = button,
        cell = index,
        enabled = args.enabled,
    }

    local contents = self.footerContent[index]
    contents[#contents + 1] = button
    SyncCell(self, index)

    self:RefreshFooter()

    return button
end

--- Puts arbitrary content in a footer cell, replacing whatever was there.
--- @param slot string|number
--- @param content Panel|nil nil empties the cell
function DialogShell:SetFooterContent(slot, content)
    local index = ResolveSlot(self, slot)
    if index == 0 then
        return
    end

    ForgetButtons(self, index)

    self.footerContent[index] = content ~= nil and {content} or {}
    SyncCell(self, index)
end

--- Empties every footer cell.
function DialogShell:ClearFooter()
    self.footerButtons = {}

    for index, _ in ipairs(self.footerCells) do
        self.footerContent[index] = {}
        SyncCell(self, index)
    end
end

--- Re-evaluates every footer button's enabled predicate. Runs on each refresh
--- of a shell that was given a document to monitor.
function DialogShell:RefreshFooter()
    for _, entry in ipairs(self.footerButtons) do
        if entry.enabled ~= nil and entry.button.valid then
            local enabled = entry.enabled(self) == true
            entry.button:SetClass("disabled", not enabled)
            entry.button.interactable = enabled
        end
    end
end

--- Runs the caller's onClose, then closes the way the shell was told to.
function DialogShell:Close()
    if self.onClose then
        self.onClose(self)
    end

    if type(self.closeMode) == "function" then
        self.closeMode(self)
        return
    end

    if self.closeMode == "destroy" then
        local root = self:Root()
        if root ~= nil and root.valid then
            root:DestroySelf()
        end
        return
    end

    -- A hosted shell does not own its own lifetime, so closing is a request to
    -- whatever put it on screen.
    if self.closeMode == "host" then
        local root = self:Root()
        if root ~= nil and root.valid and root.parent ~= nil then
            root.parent:FireEvent("close")
        end
        return
    end

    gui.CloseModal()
end

-- 4:3, sized between the Respite and Montage windows.
local SAMPLE_WIDTH = 1000
local SAMPLE_HEIGHT = 750

--- A live sample of the frame, for tweaking the header and footer bands
--- without standing a real dialog up behind them.
Commands.RegisterMacro{
    name = "testdialogshell",
    summary = "show a sample dialog shell",
    doc = "Usage: /testdialogshell\nOpens a sample dialog shell so its header and footer layout can be checked.",
    command = function(str)
        local dlg = DialogShell.CreateNew{
            title = "Sample Header",
            subtitle = "Additional header information...",
            closeButton = true,
            width = SAMPLE_WIDTH,
            height = SAMPLE_HEIGHT,
            close = "modal",
            escape = true,

            styles = {
                {
                    selectors = {"dialogShellSample"},
                    bgimage = true,
                    bgcolor = "@bgAlt",
                },
            },
        }

        dlg:SetWorkingContent{
            gui.Panel{
                classes = {"dialogShellSample"},
                width = "100%",
                height = "100%",
                flow = "vertical",
                halign = "center",
                valign = "center",

                gui.Label{
                    classes = {"sizeL", "noBold"},
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    text = "Working Area",
                },
            },
        }

        dlg:AddFooterButton{
            slot = "left",
            text = "Close",
            click = function(shell)
                shell:Close()
            end,
        }

        dlg:AddFooterButton{
            slot = "right",
            text = "Next",
            click = function(shell)
                shell:Close()
            end,
        }

        gui.ShowModal(dlg:Root())
    end,
}

local mod = dmhub.GetModLoading()

--- A journal page that points at a prepared negotiation. The page is the beat:
--- docType pins it as one, so it graphs in Flow and sits on the Run. The
--- negotiation itself is authored in the Negotiation window, never here.
---
--- EditPanel is deliberately NOT overridden. Flow reads its edges out of
--- GetTextContent(), so the page has to stay an ordinary authored page.
--- Derives from MarkdownDocument, not CustomDocument: the content, annotations
--- and the rich renderer all live there, and GetTextContent raises on a bare
--- CustomDocument, which declares no content field.
NEGDocument = RegisterGameType("NEGDocument", "MarkdownDocument")

NEGDocument.docType = "negotiation"

--- GetTextContent reads self.content plainly and neither MarkdownDocument nor
--- CustomDocument declares it, so a type default is what keeps it from raising.
NEGDocument.content = ""

--- Which library negotiation this page launches.
NEGDocument.defid = ""

--- @return NEGDefinition|nil
function NEGDocument:Target()
    return NEGDefinition.GetByID(self:try_get("defid", ""))
end

--- Every prepared negotiation, plus an opening entry for a page that does not
--- point at one yet.
--- @return {id: string, text: string}[]
local function TargetOptions()
    local options = { { id = "", text = "(none chosen)" } }
    for _, def in ipairs(NEGDefinition.GetAll()) do
        options[#options + 1] = { id = def:GetID(), text = def.name or "" }
    end
    return options
end

--- One Director-only strip - which negotiation this is, and the button that
--- opens it - above the page as MarkdownDocument renders it.
--- @param args nil|table
--- @return Panel
function NEGDocument:DisplayPanel(args)
    --args or {}: the base iterates it with pairs and does not guard nil.
    local body = MarkdownDocument.DisplayPanel(self, args or {})

    if not dmhub.isDM then
        return body
    end

    local startButton
    local picker

    local function Refresh()
        local def = self:Target()
        local running = NEGRun.Active() ~= nil
        local ready = def ~= nil and not running

        startButton:SetClass("disabled", not ready)
        startButton.interactable = ready
        startButton.text = cond(def == nil, "Choose a negotiation", "Start Negotiation")
    end

    picker = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        width = 260,
        height = 26,
        halign = "left",
        valign = "center",
        rmargin = 12,
        options = TargetOptions(),
        idChosen = self:try_get("defid", ""),
        change = function(element)
            self.defid = element.idChosen
            self:Upload()
            Refresh()
        end,
    }

    startButton = gui.Button{
        classes = { "sizeL" },
        width = 200,
        text = "Start Negotiation",
        halign = "left",
        valign = "center",
        click = function(element)
            if not element.interactable then
                return
            end
            local def = self:Target()
            if def == nil then
                return
            end
            NEGRun.BeginSetup(def:GetID(), self.id)
            LaunchablePanel.LaunchPanelByName(NEGConstants.panelName)
        end,
    }

    --Short of 100%: hpad adds to the declared width rather than insetting it.
    local strip = gui.Panel{
        classes = { "border" },
        width = "100%-40",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
        vpad = 10,
        hpad = 16,
        border = { x1 = 0, y1 = 0, x2 = 0, y2 = 1 },

        monitorGame = NEGRun.DocPath(),
        refreshGame = function()
            Refresh()
        end,

        create = function()
            Refresh()
        end,

        picker,
        startButton,
    }

    --The strip leads; the page keeps whatever height the renderer wanted.
    body.selfStyle.height = "100% available"

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        strip,
        body,
    }
end

--Off with the menu entry; the module move decides whether the journal gets one.
if false then
    CustomDocument.Register{
        id = "dsnegotiation",
        text = "New Negotiation",
        docType = "negotiation",
        icon = "phosphor/handshake.png",
        create = function()
            return NEGDocument.new{
                description = "New Negotiation",
                content = "",
                annotations = {},
            }
        end,
    }
end

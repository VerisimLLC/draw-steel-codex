local mod = dmhub.GetModLoading()

---@class RichImage
RichImage = RegisterGameType("RichImage", "RichTag")
RichImage.tag = "image"
RichImage.image = false
RichImage.halign = "left"
RichImage.uiscale = 1
RichImage.maxWidth = "100%"

function RichImage.Create()
    return RichImage.new{}
end

function RichImage.CreateDisplay(self)
    --The seamless editor's island layer marks its refresh tokens with
    --editor = true; display-mode render tokens never carry the flag. In editor
    --mode we (a) show a placeholder frame when no image is chosen (an empty
    --image renders 0x0, which left the island's reserved space as an
    --unexplained blank gap) and (b) poll for annotation edits: the annotation
    --editors mutate the tag object directly with no change event, so a set
    --image would otherwise never appear until the editor was recreated.
    --Read mode is unchanged: no placeholder, no poll.
    local m_editorMode = false
    local m_lastImage = nil
    local m_applied = false
    local m_halign = nil

    local imagePanel
    local placeholderPanel
    local UpdateState

    UpdateState = function()
        local img = self.image or nil
        if img ~= m_lastImage or not m_applied then
            m_lastImage = img
            m_applied = true
            imagePanel.bgimage = img
        end
        imagePanel.selfStyle.uiscale = self.uiscale
        if m_editorMode then
            imagePanel.selfStyle.halign = m_halign or "left"
            placeholderPanel.selfStyle.halign = m_halign or "left"
        end
        placeholderPanel:SetClass("collapsed", not m_editorMode or m_lastImage ~= nil)
    end

    imagePanel = gui.Panel{
        classes = {"image"},
        maxWidth = self.maxWidth,
        width = "auto",
        height = "auto",
        autosizeimage = true,
        uiscale = self.uiscale,
        refreshTag = function(element, tag, match, token)
            self = tag or self
            UpdateState()
        end,
    }

    placeholderPanel = gui.Panel{
        classes = {"collapsed"},
        width = 340,
        height = 64,
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "#00000044",
        border = 1,
        borderColor = "#99999977",
        gui.Label{
            text = "No image set. Choose one in the annotations strip below.",
            fontSize = 14,
            color = "#aaaaaa",
            width = "auto",
            height = "auto",
            maxWidth = 320,
            textAlignment = "center",
            halign = "center",
            valign = "center",
        },
    }

    return gui.Panel{
        width = "auto",
        height = "auto",
        valign = "center",
        flow = "vertical",
        halign = self.halign,
        refreshTag = function(element, tag, match, token)
            local halign = (token ~= nil and token.justification) or (tag or self).halign
            if token ~= nil and token.editor then
                m_editorMode = true
                --fill the island wrapper so imagePanel's maxWidth="100%"
                --resolves against the real editor width (under auto-width
                --parents a large image renders at natural size and spills
                --out of the page); alignment moves to the image panel.
                element.selfStyle.width = "100%"
                m_halign = halign
                UpdateState()
            else
                element.selfStyle.halign = halign
            end
        end,

        thinkTime = 0.35,
        think = function(element)
            if m_editorMode then
                UpdateState()
            end
        end,

        imagePanel,
        placeholderPanel,
    }
end

function RichImage.CreateEditor(self)
    local resultPanel

    resultPanel = gui.Panel{
        flow = "none",
        width = 96,
        height = "100%",
        refreshEditor = function(element, richTag)
            self = richTag or self
        end,
        gui.Button{
            classes = {"settingsButton", "sizeXxs"},
            halign = "right",
            valign = "top",
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                element.popupsInheritStyles = true
                element.popup = gui.Panel{
                    classes = {"bordered", "bg"},
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    pad = 8,

                    gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        gui.Label{
                            classes = {"sizeS"},
                            width = "auto",
                            height = "auto",
                            text = "Dimensions:",
                        },
                        gui.Label{
                            classes = {"sizeXs"},
                            width = "auto",
                            height = "auto",
                            lmargin = 4,
                            text = "--",
                            create = function(element)
                                dmhub.GetImageInfo(self.image, function(info)
                                    if info ~= nil then
                                        element.text = info.width .. " x " .. info.height
                                    else
                                        element.text = "error"
                                    end
                                end)
                            end,
                        }
                    },

                    gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        gui.Label{
                            classes = {"sizeXs"},
                            width = "auto",
                            height = "auto",
                            text = "Scale:",
                        },
                        gui.Slider{
                            width = 160,
                            labelWidth = 40,
                            height = 20,
                            minValue = 0,
                            maxValue = 1,
                            handleSize = "100%",
                            labelFormat = "percent",
                            value = self.uiscale,
                            change = function(element)
                                self.uiscale = element.value
                            end,
                        },
                    },

                    gui.Dropdown{
                        idChosen = self.halign,
                        options = {
                            {id="left", text="Align Left"},
                            {id="center", text="Align Center"},
                            {id="right", text="Align Right"},
                        },

                        change = function(element)
                            self.halign = element.idChosen
                        end,
                    },
                }
            end,
        },
        gui.IconEditor{
            width = 64,
            height = 64,
            halign = "center",
            valign = "center",
            library = "Avatar",
            value = self.image or nil,
            change = function(element)
                self.image = element.value
            end,
        },
    }

    return resultPanel
end


print("EDIT:: REGISTERING", RichImage.tag)
MarkdownDocument.RegisterRichTag(RichImage)
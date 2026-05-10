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
    return gui.Panel{
        width = "auto",
        height = "auto",
        valign = "center",
        refreshTag = function(element, tag, match, token)
            element.selfStyle.halign = token.justification or tag.halign
        end,
        halign = self.halign,
    
        gui.Panel{
            classes = {"image"},
            maxWidth = self.maxWidth,
            width = "auto",
            height = "auto",
            autosizeimage = true,
            uiscale = self.uiscale,
            refreshTag = function(element, tag, match, token)
                tag = tag or self
                element.bgimage = tag.image or nil
                element.selfStyle.uiscale = tag.uiscale
            end,
        }
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
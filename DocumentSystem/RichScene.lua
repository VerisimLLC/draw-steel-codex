local mod = dmhub.GetModLoading()

---@class RichScene
RichScene = RegisterGameType("RichScene", "RichTag")
RichScene.tag = "scene"
RichScene.image = false

function RichScene.Create()
    return RichScene.new{}
end

function RichScene.CreateDisplay(self)
    if not dmhub.isDM then
        return gui.Panel{
            width = 1,
            height = 1,
            classes = {"collapsed"},
        }
    end

	local doc = FullscreenDisplay.GetDocumentSnapshot()
    local m_image = nil
    return gui.Panel{
        width = 1920*0.15,
        height = "auto",
        valign = "center",
        flow = "vertical",
        refreshTag = function(element, tag, match, token)
            element.selfStyle.halign = token.justification or "left"
            element:SetClass("collapsed", element:FindParentWithClass("playerPreview") ~= nil)
        end,

        refreshDocument = function(element)
            element:SetClass("collapsed", element:FindParentWithClass("playerPreview") ~= nil)
        end,

        gui.Label{
            width = 1920*0.15,
            height = 22,
            fontSize = 20,
            bold = true,
            color = Styles.textColor,
            text = "Scene",
            textAlignment = "center",
        },
    
        gui.Panel{
            width = 1920*0.15,
            height = 1080*0.15,
            autosizeimage = true,
            bgcolor = "white",
            refreshTag = function(element, tag, match, token)
                tag = tag or self
                m_image = tag.image or nil
                element.bgimage = tag.image or nil
            end,
        },
        gui.EnumeratedSliderControl{
            styles = ThemeEngine.GetStyles(),
            options = {
                {id = false, text = "Hide"},
                {id = true, text = "Players"},
                {id = "all", text = "All"},
            },
            width = 1920*0.15,
            value = doc.data.coverart == m_image and doc.data.show,

            change = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.show = element.value
                doc.data.coverart = m_image
                doc:CompleteChange("Show Fullscreen Display")
            end,

            monitorGame = doc.path,
            refreshGame = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                element.SetValue(element, doc.data.show, false)
            end,
        },
        gui.Check{
            styles = ThemeEngine.GetStyles("default", "default"),
            text = "Show Below UI",
            value = doc.data.belowui,
            change = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.belowui = element.value
                doc:CompleteChange("Show Below UI")
            end,
            monitorGame = doc.path,
            refreshGame = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                element.value = doc.data.belowui
            end,
        }
    }
end

function RichScene.CreateEditor(self)
    local resultPanel

    resultPanel = gui.Panel{
        flow = "none",
        width = 96,
        height = "100%",
        refreshEditor = function(element, richTag)
            self = richTag or self
        end,
        gui.SettingsButton{
            halign = "right",
            valign = "top",
            width = 12,
            height = 12,
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                element.popup = gui.Panel{
                    styles = Styles.Default,
                    bgimage = true,
                    bgcolor = "black",
                    opacity = 0.8,
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                }
            end,
        },
        gui.IconEditor{
            width = 64,
            height = 64,
            halign = "center",
            valign = "center",
            library = "coverart",
            value = self.image or nil,
            change = function(element)
                self.image = element.value
            end,
        },
    }

    return resultPanel
end


print("EDIT:: REGISTERING", RichScene.tag)
MarkdownDocument.RegisterRichTag(RichScene)
local mod = dmhub.GetModLoading()

---@class RichScene: RichTag
RichScene = RegisterGameType("RichScene", "RichTag")
RichScene.tag = "scene"
RichScene.image = false

function RichScene.Create()
    return RichScene.new{}
end

local function SceneStyles(pal)
    local styles = {
        { selectors = {"sceneCaption"}, color = "@fg" },
        { selectors = {"enumSliderOption"}, bgcolor = "@bg", color = "@fg", borderColor = "@border" },
        { selectors = {"enumSliderOption", "selected"}, bgcolor = "@bgInverse", color = "@fgInverse" },
        { selectors = {"checkboxLabel"}, color = "@fg" },
        { selectors = {"checkBackground"}, bgcolor = "@bg", borderColor = "@border" },
        { selectors = {"checkMark"}, bgcolor = "@fg" },
    }

    if pal ~= nil then
        styles[#styles + 1] = { selectors = {"sceneCaption"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"enumSliderOption"}, bgcolor = pal.page, color = pal.ink, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"enumSliderOption", "selected"}, bgcolor = pal.accent, color = pal.page }
        styles[#styles + 1] = { selectors = {"enumSliderOption", "hover"}, bgcolor = pal.accent, color = pal.page }
        styles[#styles + 1] = { selectors = {"checkboxLabel"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"checkBackground"}, bgcolor = pal.page, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"checkMark"}, bgcolor = pal.accent }
        styles[#styles + 1] = { selectors = {"checkbox", "hover", "~disabled"}, borderColor = pal.border }
    end

    return ThemeEngine.MergeTokens(styles)
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
        styles = SceneStyles(nil),
        refreshTag = function(element, tag, match, token)
            element.selfStyle.halign = token.justification or "left"
            element:SetClass("collapsed", element:FindParentWithClass("playerPreview") ~= nil)

            --Rebuilt every render, as RichCheckbox does. Caching on the palette looks
            --free but is not: SceneStyles resolves @fg/@bg/@border through
            --ThemeEngine.MergeTokens, which snapshots the ACTIVE scheme, so a cached
            --assignment keeps the old scheme's hex values after a theme change -- and on
            --an unskinned document the palette is nil both before and after, so the cache
            --never missed and the widget never repainted at all.
            element.styles = SceneStyles(MarkdownDocument.PageSkinPalette((tag or self):GetDocument()))
        end,

        refreshDocument = function(element)
            element:SetClass("collapsed", element:FindParentWithClass("playerPreview") ~= nil)
        end,

        gui.Label{
            classes = {"sizeL", "sceneCaption", "bold"},
            width = 1920*0.15,
            text = "Scene",
            textAlignment = "center",
        },
    
        gui.Panel{
            classes = {"image"},
            width = 1920*0.15,
            height = 1080*0.15,
            autosizeimage = true,
            refreshTag = function(element, tag, match, token)
                tag = tag or self
                m_image = tag.image or nil
                element.bgimage = tag.image or nil
            end,
        },
        gui.EnumeratedSliderControl{
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
        -- This seems to do nothing?
        -- gui.Button{
        --     classes = {"settingsButton", "sizeXxs"},
        --     halign = "right",
        --     valign = "top",
        --     press = function(element)
        --         if element.popup ~= nil then
        --             element.popup = nil
        --             return
        --         end
        --         element.popup = gui.Panel{
        --             styles = Styles.Default,
        --             bgimage = true,
        --             bgcolor = "black",
        --             opacity = 0.8,
        --             width = "auto",
        --             height = "auto",
        --             flow = "vertical",
        --         }
        --     end,
        -- },
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
local mod = dmhub.GetModLoading()

---@class RichScene: RichTag
--- @field new fun(o?: table): RichScene
RichScene = RegisterGameType("RichScene", "RichTag")
RichScene.tag = "scene"
RichScene.image = false
--"Art by": the id of the creator whose art this is (DMHub Core UI/
--CreatorCredit.lua), or false. Showing the scene puts their logo badge on it.
RichScene.credit = false
--A scene from the Scenes library (ScenesPanel.lua) by id, or false. A linked
--tag shows that scene -- its picture, caption, credit and sound cue -- and
--keeps up with edits to it; otherwise the tag's own image is shown.
RichScene.scene = false

function RichScene.Create()
    return RichScene.new{}
end

--- The linked library scene's id, if the tag has one and it still exists.
--- @return nil|string
function RichScene:GetLibraryScene()
    local id = self.scene
    local scenes = rawget(_G, "Scenes")
    if type(id) ~= "string" or scenes == nil or scenes.Get(id) == nil then
        return nil
    end
    return id
end

--- The picture the tag shows: the linked scene's, or its own.
--- @return nil|string
function RichScene:GetImage()
    local id = self:GetLibraryScene()
    if id ~= nil then
        return Scenes.Get(id).image
    end
    return self.image or nil
end

--- What this tag's Hide / Players / All control shows.
--- @return boolean|string
function RichScene:GetShowState()
    local id = self:GetLibraryScene()
    if id ~= nil then
        return Scenes.ShowState(id)
    end
    local data = FullscreenDisplay.GetDocumentSnapshot().data
    if data.show and data.coverart == self.image and type(data.sceneid) ~= "string" then
        return data.show
    end
    return false
end

--- The creator id credited for this scene's art, or nil.
--- @return nil|string
function RichScene:GetCredit()
    local credit = self.credit
    if type(credit) == "string" and credit ~= "" and credit ~= "none" then
        return credit
    end
    return nil
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
    local m_credit = nil
    local m_tag = self
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
            --a linked tag is titled with the library scene's name.
            refreshTag = function(element, tag, match, token)
                local id = (tag or self):GetLibraryScene()
                if id ~= nil then
                    element.text = Scenes.Name(id)
                else
                    element.text = "Scene"
                end
            end,
        },
    
        gui.Panel{
            classes = {"image"},
            width = 1920*0.15,
            height = 1080*0.15,
            autosizeimage = true,
            refreshTag = function(element, tag, match, token)
                tag = tag or self
                m_tag = tag
                m_image = tag:GetImage()
                m_credit = tag:GetCredit()
                element.bgimage = m_image
            end,
        },
        gui.EnumeratedSliderControl{
            options = {
                {id = false, text = "Hide"},
                {id = true, text = "Players"},
                {id = "all", text = "All"},
            },
            width = 1920*0.15,
            value = self:GetShowState(),

            change = function(element)
                --a linked library scene is shown through the library, so its
                --caption and sound cue come with it.
                local sceneid = m_tag:GetLibraryScene()
                if sceneid ~= nil then
                    Scenes.Present(sceneid, element.value)
                    return
                end
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.show = element.value
                doc.data.coverart = m_image
                --the full-screen display shows this creator's badge.
                doc.data.coverartCredit = m_credit or false
                doc.data.sceneid = false
                doc.data.caption = false
                doc.data.subtitle = false
                doc:CompleteChange("Show Fullscreen Display")
            end,

            monitorGame = doc.path,
            refreshGame = function(element)
                element.SetValue(element, m_tag:GetShowState(), false)
            end,
        },
        gui.Check{
            text = "Show Above UI",
            value = doc.data.aboveui == true,
            change = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                doc:BeginChange()
                doc.data.aboveui = element.value
                doc:CompleteChange("Show Above UI")
            end,
            monitorGame = doc.path,
            refreshGame = function(element)
                local doc = FullscreenDisplay.GetDocumentSnapshot()
                element.value = doc.data.aboveui == true
            end,
        }
    }
end

--The Scenes library as dropdown options, by name, after "None".
local function LibrarySceneOptions()
    local result = {}
    local scenes = rawget(_G, "Scenes")
    if scenes ~= nil then
        for id, scene in pairs(scenes.All()) do
            if type(scene) == "table" then
                result[#result+1] = {id = id, text = scenes.Name(id)}
            end
        end
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    table.insert(result, 1, {id = "none", text = "None"})
    return result
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
        --settings: who made the art ("Art by"), for the logo badge.
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

                    gui.Label{
                        classes = {"sizeXs"},
                        width = "auto",
                        height = "auto",
                        text = "Art by:",
                    },
                    gui.Dropdown{
                        width = 200,
                        options = CreatorCredit.DropdownOptions(),
                        idChosen = self:GetCredit() or "none",
                        change = function(element)
                            ---@cast element Dropdown
                            local id = element.idChosen
                            self.credit = cond(type(id) == "string" and id ~= "none", id, false)
                        end,
                    },

                    gui.Label{
                        classes = {"sizeXs"},
                        width = "auto",
                        height = "auto",
                        tmargin = 8,
                        text = "Library scene:",
                    },
                    gui.Dropdown{
                        width = 200,
                        options = LibrarySceneOptions(),
                        idChosen = self:GetLibraryScene() or "none",
                        change = function(element)
                            ---@cast element Dropdown
                            local id = element.idChosen
                            self.scene = cond(type(id) == "string" and id ~= "none", id, false)
                            resultPanel:FireEventTree("refreshEditor", self)
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
            library = "coverart",
            value = self:GetImage(),
            refreshEditor = function(element, richTag)
                element.SetValue(element, (richTag or self):GetImage(), false)
            end,
            --picking a picture of its own unlinks the tag from the library.
            change = function(element)
                self.image = element.value
                self.scene = false
            end,
        },
    }

    return resultPanel
end


print("EDIT:: REGISTERING", RichScene.tag)
MarkdownDocument.RegisterRichTag(RichScene)
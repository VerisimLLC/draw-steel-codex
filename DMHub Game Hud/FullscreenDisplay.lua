local mod = dmhub.GetModLoading()

RegisterGameType("FullscreenDisplay")

FullscreenDisplay.docid = "fullscreen_display"

function FullscreenDisplay.Create(options)
    local belowui = options.belowui or false
	local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    local displayPanel = gui.Panel{
        classes = {"hidden", cond(belowui, "belowui", "aboveui")},
        width = "100%",
        height = "100%",
        bgimage = doc.data.coverart,
        bgcolor = "white",
        halign = "center",
        valign = "center",
        floating = true,

        styles = {
            {
                selectors = {"~dm", "closebutton"},
                hidden = 1,
            }
        },

        screenResized = function(element)
            element:ScheduleEvent("imageLoaded", 0.5)
        end,

        imageLoaded = function(element)
            if element.bgsprite == nil then
                return
            end

            local w = element.parent.renderedWidth
            local h = element.parent.renderedHeight
            local aspect = h / w

            local imageAspect = element.bgsprite.dimensions.y/element.bgsprite.dimensions.x

            if aspect == imageAspect then
                element.selfStyle.width = "100%"
                element.selfStyle.height = "100%"
            elseif aspect > imageAspect then
                element.selfStyle.height = "100%"
                element.selfStyle.width = string.format("%f%% height", 100/imageAspect)
            else
                element.selfStyle.width = "100%"
                element.selfStyle.height = string.format("%f%% width", 100*imageAspect)
            end
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        displayPanel,

        data = {
            presentationInfo = nil,
        },

        monitorGame = doc.path,

        refreshGame = function(element)
	        local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
            displayPanel.bgimage = doc.data and doc.data.coverart
            local hide = doc.data == nil or (doc.data.belowui or false) ~= belowui or (not doc.data.show) or (doc.data.show ~= "all" and dmhub.isDM)
            displayPanel:SetClass("hidden", hide)

            if not hide then
                displayPanel:FireEvent("imageLoaded")
            end

            if doc.data == nil or (not doc.data.show) or not dmhub.isDM then
                if element.data.presentationInfo ~= nil then
                    TopBar.ClearPresentationInfo(element.data.presentationInfo.id)
                    element.data.presentationInfo = nil
                end
            else
                local info = element.data.presentationInfo or {}
                info.id = info.id or dmhub.GenerateGuid()
                info.text = "Show Scene"
                info.onchange = info.onchange or function(value)
                    local doc = FullscreenDisplay.GetDocumentSnapshot()
                    doc:BeginChange()
                    doc.data.show = value
                    doc:CompleteChange("Show Fullscreen Display")
                end
                info.options = info.options or {
                    {
                        id = false,
                        text = "Hide",
                        execute = function()
                        end,
                    },
                    {
                        id = true,
                        text = "Players",
                        execute = function()
                        end,
                    },
                    {
                        id = "all",
                        text = "All",
                        execute = function()
                        end,
                    }
                }
                info.value = doc.data.show
                TopBar.SetPresentationInfo(info)
                element.data.presentationInfo = info
            end
        end,
    }
end

function FullscreenDisplay.GetDocumentSnapshot()
	local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    return doc
end
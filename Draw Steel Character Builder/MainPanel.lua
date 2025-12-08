--[[
    Main panel of the Character Builder
    ... plus some other WIP that will eventually move out
]]

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getCreature = CharacterBuilder._getCreature
local _getToken = CharacterBuilder._getToken

--- Minimal implementation for the center panel. Non-reactive.
function CharacterBuilder._detailPanel(builderPanel)
    local detailPanel

    detailPanel = gui.Panel{
        id = "detailPanel",
        classes = {"detailPanel", "panel-base", "builder-base"},
        width = CharacterBuilder.SIZES.CENTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        borderColor = "blue",
    }

    return detailPanel
end

-- Minimal implementation for the character panel. Non-reactive.
function CharacterBuilder._characterPanel(builderPanel)

    local characterPanel

    local popoutAvatar = gui.Panel {
        classes = { "hidden" },
        interactable = false,
        width = 800,
        height = 800,
        halign = "center",
        valign = "center",
        bgcolor = "white",
    }

    local avatar = gui.IconEditor {
        library = cond(dmhub.GetSettingValue("popoutavatars"), "popoutavatars", "Avatar"),
        restrictImageType = "Avatar",
        allowPaste = true,
        borderColor = Styles.textColor,
        borderWidth = 2,
        cornerRadius = math.floor(0.5 * CharacterBuilder.SIZES.AVATAR_DIAMETER),
        width = CharacterBuilder.SIZES.AVATAR_DIAMETER,
        height = CharacterBuilder.SIZES.AVATAR_DIAMETER,
        autosizeimage = true,
        halign = "center",
        valign = "top",
        tmargin = 20,
        bgcolor = "white",

        children = { popoutAvatar, },

        thinkTime = 0.2,
        think = function(element)
            element:FireEvent("imageLoaded")
        end,

        updatePopout = function(element, ispopout)
            if not ispopout then
                popoutAvatar:SetClass("hidden", true)
            else
                popoutAvatar:SetClass("hidden", false)
                popoutAvatar.bgimage = element.value
                popoutAvatar.selfStyle.scale = .25
                element.bgimage = false --"panels/square.png"
            end

            local parent = element:FindParentWithClass("avatarSelectionParent")
            if parent ~= nil then
                parent:SetClassTree("popout", ispopout)
            end
        end,

        imageLoaded = function(element)
            if element.bgsprite == nil then
                return
            end

            local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
            if maxDim > 0 then
                local yratio = element.bgsprite.dimensions.x / maxDim
                local xratio = element.bgsprite.dimensions.y / maxDim
                element.selfStyle.imageRect = { x1 = 0, y1 = 1 - yratio, x2 = xratio, y2 = 1 }
            end
        end,

        refreshAppearance = function(element, info)
            print("APPEARANCE:: Set avatar", info.token.portrait)
            element.SetValue(element, info.token.portrait, false)
            element:FireEvent("imageLoaded")
            element:FireEvent("updatePopout", info.token.popoutPortrait)
        end,

        change = function(element)
            -- local info = CharacterSheet.instance.data.info
            -- info.token.portrait = element.value
            -- info.token:UploadAppearance()
            -- CharacterSheet.instance:FireEvent("refreshAll")
            -- element:FireEvent("imageLoaded")
        end,
    }

    local characterName = gui.Label {
        classes = {"label", "builder-base"},
        text = "calculating...",
        width = "98%",
        height = "auto",
        halign = "center",
        valign = "top",
        textAlignment = "center",
        tmargin = 12,
        fontSize = 24,
        editable = true,
        data = {
            text = "",
        },
        refreshToken = function(element)
            local t = _getToken(element)
            element.data.text = (t and t.name and #t.name > 0) and t.name or "Unnamed Character"
            element.text = string.upper(element.data.text)
        end,
        change = function(element)
            if element.data.text ~= element.text then
                element.data.text = element.text
                local t = _getToken(element)
                if t then
                    t.name = element.data.text
                    _fireControllerEvent(element, "tokenDataChanged")
                end
            end
        end,
    }

    characterPanel = gui.Panel{
        id = "characterPanel",
        classes = {"builder-base", "panel-base", "panel-border", "characterPanel"},
        width = CharacterBuilder.SIZES.CHARACTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        bgimage = true,
        -- halign = "right",
        flow = "vertical",

        avatar,
        characterName,
    }

    return characterPanel
end

--- Create the main panel for the builder.
--- Supports being placed inside the CharacterSheet as a tab
--- or as a stand-alone dialog.
--- In the CharacterSheet, it will instantly update the token.
--- @return Panel
function CharacterBuilder.CreatePanel()

    local builderPanel

    local selectorsPanel = CharacterBuilder._selectorsPanel(builderPanel)
    local detailPanel = CharacterBuilder._detailPanel(builderPanel)
    local characterPanel = CharacterBuilder._characterPanel(builderPanel)

    builderPanel = gui.Panel{
        id = CharacterBuilder.CONTROLLER_CLASS,
        styles = CharacterBuilder._getStyles(),
        classes = {"panel-base", "builder-base", CharacterBuilder.CONTROLLER_CLASS},
        width = "99%",
        height = "99%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        borderColor = "red",  

        data = {
            state = CharacterBuilderState:new(),

            detailPanels = {},

            selectorData = {},

            cachedCharSheetInstance = false,
            charSheetInstance = nil,
            token = nil,
            _cacheToken = function(element)
                if element.data.charSheetInstance == nil and not element.data.cachedCharSheetInstance then
                    element.data.charSheetInstance = CharacterBuilder._getCharacterSheet(element)
                    element.data.cachedCharSheetInstance = true
                end
                if element.data.charSheetInstance and element.data.charSheetInstance.data and element.data.charSheetInstance.data.info then
                    element.data.token = element.data.charSheetInstance.data.info.token
                else
                    -- TODO: Can we create a token without attaching it to the game immediately?
                end
                return element.data.token
            end,
            GetToken = function(element)
                if element.data.token ~= nil then return element.data.token end
                return element.data._cacheToken(element)
            end,
        },

        create = function(element)
            if element.data._cacheToken(element) ~= nil then
                element:FireEventTree("refreshToken")
            end
        end,

        refreshToken = function(element, info)
            if info then
                element.data.token = info.token
            else
                element.data._cacheToken(element)
            end
            if element.data.token then
                element.data.state:Set("ancestry.selectedId", element.data.token.properties:try_get("raceid"))
                element:FireEventTree("refreshBuilderState", element.data.state)
            end
        end,

        selectorChange = function(element, newSelector)
            local selectorDetail = element.data.detailPanels[newSelector]
            if not selectorDetail then
                local selector = CharacterBuilder.SelectorLookup[newSelector]
                if selector and selector.detail then
                    selectorDetail = selector.detail()
                    element.data.detailPanels[newSelector] = selectorDetail
                    detailPanel:AddChild(selectorDetail)
                end
            end
            element.data.state:Set("activeSelector", newSelector)
            element:FireEventTree("refreshBuilderState", element.data.state)
        end,

        updateState = function(element, info)
            if info then
                element.data.state:Set(info.key, info.value)
            end
            element:FireEventTree("refreshBuilderState", element.data.state)
        end,

        tokenDataChanged = function(element)
            if element.data.charSheetInstance then
                element.data.charSheetInstance:FireEvent("refreshAll")
            else
                element:FireEvent("refreshBuilderState", element.data.state)
                element:FireEvent("refreshBuilder", element.data.selectorData)
            end
        end,

        selectorsPanel,
        detailPanel,
        characterPanel,
    }

    return builderPanel
end

-- TODO: Remove the gate on dev mode
if devmode() then

--- Our tab in the character sheet
CharSheet.RegisterTab {
    id = "builder2",
    text = "Builder (WIP)",
	visible = function(c)
		return c ~= nil and c:IsHero()
	end,
    panel = CharacterBuilder.CreatePanel
}
dmhub.RefreshCharacterSheet()

end

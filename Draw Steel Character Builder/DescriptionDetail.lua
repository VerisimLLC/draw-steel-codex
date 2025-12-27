--[[
    Description detail
]]
CBDescriptionDetail = RegisterGameType("CBDescriptionDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = "character"

local _getHero = CharacterBuilder._getHero
local _fireControllerEvent = CharacterBuilder._fireControllerEvent

--- Build the character description editor panel
--- @return Panel
function CBDescriptionDetail._editPane()

    local function wrapEditor(editor, labelText)
        return gui.Panel{
            classes = {"builder-base", "panel-base"},
            width = "96%",
            height = "auto",
            valign = "top",
            flow = "vertical",
            vmargin = 12,
            (labelText and #labelText > 0) and gui.Label{
                classes = {"builder-base", "label", "info"},
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
                textAlignment = "left",
                text = labelText .. ":",
                color = CBStyles.COLORS.GRAY02,
            } or nil,
            editor,
        }
    end

    local function makeDescriptionField(placeholderText, getter, setter, opts)
        local inputConfig = dmhub.DeepCopy(opts or {})

        -- If opts had classes, append them to the base classes
        local baseClasses = {"builder-base", "input", "primary"}
        if inputConfig.classes then
            for _, cls in ipairs(inputConfig.classes) do
                table.insert(baseClasses, cls)
            end
        end

        inputConfig.classes = baseClasses
        inputConfig.width = "94%"
        inputConfig.placeholderText = placeholderText
        inputConfig.editlag = 0.5

        inputConfig.refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if hero then
                local desc = hero:Description()
                if desc then
                    element.text = getter(desc)
                end
            end
        end

        inputConfig.change = function(element)
            local hero = _getHero(element)
            if hero then
                local desc = hero:Description()
                if desc then
                    if element.text ~= getter(desc) then
                        setter(desc, element.text)
                        _fireControllerEvent(element, "tokenDataChanged")
                    end
                end
            end
        end

        inputConfig.edit = function(element)
            element:FireEvent("change")
        end

        return wrapEditor(gui.Input(inputConfig), placeholderText)
    end

    local header = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "horizontal",
        borderColor = "teal",
        gui.Panel{
            width = 64,
            height = 64,
            halign = "left",
            valign = "top",
            bgimage = mod.images.grayD10,
            bgcolor = "white",
        },
        gui.Label{
            classes = {"builder-base", "label", "header"},
            width = "98%-70",
            height = "auto",
            halign = "left",
            valign = "top",
            lmargin = 6,
            textAlignment = "left",
            text = string.upper("Create Your Own Adventurer"),
        }
    }

    local level = wrapEditor(gui.Dropdown{
        classes = {"panel-base", "dropdown", "primary"},
        width = "98%",
        textAlignment = "left",
        halign = "left",
        options = {
            { id = "first", text = "First Encounter",},
            { id = "second", text = "Second Encounter",},
            { id = "third", text = "Third Encounter",},
            { id = "fourth", text = "Fourth Encounter",},
            { id = 1, text = "Level 1",},
            { id = 2, text = "Level 2",},
            { id = 3, text = "Level 3",},
            { id = 4, text = "Level 4",},
            { id = 5, text = "Level 5",},
            { id = 6, text = "Level 6",},
            { id = 7, text = "Level 7",},
            { id = 8, text = "Level 8",},
            { id = 9, text = "Level 9",},
            { id = 10, text = "Level 10",},
        },

        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if hero then
                local level = hero:CharacterLevel()
                if level == 1 then
                    local extra = hero:ExtraLevelInfo()
                    if type(extra.encounter) == "number" then
                        local mapping = {"first", "second", "third", "fourth"}
                        element.idChosen = mapping[extra.encounter] or 1
                    else
                        element.idChosen = 1
                    end
                else
                    element.idChosen = hero:CharacterLevel()
                end
            end
        end,

        change = function(element)
            local hero = _getHero(element)
            if hero then
                local extra = hero:ExtraLevelInfo()
                if type(element.idChosen) == "string" then
                    hero.levelOverride = 1
                    if element.idChosen == "first" then
                        extra.encounter = 1
                    elseif element.idChosen == "second" then
                        extra.encounter = 2
                    elseif element.idChosen == "third" then
                        extra.encounter = 3
                    else
                        extra.encounter = 4
                    end
                else
                    extra.encounter = nil
                    hero.levelOverride = element.idChosen
                end
                hero.extraLevelInfo = extra

                for _,classInfo in ipairs(hero:try_get("classes", {})) do
                    classInfo.level = hero.levelOverride
                end

                _fireControllerEvent(element, "tokenDataChanged")
            end
        end
    })

    local height = makeDescriptionField("Height",
        function(desc) return desc:GetHeight() end,
        function(desc, val) desc:SetHeight(val) end)

    local weight = makeDescriptionField("Weight",
        function(desc) return desc:GetWeight() end,
        function(desc, val) desc:SetWeight(val) end)

    local hair = makeDescriptionField("Hair",
        function(desc) return desc:GetHair() end,
        function(desc, val) desc:SetHair(val) end)

    local eyes = makeDescriptionField("Eyes",
        function(desc) return desc:GetEyes() end,
        function(desc, val) desc:SetEyes(val) end)

    local build = makeDescriptionField("Build",
        function(desc) return desc:GetBuild() end,
        function(desc, val) desc:SetBuild(val) end)

    local skin = makeDescriptionField("Skin tone",
        function(desc) return desc:GetSkinTone() end,
        function(desc, val) desc:SetSkinTone(val) end)

    local gender = makeDescriptionField("Gender presentation",
        function(desc) return desc:GetGenderPresentation() end,
        function(desc, val) desc:SetGenderPresentation(val) end)

    local pronouns = makeDescriptionField("Pronouns",
        function(desc) return desc:GetPronouns() end,
        function(desc, val) desc:SetPronouns(val) end)

    local features = makeDescriptionField("Physical features",
        function(desc) return desc:GetPhysicalFeatures() end,
        function(desc, val) desc:SetPhysicalFeatures(val) end,
        {
            classes = {"multiline"},
            multiline = true,
            textAlignment = "topleft",
            lineType = "MultiLineNewLine"
        })

    return gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = CBStyles.SIZES.DESCRIPTION_PANEL_WIDTH,
        height = "98%",
        hmargin = 12,
        halign = "left",
        valign = "center",
        flow = "vertical",
        vscroll = true,

        header,
        level,
        height,
        weight,
        hair,
        eyes,
        build,
        skin,
        gender,
        pronouns,
        features,
    }
end

function CBDescriptionDetail._artPane()
    return gui.Panel{
        classes = {"builder-base", "panel-base", "border"},
        width = 300,
        height = 975,
        halign = "center",
        valign = "center",
        bgimage = mod.images.byoHome,
        bgcolor = "white",
    }
end

--- Build the Character / Description detail panel
--- @return Panel
function CBDescriptionDetail.CreatePanel()

    local editPane = CBDescriptionDetail._editPane()
    local artPane = CBDescriptionDetail._artPane()

    return gui.Panel{
        id = "descriptionPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "descriptionPanel"},
        data = {
            selector = SELECTOR,
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed", not visible)
            if not visible then element:HaltEventPropagation() end
        end,

        editPane,
        artPane,
    }
end
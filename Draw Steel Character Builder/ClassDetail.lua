--[[
    Class detail / selectors
]]
CBClassDetail = RegisterGameType("CBClassDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.CLASS
local INITIAL_CATEGORY = "overview"
local AVAILABLE_WITHOUT_CLASS = {overview = true}
local CHARACTERISTIC_GUID = "7f3c8a2e-5b14-4d9a-9e61-3c7f2a8b5d4e"

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _formatOrder = CharacterBuilder._formatOrder
local _getHero = CharacterBuilder._getHero
local _getState = CharacterBuilder._getState
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

--- Return the hero's currently selected class
--- @param hero character
--- @return string|nil classId
function CBClassDetail._getSelectedClass(hero)
    local class = hero:GetClass()
    if class then return class.id end
    return nil
end

--- Generate the navigation panel
--- @return Panel
function CBClassDetail._navPanel()

    local overviewButton = _makeDetailNavButton(SELECTOR, {
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
    })
    local changeButton = _makeDetailNavButton(SELECTOR, {
        classes = {"changeClass"},
        text = "Change Class",
        data = { category = "change" },
        click = function(element)
            _fireControllerEvent(element, "removeClass")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if hero then
                local classes = hero:try_get("classes", {})
                element:FireEvent("setAvailable", #classes > 0)
            end
        end,
    })

    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "detail-nav-panel"},
        vscroll = true,

        create = function(element)
            _fireControllerEvent(element, "updateState", {
                key = SELECTOR .. ".category.selectedId",
                value = INITIAL_CATEGORY,
            })
        end,

        registerFeatureButton = function(element, button)
            element:AddChild(button)
            local changeButton = element:FindChildRecursive(function(element) return element:HasClass("changeClass") end)
            if changeButton then changeButton:SetAsLastSibling() end
            element.children = CharacterBuilder._sortButtons(element.children)
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        overviewButton,
        changeButton,
    }
end

--- Build the overview panel
--- Used when no Class is selected and to overview the selected class
--- @return Panel
function CBClassDetail._overviewPanel()

    local nameLabel = gui.Label{
        classes = {"builder-base", "label", "info", "header"},
        width = "100%",
        height = "auto",
        hpad = 12,
        text = "CLASS",
        textAlignment = "left",

        refreshBuilderState = function(element, state)
            local text = "CLASS"
            local classId = state:Get(SELECTOR .. ".selectedId")
            if classId then
                local class = state:Get(SELECTOR .. ".selectedItem")
                if not class then
                    class = dmhub.GetTable(Class.tableName)[classId]
                end
                if class then text = class.name end
            end
            element.text = text
        end
    }

    local introLabel = gui.Label{
        classes = {"builder-base", "label", "info"},
        width = "100%",
        height = "auto",
        vpad = 6,
        hpad = 12,
        bmargin = 12,
        textAlignment = "left",
        text = CharacterBuilder.STRINGS.CLASS.INTRO,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.CLASS.INTRO
            local classId = state:Get(SELECTOR .. ".selectedId")
            if classId then
                local class = state:Get(SELECTOR .. ".selectedItem")
                if not class then
                    class = dmhub.GetTable(Class.tableName)[classId]
                end
                if class then text = CharacterBuilder._trimToLength(class.details, 300) end
            end
            element.text = text
        end,
    }

    local detailLabel = gui.Label{
        classes = {"builder-base", "label", "info"},
        width = "100%",
        height = "auto",
        vpad = 6,
        hpad = 12,
        tmargin = 12,
        textAlignment = "left",
        bold = false,
        text = CharacterBuilder.STRINGS.CLASS.OVERVIEW,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.CLASS.OVERVIEW
            local classId = state:Get(SELECTOR .. ".selectedId")
            if classId then
                local textItems = {}

                local featureCache = state:Get(SELECTOR .. ".featureCache")
                local featureDetails = featureCache:GetFlattenedFeatures()
                for _,item in ipairs(featureDetails) do
                    local s = item.feature:GetSummaryText()
                    if s ~= nil and #s > 0 then
                        textItems[#textItems+1] = s
                    end
                end

                text = CharacterBuilder._trimToLength(table.concat(textItems, "\n\n"), 1800, false)
            end
            element.text = text
        end
    }

    return gui.Panel{
        id = "classOverviewPanel",
        classes = {"classOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.classHome,

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local classId = state:Get(SELECTOR .. ".selectedId")

            local visible = classId == nil or state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)

            if visible then
                if classId == nil then
                    element.bgimage = mod.images.classHome
                    return
                end
                local class = state:Get(SELECTOR .. ".selectedItem")
                if not class then
                    class = dmhub.GetTable(Class.tableName)[classId]
                end
                if class then element.bgimage = class.portraitid end
            end
        end,

        gui.Panel{
            width = "100%-2",
            height = "auto",
            valign = "bottom",
            vmargin = 32,
            flow = "vertical",
            bgimage = true,
            vpad = 8,
            nameLabel,
            introLabel,
            detailLabel,
        }
    }
end

--- Build the Select button
--- @return PrettyButton|Panel
function CBClassDetail._selectButton()
    return CharacterBuilder._makeSelectButton{
        classes = {"selectButton"},
        click = function(element)
            _fireControllerEvent(element, "applyCurrentClass")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if hero then
                local heroClass = hero:GetClass()
                local canSelect = heroClass == nil and state:Get(SELECTOR .. ".selectedId") ~= nil
                element:SetClass("collapsed", not canSelect)
            end
        end,
    }
end

--- Build the Detail Panel
--- @return Panel
function CBClassDetail.CreatePanel()

    local navPanel = CBClassDetail._navPanel()

    local overviewPanel = CBClassDetail._overviewPanel()

    local selectButton = CBClassDetail._selectButton()

    local detailPanel = gui.Panel{
        id = "classDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "classDetailpanel"},

        registerFeaturePanel = function(element, panel)
            element:AddChild(panel)
            local selectButton = element:FindChildRecursive(function(e) return e:HasClass("selectButton") end)
            if selectButton then selectButton:SetAsLastSibling() end
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        overviewPanel,
        selectButton,
    }

    return gui.Panel{
        id = "classPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "classPanel"},
        data = {
            selector = SELECTOR,
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end

            local categoryKey = SELECTOR .. ".category.selectedId"
            local currentCategory = state:Get(categoryKey) or INITIAL_CATEGORY
            local hero = _getHero(state)
            if hero then
                local heroClass = hero:GetClass()

                if heroClass ~= nil then
                    for id,_ in pairs(element.data.features) do
                        element.data.features[id] = false
                    end

                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    local features = featureCache:GetSortedFeatures()
                    for _,f in ipairs(features) do
                        local featureId = f.guid
                        local feature = featureCache:GetFeature(featureId)
                        if feature then
                            if element.data.features[featureId] == nil then
                                local featureRegistry = CharacterBuilder._makeFeatureRegistry{
                                    feature = feature,
                                    selector = SELECTOR,
                                    selectedId = heroClass.id,
                                    getSelected = CBClassDetail._getSelectedClass,
                                }
                                if featureRegistry then
                                    element.data.features[featureId] = true
                                    navPanel:FireEvent("registerFeatureButton", featureRegistry.button)
                                    detailPanel:FireEvent("registerFeaturePanel", featureRegistry.panel)
                                end
                            else
                                element.data.features[featureId] = true
                            end
                        end
                    end

                    for id, active in pairs(element.data.features) do
                        if active == false then
                            navPanel:FireEvent("destroyFeature", id)
                            detailPanel:FireEvent("destroyFeature", id)
                            element.data.features[id] = nil
                        end
                    end
                else
                    if not AVAILABLE_WITHOUT_CLASS[currentCategory] then
                        currentCategory = INITIAL_CATEGORY
                    end
                end
            end

            -- Which category to show?
            if not AVAILABLE_WITHOUT_CLASS[currentCategory] then
                if not element.data.features[currentCategory] then
                    currentCategory = INITIAL_CATEGORY
                end
            end
            state:Set{ key = categoryKey, value = currentCategory }
        end,

        navPanel,
        detailPanel,
    }
end

--- Build the characteristic editor panel, leveraged by injection
--- through CharacterCharacteristicChoice into the feature editor.
--- @return Panel
function CBClassDetail._characteristicPanel()

    local function attrPanel(attr)
        return gui.Panel{
            classes = {"builder-base", "panel-base", "attr-item"},
            flow = "vertical",
            data = {
                attr = attr,
            },
            refreshBuilderState = function(element, state)
                local isLocked = true
                local classItem = state:Get(SELECTOR .. ".selectedItem")
                if classItem then
                    local baseChars = classItem:try_get("baseCharacteristics", {})
                    isLocked = baseChars[element.data.attr.id] ~= nil
                end
                element:SetClass("locked", isLocked)
            end,
            gui.Label{
                classes = {"builder-base", "label", "attr-name"},
                text = attr.description:upper()
            },
            gui.Label{
                classes = {"builder-base", "label", "attr-value"},
                refreshBuilderState = function(element, state)
                    local hero = _getHero(state)
                    local attributes = hero:try_get("attributes")
                    local baseValue = attributes and attributes[attr.id] and attributes[attr.id].baseValue or 0
                    element.text = string.format("%+d", baseValue)
                end,
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "attr-lock"},
                floating = true,
            }
        }
    end

    return gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "line",
            width = "96%",
            vpad = 4,
            bgcolor = CBStyles.COLORS.GOLD
        },
        gui.Panel{
            classes = {"builder-base", "panel-base", "container", "attr-container"},
            flow = "horizontal",
            valign = "top",

            refreshBuilderState = function(element, state)
                if #element.children == 0 then
                    local attrInfo = CharacterBuilder._toArray(creature.attributesInfo)
                    CharacterBuilder._sortArrayByProperty(attrInfo, "order")
                    for _,attr in ipairs(attrInfo) do
                        element:AddChild(attrPanel(attr))
                    end
                end
            end,
        },
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "line",
            width = "96%",
            vpad = 4,
            bgcolor = CBStyles.COLORS.GOLD
        },
    }
end

-- function CBClassDetail._characteristicButton(classId)
--     local key = SELECTOR .. ".category.selectedId"
--     return CharacterBuilder._makeCategoryButton{
--         text = "Characteristics",
--         data = {
--             featureId = CHARACTERISTIC_GUID,
--             selectedId = classId,
--             order = _formatOrder(0, "Characteristics"),
--         },
--         click = function(element)
--             CharacterBuilder._fireControllerEvent(element, "updateState", {
--                 key = key,
--                 value = element.data.featureId,
--             })
--         end,
--         refreshBuilderState = function(element, state)
--             local tokenSelected = CBClassDetail._getSelectedClass(_getHero(state))
--             local visible = tokenSelected ~= nil
--             element:FireEvent("setAvailable", visible)
--             element:FireEvent("setSelected", element.data.featureId == state:Get(key))
--             element:SetClass("collapsed", not visible)
--         end
--     }
-- end

-- function CBClassDetail._characteristicPanel(hero, classItem)

--     local controllerClass = "characteristicsController"
--     local key = SELECTOR .. ".category.selectedId"
--     local attrInfo = creature.attributesInfo

--     local function fireFeatureControllerEventTree(element, eventName, ...)
--         local featureController = element:FindParentWithClass(controllerClass)
--         if featureController then
--             featureController:FireEventTree(eventName, ...)
--         end
--     end

--     local function formatArrayLabel(array)
--         table.sort(array, function(a,b) return b < a end)
--         return table.concat(array, ", ")
--     end

--     local header = {
--         name = "Characteristics",
--         description = CharacterBuilder._parseStartingCharacteristics(classItem.baseCharacteristics),
--     }

--     local targetPanel = gui.Panel{
--         classes = {"builder-base", "panel-base", "feature-target", "empty"},
--         data = {
--             selectedArray = nil,
--         },
--         click = function(element)
--             -- TODO: Remove the selection
--         end,
--         linger = function(element)
--             if element.data.selectedArray then
--                 gui.Tooltip("Press to delete")(element)
--             end
--         end,
--         refreshBuilderState = function(element, state)
--             element.data.selectedArray = nil
--             local arrayText = "Empty Slot"
--             local classItem = state:Get(SELECTOR .. ".selectedItem")
--             if classItem ~= nil then
--                 local baseChars = classItem.baseCharacteristics
--                 local hero = _getHero(state)
--                 local attrBuild = hero.attributeBuild
--                 if attrBuild == nil or attrBuild.array == nil then
--                     attrBuild = CharacterBuilder._deriveAttributeBuild(hero, baseChars)
--                 end
--                 element.data.selectedArray = attrBuild and attrBuild.array
--                 if attrBuild then arrayText = formatArrayLabel(baseChars.arrays[attrBuild.array]) end
--             end

--             element:FireEventTree("setArrayText", arrayText)
--             element:SetClass("filled", element.data.selectedArray ~= nil)
--         end,
--         gui.Label{
--             classes = {"builder-base", "label", "feature-target"},
--             text = "Empty Slot",
--             textAlignment = "center",
--             setArrayText = function(element, text)
--                 if element.text ~= text then element.text = text end
--             end,
--         },
--     }

--     local targetsContainer = {
--         data = {},
--         refreshBuilderState = function(element, state)
--         end,
--         targetPanel,
--     }

--     local function arrayPanel(index)
--         return gui.Panel{
--             classes = {"builder-base", "panel-base", "feature-choice"},
--             valign = "top",
--             data = {
--                 index = index,
--                 item = nil,
--             },
--             assignItem = function(element, item)
--                 element.data.item = item
--             end,
--             click = function(element)
--                 fireFeatureControllerEventTree(element, "selectItem", element.data.index)
--             end,
--             refreshBuilderState = function(element, state)
--                 local visible = element.data.item ~= nil
--                 element:SetClass("collapsed", not visible)
--                 if not visible then
--                     element:HaltEventPropagation()
--                     return
--                 end

--                 element:FireEventTree("setArrayText", formatArrayLabel(element.data.item.arrays[element.data.index]))
--             end,
--             selectItem = function(element, index)
--                 element:SetClass("selected", index == element.data.index)
--             end,
--             gui.Label {
--                 classes = {"builder-base", "label", "feature-choice"},
--                 textAlignment = "center",
--                 setArrayText = function(element, text)
--                     element.text = text
--                 end,
--             },
--         }
--     end

--     local optionsContainer = {
--         data = {
--             classId = nil,
--         },
--         refreshBuilderState = function(element, state)
--             local classItem = state:Get(SELECTOR .. ".selectedItem")
--             if classItem == nil or classItem.id == element.data.classId then return end
--             element.data.classId = classItem.id
--             local baseChars = classItem.baseCharacteristics
--             if baseChars == nil then return end
--             local numArrays = baseChars.arrays and #baseChars.arrays or 0
--             if numArrays == 0 then return end
--             for i = #element.children + 1, numArrays do
--                 element:AddChild(arrayPanel(i))
--             end
--             for i, child in ipairs(element.children) do
--                 child:FireEventTree("assignItem", i <= numArrays and baseChars or nil)
--             end
--         end,
--     }

--     local selectButton = {
--         data = {
--             selectedIndex = nil,
--         },
--         click = function(element)
--             fireFeatureControllerEventTree(element, "applyCurrentItem")
--         end,
--         create = function(element)
--             element:FireEvent("selectCharacteristics", nil, nil)
--         end,
--         refreshBuilderState = function(element, state)
--             local enabled = element.data.selectedIndex ~= nil
--             element:SetClass("disabled", not enabled)
--             element.interactable = enabled
--         end,
--         selectItem = function(element, index)
--             element.data.selectedIndex = index
--             local enabled = element.data.selectedIndex ~= nil
--             element:SetClass("disabled", not enabled)
--             element.interactable = enabled
--         end,
--     }

--     local mainPanel = {
--         data = {
--             selectedIndex = nil,
--         },
--         applyCurrentItem = function(element)
--             if element.data.selectedIndex == nil then return end
--             local hero = _getHero(element)
--             if hero == nil then return end
--             local classItem = hero:GetClass()
--             if classItem == nil then return end
--             local heroAttrs = hero:try_get("attributes")
--             if heroAttrs == nil then return end
--             local attrs = {}
--             local attributeBuild = { array = element.data.selectedIndex }
--             local baseChars = classItem.baseCharacteristics
--             local scoreArray = baseChars.arrays[element.data.selectedIndex]
--             local nextIndex = 1
--             for _,attr in pairs(attrInfo) do
--                 if baseChars[attr.id] ~= nil then
--                     attrs[attr.id] = baseChars[attr.id]
--                 else
--                     attrs[attr.id] = scoreArray[nextIndex]
--                     attributeBuild[attr.id] = nextIndex
--                     nextIndex = nextIndex + 1
--                 end
--             end
--             hero.attributeBuild = attributeBuild
--             for k,v in pairs(attrs) do
--                 heroAttrs[k].baseValue = v
--             end
--             _fireControllerEvent(element, "tokenDataChanged")
--             element:FireEventTree("selectItem", nil)
--         end,
--         selectItem = function(element, index)
--             element.data.selectedIndex = index
--         end,
--     }

--     local featurePanel = CBFeatureSelector.BuildSelectorPanel{
--         controllerClass = controllerClass,
--         header = header,
--         targetsContainer = targetsContainer,
--         optionsContainer = optionsContainer,
--         selectButton = selectButton,
--         mainPanel = mainPanel,
--     }

--     return CharacterBuilder._makeFeaturePanelContainer{
--         data = {
--             featureId = CHARACTERISTIC_GUID,
--             classId = classItem.id,
--         },
--         refreshBuilderState = function(element, state)
--             local classId = CBClassDetail._getSelectedClass(_getHero(state))
--             local visible = element.data.featureId == state:Get(key) and classId ~= nil
--             element:SetClass("collapsed", not visible)
--             if not visible then
--                 element:HaltEventPropagation()
--                 return
--             end

--             if classId ~= element.data.classId then
--                 local classItem = state:Get(SELECTOR .. ".selectedItem")
--                 if classItem then
--                     element:FireEventTree("updateHeaderDesc", CharacterBuilder._parseStartingCharacteristics(classItem.baseCharacteristics))
--                 end
--                 element.data.classId = classId
--             end
--         end,
--         featurePanel,
--     }
-- end

-- function CBClassDetail._characteristicPanelFSStyle(hero, classItem)

--     local controllerClass = "characteristicsController"
--     local key = SELECTOR .. ".category.selectedId"

--     local function fireFeatureControllerEventTree(element, eventName, ...)
--         local featureController = element:FindParentWithClass(controllerClass)
--         if featureController then
--             featureController:FireEventTree(eventName, ...)
--         end
--     end

--     local header = {
--         name = "Characteristics",
--         description = CharacterBuilder._parseStartingCharacteristics(classItem.baseCharacteristics),
--     }

--     local targetsContainer = {
--         data = {},
--         refreshBuilderState = function(element, state)
--         end,
--         gui.Label{
--             width = "auto",
--             height= "auto",
--             fontSize = 32,
--             floating = true,
--             valign = "center",
--             halign = "center",
--             rotate = 35,
--             color = "red",
--             textAlignment = "center",
--             text = "TARGETS",
--         }
--     }

--     local function assignmentPanel(arrayIndex, index)
--         local children = {}
--         for _,item in pairs(character.attributesInfo) do
--             children[#children+1] = gui.Panel{
--                 classes = {"builder-base", "panel-base", "chararray", "item"},
--                 data = {
--                     order = item.order,
--                 },
--                 gui.Label{
--                     classes = {"builder-base", "label", "chararray", "item-name"},
--                     text = item.description,
--                 },
--                 gui.Label{
--                     classes = {"builder-base", "label", "chararray", "item-value"},
--                     text = "",
--                     data = {
--                         arrayIndex = arrayIndex,
--                         index = index,
--                         attrId = item.id,
--                     },
--                     assignArray = function(element, array)
--                         element.text = array and string.format("%+d", array[element.data.attrId]) or ""
--                     end,
--                 }
--             }
--         end
--         table.sort(children, function(a,b) return a.data.order < b.data.order end)
--         return gui.Panel{
--             classes = {"builder-base", "panel-base", "chararray", "detail"},
--             valign = "top",
--             data = {
--                 arrayIndex = arrayIndex,
--                 index = index,
--                 array = nil,
--             },
--             assignArray = function(element, array)
--                 element.data.array = array
--             end,
--             click = function(element)
--                 fireFeatureControllerEventTree(element, "selectCharacteristics", element.data.arrayIndex, element.data.index)
--             end,
--             refreshBuilderState = function(element, state)
--                 local visible = element.data.array ~= nil
--                 element:SetClass("collapsed", not visible)
--                 if not visible then
--                     element:HaltEventPropagation()
--                     return
--                 end
--                 element:FireEventTree("setArrayLabelText", json(element.data.array))
--             end,
--             selectCharacteristics = function(element, arrayIndex, index)
--                 element:SetClass("selected", arrayIndex == element.data.arrayIndex and index == element.data.index)
--             end,
--             children = children,
--         }
--     end

--     local function arrayPanel(index)
--         local detailContainer = gui.Panel{
--             classes = {"builder-base", "panel-base", "chararray", "container", "collapsed-anim"},
--             valign = "top",
--             flow = "vertical",
--             vscroll = true,
--             data = {
--                 index = index,
--                 item = nil,
--             },
--             selectArray = function(element, index)
--                 element:SetClass("collapsed-anim", index ~= element.data.index)
--             end,
--             assignItem = function(element, item)
--                 element.data.item = item
--             end,
--             refreshBuilderState = function(element, state)
--                 local visible = element.data.item ~= nil
--                 element:SetClass("collapsed", not visible)
--                 if not visible then
--                     element:HaltEventPropagation()
--                     return
--                 end

--                 local potentialArrays = CharacterBuilder._generateAttributeCombinations(element.data.item, element.data.index)
--                 for i = #element.children + 1, #potentialArrays do
--                     element:AddChild(assignmentPanel(element.data.index, i))
--                 end
--                 for i,child in ipairs(element.children) do
--                     child:FireEventTree("assignArray", potentialArrays[i])
--                 end
--             end,
--         }
--         local headerPanel = gui.Panel{
--             classes = {"builder-base", "panel-base", "chararray", "header"},
--             valign = "top",
--             data = {
--                 index = index,
--                 item = nil,
--             },
--             selectArray = function(element, index)
--                 element:SetClass("selected", index == element.data.index)
--             end,
--             assignItem = function(element, item)
--                 element.data.item = item
--             end,
--             click = function(element)
--                 fireFeatureControllerEventTree(element, "selectArray", element.data.index)
--             end,
--             refreshBuilderState = function(element, state)
--                 local visible = element.data.item ~= nil
--                 element:SetClass("collapsed", not visible)
--                 if not visible then
--                     element:HaltEventPropagation()
--                     return
--                 end

--                 local array = element.data.item.arrays[element.data.index]
--                 table.sort(array, function(a,b) return b < a end)
--                 element:FireEventTree("setArrayText", table.concat(array, ", "))
--             end,
--             gui.Label {
--                 classes = {"builder-base", "label", "chararray", "header"},
--                 setArrayText = function(element, text)
--                     element.text = text
--                 end,
--             },
--         }
--         return gui.Panel{
--             classes = {"builder-base", "panel-base", "chararray"},
--             detailContainer,
--             headerPanel,
--         }
--     end

--     local optionsContainer = {
--         data = {
--             classId = nil,
--         },
--         refreshBuilderState = function(element, state)
--             local classItem = state:Get(SELECTOR .. ".selectedItem")
--             if classItem == nil or classItem.id == element.data.classId then return end
--             element.data.classId = classItem.id
--             local baseChars = classItem.baseCharacteristics
--             if baseChars == nil then return end
--             local numArrays = baseChars.arrays and #baseChars.arrays or 0
--             if numArrays == 0 then return end
--             for i = #element.children + 1, numArrays do
--                 element:AddChild(arrayPanel(i))
--             end
--             for i, child in ipairs(element.children) do
--                 child:FireEventTree("assignItem", i <= numArrays and baseChars or nil)
--             end
--         end,
--     }

--     local selectButton = {
--         data = {},
--         click = function(element)
--         end,
--         create = function(element)
--             element:FireEvent("selectCharacteristics", nil, nil)
--         end,
--         refreshBuilderState = function(element, state)
--         end,
--         selectCharacteristics = function(element, arrayIndex, itemIndex)
--             local enabled = arrayIndex ~= nil and itemIndex ~= nil
--             element:SetClass("diabled", not enabled)
--             element.interactable = enabled
--         end,
--     }

--     local mainPanel = {
--         data = {},
--         applyCurrentItem = function(element)
--         end,
--         selectArray = function(element, index)
--             element:FireEventTree("selectCharacteristics", nil, nil)
--         end,
--         selectItem = function(element, itemId)
--         end,
--     }

--     local featurePanel = CBFeatureSelector.BuildSelectorPanel{
--         controllerClass = controllerClass,
--         header = header,
--         targetsContainer = targetsContainer,
--         optionsContainer = optionsContainer,
--         selectButton = selectButton,
--         mainPanel = mainPanel,
--     }

--     return CharacterBuilder._makeFeaturePanelContainer{
--         data = {
--             featureId = CHARACTERISTIC_GUID,
--             classId = classItem.id,
--         },
--         refreshBuilderState = function(element, state)
--             local classId = CBClassDetail._getSelectedClass(_getHero(state))
--             local visible = element.data.featureId == state:Get(key) and classId ~= nil
--             element:SetClass("collapsed", not visible)
--             if not visible then
--                 element:HaltEventPropagation()
--                 return
--             end

--             if classId ~= element.data.classId then
--                 local classItem = state:Get(SELECTOR .. ".selectedItem")
--                 if classItem then
--                     element:FireEventTree("updateHeaderDesc", CharacterBuilder._parseStartingCharacteristics(classItem.baseCharacteristics))
--                 end
--                 element.data.classId = classId
--             end
--         end,
--         featurePanel,
--     }
-- end
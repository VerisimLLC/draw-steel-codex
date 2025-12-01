--- Load all the visible skills from the skill table
--- @return table skillList All the skills
local function loadSkills()
    local skillsList = {}
    local skillsLookup = {}
    local categoriesLookup = {}
    for id,item in pairs(dmhub.GetTableVisible(Skill.tableName)) do
        local entry = {
            id = id,
            text = item.name,
            category = item.category,
        }
        skillsList[#skillsList + 1] = entry
        skillsLookup[id] = item.name
        if categoriesLookup[item.category] == nil then
            categoriesLookup[item.category] = {}
        end
        categoriesLookup[item.category][id] = true
    end
    table.sort(skillsList, function(a,b) return a.text < b.text end)
    return {list = skillsList, lookup = skillsLookup, categories = categoriesLookup}
end

--- Process an item to determine the game element it came from
--- @param item table An item to process
--- @return string|nil source The source or nil if not found / invalid
local function processChoiceSource(item)
    if item.background then return "career" end
    if item.upbringing or item.organization or item.environment then
        return "culture"
    end
    if item.class then return "class" end
    return nil
end

--- Process data of CharacterFeature type
--- @param feature CharacterFeature The object to process
--- @return table|nil skillInfo The info gathered about the skill, or nil if it's not for a skill
local function processCharacterFeature(feature)

    local modifiers = feature:try_get("modifiers")
    if modifiers then
        local skillInfo = {}
        for _,item in ipairs(modifiers) do
            if item.typeName and item.typeName == "CharacterModifier" then
                local subtype = item:try_get("subtype")
                if subtype and subtype == "skill" then
                    local skills = item:try_get("skills")
                    if skills and type(skills) == "table" then
                        local selected = {}
                        for k,_ in pairs(skills) do
                            selected[#selected + 1] = k
                        end
                        skillInfo[#skillInfo + 1] = {
                            type = "static",
                            guid = item.guid,
                            sourceGuid = item.sourceguid,
                            name = item.name or "Static Skill",
                            description = item.description or "You gain a static skill.",
                            selected = selected,
                        }
                    end
                end
            end
        end
        return #skillInfo > 0 and skillInfo or nil
    end
    return nil
end

--- Process a skill choice node
--- @param feature CharacterSkillChoice The object to process
--- @param levelChoices table The features the character has selected
--- @return table|nil skillInfo The info gathered about the skill choice
local function processCharacterSkillChoice(feature, levelChoices)

    local guid = feature:try_get("guid")
    if guid then
        return {{
            type = "choice",
            guid = guid,
            categories = feature:try_get("categories"),
            individualSkills = feature:try_get("individualSkills"),
            name = feature:try_get("name", "Skill Choice"),
            description = feature:try_get("description", "You gain a skill choice."),
            numChoices = feature:try_get("numChoices", 1),
            selected = levelChoices[guid],
        }}
    end

    return nil
end

--- Aggregate all the skill choices available and what was selected
--- @param selectedFeatures table The list of all available features to a character
--- @param customFeatures table The list of custom features on the character
--- @param levelChoices table The features the character has selected
--- @return table skillChoices The aggregated options with selections made
local function aggregateSkillChoices(selectedFeatures, customFeatures, levelChoices)
    local skillChoices = {
        features = {},
    }

    for _,item in ipairs(selectedFeatures) do
        if item.feature then
            local typeName = item.feature.typeName
            if typeName then

                local skillInfo
                if typeName == "CharacterFeature" then
                    skillInfo = processCharacterFeature(item.feature)
                elseif typeName == "CharacterSkillChoice" then
                    skillInfo = processCharacterSkillChoice(item.feature, levelChoices)
                end

                if skillInfo and #skillInfo > 0 then
                    local source = processChoiceSource(item)
                    if source then
                        if skillChoices[source] == nil then
                            skillChoices[source] = {}
                        end
                        table.move(skillInfo, 1, #skillInfo, #skillChoices[source] + 1, skillChoices[source])
                    end
                end

            end
        end
    end

    for _,item in ipairs(customFeatures) do
        if item.typeName and item.typeName == "CharacterFeature" then
            local skillInfo = processCharacterFeature(item)
            if skillInfo and #skillInfo > 0 then
                -- These are always choices so force their data into compliance
                for _,item in ipairs(skillInfo) do
                    item.type = "choice"
                    item.canDelete = true
                    item.numChoices = (#item.selected and #item.selected > 0) and #item.selected or 1
                end
                table.move(skillInfo, 1, #skillInfo, #skillChoices["features"] + 1, skillChoices["features"])
            end
        end
    end

    print("THC:: SKILLCHOICES::", json(skillChoices))
    return skillChoices
end

--- Add compensating feature entries for duplicate static skills
--- @param skillChoices table The aggregated skill choices
--- @param skills table The skills data from loadSkills()
local function addCompensatingFeatures(skillChoices, skills)
    -- Check if we already have a "Duplicate Skill" feature
    if skillChoices["features"] then
        for _, item in ipairs(skillChoices["features"]) do
            if item.name == "Duplicate Skill" then
                return
            end
        end
    end

    -- Count static skill occurrences across career, culture, class
    local staticCounts = {}
    for _, section in ipairs({"career", "culture", "class"}) do
        if skillChoices[section] then
            for _, item in ipairs(skillChoices[section]) do
                if item.type == "static" then
                    for _, skillId in ipairs(item.selected) do
                        staticCounts[skillId] = (staticCounts[skillId] or 0) + 1
                    end
                end
            end
        end
    end

    -- Find the first duplicate skill and add one compensating feature
    for skillId, count in pairs(staticCounts) do
        if count >= 2 then
            if not skillChoices["features"] then
                skillChoices["features"] = {}
            end
            local skillName = skills.lookup[skillId] or skillId
            skillChoices["features"][#skillChoices["features"] + 1] = {
                type = "choice",
                canDelete = true,
                numChoices = 1,
                selected = {},
                name = "Duplicate Skill",
                description = string.format("Duplicated %s skill - select an alternative.", skillName),
            }
            return
        end
    end
end

--- Validate and transform options
--- @param options table Table with data, options, and callback functions
--- @return table opts Modified options table
local function validateOptions(options)
    local opts = shallow_copy_list(options)

    if not opts.callbacks then opts.callbacks = {} end
    local confirmHandler = opts.callbacks.confirm
    local cancelHandler = opts.callbacks.cancel

    opts.callbacks = {
        confirmHandler = function(newSkills)
            if confirmHandler then
                confirmHandler(newSkills)
            end
        end,
        cancelHandler = function()
            if cancelHandler then
                cancelHandler()
            end
        end
    }

    return opts
end

--- @class CharacterSkillDialog
--- A dialog for editing skills in the context of a character sheet
CharacterSkillDialog = RegisterGameType("CharacterSkillDialog")

local dialogStyles = {
    {   -- Base
        selectors = {"skilldlg-base"},
        fontSize = 18,
        fontFace = "berling",
        color = Styles.textColor,
    },

    {   -- Dialog
        selectors = {"skilldlg-dialog", "skilldlg-base"},
        halign = "center",
        valign = "center",
        bgcolor = "#111111ff",
        borderWidth = 2,
        borderColor = Styles.textColor,
        bgimage = "panels/square.png",
        flow = "vertical",
        hpad = 8,
        vpad = 8,
    },

    {   -- Panel base
        selectors = {"skilldlg-panel", "skilldlg-base"},
        width = "100%",
        height = "auto",
        valign = "center",
    },
    {   -- Body Panel
        selectors = {"skilldlg-body", "skilldlg-panel", "skilldlg-base"},
        flow = "vertical",
    },
    {   -- Skill Section Panel
        selectors = {"skilldlg-section", "skilldlg-panel", "skilldlg-base"},
        flow = "vertical",
        vpad = 8,
    },

    {   -- Label
        selectors = {"skilldlg-label", "skilldlg-base"},
        height = "auto",
        bold = true,
    },
    {   -- Choice Description
        selectors = {"skilldlg-choicedescr", "skilldlg-label", "skilldlg-base"},
        height = "auto",
        fontSize = 12,
        minFontSize = 8,
        bold = false,
        vmargin = 6,
        hmargin = 2,
    },

    {   -- Dropdown
        selectors = {"skilldlg-dropdown", "skilldlg-base"},
        bgcolor = Styles.backgroundColor,
        borderWidth = 1,
        borderColor = Styles.textColor,
        height = 20,
        hmargin = 4,
        bold = false,
    },

    {   -- Button
        selectors = {"skilldlg-button", "skilldlg-base"},
        fontSize = 22,
        textAlignment = "center",
        bold = true,
        height = 35,
        cornerRadius = 4,
    },

    {   -- Duplicate flag
        selectors = {"dup-flag", "skilldlg-base"},
        bgimage = "icons/icon_app/icon_app_187.png",
        bgcolor = "#cc0000",
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
    },
}

--- Wrap a skill UI component with delete button and duplicate flag
--- @param skillId string The skill ID being displayed
--- @param item table The skill item data
--- @param uiComponent table The GUI component to wrap
--- @return table panel The wrapped panel
local function wrapDisplay(skillId, item, uiComponent)

    local deleteButton = item.canDelete and gui.DeleteItemButton{
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        hmargin = 2,
        click = function(element)
            local wrapper = element:FindParentWithClass("skilldlg-wrapper")
            if wrapper then
                wrapper:FireEvent("deleteSkill")
            end
            local controller = element:FindParentWithClass("skilldlg-dialog")
            if controller then
                controller:FireEvent("valueChanged")
            end
        end,
    } or nil

    local panel = gui.Panel{
        classes = {"skilldlg-wrapper", "skilldlg-panel", "skilldlg-base"},
        width = "100%",
        valign = "top",
        pad = 4,
        flow = "horizontal",
        data = {
            item = item,
            skillId = skillId,
            deleted = false,
        },

        deleteSkill = function(element)
            element.data.deleted = true
            element:SetClass("collapsed", true)
            local controller = element:FindParentWithClass("skilldlg-dialog")
            if controller then
                controller:FireEvent("valueChanged")
            end
            -- Check if parent panel should collapse
            local skillPanel = element:FindParentWithClass("skilldlg-panel")
            if skillPanel then
                skillPanel:FireEvent("checkEmpty")
            end
            if element.data.item.added then
                element:DestroySelf()
            end
        end,
        updateSkillId = function(element, newId)
            element.data.skillId = newId
        end,
        checkDups = function(element, dupGuids)
            local isDuplicate = dupGuids[element.data.skillId] == true
            local flags = element:GetChildrenWithClassRecursive("dup-flag")
            if flags then
                for _,flag in ipairs(flags) do
                    flag:SetClass("collapsed", not isDuplicate)
                end
            end
        end,

        uiComponent,
        deleteButton,
        gui.Panel{
            classes = {"dup-flag", "skilldlg-base", "collapsed"}
        },
    }
    return panel
end

--- Create display panels for static (non-editable) skills
--- @param item table The skill item with selected skills
--- @param skills table The skills data from loadSkills()
--- @return table|nil panels Array of wrapped label panels, or nil if empty
local function makeStaticSkillDisplay(item, skills)
    local panels = {}
    for _,skillId in ipairs(item.selected) do
        local panel = wrapDisplay(skillId, item,
            gui.Label{
                classes = {"skilldlg-label", "skilldlg-base"},
                text = skills.lookup[skillId],
                data = {
                    skillId = skillId,
                },
            }
        )
        panels[#panels + 1] = panel
    end
    return #panels > 0 and panels or nil
end

--- Create dropdown panels for skill choices
--- @param item table The skill choice item with categories and selection count
--- @param skills table The skills data from loadSkills()
--- @return table|nil panels Array of wrapped dropdown panels, or nil if empty
local function makeSkillDropdowns(item, skills)
    local panels = {}

    local skillOpts = {}
    if (item.individualSkills and next(item.individualSkills)) or (item.categories and next(item.categories)) then
        local includeSkills = {}
        if item.individualSkills then
            for k,_ in pairs(item.individualSkills) do
                includeSkills[k] = skills.lookup[k]
            end
        end
        if item.categories then
            for cat,_ in pairs(item.categories) do
                for k,_ in pairs(skills.categories[cat]) do
                    includeSkills[k] = skills.lookup[k]
                end
            end
        end
        for k,t in pairs(includeSkills) do
            skillOpts[#skillOpts + 1] = { id = k, text = t }
        end
        table.sort(skillOpts, function(a,b) return a.text < b.text end)
    else
        skillOpts = DeepCopy(skills.list)
    end

    print("THC:: ITEM::", json(item))
    local selected = item.selected or {}
    for i = 1, item.numChoices or 1 do
        local skillId = selected[i]
        local panel = wrapDisplay(skillId, item,
            gui.Dropdown{
                classes = {"skilldlg-dropdown", "skilldlg-base"},
                options = skillOpts,
                idChosen = skillId,
                fontSize = 14,
                textDefault = "Select a skill...",
                hasSearch = true,
                data = {
                    skillId = skillId,
                },
                change = function(element)
                    local newId = element.idChosen
                    if newId ~= element.data.skillId then
                        element.data.skillId = newId
                        local wrapper = element:FindParentWithClass("skilldlg-wrapper")
                        if wrapper then
                            wrapper:FireEvent("updateSkillId", newId)
                        end
                        local controller = element:FindParentWithClass("skilldlg-dialog")
                        if controller then
                            controller:FireEvent("valueChanged")
                        end
                    end
                end
            }
        )
        panels[#panels + 1] = panel
    end

    return #panels > 0 and panels or nil
end

--- Create the appropriate skill display based on item type
--- @param item table The skill item to display
--- @param skills table The skills data from loadSkills()
--- @return table|nil panels Array of skill display panels, or nil if empty
local function makeSkillDisplay(item, skills)
    if item.type == "static" then
        return makeStaticSkillDisplay(item, skills)
    else
        return makeSkillDropdowns(item, skills)
    end
end

--- Create a skill panel with label and skill controls
--- @param item table The skill item data
--- @param skills table The skills data from loadSkills()
--- @return table panel The GUI panel
local function makeSkillPanel(item, skills)
    local skillItems = makeSkillDisplay(item, skills)
    local children = {
        gui.Label {
            classes = {"skilldlg-choicedescr", "skilldlg-label", "skilldlg-base"},
            width = "90%",
            height = "auto",
            text = string.format("<b>%s:</b> %s", item.name, item.description)
        }
    }
    table.move(skillItems, 1, #skillItems, #children + 1, children)
    return gui.Panel{
        classes = {"skilldlg-panel", "skilldlg-base"},
        flow = "vertical",
        data = {
            item = item,
        },
        checkEmpty = function(element)
            local wrappers = element:GetChildrenWithClassRecursive("skilldlg-wrapper")
            if not wrappers then
                if item.added then
                    element:DestroySelf()
                else
                    element:SetClass("collapsed", true)
                end
                return
            end
            local allDeleted = true
            for _, w in ipairs(wrappers) do
                if not w.data.deleted then
                    allDeleted = false
                    break
                end
            end
            if allDeleted then
                if item.added then
                    element:DestroySelf()
                else
                    element:SetClass("collapsed", true)
                end
            end
        end,
        children = children,
    }
end

--- Format selected skills grouped by category for display
--- @param idsSelected table Map of skillId to selection count
--- @param skills table The skills data from loadSkills()
--- @return string text Formatted string with categories and skills
local function formatSelectedSkillsByCategory(idsSelected, skills)
    -- Build skillId -> category lookup from skills.list
    local skillToCategory = {}
    for _, entry in ipairs(skills.list) do
        skillToCategory[entry.id] = entry.category
    end

    -- Group selected skills by category
    local byCategory = {}
    for skillId, count in pairs(idsSelected) do
        local category = skillToCategory[skillId]
        if category then
            if not byCategory[category] then
                byCategory[category] = {}
            end
            byCategory[category][skillId] = count
        end
    end

    -- Sort categories alphabetically
    local sortedCategories = {}
    for category, _ in pairs(byCategory) do
        sortedCategories[#sortedCategories + 1] = category
    end
    table.sort(sortedCategories)

    -- Build output string
    local lines = {}
    for _, category in ipairs(sortedCategories) do
        local skillsInCat = byCategory[category]

        -- Get skill names with counts, sorted alphabetically
        local skillEntries = {}
        for skillId, count in pairs(skillsInCat) do
            local name = skills.lookup[skillId] or skillId
            local entry
            if count >= 2 then
                entry = string.format('%s <color=red>(x%d)</color>', name, count)
            else
                entry = name
            end
            skillEntries[#skillEntries + 1] = {name = name, text = entry}
        end
        table.sort(skillEntries, function(a, b) return a.name < b.name end)

        -- Build category line
        local skillTexts = {}
        for _, e in ipairs(skillEntries) do
            skillTexts[#skillTexts + 1] = e.text
        end
        local categoryDisplay = category:sub(1,1):upper() .. category:sub(2)
        local line = string.format("<b>%s:</b> %s\n", categoryDisplay, table.concat(skillTexts, ", "))
        lines[#lines + 1] = line
    end

    return table.concat(lines)
end

--- Assemble skill updates from dialog state for saving
--- @param element table The root dialog element
--- @return table results Contains levelChoices and features tables
local function assembleSkillUpdates(element)
    local results = {
        levelChoices = {},
        features = {},
    }

    local controls = element:GetChildrenWithClassRecursive("skilldlg-wrapper")
    if not controls then
        return results
    end

    local choicesByGuid = {}

    for _, c in ipairs(controls) do
        local item = c.data.item
        local skillsTable = (not c.data.deleted and c.data.skillId) and {[c.data.skillId] = true} or {}

        if item.canDelete then
            results.features[#results.features + 1] = {
                type = item.type,
                guid = item.guid,
                sourceGuid = item.sourceGuid,
                name = item.name,
                description = item.description,
                canDelete = item.canDelete,
                numChoices = item.numChoices,
                categories = item.categories,
                individualSkills = item.individualSkills,
                skills = skillsTable,
            }
        elseif item.guid then
            if not choicesByGuid[item.guid] then
                choicesByGuid[item.guid] = {}
            end
            if not c.data.deleted and c.data.skillId then
                choicesByGuid[item.guid][c.data.skillId] = true
            end
        end
    end

    for guid, skillsTable in pairs(choicesByGuid) do
        results.levelChoices[guid] = skillsTable
    end

    return results
end

--- Creates a character skill editor dialog
--- Designed to be used from the character sheet
--- @param options table Table with data, options, and callback functions
--- @return table|nil panel The GUI panel ready for AddChild
function CharacterSkillDialog.CreateAsChild(options)
    if not options then return end

    local token = CharacterSheet.instance and CharacterSheet.instance.data and CharacterSheet.instance.data.info.token
    if not token or not token.properties or not token.properties:IsHero() then return end

    local levelChoices = token.properties:GetLevelChoices()
    local selectedFeatures = token.properties:GetClassFeaturesAndChoicesWithDetails()
    local customFeatures = token.properties:try_get("characterFeatures", {})
    local skillChoices = aggregateSkillChoices(selectedFeatures, customFeatures, levelChoices)
    local skills = loadSkills()
    addCompensatingFeatures(skillChoices, skills)

    local opts = validateOptions(options)

    local resultPanel

    local headerPanel = gui.Panel{
        classes = {"skilldlg-panel", "skilldlg-base"},
        valign = "top",
        flow = "vertical",
        gui.Label{
            classes = {"skilldlg-label", "skilldlg-base"},
            text = "Manage Character Skills",
            fontSize = 24,
            width = "100%",
            height = 30,
            textAlignment = "center",
        },
        gui.Divider { width = "50%" },
    }

    local summaryPanel = gui.Panel{
        classes = {"skilldlg-body", "skilldlg-panel", "skilldlg-base"},
        height = 80,
        width = "100%",
        halign = "center",
        flow = "vertical",
        tmargin = 8,
        vscroll = true,
        gui.Label{
            classes = {"skilldlg-label", "skilldlg-base"},
            width = "90%",
            valign = "top",
            vpad = 8,
            bold = false,
            fontSize = 14,
            text = "calculating...",
            onSetSummary = function(element, summary)
                element.text = summary
            end,
        },
    }

    -- TODO: If we have identical static skills, add an extra skill in features
    -- if there isn't one already
    local skillSections = {}
    for id,content in pairs(skillChoices) do

        -- Innermost content - the name, description, and choices
        local skillPanels = {}
        for _,item in ipairs(content) do
            skillPanels[#skillPanels + 1] = makeSkillPanel(item, skills)
        end

        if #skillPanels then
            local sectionName = id:sub(1,1):upper() .. id:sub(2) .. " Skills"
            local children = {
                gui.Label {
                    classes = {"skilldlg-label", "skilldlg-base"},
                    text = sectionName,
                    width = "98%",
                    bgimage = true,
                    borderColor = Styles.textColor,
                    border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
                },
            }
            table.move(skillPanels, 1, #skillPanels, #children + 1, children)
            local section = gui.Panel{
                id = id .. "-skills",
                classes = {"skilldlg-section", "skilldlg-panel", "skilldlg-base"},
                valign = "top",
                addSkill = function(element)
                    if element.id == "features-skills" then
                        local item = {
                            type = "choice",
                            canDelete = true,
                            numChoices = 1,
                            selected = {},
                            name = "New Skill",
                            description = "Choose a new skill.",
                            added = true,
                        }
                        element:AddChild(makeSkillPanel(item, skills))
                        resultPanel:FireEvent("valueChanged")
                    end
                end,
                children = children,
            }
            skillSections[#skillSections + 1] = section
        end
        table.sort(skillSections, function(a,b) return a.id < b.id end)
    end

    local addButton = gui.PrettyButton{
        classes = {"skilldlg-button", "skilldlg-base"},
        width = "auto",
        halign = "left",
        tmargin = 12,
        hpad = 20,
        vpad = 4,
        text = "Add A Skill",
        fontSize = 12,
        cornerRadius = 0,
        click = function(element)
            resultPanel:FireEventTree("addSkill")
        end
    }
    skillSections[#skillSections + 1] = addButton

    local selectorPanel = gui.Panel{
        classes = {"skilldlg-body", "skilldlg-panel", "skilldlg-base"},
        height = "100%-90",
        width = "100%",
        halign = "left",
        tmargin = 8,
        vscroll = true,
        children = skillSections,
    }

    local bodyPanel = gui.Panel{
        classes = {"skilldlg-body", "skilldlg-panel", "skilldlg-base"},
        height = "100%-100,",
        flow = "vertical",
        valign = "center",
        summaryPanel,
        gui.Divider { width = "50%" },
        selectorPanel,
    }

    local footerPanel = gui.Panel{
        classes = {"skilldlg-panel", "skilldlg-base"},
        flow = "horizontal",
        valign = "bottom",
        gui.Button{
            classes = {"skilldlg-button", "skilldlg-base"},
            text = "Cancel",
            width = 120,
            halign = "center",
            click = function(element)
                resultPanel:FireEvent("escape")
            end,
        },
        gui.Button{
            classes = {"skilldlg-button", "skilldlg-base"},
            text = "Confirm",
            width = 120,
            halign = "center",
            click = function(element)
                resultPanel:FireEvent("confirm")
            end
        }
    }

    -- skills by catgory.
    resultPanel = gui.Panel {
        styles = dialogStyles,
        classes = {"skilldlg-dialog", "skilldlg-base"},
        width = 600,
        height = 800,
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,

        create = function(element)
            element:FireEvent("valueChanged")
        end,
        valueChanged = function(element)
            local idsSelected = {}
            local controls = element:GetChildrenWithClassRecursive("skilldlg-wrapper")
            if controls then
                for _,c in ipairs(controls) do
                    if not c.data.deleted and c.data.skillId then
                        local qty = idsSelected[c.data.skillId] or 0
                        idsSelected[c.data.skillId] = qty + 1
                    end
                end
                local summaryText = formatSelectedSkillsByCategory(idsSelected, skills)
                element:FireEventTree("onSetSummary", summaryText)
                for k,v in pairs(idsSelected) do
                    idsSelected[k] = (v >= 2) or nil
                end
                element:FireEventTree("checkDups", idsSelected)
            end
        end,
        close = function(element)
            resultPanel:DestroySelf()
        end,
        escape = function(element)
            opts.callbacks.cancelHandler()
            element:FireEvent("close")
        end,
        confirm = function(element)
            local results = assembleSkillUpdates(element)
            print("THC:: RESULTS::", json(results))
            -- opts.callbacks.confirmHandler(results)
            -- element:FireEvent("close")
        end,

        headerPanel,
        bodyPanel,
        footerPanel,
    }

    return resultPanel
end

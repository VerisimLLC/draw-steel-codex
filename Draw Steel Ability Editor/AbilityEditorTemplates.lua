local mod = dmhub.GetModLoading()

--[[
    ============================================================================
    Ability Templates & Entry Modal
    ============================================================================
    Provides:
    1. AbilityTemplate game type + compendium section for managing templates
    2. Ability source crawler for the "Duplicate Existing" path
    3. Entry modal UI shown on first edit of a new ability
]]

local COLORS = AbilityEditor.COLORS

-- Template categories for grouping in both the compendium editor and the
-- entry modal's "Start from Template" sub-view.
local TEMPLATE_CATEGORIES = {
    { id = "Attack",   label = "Attack" },
    { id = "Support",  label = "Support" },
    { id = "Control",  label = "Control" },
    { id = "Utility",  label = "Utility" },
    { id = "Monster",  label = "Monster" },
    { id = "General",  label = "General" },
}

-- ============================================================================
-- 1. AbilityTemplate game type
-- ============================================================================

AbilityTemplate = RegisterGameType("AbilityTemplate")
AbilityTemplate.tableName = "abilityTemplates"
AbilityTemplate.name = "New Template"
AbilityTemplate.description = ""
AbilityTemplate.category = "General"

function AbilityTemplate.CreateNew()
    local result = AbilityTemplate.new{
        name = "New Template",
        description = "",
        category = "General",
        ability = ActivatedAbility.Create{
            name = "New Template",
        },
    }
    -- Clear the _tmp_isNewAbility flag on the embedded ability so the entry
    -- modal does not fire when editing a template's ability.
    result.ability._tmp_isNewAbility = false
    return result
end

-- ============================================================================
-- 1b. Compendium panel for Ability Templates
-- ============================================================================

local function CreateAbilityTemplateEditor(tableName)
    local m_item = nil
    local m_key = nil

    local editPanel
    editPanel = gui.Panel{
        classes = {"hidden"},
        selfStyle = {
            flow = "vertical",
            height = "100%",
            width = "auto",
            vpad = 8,
            hpad = 12,
            borderBox = true,
        },

        change = function(element)
            if m_item ~= nil and m_key ~= nil then
                dmhub.SetAndUploadTableItem(tableName, m_item)
            end
        end,

        setdata = function(element, item, key)
            m_item = item
            m_key = key
            element:SetClass("hidden", item == nil)
            element:FireEventTree("refreshTemplate")
        end,

        -- Name
        gui.Panel{
            flow = "horizontal",
            width = 360,
            height = "auto",
            halign = "left",
            bmargin = 6,

            gui.Label{
                width = 90, height = "auto", fontSize = 14,
                color = "#cccccc", textAlignment = "left",
                valign = "center", text = "Name",
            },
            gui.Input{
                width = 240,
                fontSize = 14,
                refreshTemplate = function(element)
                    if m_item ~= nil then
                        element.text = m_item.name
                    end
                end,
                change = function(element)
                    if m_item ~= nil then
                        m_item.name = element.text
                        editPanel:FireEvent("change")
                    end
                end,
            },
        },

        -- Description
        gui.Panel{
            flow = "horizontal",
            width = 360,
            height = "auto",
            halign = "left",
            bmargin = 6,

            gui.Label{
                width = 90, height = "auto", fontSize = 14,
                color = "#cccccc", textAlignment = "left",
                valign = "center", text = "Description",
            },
            gui.Input{
                width = 240,
                height = 60,
                fontSize = 14,
                multiline = true,
                refreshTemplate = function(element)
                    if m_item ~= nil then
                        element.text = m_item.description
                    end
                end,
                change = function(element)
                    if m_item ~= nil then
                        m_item.description = element.text
                        editPanel:FireEvent("change")
                    end
                end,
            },
        },

        -- Category
        gui.Panel{
            flow = "horizontal",
            width = 360,
            height = "auto",
            halign = "left",
            bmargin = 6,

            gui.Label{
                width = 90, height = "auto", fontSize = 14,
                color = "#cccccc", textAlignment = "left",
                valign = "center", text = "Category",
            },
            gui.Dropdown{
                width = 240,
                refreshTemplate = function(element)
                    if m_item ~= nil then
                        local options = {}
                        for _, cat in ipairs(TEMPLATE_CATEGORIES) do
                            options[#options + 1] = {
                                id = cat.id,
                                text = cat.label,
                            }
                        end
                        element.options = options
                        element.idChosen = m_item.category or "General"
                    end
                end,
                change = function(element)
                    if m_item ~= nil then
                        m_item.category = element.idChosen
                        editPanel:FireEvent("change")
                    end
                end,
            },
        },

        -- Edit Ability button
        gui.PrettyButton{
            text = "Edit Ability",
            width = 160,
            height = 36,
            fontSize = 16,
            halign = "left",
            tmargin = 8,
            click = function(element)
                if m_item ~= nil then
                    if m_item:try_get("ability") == nil then
                        m_item.ability = ActivatedAbility.Create{
                            name = m_item.name,
                        }
                        m_item.ability._tmp_isNewAbility = false
                    end
                    element.root:AddChild(
                        m_item.ability:ShowEditActivatedAbilityDialog{
                            destroy = function()
                                editPanel:FireEvent("change")
                            end,
                        }
                    )
                end
            end,
        },
    }

    return editPanel
end

local function ShowAbilityTemplatesPanel(parentPanel)
    local tableName = AbilityTemplate.tableName
    local dataItems = {}
    local editPanel = CreateAbilityTemplateEditor(tableName)

    local itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local children = {}
            local dataTable = dmhub.GetTable(tableName) or {}
            local newDataItems = {}

            for k, item in pairs(dataTable) do
                newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = tableName,
                    key = k,
                    select = element.aliveTime > 0.2,
                    click = function()
                        editPanel:SetClass("hidden", false)
                        editPanel:FireEventTree("setdata", dataTable[k], k)
                    end,
                }

                local desc = item.name
                if desc == nil or desc == "" then
                    desc = "(unnamed)"
                end
                newDataItems[k].text = desc
                children[#children + 1] = newDataItems[k]
            end

            table.sort(children, function(a, b)
                return a.text < b.text
            end)

            dataItems = newDataItems
            element.children = children
        end,
    }

    itemsListPanel:FireEvent("refreshAssets")

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = "vertical",
            height = "100%",
            width = "auto",
        },

        itemsListPanel,
        Compendium.AddButton{
            click = function(element)
                local newData = AbilityTemplate.CreateNew()
                dmhub.SetAndUploadTableItem(tableName, newData)
            end,
        },
    }

    parentPanel.children = {leftPanel, editPanel}
end

Compendium.Register{
    section = "Rules",
    text = "Ability Templates",
    contentType = "abilityTemplates",
    click = function(contentPanel)
        ShowAbilityTemplatesPanel(contentPanel)
    end,
}

-- ============================================================================
-- 2. Ability source crawler
-- ============================================================================

-- Helper: extract abilities from a feature's modifiers list.
-- Skips abilities with hidden = true.
local function _extractFromModifiers(modifiers, sourceName, group, results)
    if modifiers == nil then return end
    for _, m in ipairs(modifiers) do
        local ability = m:try_get("activatedAbility")
        if ability ~= nil and not ability:try_get("hidden", false) then
            results[#results + 1] = {
                ability = ability,
                name = ability:try_get("name", "Unnamed"),
                source = sourceName,
                group = group,
            }
        end
        local triggered = m:try_get("triggeredAbility")
        if triggered ~= nil and not triggered:try_get("hidden", false) then
            results[#results + 1] = {
                ability = triggered,
                name = triggered:try_get("name", "Unnamed"),
                source = sourceName,
                group = group,
            }
        end
    end
end

-- Helper: extract abilities from a features list. Recurses into choice
-- options which can themselves contain nested features (e.g. Conduit
-- domain choices contain sub-features with their own abilities).
local _extractFromFeatures
_extractFromFeatures = function(features, sourceName, group, results)
    if features == nil then return end
    for _, feat in ipairs(features) do
        pcall(function()
            _extractFromModifiers(
                feat:try_get("modifiers"), sourceName, group, results)
            -- Choice-based features store options with their own modifiers
            -- and potentially nested features.
            local options = feat:try_get("options")
            if options ~= nil then
                for _, opt in ipairs(options) do
                    _extractFromModifiers(
                        opt:try_get("modifiers"), sourceName, group, results)
                    -- Recurse into nested features (e.g. domain choices)
                    _extractFromFeatures(
                        opt:try_get("features"), sourceName, group, results)
                end
            end
        end)
    end
end

-- Crawl a category and return {sourceName -> {ability entries}} map.
-- Each category has its own access pattern. Results are grouped by source
-- so the UI can show Source -> Abilities hierarchy.
local CATEGORY_CRAWLERS = {}

CATEGORY_CRAWLERS["Classes"] = function()
    local sourceMap = {}
    local dataTable = dmhub.GetTable("classes")
    if dataTable == nil then return sourceMap end
    for k, class in pairs(dataTable) do
        pcall(function()
            if class:try_get("hidden") then return end
            if class:try_get("isSubclass") then return end
            local name = class:try_get("name", "Unknown Class")
            local entries = {}
            local levels = class:try_get("levels")
            if levels ~= nil then
                for levelKey, level in pairs(levels) do
                    _extractFromFeatures(
                        level:try_get("features"), name, name, entries)
                end
            end
            if #entries > 0 then
                sourceMap[name] = entries
            end
        end)
    end
    return sourceMap
end

CATEGORY_CRAWLERS["Subclasses"] = function()
    local sourceMap = {}
    local dataTable = dmhub.GetTable("subclasses")
    if dataTable == nil then return sourceMap end
    -- Build lookup of parent class names so subclasses are grouped
    -- under their class: "Fury" -> [Reaver entries, Stormwight entries].
    -- The linking field is `primaryClassId` (not `parentClass`).
    local classTable = dmhub.GetTable("classes") or {}
    for k, sub in pairs(dataTable) do
        pcall(function()
            if sub:try_get("hidden") then return end
            local subName = sub:try_get("name", "Unknown Subclass")
            local parentId = sub:try_get("primaryClassId", "")
            local parentClass = classTable[parentId]
            -- Skip subclasses whose parent class is missing or hidden.
            if parentClass == nil then return end
            if parentClass:try_get("hidden", false) then return end
            local parentName = parentClass:try_get("name", "Unknown")
            local entries = {}
            local levels = sub:try_get("levels")
            if levels ~= nil then
                for levelKey, level in pairs(levels) do
                    _extractFromFeatures(
                        level:try_get("features"), subName, parentName, entries)
                end
            end
            if #entries > 0 then
                -- Group under parent class name so the browse UI shows
                -- Class -> Subclass -> Abilities. Multiple subclasses
                -- of the same class merge into one source map entry;
                -- each ability's `source` field carries the subclass
                -- name so showSubSources can drill down further.
                if sourceMap[parentName] == nil then
                    sourceMap[parentName] = {}
                end
                for _, entry in ipairs(entries) do
                    sourceMap[parentName][#sourceMap[parentName] + 1] = entry
                end
            end
        end)
    end
    return sourceMap
end

CATEGORY_CRAWLERS["Monsters"] = function()
    -- Crawl the bestiary tree (assets:GetMonsterNode) rather than the
    -- MonsterGroup table. Each monster's `groupid` links to a MonsterGroup
    -- entry which provides the category name (e.g., "Angulotls", "Devils").
    local sourceMap = {}
    local mgTable = dmhub.GetTable("MonsterGroup") or {}

    -- Pre-build set of hidden group IDs so we can skip them cheaply.
    local hiddenGroups = {}
    for gid, g in pairs(mgTable) do
        if g:try_get("hidden", false) then
            hiddenGroups[gid] = true
        end
    end

    -- Track seen ability GUIDs to deduplicate across monster variants
    -- (e.g. multiple Arixx stat blocks sharing the same ability objects).
    local seenGuids = {}

    local function crawlBestiaryNode(node)
        if node == nil then return end
        pcall(function()
            local children = node.children
            if children == nil then return end
            for _, child in ipairs(children) do
                pcall(function()
                    if child.monster ~= nil then
                        local props = child.monster.properties
                        if props ~= nil then
                            -- Skip hidden monsters.
                            if props:try_get("hidden", false) then return end

                            local mtype = props:try_get("monster_type", "Unknown")
                            local groupid = props:try_get("groupid", "none")

                            -- Skip monsters whose group is hidden (retired
                            -- content like Ankheg).
                            if hiddenGroups[groupid] then return end

                            -- Skip monsters with no valid group assignment.
                            -- These are orphan/draft entries (e.g. an old
                            -- ungrouped Arixx that would steal GUIDs from
                            -- the properly grouped variants).
                            if groupid == "none" or mgTable[groupid] == nil then
                                return
                            end

                            local groupName = mgTable[groupid]:try_get("name", "Uncategorized")
                            local innate = props:try_get("innateActivatedAbilities")
                            if innate ~= nil and #innate > 0 then
                                if sourceMap[groupName] == nil then
                                    sourceMap[groupName] = {}
                                end
                                for _, ability in ipairs(innate) do
                                    -- Skip hidden abilities.
                                    if not ability:try_get("hidden", false) then
                                        -- Deduplicate by GUID so multiple
                                        -- variants of the same monster don't
                                        -- produce duplicate entries.
                                        local guid = ability:try_get("guid", "")
                                        if guid == "" or not seenGuids[guid] then
                                            if guid ~= "" then
                                                seenGuids[guid] = true
                                            end
                                            sourceMap[groupName][#sourceMap[groupName] + 1] = {
                                                ability = ability,
                                                name = ability:try_get("name", "Unnamed"),
                                                source = mtype,
                                                group = groupName,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                    -- Recurse into sub-folders
                    crawlBestiaryNode(child)
                end)
            end
        end)
    end

    local rootNode = assets:GetMonsterNode("")
    crawlBestiaryNode(rootNode)
    return sourceMap
end

CATEGORY_CRAWLERS["Titles"] = function()
    local sourceMap = {}
    local dataTable = dmhub.GetTable("titles")
    if dataTable == nil then return sourceMap end
    local allEntries = {}
    for k, title in pairs(dataTable) do
        pcall(function()
            if title:try_get("hidden") then return end
            local titleName = title:try_get("name", "Unknown Title")
            local modInfo = title:try_get("modifierInfo")
            if modInfo ~= nil then
                local features = modInfo.features
                _extractFromFeatures(
                    features, titleName, "Titles", allEntries)
            end
        end)
    end
    if #allEntries > 0 then
        sourceMap["Titles"] = allEntries
    end
    return sourceMap
end

CATEGORY_CRAWLERS["Complications"] = function()
    local sourceMap = {}
    local dataTable = dmhub.GetTable("complications")
    if dataTable == nil then return sourceMap end
    local allEntries = {}
    for k, comp in pairs(dataTable) do
        pcall(function()
            if comp:try_get("hidden") then return end
            local compName = comp:try_get("name", "Unknown")
            local modInfo = comp:try_get("modifierInfo")
            if modInfo ~= nil then
                local features = modInfo.features
                _extractFromFeatures(
                    features, compName, "Complications", allEntries)
            end
        end)
    end
    if #allEntries > 0 then
        sourceMap["Complications"] = allEntries
    end
    return sourceMap
end

CATEGORY_CRAWLERS["Global Rules"] = function()
    local sourceMap = {}
    local dataTable = dmhub.GetTable("globalRuleMods")
    if dataTable == nil then return sourceMap end
    for k, ruleMod in pairs(dataTable) do
        pcall(function()
            if ruleMod:try_get("hidden") then return end
            local name = ruleMod:try_get("name", "Unknown")
            local entries = {}
            -- Global rule mods store features like classes/titles
            local modInfo = ruleMod:try_get("modifierInfo")
            if modInfo ~= nil then
                local features = modInfo.features
                _extractFromFeatures(features, name, name, entries)
            end
            -- Also try levels (some rule mods use the class pattern)
            local levels = ruleMod:try_get("levels")
            if levels ~= nil then
                for levelKey, level in pairs(levels) do
                    _extractFromFeatures(
                        level:try_get("features"), name, name, entries)
                end
            end
            if #entries > 0 then
                sourceMap[name] = entries
            end
        end)
    end
    return sourceMap
end

-- Ordered list of browse categories shown in the duplicate UI.
local DUPLICATE_CATEGORIES = {
    { id = "Classes",       label = "Classes" },
    { id = "Subclasses",    label = "Subclasses" },
    { id = "Monsters",      label = "Monsters" },
    { id = "Titles",        label = "Titles" },
    { id = "Complications", label = "Complications" },
    { id = "Global Rules",  label = "Global Rules" },
}

-- Persistent crawler cache. Populated lazily per-category on first access,
-- then reused across modal opens. Pre-warmed in the background on module
-- load so the Duplicate Existing path feels instant even on first use.
-- Invalidated on compendium changes via monitorAssets (see below).
AbilityEditor._duplicateCache = AbilityEditor._duplicateCache or {}

-- Crawl a single category, caching the result.
local function _crawlCategory(categoryId)
    if AbilityEditor._duplicateCache[categoryId] == nil then
        local crawler = CATEGORY_CRAWLERS[categoryId]
        if crawler ~= nil then
            AbilityEditor._duplicateCache[categoryId] = crawler()
        else
            AbilityEditor._duplicateCache[categoryId] = {}
        end
    end
    return AbilityEditor._duplicateCache[categoryId]
end

-- Invalidate the cache (called when compendium content changes).
function AbilityEditor._invalidateDuplicateCache()
    AbilityEditor._duplicateCache = {}
end

-- Crawl ALL categories (used by search). Returns a flat list.
local function _crawlAllFlat()
    local results = {}
    for _, catDef in ipairs(DUPLICATE_CATEGORIES) do
        local sourceMap = _crawlCategory(catDef.id)
        for sourceName, entries in pairs(sourceMap) do
            for _, entry in ipairs(entries) do
                results[#results + 1] = entry
            end
        end
    end
    table.sort(results, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    return results
end

-- Legacy API kept for external callers.
function AbilityEditor._crawlAllAbilities()
    return _crawlAllFlat()
end

-- ============================================================================
-- 3. Entry modal UI
-- ============================================================================

-- Apply a source ability's fields onto the target ability (in-place mutation).
-- Preserves the target's guid so it stays unique in whatever table owns it.
-- Resets implementation status so the new ability starts as unimplemented.
local function _applyAbilityFields(target, source, isDuplicate)
    local copy = DeepCopy(source)
    local savedGuid = target:try_get("guid")
    local savedDomains = target:try_get("domains")

    -- Fields that should NOT transfer from the source -- they describe the
    -- source's identity or implementation state, not its game design.
    local SKIP_FIELDS = {
        guid = true,
        domains = true,
        implementation = true,
        implementationNotes = true,
        sourceReference = true,
    }

    for k, v in pairs(copy) do
        if not SKIP_FIELDS[k] then
            target[k] = v
        end
    end

    -- Restore guid and domains
    if savedGuid ~= nil then
        target.guid = savedGuid
    end
    if savedDomains ~= nil then
        target.domains = savedDomains
    end

    -- Regenerate GUIDs on copied behaviors so two abilities created from
    -- the same source don't share identical behavior GUIDs.
    local behaviors = target:try_get("behaviors")
    if behaviors ~= nil then
        for _, b in ipairs(behaviors) do
            if b:try_get("guid") ~= nil then
                b.guid = dmhub.GenerateGuid()
            end
        end
    end

    if isDuplicate then
        target.name = target.name .. " - Copy"
    end
end

-- ---- Path button ----

local function _makePathButton(title, description, onClick)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        hpad = 16,
        vpad = 16,
        bmargin = 6,
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 4,
        borderBox = true,

        press = onClick,

        styles = {
            {
                selectors = {"hover"},
                borderColor = COLORS.GOLD_BRIGHT,
                brightness = 1.2,
                transitionTime = 0.15,
            },
        },

        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 20,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            text = title,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            color = COLORS.GRAY,
            textAlignment = "left",
            text = description,
        },
    }
end

-- Shared back-link label.
local function _makeBackLabel(text, onClick)
    return gui.Label{
        width = "auto",
        height = "auto",
        fontSize = 13,
        color = COLORS.GOLD_DIM,
        textAlignment = "left",
        bmargin = 4,
        text = "< " .. text,
        press = onClick,
    }
end

-- ---- Template list sub-view ----

local function _buildTemplateListView(ability, rootPanel, onComplete, rebuildEditor)
    local templatesTable = dmhub.GetTable(AbilityTemplate.tableName) or {}

    -- Group templates by category
    local groups = {}
    for _, catDef in ipairs(TEMPLATE_CATEGORIES) do
        groups[catDef.id] = {label = catDef.label, entries = {}}
    end

    for k, template in pairs(templatesTable) do
        if not template:try_get("hidden") then
            local cat = template:try_get("category", "General")
            if groups[cat] == nil then
                groups[cat] = {label = cat, entries = {}}
            end
            groups[cat].entries[#groups[cat].entries + 1] = template
        end
    end

    local children = {}

    -- Back button
    children[#children + 1] = _makeBackLabel("Back", function()
        onComplete(nil)
    end)

    local hasAny = false
    for _, catDef in ipairs(TEMPLATE_CATEGORIES) do
        local group = groups[catDef.id]
        if group ~= nil and #group.entries > 0 then
            hasAny = true
            -- Sort entries by name
            table.sort(group.entries, function(a, b)
                return (a.name or "") < (b.name or "")
            end)

            -- Group heading
            children[#children + 1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                bold = true,
                color = COLORS.GOLD_DIM,
                textAlignment = "left",
                bmargin = 2,
                tmargin = 2,
                text = group.label,
            }

            -- Template cards
            for _, template in ipairs(group.entries) do
                local t = template
                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    hpad = 8,
                    vpad = 5,
                    bmargin = 2,
                    bgimage = "panels/square.png",
                    bgcolor = COLORS.PANEL_BG,
                    borderWidth = 1,
                    borderColor = COLORS.GOLD,
                    cornerRadius = 3,
                    borderBox = true,

                    press = function()
                        local templateAbility = t:try_get("ability")
                        if templateAbility ~= nil then
                            _applyAbilityFields(ability, templateAbility, false)
                        end
                        gui.CloseModal()
                        if templateAbility ~= nil and rebuildEditor ~= nil then
                            rebuildEditor()
                        end
                    end,

                    gui.Label{
                        width = "100%",
                        height = "auto",
                        fontSize = 14,
                        bold = true,
                        color = COLORS.CREAM_BRIGHT,
                        textAlignment = "left",
                        text = t.name or "(unnamed)",
                    },
                    gui.Label{
                        width = "100%",
                        height = "auto",
                        fontSize = 12,
                        italics = true,
                        color = COLORS.GRAY,
                        textAlignment = "left",
                        text = t.description or "",
                    },
                }
            end
        end
    end

    if not hasAny then
        children[#children + 1] = gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            italics = true,
            color = COLORS.GRAY,
            textAlignment = "center",
            vmargin = 24,
            text = "No templates found. Add templates in the Compendium > Ability Templates section.",
        }
    end

    return children
end

-- ---- Duplicate sub-view: hierarchical browse + search ----
--
-- Drill-down: Categories -> Sources -> Abilities.
-- Search crawls all categories on first keystroke and shows flat results.

-- Shared helper: make an ability result card that applies and closes.
local function _makeAbilityCard(entry, ability, rootPanel, rebuildEditor)
    local e = entry
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 8,
        vpad = 5,
        bmargin = 3,
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        borderBox = true,

        press = function()
            _applyAbilityFields(ability, e.ability, true)
            gui.CloseModal()
            if rebuildEditor ~= nil then
                rebuildEditor()
            end
        end,

        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.CREAM_BRIGHT,
            textAlignment = "left",
            text = e.name,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 11,
            color = COLORS.GRAY,
            textAlignment = "left",
            text = e.source or "",
        },
    }
end

-- (_makeBackLabel moved above _buildTemplateListView)

local function _buildDuplicateListView(ability, rootPanel, onComplete, rebuildEditor)
    -- The contentPanel whose children are swapped between browse levels.
    -- All show* functions use setContent() instead of setting children
    -- directly so items always stack at the top (auto-height wrapper
    -- prevents the scroll container from distributing children vertically).
    local contentPanel = nil

    local function setContent(children)
        contentPanel.children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                bgcolor = "clear",
                children = children,
            },
        }
    end

    -- Shared helper: a clickable row with a name and a count badge.
    local function _makeSourceRow(label, count, onClick)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            hpad = 8,
            vpad = 6,
            bmargin = 3,
            bgimage = "panels/square.png",
            bgcolor = COLORS.PANEL_BG,
            borderWidth = 1,
            borderColor = COLORS.GOLD,
            cornerRadius = 3,
            borderBox = true,
            press = onClick,

            gui.Label{
                width = "100%-30",
                height = "auto",
                fontSize = 13,
                bold = true,
                color = COLORS.CREAM_BRIGHT,
                textAlignment = "left",
                text = label,
            },
            gui.Label{
                width = 30,
                height = "auto",
                fontSize = 11,
                color = COLORS.GRAY,
                textAlignment = "right",
                text = tostring(count),
            },
        }
    end

    -- ---- Ability list for a single source ----
    local function showAbilityList(heading, entries, backLabel, goBack)
        local children = {}
        children[#children + 1] = _makeBackLabel(backLabel, goBack)

        children[#children + 1] = gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.GOLD_DIM,
            textAlignment = "left",
            bmargin = 4,
            text = heading,
        }

        table.sort(entries, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(entries) do
            children[#children + 1] = _makeAbilityCard(entry, ability, rootPanel, rebuildEditor)
        end

        setContent(children)
    end

    -- ---- Sub-source list (e.g., individual monsters within a group) ----
    -- Takes a flat entry list, sub-groups by entry.source, and shows each
    -- sub-source as a clickable row that drills into its abilities.
    local function showSubSources(catId, groupName, entries, goBack)
        -- Sub-group by source (individual creature/entry name)
        local subMap = {}
        local subOrder = {}
        for _, entry in ipairs(entries) do
            local src = entry.source or groupName
            if subMap[src] == nil then
                subMap[src] = {}
                subOrder[#subOrder + 1] = src
            end
            subMap[src][#subMap[src] + 1] = entry
        end
        table.sort(subOrder)

        -- Single sub-source: skip straight to abilities.
        if #subOrder == 1 then
            showAbilityList(subOrder[1], subMap[subOrder[1]], groupName, goBack)
            return
        end

        local children = {}
        children[#children + 1] = _makeBackLabel(catId, goBack)

        children[#children + 1] = gui.Label{
            width = "100%",
            height = "auto",
            fontSize = 14,
            bold = true,
            color = COLORS.GOLD_DIM,
            textAlignment = "left",
            bmargin = 4,
            text = groupName,
        }

        for _, subName in ipairs(subOrder) do
            local subEntries = subMap[subName]
            local sn = subName
            children[#children + 1] = _makeSourceRow(sn, #subEntries, function()
                showAbilityList(sn, subEntries, groupName,
                    function() showSubSources(catId, groupName, entries, goBack) end)
            end)
        end

        setContent(children)
    end

    -- Categories that need the extra sub-source drill-down level.
    local SUBSOURCE_CATEGORIES = {
        Monsters = true,
    }

    -- Flat categories show all sources as section headers with their
    -- sub-entries (grouped by entry.source) as clickable buttons inline,
    -- rather than requiring drill-down through a source list first.
    -- Used for Subclasses: Class headers with subclass buttons underneath.
    local FLAT_CATEGORIES = {
        Subclasses = true,
    }

    -- ---- Flat source display ----
    -- Shows all sources as section headers with sub-entries grouped by
    -- entry.source as clickable buttons. Used for Subclasses (Class
    -- headers with subclass buttons underneath).
    local function showFlat(catId, showCategories)
        local sourceMap = _crawlCategory(catId)

        local sourceNames = {}
        for name, _ in pairs(sourceMap) do
            sourceNames[#sourceNames + 1] = name
        end
        table.sort(sourceNames)

        local children = {}
        children[#children + 1] = _makeBackLabel("Categories", showCategories)

        for _, sourceName in ipairs(sourceNames) do
            local entries = sourceMap[sourceName]
            -- Group entries by entry.source (e.g. subclass name)
            local subMap = {}
            local subOrder = {}
            for _, entry in ipairs(entries) do
                local src = entry.source or sourceName
                if subMap[src] == nil then
                    subMap[src] = {}
                    subOrder[#subOrder + 1] = src
                end
                subMap[src][#subMap[src] + 1] = entry
            end
            table.sort(subOrder)

            -- Class header
            children[#children + 1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                bold = true,
                color = COLORS.GOLD_DIM,
                textAlignment = "left",
                tmargin = 6,
                bmargin = 2,
                text = sourceName,
            }

            -- Subclass buttons
            for _, subName in ipairs(subOrder) do
                local subEntries = subMap[subName]
                local sn = subName
                children[#children + 1] = _makeSourceRow(sn, #subEntries, function()
                    showAbilityList(sn, subEntries, catId,
                        function() showFlat(catId, showCategories) end)
                end)
            end
        end

        if #sourceNames == 0 then
            children[#children + 1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                italics = true,
                color = COLORS.GRAY,
                textAlignment = "center",
                vmargin = 24,
                text = "No abilities found in " .. catId,
            }
        end

        setContent(children)
    end

    -- ---- Source list within a category ----
    local function showSources(catId, showCategories)
        -- Flat categories render inline headers + buttons on one screen.
        if FLAT_CATEGORIES[catId] then
            showFlat(catId, showCategories)
            return
        end

        local sourceMap = _crawlCategory(catId)
        local useSubSources = SUBSOURCE_CATEGORIES[catId] or false

        -- Sort source names
        local sourceNames = {}
        for name, _ in pairs(sourceMap) do
            sourceNames[#sourceNames + 1] = name
        end
        table.sort(sourceNames)

        -- Single source: skip to next level. Back goes to categories
        -- (not back to showSources, which would re-skip in a loop).
        if #sourceNames == 1 then
            local name = sourceNames[1]
            if useSubSources then
                showSubSources(catId, name, sourceMap[name], showCategories)
            else
                showAbilityList(name, sourceMap[name],
                    "Categories", showCategories)
            end
            return
        end

        local children = {}
        children[#children + 1] = _makeBackLabel("Categories", showCategories)

        if #sourceNames == 0 then
            children[#children + 1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 14,
                italics = true,
                color = COLORS.GRAY,
                textAlignment = "center",
                vmargin = 24,
                text = "No abilities found in " .. catId,
            }
        end

        for _, name in ipairs(sourceNames) do
            local entries = sourceMap[name]
            local n = name
            children[#children + 1] = _makeSourceRow(n, #entries, function()
                if useSubSources then
                    showSubSources(catId, n, entries,
                        function() showSources(catId, showCategories) end)
                else
                    showAbilityList(n, entries, catId,
                        function() showSources(catId, showCategories) end)
                end
            end)
        end

        setContent(children)
    end

    -- ---- Level 1: Category list ----
    local function showCategories()
        local children = {}
        children[#children + 1] = _makeBackLabel("Back", function()
            onComplete(nil)
        end)

        for _, catDef in ipairs(DUPLICATE_CATEGORIES) do
            local cid = catDef.id
            children[#children + 1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                hpad = 8,
                vpad = 7,
                bmargin = 3,
                bgimage = "panels/square.png",
                bgcolor = COLORS.PANEL_BG,
                borderWidth = 1,
                borderColor = COLORS.GOLD,
                cornerRadius = 3,
                borderBox = true,

                press = function()
                    showSources(cid, showCategories)
                end,

                gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 14,
                    bold = true,
                    color = COLORS.CREAM_BRIGHT,
                    textAlignment = "left",
                    text = catDef.label,
                },
            }
        end

        setContent(children)
    end

    -- ---- Search ----
    local allAbilitiesFlat = nil  -- lazy, crawled on first search keystroke

    local searchInput = nil
    searchInput = gui.Input{
        width = "100%",
        height = 30,
        placeholderText = "Search all abilities...",
        bgimage = "panels/square.png",
        bgcolor = COLORS.PANEL_BG,
        borderWidth = 1,
        borderColor = COLORS.GOLD,
        cornerRadius = 3,
        hpad = 8,
        vpad = 4,
        borderBox = true,
        fontSize = 14,
        color = COLORS.CREAM_BRIGHT,
        bmargin = 8,
        textAlignment = "left",

        editlag = 0.2,
        edit = function(element)
            local rawQuery = element.text or ""
            if rawQuery == "" then
                -- Return to category browse
                showCategories()
                return
            end

            -- Lazy crawl all on first search
            if allAbilitiesFlat == nil then
                allAbilitiesFlat = _crawlAllFlat()
            end

            local query = string.lower(rawQuery)
            local filtered = {}
            for _, entry in ipairs(allAbilitiesFlat) do
                local nameMatch = string.find(
                    string.lower(entry.name or ""), query, 1, true)
                local sourceMatch = string.find(
                    string.lower(entry.source or ""), query, 1, true)
                local groupMatch = string.find(
                    string.lower(entry.group or ""), query, 1, true)
                if nameMatch or sourceMatch or groupMatch then
                    filtered[#filtered + 1] = entry
                end
            end

            -- Group results by source
            local groupOrder = {}
            local groupMap = {}
            for _, entry in ipairs(filtered) do
                local g = entry.group or "Other"
                if groupMap[g] == nil then
                    groupMap[g] = {}
                    groupOrder[#groupOrder + 1] = g
                end
                groupMap[g][#groupMap[g] + 1] = entry
            end
            table.sort(groupOrder)

            local children = {}
            for _, groupName in ipairs(groupOrder) do
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 16,
                    bold = true,
                    color = COLORS.GOLD_DIM,
                    textAlignment = "left",
                    bmargin = 4,
                    tmargin = 4,
                    text = groupName,
                }
                for _, entry in ipairs(groupMap[groupName]) do
                    children[#children + 1] = _makeAbilityCard(
                        entry, ability, rootPanel, rebuildEditor)
                end
            end

            if #filtered == 0 then
                children[#children + 1] = gui.Label{
                    width = "100%",
                    height = "auto",
                    fontSize = 14,
                    italics = true,
                    color = COLORS.GRAY,
                    textAlignment = "center",
                    vmargin = 24,
                    text = "No abilities match \"" .. rawQuery .. "\"",
                }
            end

            setContent(children)
        end,
    }

    contentPanel = gui.Panel{
        width = "100%",
        height = "100%-46",
        flow = "vertical",
        vscroll = true,
        bgcolor = "clear",
        halign = "left",
        valign = "top",
    }

    -- Start at category level
    showCategories()

    return {searchInput, contentPanel}
end

-- ---- Main entry modal ----

function AbilityEditor.ShowEntryModal(ability, rootPanel, rebuildEditor)
    -- Invalidate the duplicate crawler cache so any compendium changes
    -- since the last open are picked up.
    AbilityEditor._invalidateDuplicateCache()

    -- The content panel whose children get swapped between the main view
    -- and the template/duplicate sub-views.
    local contentPanel = nil
    local innerPanel = nil

    local function showMainView()
        local buttons = {}

        buttons[#buttons + 1] = _makePathButton(
            "Start from Template",
            "Choose from pre-built ability archetypes",
            function()
                -- Switch to template list sub-view
                local templateChildren = _buildTemplateListView(
                    ability, rootPanel,
                    function(result)
                        if result == nil then
                            showMainView()
                        end
                    end,
                    rebuildEditor
                )
                innerPanel.children = templateChildren
            end
        )

        buttons[#buttons + 1] = _makePathButton(
            "Duplicate Existing",
            "Copy an ability from monsters, classes, or other content",
            function()
                -- Switch to duplicate list sub-view
                local dupChildren = _buildDuplicateListView(
                    ability, rootPanel,
                    function(result)
                        if result == nil then
                            showMainView()
                        end
                    end,
                    rebuildEditor
                )
                innerPanel.children = dupChildren
            end
        )

        buttons[#buttons + 1] = _makePathButton(
            "Blank",
            "Start with an empty ability",
            function()
                gui.CloseModal()
            end
        )

        -- Wrap in a centering container so the buttons sit in the
        -- vertical middle of the modal rather than sticking to the top.
        innerPanel.children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "center",
                valign = "center",
                bgcolor = "clear",
                children = buttons,
            },
        }
    end

    -- Inner panel that holds the actual content. height = "auto" ensures
    -- children stack tightly at the top instead of being distributed
    -- across the scroll viewport.
    innerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgcolor = "clear",
        halign = "left",
        valign = "top",
    }

    contentPanel = gui.Panel{
        width = "100%",
        height = "100%-36",
        vscroll = true,
        bgcolor = "clear",
        halign = "left",
        valign = "top",
        children = {innerPanel},
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        styles = {Styles.Default, Styles.Panel},
        width = 460,
        height = 500,
        flow = "vertical",
        pad = 14,
        borderBox = true,
        halign = "center",
        valign = "center",
        fontFace = "Berling",

        children = {
            -- Title
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 22,
                bold = true,
                color = COLORS.GOLD_BRIGHT,
                textAlignment = "left",
                bmargin = 12,
                text = "Create New Ability",
            },

            contentPanel,

            -- Close button
            gui.CloseButton{
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },
    }

    showMainView()
    gui.ShowModal(dialogPanel)
end

-- ============================================================================
-- 4. Background pre-warm & cache invalidation
-- ============================================================================

-- Pre-warm the crawler cache in the background so the first Duplicate
-- Existing click is instant. Each category is crawled on a separate
-- deferred frame to avoid a single long stall.
local _warmIndex = 1
local function _warmNextCategory()
    if mod.unloaded then return end
    if _warmIndex > #DUPLICATE_CATEGORIES then return end
    local catId = DUPLICATE_CATEGORIES[_warmIndex].id
    _crawlCategory(catId)
    _warmIndex = _warmIndex + 1
    dmhub.Schedule(0, _warmNextCategory)
end
-- Kick off after a short delay so module loading finishes first.
dmhub.Schedule(0.5, _warmNextCategory)

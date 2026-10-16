--[[
    Choices Detail

    Catch-all section for any CharacterChoice-derived features that aren't
    covered by the per-source tabs (Ancestry, Class, Career, etc.). Currently
    used by the monster builder path; can be extended to heroes later.
]]
--- @class CBChoicesDetail: GameType
--- @field new fun(o?: table): CBChoicesDetail
CBChoicesDetail = RegisterGameType("CBChoicesDetail")

local SEL = CharacterBuilder.SELECTOR
local _getHero = CharacterBuilder._getHero
local _getCreature = CharacterBuilder._getCreature
local _safeGet = CharacterBuilder._safeGet
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

local mod = dmhub.GetModLoading()

local SELECTOR = SEL.CHOICES
local INITIAL_CATEGORY = "overview"
local CHOICES_SENTINEL = "choices"

function CBChoicesDetail._navPanel()

    local overviewButton = _makeDetailNavButton(SELECTOR, {
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
        refreshBuilderState = function(element, state)
            element:FireEvent("setAvailable", true)
            -- No page picked yet (fresh builder state) means Overview.
            element:FireEvent("setSelected", (state:Get(SELECTOR .. ".category.selectedId") or INITIAL_CATEGORY) == element.data.category)
        end,
    })

    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "detail-nav-panel"},
        vscroll = true,

        create = function(element)
            _fireControllerEvent("updateState", {
                key = SELECTOR .. ".category.selectedId",
                value = INITIAL_CATEGORY,
            })
        end,

        registerFeatureButton = function(element, button)
            element:AddChild(button)
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
    }
end

local function _trim(s)
    return (string.match(s, "^%s*(.-)%s*$"))
end

--- Split off a trailing "Codex Note" paragraph ("{<B> Codex Note: </B> ...}"
--- or "**Codex Note:** ...") so it can render as a callout.
--- @param text string
--- @return string main Description without the note.
--- @return string|nil note The note body, or nil when there is none.
local function _splitCodexNote(text)
    local markerPos = string.find(text, "Codex Note", 1, true)
    if markerPos == nil then
        return text, nil
    end

    -- The note runs from the start of the paragraph holding the marker.
    local paraStart = 1
    local searchPos = 1
    while true do
        local nl = string.find(text, "\n", searchPos, true)
        if nl == nil or nl >= markerPos then break end
        paraStart = nl + 1
        searchPos = nl + 1
    end

    local main = _trim(string.sub(text, 1, paraStart - 1))
    local note = _trim(string.sub(text, paraStart))
    note = string.gsub(note, "^{", "")
    note = string.gsub(note, "}$", "")
    note = string.gsub(note, "^%s*<[bB]>%s*Codex Note%s*:?%s*</[bB]>%s*:?", "")
    note = string.gsub(note, "^%s*%*%*Codex Note%s*:?%s*%*%*%s*:?", "")
    note = string.gsub(note, "^%s*Codex Note%s*:", "")
    note = _trim(note)
    if note == "" then
        return text, nil
    end
    return main, note
end

--- Codex-logo callout that sets implementation notes apart from rules text.
--- @param note string
--- @return Panel
local function _codexNoteCallout(note)
    return gui.Panel{
        classes = {"panel", "blockQuote", "codex-note"},
        width = "100%-64",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        gui.Panel{
            width = 24,
            height = 24,
            valign = "top",
            tmargin = 8,
            bgimage = "ui-icons/codex-logo.png",
            bgcolor = "white",
        },
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "codex-note-text"},
            width = "100%-24",
            vpad = 6,
            markdown = true,
            text = "<b>Codex Note:</b> " .. note,
        },
    }
end

--- Build a single overview entry for a feature that grants choices: its
--- title and (when present) its description text.
--- @param title string|nil Omitted when the feature name is already the section header.
--- @param description string|nil
--- @return Panel
local function _featureOverviewEntry(title, description)
    local children = {}

    if title ~= nil and title ~= "" then
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "info", "overview", "detail-header"},
            text = title,
        }
    end

    local note = nil
    if description ~= nil and description ~= "" then
        description, note = _splitCodexNote(description)
    end

    if description ~= nil and description ~= "" then
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            markdown = true,
            text = description,
        }
    end

    if note ~= nil then
        children[#children+1] = _codexNoteCallout(note)
    end

    return gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels", "seamless"},
        children = children,
    }
end

--- Return the cached features that actually grant choices, in sorted order.
--- The cache can hold features whose choices are accounted for elsewhere
--- (or who grant none); those report zero choices and are filtered out here.
--- @param featureCache CBFeatureCache|nil
--- @return CBFeatureWrapper[]
local function _featuresWithChoices(featureCache)
    local result = {}
    if featureCache == nil then return result end
    for _,item in ipairs(featureCache:GetSortedFeatures()) do
        local feature = featureCache:GetFeature(item.guid)
        if feature ~= nil and feature:GetNumChoices() > 0 then
            result[#result+1] = feature
        end
    end
    return result
end

--- Resolve the title for the Choices overview header.
---
--- Choice features are usually sub-choices housed under a single parent --
--- a feat, template, or monster group (e.g. four "Choice of X Traits"
--- features all granted by an "Animal Traits" template). When every
--- choice feature traces back to the same parent, that parent's name
--- titles the section. A lone choice feature with no parent titles the
--- section with its own name. Anything else falls back to "CHOICES".
--- Also returns that shared parent, if any.
--- @param features CBFeatureWrapper[] The choice-granting features (from _featuresWithChoices).
--- @param creature creature|nil
--- @return string title
--- @return table|nil parent
local function _choicesTitle(features, creature)
    if #features == 0 then
        return "CHOICES"
    end

    -- Map each choice feature's guid to the parent that houses it. The
    -- builder's own choice enumeration carries the originating feat /
    -- template / monster group alongside each flattened choice feature.
    local parents = {}
    if creature ~= nil and creature.GetBuilderChoiceFeatures ~= nil then
        for _,entry in ipairs(creature:GetBuilderChoiceFeatures()) do
            local feature = entry.feature
            local parent = entry.feat or entry.monsterGroup
            if feature ~= nil and parent ~= nil then
                parents[feature.guid] = parent
            end
        end
    end

    -- Every choice feature must resolve to the same owner for the header to
    -- adopt its name. A choice's owner is its parent when it has one, else
    -- the choice itself; compare owners by object identity.
    local ownerKey = nil
    local ownerName = nil
    local ownerParent = nil
    for _,feature in ipairs(features) do
        local parent = parents[feature:GetGuid()]
        local key, name
        if parent ~= nil then
            key = parent
            name = _safeGet(parent, "name", "")
        else
            key = feature:GetGuid()
            name = feature:GetName()
        end

        if ownerKey == nil then
            ownerKey = key
            ownerName = name
            ownerParent = parent
        elseif ownerKey ~= key then
            return "CHOICES", nil
        end
    end

    if ownerName == nil or ownerName == "" then
        return "CHOICES", nil
    end
    return ownerName, ownerParent
end

--- Rulebook-style sidebar box: rounded frame, centered title, diamonds.
--- @param title string
--- @param text string
--- @return Panel
local function _sidebarBox(title, text)
    local main, note = _splitCodexNote(text)
    local children = {
        gui.Panel{
            classes = {"builder-sidebar-ornament"},
            floating = true,
            valign = "top",
            y = -18,
            rotate = 45,
        },
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "builder-sidebar-title"},
            text = title,
        },
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            markdown = true,
            text = main,
        },
    }
    -- A trailing Codex Note paragraph becomes a callout inside the box.
    if note ~= nil then
        children[#children+1] = _codexNoteCallout(note)
    end
    children[#children+1] = gui.Panel{
        classes = {"builder-sidebar-ornament"},
        floating = true,
        valign = "bottom",
        y = 18,
        rotate = 45,
    }
    return gui.Panel{
        classes = {"builder-sidebar"},
        children = children,
    }
end

function CBChoicesDetail._overviewPanel()

    -- Section header. Its text is set by featureListPanel's refreshBuilderState
    -- (via _choicesTitle) so the title and the feature list stay in sync.
    local headerLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview", "header"},
        text = "CHOICES",
    }

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels", "seamless"},
        headerLabel,
    }

    -- Built on demand only when no features actually grant choices yet.
    -- Created lazily so an unused instance is never left orphaned.
    local function makeEmptyLabel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "detail-overview-labels", "seamless"},
            gui.Label{
                classes = {"builder-base", "label", "info", "overview"},
                vpad = 6,
                markdown = true,
                text = CharacterBuilder.STRINGS.CHOICES.INTRO,
            },
        }
    end

    -- Lists the features granting additional choices, showing each feature's
    -- title and description rather than generic boilerplate text.
    local featureListPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        width = "100%",
        height = "auto",
        flow = "vertical",

        data = {
            -- Signature of the currently-rendered feature set; used to skip
            -- rebuilding the child panels when nothing relevant changed.
            signature = nil,
        },

        refreshBuilderState = function(element, state)
            local featureCache = state:Get(SELECTOR .. ".featureCache")
            local features = _featuresWithChoices(featureCache)

            -- Keep the section header in sync with the feature set: a shared
            -- parent feature's name when there is one, else "CHOICES".
            local title, parent = _choicesTitle(features, _getCreature())

            local sigParts = {}
            for _,feature in ipairs(features) do
                sigParts[#sigParts+1] = feature:GetGuid()
            end
            if parent ~= nil then
                sigParts[#sigParts+1] = tostring(_safeGet(parent, "description", ""))
                sigParts[#sigParts+1] = tostring(_safeGet(parent, "builderSidebar", ""))
            end
            local signature = table.concat(sigParts, "|")
            if signature == element.data.signature then return end
            element.data.signature = signature

            -- A parent can title this column itself (builderOverviewTitle).
            local overviewTitle = parent and _safeGet(parent, "builderOverviewTitle", "") or ""
            headerLabel.text = (type(overviewTitle) == "string" and overviewTitle ~= "") and overviewTitle or title

            -- A single feature's name already titles the section, so omit
            -- the redundant per-entry title in that case.
            local single = #features == 1

            local children = {}

            -- The shared parent's rules text goes under the title.
            if parent ~= nil then
                children[#children+1] = _featureOverviewEntry(nil, _safeGet(parent, "description", ""))
            end
            -- A showcase-style parent gives each choice its own page, so the
            -- choices aren't summarised again here.
            local showcase = parent ~= nil and _safeGet(parent, "builderArtStyle", "") == "showcase"
            if not showcase then
                for _,feature in ipairs(features) do
                    local title = nil
                    if not single then
                        title = feature:GetName()
                    end
                    children[#children+1] = _featureOverviewEntry(title, feature:GetDescription())
                end
            end
            -- In showcase style the parent's sidebar box closes the overview.
            local sidebar = parent ~= nil and showcase and _safeGet(parent, "builderSidebar", "") or ""
            if parent ~= nil and type(sidebar) == "string" and sidebar ~= "" then
                children[#children+1] = gui.Panel{
                    width = "100%-24",
                    height = "auto",
                    halign = "center",
                    vmargin = 24,
                    _sidebarBox(_safeGet(parent, "builderSidebarTitle", ""), sidebar),
                }
            end

            if #children == 0 then
                children = {makeEmptyLabel()}
            end

            element.children = children
        end,
    }

    return gui.Panel{
        id = "choicesOverviewPanel",
        -- Solid backing (no gradient bands); tmargin aligns with the nav.
        classes = {"choicesOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "solid-bg", "border", "collapsed"},
        valign = "top",
        tmargin = 20,
        height = "100%-24",

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local visible = (state:Get(SELECTOR .. ".category.selectedId") or INITIAL_CATEGORY) == element.data.category
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            height = "100%-40",
            tmargin = 32,
            valign = "top",
            vscroll = true,
            -- One shared backing so gaps between entries match the entries.
            gui.Panel{
                classes = {"builder-base", "panel-base", "choices-overview-body"},
                nameLabel,
                featureListPanel,
            },
        }
    }
end

function CBChoicesDetail._detailPanel()

    local overviewPanel = CBChoicesDetail._overviewPanel()

    return gui.Panel{
        id = "choicesDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "choicesDetailPanel"},

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
    }
end

--- A data field that must be a non-empty string, else nil.
local function _stringField(obj, name)
    local value = obj ~= nil and _safeGet(obj, name, nil) or nil
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

--- What the showcase page (art with text laid over it) shows for the current
--- nav category, or nil to use the plain lore/art columns instead.
---   Overview: the shared parent, when it sets builderArtStyle = "showcase".
---   A choice with builderShowcase = true: the picked option (raceid/builderArt
---   and builderSummary), or the choice itself before anything is picked.
---   A choice with builderArt: that art plus its builderIntro/builderSidebar.
---   Any other choice in a showcase-style parent: the parent's art.
--- @param state table Builder state.
--- @return {image: string|nil, title: string, body: string, sidebarTitle: string|nil, sidebar: string|nil}|nil
local function _showcaseSource(state)
    local categoryId = state:Get(SELECTOR .. ".category.selectedId") or INITIAL_CATEGORY
    local featureCache = state:Get(SELECTOR .. ".featureCache")
    if featureCache == nil then return nil end

    if categoryId == INITIAL_CATEGORY then
        local _, parent = _choicesTitle(_featuresWithChoices(featureCache), _getCreature())
        if parent == nil or _stringField(parent, "builderArtStyle") ~= "showcase" then return nil end
        return {
            image = _stringField(parent, "builderArt"),
            title = _stringField(parent, "builderIntroTitle") or _safeGet(parent, "name", ""),
            body = _stringField(parent, "builderIntro") or "",
        }
    end

    local cached = featureCache:GetFeature(categoryId)
    if cached == nil then return nil end
    local choice = cached:GetFeature()

    if _safeGet(choice, "builderShowcase", false) == true then
        local selectedId = cached:GetSelected()[1]
        local wrapper = selectedId and cached:GetOption(selectedId)
        local option = wrapper and wrapper:GetOption()
        if option == nil then
            -- Nothing picked yet: the parent's art and the title, like the other pages.
            local _, parent = _choicesTitle(_featuresWithChoices(featureCache), _getCreature())
            local art = _stringField(choice, "builderArt") or _stringField(parent, "builderArt")
            return { image = art, title = cached:GetName(), body = "" }
        end
        local raceid = _stringField(option, "raceid")
        local race = raceid and dmhub.GetTable(Race.tableName)[raceid]
        return {
            image = (race and race.portraitid) or _stringField(option, "builderArt"),
            title = _safeGet(option, "name", cached:GetName()),
            body = _stringField(option, "builderSummary") or "",
        }
    end

    local art = _stringField(choice, "builderArt")
    if art == nil then
        -- No art of its own: in a showcase-style parent, reuse the parent's art so
        -- every page of that builder shares one layout.
        local _, parent = _choicesTitle(_featuresWithChoices(featureCache), _getCreature())
        if parent == nil or _stringField(parent, "builderArtStyle") ~= "showcase" then return nil end
        -- Title only: the choice's rules text already heads the list beside it.
        return { image = _stringField(parent, "builderArt"), title = cached:GetName(), body = "" }
    end
    return {
        image = art,
        title = _stringField(choice, "builderIntroTitle") or cached:GetName(),
        body = _stringField(choice, "builderIntro") or "",
        sidebarTitle = _stringField(choice, "builderSidebarTitle"),
        sidebar = _stringField(choice, "builderSidebar"),
    }
end


--- Intro text and sidebar tip from the shared parent's optional data fields
--- builderIntroTitle/builderIntro and builderSidebarTitle/builderSidebar.
--- @return Panel
function CBChoicesDetail._lorePanel()
    local introTitle = gui.Label{
        classes = {"builder-base", "label", "info", "overview", "detail-header"},
        vpad = 6,
    }
    local introText = gui.Label{
        classes = {"builder-base", "label", "info", "overview"},
        vpad = 6,
        markdown = true,
    }
    local introPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels", "lore-box"},
        -- detail-overview-labels bottom-aligns by default.
        valign = "top",
        introTitle,
        introText,
    }
    local sidebarSlot = gui.Panel{
        width = "100%-4",
        height = "auto",
        halign = "center",
        valign = "top",
        tmargin = 20,
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base", "choices-lore-panel", "collapsed"},
        vscroll = true,
        data = {
            signature = nil,
        },

        refreshBuilderState = function(element, state)
            -- The showcase page takes this column while it is up.
            if _showcaseSource(state) ~= nil then
                element:SetClass("collapsed", true)
                element.data.signature = nil
                return
            end
            local features = _featuresWithChoices(state:Get(SELECTOR .. ".featureCache"))
            local _, parent = _choicesTitle(features, _getCreature())
            local function field(name)
                local value = parent and _safeGet(parent, name, "") or ""
                return type(value) == "string" and value or ""
            end
            local iTitle, iText = field("builderIntroTitle"), field("builderIntro")
            local sTitle, sText = field("builderSidebarTitle"), field("builderSidebar")

            local signature = table.concat({iTitle, iText, sTitle, sText}, "\n")
            if signature == element.data.signature then return end
            element.data.signature = signature

            element:SetClass("collapsed", iText == "" and sText == "")
            introPanel:SetClass("collapsed", iText == "")
            introTitle.text = iTitle
            introTitle:SetClass("collapsed", iTitle == "")
            introText.text = iText
            if sText ~= "" then
                sidebarSlot.children = {_sidebarBox(sTitle, sText)}
            else
                sidebarSlot.children = {}
            end
        end,

        introPanel,
        sidebarSlot,
    }
end

--- The shared parent's builderArt image at its own proportions.
--- @return Panel
function CBChoicesDetail._artPanel()
    local image = gui.Panel{
        classes = {"builder-base", "panel-base", "choices-art-image"},
        autosizeimage = true,
        bgcolor = "white",
    }

    -- "Animal 1 EV: 14 (+2 EV)": the sheet's EV, with the amount over base EV in red.
    local evLabel = gui.Label{
        classes = {"builder-base", "label", "choices-art-ev"},
        text = "",
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base", "choices-art-panel", "collapsed"},
        data = {
            art = nil,
        },

        refreshBuilderState = function(element, state)
            local creature = _getCreature()
            local evText = nil
            if creature ~= nil and creature:IsMonster() then
                local ev = round(creature:EV())
                local added = ev - round(creature:BaseEV())
                --_getToken's @return names an undeclared LuaCharacterToken; it is a CharacterToken.
                local token = CharacterBuilder._getToken() --[[@as CharacterToken?]]
                local name = token and token.name or ""
                if name == "" then
                    name = creature:try_get("monster_type", "")
                end
                evText = string.format("%s EV: %d", name, ev)
                if added > 0 then
                    evText = string.format("%s <color=@danger>(+%d EV)</color>", evText, added)
                end
            end
            evLabel:SetClass("collapsed", evText == nil)
            evLabel.text = ThemeEngine.ResolveTokens(evText or "")

            local features = _featuresWithChoices(state:Get(SELECTOR .. ".featureCache"))
            local _, parent = _choicesTitle(features, creature)
            local art = parent and _safeGet(parent, "builderArt", nil) or nil
            if type(art) ~= "string" or art == "" or _showcaseSource(state) ~= nil then
                art = nil
            end
            if art == element.data.art then return end
            element.data.art = art

            element:SetClass("collapsed", art == nil)
            if art ~= nil then
                image.bgimage = art
            end
        end,

        image,
        evLabel,
    }
end

--- Hero-ancestry-style page for a showcase choice: the picked option's art
--- behind its name and a summary of what it changes. Option data fields:
--- raceid (use that ancestry's portrait) or builderArt, and builderSummary.
--- @return Panel
function CBChoicesDetail._showcasePanel()
    local headerLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview", "header"},
    }
    local bodyLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview"},
        vpad = 6,
        markdown = true,
    }
    -- Codex Note callout and sidebar box, rebuilt when the source changes.
    local extrasPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        flow = "vertical",
    }

    local art = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-panel", "border"},
        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            height = "100%-40",
            bmargin = 32,
            valign = "bottom",
            vscroll = true,
            -- Pushes the text down so the top of the art stays clear.
            gui.Panel{
                classes = {"builder-base", "panel-base", "container"},
                width = "50%",
                height = "66%",
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "detail-overview-labels"},
                headerLabel,
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "detail-overview-labels"},
                bodyLabel,
            },
            extrasPanel,
        },
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base", "choices-showcase-panel", "collapsed"},
        data = {
            signature = nil,
        },

        refreshBuilderState = function(element, state)
            local source = _showcaseSource(state)
            element:SetClass("collapsed", source == nil)
            if source == nil then
                element.data.signature = nil
                return
            end

            local signature = table.concat({source.title, source.body, tostring(source.image),
                source.sidebarTitle or "", source.sidebar or ""}, "\n")
            if signature == element.data.signature then return end
            element.data.signature = signature

            local body, note = _splitCodexNote(source.body)
            headerLabel.text = source.title
            bodyLabel.text = body
            bodyLabel:SetClass("collapsed", body == "")

            local extras = {}
            if note ~= nil then
                extras[#extras+1] = _codexNoteCallout(note)
            end
            if source.sidebar ~= nil then
                extras[#extras+1] = gui.Panel{
                    width = "100%-4",
                    height = "auto",
                    halign = "center",
                    vmargin = 24,
                    _sidebarBox(source.sidebarTitle or "", source.sidebar),
                }
            end
            extrasPanel.children = extras
            extrasPanel:SetClass("collapsed", #extras == 0)

            art.bgimage = source.image or "panels/square.png"
            art:SetClass("solid-bg", source.image == nil)
        end,

        art,
    }
end

function CBChoicesDetail.CreatePanel()

    local showcasePanel = CBChoicesDetail._showcasePanel()
    local lorePanel = CBChoicesDetail._lorePanel()
    local artPanel = CBChoicesDetail._artPanel()
    local navPanel = CBChoicesDetail._navPanel()
    local detailPanel = CBChoicesDetail._detailPanel()

    return gui.Panel{
        id = "choicesPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "choicesPanel"},
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

            for id,_ in pairs(element.data.features) do
                element.data.features[id] = false
            end

            local featureCache = state:Get(SELECTOR .. ".featureCache")
            local features = featureCache and featureCache:GetSortedFeatures() or {}
            for _,f in ipairs(features) do
                local featureId = f.guid
                local feature = featureCache:GetFeature(featureId)
                if feature then
                    if element.data.features[featureId] == nil then
                        local featureRegistry = CharacterBuilder._makeFeatureRegistry{
                            feature = feature,
                            selector = SELECTOR,
                            selectedId = CHOICES_SENTINEL,
                            getSelected = function(hero)
                                return CHOICES_SENTINEL
                            end,
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

            for id,active in pairs(element.data.features) do
                if active == false then
                    navPanel:FireEvent("destroyFeature", id)
                    detailPanel:FireEvent("destroyFeature", id)
                    element.data.features[id] = nil
                end
            end
        end,

        navPanel,
        showcasePanel,
        lorePanel,
        artPanel,
        detailPanel,
    }
end

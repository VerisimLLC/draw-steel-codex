local mod = dmhub.GetModLoading()

----------------------------------------------------------------------
-- HEROIC TESTS
--
-- A Heroic Test is one skill test prepped as a first-class journal
-- document: a title, a difficulty, setup prose, suggested
-- characteristics/skills, and the outcome for each power roll tier.
-- docType "heroictest" is a BEAT, so it sequences on the Run panel and
-- appears as a Flow node alongside montages and negotiations.
--
-- It deliberately introduces NO new roll mechanism. The one play action
-- hands off to the same "Request Rolls" panel the journal's power-roll
-- island already uses (see MarkdownDocument.lua PowerRollDisplay), which
-- also means the optional 4th "critical" tier flows through for free.
--
-- The generic tier text below mirrors the presets already shipped at
-- MarkdownDocument.lua g_hardwiredPowerTableList (and the compendium
-- "Tests" power roll group). It is core rules vocabulary, NOT book
-- content -- no shipped code here may reference licensed book content.
----------------------------------------------------------------------

--Power roll tier ranges. Rules constants, spelled out rather than derived
--so the editor reads the way the book does.
local TIER_RANGES = { "<=11", "12-16", "17+" }
--"Critical" matches the wording the Request Rolls dialog uses for the same row
--(DSRequestRollsDialog.lua tierLabels), so a Director sees one name per concept
--across the click. The <= ranges stay terse to fit the caption column.
local CRITICAL_RANGE = "Critical"
local CRITICAL_LABEL = "Success with Reward"
local CRITICAL_PRESET = "You succeed on the task with a reward."

--Difficulty drives the tier LABELS and whether a critical tier exists.
--Easy tests have no critical tier: their third tier is already the reward
--outcome. (Verified against the source: of 212 tests, exactly the 153
--medium and hard ones carry a natural 19-20 result.)
local g_difficulties = {
    easy = {
        id = "easy",
        text = "Easy",
        critical = false,
        labels = { "Success with Consequence", "Success", "Success with Reward" },
        presets = {
            "You succeed on the task and incur a consequence.",
            "You succeed on the task.",
            "You succeed on the task with a reward.",
        },
    },
    medium = {
        id = "medium",
        text = "Medium",
        critical = true,
        labels = { "Failure", "Success with Consequence", "Success" },
        presets = {
            "You fail the task.",
            "You succeed on the task and incur a consequence.",
            "You succeed on the task.",
        },
    },
    hard = {
        id = "hard",
        text = "Hard",
        critical = true,
        labels = { "Failure with Consequence", "Failure", "Success" },
        presets = {
            "You fail the task and incur a consequence.",
            "You fail the task.",
            "You succeed on the task.",
        },
    },
}

local g_difficultyOrder = { "easy", "medium", "hard" }

local g_difficultyDropdownOptions = {}
for _, id in ipairs(g_difficultyOrder) do
    g_difficultyDropdownOptions[#g_difficultyDropdownOptions + 1] =
        { id = id, text = g_difficulties[id].text }
end

---@class HeroicTestDocument:CustomDocument
---@field summary string Setup prose: what the hero is attempting.
---@field difficulty string "easy" | "medium" | "hard"
---@field characteristics table<string,boolean> Suggested characteristics (a SET).
---@field skills table<string,boolean> Suggested skills (a SET).
---@field tiers table<number,string> Outcome text for tiers 1-3.
---@field criticalTier string Outcome text for a natural 19-20. Medium/hard only.
HeroicTestDocument = RegisterGameType("HeroicTestDocument", "CustomDocument")
HeroicTestDocument.docType = "heroictest"  --pins the semantic type (see DocumentSystem.lua)
HeroicTestDocument.summary = ""
HeroicTestDocument.difficulty = "medium"
HeroicTestDocument.criticalTier = ""
--Table-valued fields are deliberately NOT declared at type level: a shared
--default table would be mutated across every instance. CreateNew always
--supplies fresh ones, and EnsureTables backfills any document that predates
--a field. The document does its own scrolling in EditPanel.
HeroicTestDocument.vscroll = false

--Give this instance its own tables before anything mutates them. Reads use
--try_get, which sees only the instance's raw fields -- exactly what we want
--here, since a fallback table returned from try_get would be thrown away.
function HeroicTestDocument:EnsureTables()
    if self:try_get("tiers") == nil then
        self.tiers = { "", "", "" }
    end
    if self:try_get("characteristics") == nil then
        self.characteristics = {}
    end
    if self:try_get("skills") == nil then
        self.skills = {}
    end
end

--Never nil: an unknown or unset difficulty reads as medium.
function HeroicTestDocument:DifficultyInfo()
    return g_difficulties[self:try_get("difficulty", "medium")] or g_difficulties.medium
end

function HeroicTestDocument:HasCriticalTier()
    return self:DifficultyInfo().critical
end

--True if `text` is still one of the canned presets for this tier slot (under
--ANY difficulty), i.e. text the Director has not personalised. Used so that
--switching difficulty relabels and re-prefills the rows without ever
--clobbering something they actually wrote.
local function IsPresetTierText(index, text)
    if text == nil or text == "" then
        return true
    end
    if index == nil then
        return text == CRITICAL_PRESET
    end
    for _, id in ipairs(g_difficultyOrder) do
        if g_difficulties[id].presets[index] == text then
            return true
        end
    end
    return false
end

--Switch difficulty, carrying any bespoke tier text across and refreshing the
--rest from the new difficulty's presets.
function HeroicTestDocument:SetDifficulty(difficultyId)
    if g_difficulties[difficultyId] == nil then
        return
    end
    self:EnsureTables()
    self.difficulty = difficultyId
    local info = g_difficulties[difficultyId]
    for i = 1, #info.presets do
        if IsPresetTierText(i, self.tiers[i]) then
            self.tiers[i] = info.presets[i]
        end
    end
    if info.critical then
        if IsPresetTierText(nil, self:try_get("criticalTier", "")) then
            self.criticalTier = CRITICAL_PRESET
        end
    end
end

--The tier list to hand to PowerRollTable.Create: three tiers, plus the
--critical tier when this difficulty has one and it has been filled in.
function HeroicTestDocument:PowerRollTiers()
    self:EnsureTables()
    local result = {}
    for i = 1, #TIER_RANGES do
        result[i] = self.tiers[i] or ""
    end
    local critical = self:try_get("criticalTier", "")
    if self:HasCriticalTier() and critical ~= "" then
        result[#result + 1] = critical
    end
    return result
end

--Suggested characteristics, in the game's canonical characteristic order.
function HeroicTestDocument:CharacteristicNames()
    self:EnsureTables()
    local keys = table.keys(self.characteristics)
    table.sort(keys, function(a, b)
        return creature.attributesInfo[a].order < creature.attributesInfo[b].order
    end)
    local result = {}
    for _, k in ipairs(keys) do
        result[#result + 1] = creature.attributesInfo[k].description
    end
    return result
end

function HeroicTestDocument:SkillNames()
    self:EnsureTables()
    local result = {}
    for k, _ in pairs(self.skills) do
        local skillInfo = Skill.SkillsById[k]
        if skillInfo then
            result[#result + 1] = skillInfo.name
        end
    end
    table.sort(result)
    return result
end

--Push the test to the party. This is the same call the power-roll island
--makes (MarkdownDocument.lua PowerRollDisplay): characteristics go as a SET
--keyed by characteristic id, skills as a LIST -- the Request Rolls dialog
--reads args.characteristics[id] and table.list_to_set(args.skills).
function HeroicTestDocument:RequestRoll()
    self:EnsureTables()
    LaunchablePanel.LaunchPanelByName("Request Rolls", {
        title = self.description,
        powerRollTable = PowerRollTable.Create {
            tiers = self:PowerRollTiers(),
        },
        characteristics = self.characteristics,
        skills = table.set_to_list(self.skills),
    })
end

--Range + outcome-label caption for one tier row. `index` nil = the critical row.
local function TierLabelText(doc, index)
    if index == nil then
        return string.format("%s  %s", CRITICAL_RANGE, CRITICAL_LABEL)
    end
    return string.format("%s  %s", TIER_RANGES[index], doc:DifficultyInfo().labels[index])
end

--"Suggested Characteristics/Skills" prose. Empty string when the Director has
--named neither (the source book deliberately leaves the characteristic open).
local function SuggestedText(doc)
    local lines = {}
    local characteristics = doc:CharacteristicNames()
    local skills = doc:SkillNames()
    if #characteristics > 0 then
        lines[#lines + 1] = string.format("*Suggested Characteristics:* %s.",
            table.concat(characteristics, ", "))
    end
    if #skills > 0 then
        lines[#lines + 1] = string.format("*Suggested Skills:* %s.",
            table.concat(skills, ", "))
    end
    return table.concat(lines, "\n")
end

--One tier row caption, shared by the display and the editor. It answers to BOTH
--refresh events on purpose: the display side broadcasts "savedoc", the editor
--broadcasts "refreshDifficulty" (in the editor, "savedoc" means upload, so the
--caption must not depend on it). The text is also set at construction so the
--caption is never blank before the first broadcast.
local function TierRowLabel(doc, index)
    local function Sync(element)
        element.text = TierLabelText(doc, index)
    end
    return gui.Label {
        classes = { "bold" },
        width = 190,
        height = "auto",
        halign = "left",
        valign = "top",
        textAlignment = "topleft",
        text = TierLabelText(doc, index),
        savedoc = Sync,
        refreshDifficulty = Sync,
    }
end

function HeroicTestDocument:OutcomesDisplay()
    self:EnsureTables()

    --Horizontal-flow children need an explicit halign in this engine, or they
    --drift off the left edge (see UI_BEST_PRACTICES / engine layout notes).
    local rows = {}
    for i = 1, #TIER_RANGES do
        rows[#rows + 1] = gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 2,
            TierRowLabel(self, i),
            gui.Label {
                width = "100%-190",
                height = "auto",
                halign = "left",
                valign = "top",
                textAlignment = "topleft",
                markdown = true,
                text = self.tiers[i] or "",
                savedoc = function(element)
                    element.text = self.tiers[i] or ""
                end,
            },
        }
    end

    --The critical row is present only for difficulties that have one.
    rows[#rows + 1] = gui.Panel {
        classes = { cond(not self:HasCriticalTier(), "collapsed") },
        flow = "horizontal",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 2,
        savedoc = function(element)
            element:SetClass("collapsed", not self:HasCriticalTier())
        end,
        TierRowLabel(self, nil),
        gui.Label {
            width = "100%-190",
            height = "auto",
            halign = "left",
            valign = "top",
            textAlignment = "topleft",
            markdown = true,
            text = self:try_get("criticalTier", ""),
            savedoc = function(element)
                element.text = self:try_get("criticalTier", "")
            end,
        },
    }

    local resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        children = rows,
    }

    resultPanel:FireEventTree("savedoc")

    return resultPanel
end

function HeroicTestDocument:DisplayPanel()
    self:EnsureTables()

    local resultPanel

    --Every child of a vertical flow carries valign="top": without it the flow
    --distributes its leftover height BETWEEN the children, which showed up as
    --large dead gaps between the title, difficulty, prose and outcomes.
    local titleLabel = gui.Label {
        classes = { "bold", "sizeXl" },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 4,
        text = self.description,
        savedoc = function(element)
            element.text = self.description
        end,
    }

    local difficultyLabel = gui.Label {
        classes = { "fgMuted", "sizeM" },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 2,
        --Text is set at CONSTRUCTION, not only in savedoc: the viewer can show
        --a read-mode panel without ever broadcasting savedoc, which left the
        --caption and the prose below blank. savedoc is refresh only.
        text = string.format("%s Test", self:DifficultyInfo().text),
        savedoc = function(element)
            element.text = string.format("%s Test", self:DifficultyInfo().text)
        end,
    }

    local summaryLabel = gui.Label {
        classes = { "sizeS" },
        width = "95%",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 6,
        textWrap = true,
        textAlignment = "topleft",
        markdown = true,
        links = true,
        text = self.summary,
        savedoc = function(element)
            element.text = self.summary
        end,
    }

    --Suggested characteristics/skills, collapsed when there are none.
    local suggestedLabel = gui.Label {
        classes = { cond(SuggestedText(self) == "", "collapsed"), "sizeS" },
        width = "95%",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 2,
        textWrap = true,
        textAlignment = "topleft",
        markdown = true,
        text = SuggestedText(self),
        savedoc = function(element)
            local text = SuggestedText(self)
            element.text = text
            element:SetClass("collapsed", text == "")
        end,
    }

    --Outcomes are Director information, read aloud AFTER the roll, so the
    --whole block (and the request button) is hidden in player view.
    local outcomesHeading = gui.Label {
        classes = { "bold", "sizeM" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 12,
        markdown = true,
        text = "## Outcomes",
    }

    local outcomesPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        outcomesHeading,
        self:OutcomesDisplay(),
        create = function(element)
            element:SetClass("collapsed", self:IsPlayerView(element))
        end,
    }

    local scrollablePanel = gui.Panel {
        width = "100%",
        height = "100%-50",
        flow = "vertical",
        valign = "top",
        vscroll = true,
        titleLabel,
        difficultyLabel,
        summaryLabel,
        suggestedLabel,
        outcomesPanel,
    }

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        scrollablePanel,

        gui.Button {
            classes = { "bold", "sizeL" },
            valign = "bottom",
            halign = "center",
            text = "Request Roll",
            create = function(element)
                element:SetClass("collapsed", self:IsPlayerView(element))
            end,
            click = function(element)
                self:RequestRoll()
            end,
        },
    }

    return resultPanel
end

function HeroicTestDocument:EditPanel()
    self:EnsureTables()

    local resultPanel

    --One style for every section header, matching the montage editor.
    local function sectionLabel(text, topMargin)
        return gui.Label {
            classes = { "bold", "sizeM" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            tmargin = topMargin or 0,
            markdown = true,
            text = text,
        }
    end

    local nameInput = gui.Input {
        classes = { "sizeL" },
        halign = "left",
        valign = "top",
        width = 300,
        height = 20,
        vmargin = 4,
        text = self.description,
        characterLimit = 128,
        placeholderText = "Heroic test title",
        change = function(element)
            self.description = element.text
            resultPanel:FireEventTree("savedoc")
        end,
    }

    local summaryInput = gui.Input {
        classes = { "sizeS" },
        width = "90%",
        height = "auto",
        maxHeight = 200,
        multiline = true,
        halign = "left",
        valign = "top",
        vmargin = 4,
        textAlignment = "topleft",
        characterLimit = 2048,
        text = self.summary,
        placeholderText = "What is the hero attempting?",
        change = function(element)
            self.summary = element.text
        end,
    }

    --Tier inputs are built once and re-pointed by refreshDifficulty, so
    --switching difficulty relabels the rows in place rather than rebuilding.
    local tierRows = {}
    for i = 1, #TIER_RANGES do
        tierRows[#tierRows + 1] = gui.Panel {
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 3,
            TierRowLabel(self, i),
            gui.Input {
                classes = { "sizeS" },
                width = 400,
                height = "auto",
                minHeight = 22,
                multiline = true,
                halign = "left",
                valign = "top",
                textAlignment = "topleft",
                characterLimit = 1024,
                text = self.tiers[i] or "",
                change = function(element)
                    self.tiers[i] = element.text
                end,
                refreshDifficulty = function(element)
                    element.text = self.tiers[i] or ""
                end,
            },
        }
    end

    local criticalRow = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 3,
        refreshDifficulty = function(element)
            element:SetClass("collapsed", not self:HasCriticalTier())
        end,
        TierRowLabel(self, nil),
        gui.Input {
            classes = { "sizeS" },
            width = 400,
            height = "auto",
            minHeight = 22,
            multiline = true,
            halign = "left",
            valign = "top",
            textAlignment = "topleft",
            characterLimit = 1024,
            text = self:try_get("criticalTier", ""),
            change = function(element)
                self.criticalTier = element.text
            end,
            refreshDifficulty = function(element)
                element.text = self:try_get("criticalTier", "")
            end,
        },
    }
    --The critical row lives in the SAME container as the other three: as a
    --sibling it sat under a second auto-height wrapper and the two panels'
    --slack stacked into visible dead space above and below the group.
    tierRows[#tierRows + 1] = criticalRow

    for _, row in ipairs(tierRows) do
        row:FireEventTree("refreshDifficulty")
    end

    local difficultyDropdown = gui.Dropdown {
        width = 160,
        halign = "left",
        valign = "top",
        vmargin = 4,
        options = g_difficultyDropdownOptions,
        idChosen = self:try_get("difficulty", "medium"),
        change = function(element)
            self:SetDifficulty(element.idChosen)
            resultPanel:FireEventTree("refreshDifficulty")
            --Tier row labels live on savedoc, which is also what the display
            --side listens to, so one broadcast keeps both in step.
            resultPanel:FireEventTree("savedoc")
        end,
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "top",
        vscroll = true,

        savedoc = function(element)
            self:Upload()
        end,

        sectionLabel("## Title"),
        nameInput,

        sectionLabel("## Difficulty", 12),
        difficultyDropdown,

        sectionLabel("## Setup", 12),
        summaryInput,

        sectionLabel("## Suggested", 12),
        --Side by side under captions: a Multiselect reserves vertical space for
        --its (initially empty) chosen-item list, so stacking the two left a
        --chasm between them and read as two orphaned dropdowns.
        gui.Panel {
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            gui.Panel {
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "top",
                rmargin = 24,
                gui.Label {
                    classes = { "fgMuted" },
                    width = "auto", height = "auto", halign = "left",
                    fontSize = 14,
                    text = "Characteristics",
                },
                gui.Multiselect {
                    halign = "left",
                    width = 240,
                    vmargin = 4,
                    value = self.characteristics,
                    addItemText = "Add Characteristic...",
                    options = creature.attributeDropdownOptions,
                    change = function(element, val)
                        self.characteristics = val
                    end,
                },
            },
            gui.Panel {
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "top",
                gui.Label {
                    classes = { "fgMuted" },
                    width = "auto", height = "auto", halign = "left",
                    fontSize = 14,
                    text = "Skills",
                },
                gui.Multiselect {
                    halign = "left",
                    width = 240,
                    vmargin = 4,
                    value = self.skills,
                    addItemText = "Add Skill...",
                    options = Skill.skillsDropdownOptions,
                    change = function(element, val)
                        self.skills = val
                    end,
                },
            },
        },

        sectionLabel("## Outcomes", 12),
        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            children = tierRows,
        },
    }

    return resultPanel
end

function HeroicTestDocument.CreateNew(args)
    local difficulty = g_difficulties.medium
    local result = HeroicTestDocument.new {
        description = "New Heroic Test",
        summary = "",
        difficulty = difficulty.id,
        characteristics = {},
        skills = {},
        tiers = { difficulty.presets[1], difficulty.presets[2], difficulty.presets[3] },
        criticalTier = CRITICAL_PRESET,
    }
    if args then
        for k, v in pairs(args) do
            result[k] = v
        end
    end
    return result
end

--Creation lives in the journal's "New Document" palette, like montages.
CustomDocument.Register {
    id = "heroictest",
    text = "New Heroic Test",
    docType = "heroictest",
    icon = CustomDocument.docTypeInfo["heroictest"].icon,
    create = function()
        return HeroicTestDocument.CreateNew {}
    end,
}

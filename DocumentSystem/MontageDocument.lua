local mod = dmhub.GetModLoading()

local g_numbers = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight" }

---@class MontageDocument:CustomDocument
--- @field new fun(o?: table): MontageDocument
---@field scene string
---@field summary string
---@field twist string
---@field difficulty table<number, {success:number, failure:number}>
---@field challenges MontageChallenge[]
---@field consequences MontageConsequence[]
---@field rewards MontageConsequence[]
---@field outcomes table<string, MontageOutcome> Keyed "success", "partial", "failure"; set by MontageTest.CreateNew.
MontageDocument = RegisterGameType("MontageDocument", "CustomDocument")
MontageDocument.docType = "montage"   --pins the semantic type (see DocumentSystem.lua)
MontageDocument.scene = ""
--Illustration for the scene, shown above the scene prose wherever the montage
--document is rendered. Empty string = no image. Set via the IconEditor in
--EditPanel, which carries its own "Upload Image" button for bringing in a file.
MontageDocument.sceneImage = ""
MontageDocument.summary = ""  -- shown as the "Description" box; the montage title
                              -- lives in self.description (the CustomDocument name)
MontageDocument.twist = ""    -- shown as the "Optional Twist" box
MontageDocument.vscroll = false

function MontageDocument:GetDifficultyInfo(numHeroes)
    local result = self.difficulty[numHeroes]
    if not result then
        if numHeroes < 3 then
            result = self.difficulty[3]
        else
            result = self.difficulty[6]
        end
    end
    return result
end

---@class MontageChallenge: GameType
--- @field new fun(o?: table): MontageChallenge
---@field name string
---@field details string
---@field characteristics table<string,boolean>
---@field skills table<string,boolean>
MontageChallenge = RegisterGameType("MontageChallenge")
MontageChallenge.name = "Challenge"
MontageChallenge.details = ""
MontageChallenge.maximum = 1

---@class MontageConsequence: GameType
--- @field new fun(o?: table): MontageConsequence
MontageConsequence = RegisterGameType("MontageConsequence")

---@class MontageOutcome: GameType
--- @field new fun(o?: table): MontageOutcome
---@field text string
---@field victoriesHard number
---@field victoriesMedium number
MontageOutcome = RegisterGameType("MontageOutcome")
MontageOutcome.text = ""
--Victories awarded for this outcome depend on the montage test difficulty.
MontageOutcome.victoriesHard = 0
MontageOutcome.victoriesMedium = 0

---@class LiveMontageParticipant: GameType
--- @field new fun(o?: table): LiveMontageParticipant
---@field tokenid string
LiveMontageParticipant = RegisterGameType("LiveMontageParticipant")
LiveMontageParticipant.tokenid = ""

--representation of an actual montage test in flight.
---@class LiveMontage: GameType
--- @field new fun(o?: table): LiveMontage
---@field participants table<string, LiveMontageParticipant>
LiveMontage = RegisterGameType("LiveMontage")
LiveMontage.participants = {}
LiveMontage.success = 0
LiveMontage.failure = 0

function LiveMontage:HeroCount()
    return table.count_elements(self.participants)
end

--[[
CustomDocument.Register {
    id = "montage",
    text = "New Montage",
    create = function()
        return MontageDocument.new {
            description = "New Montage",
            difficulty = {
                difficulty = true,
                [3] = { success = 3, failure = 3 },
                [4] = { success = 4, failure = 4 },
                [5] = { success = 5, failure = 5 },
                [6] = { success = 6, failure = 6 },
            },
            challenges = {},
            consequences = {},
            rewards = {},
            outcomes = {
                success = MontageOutcome.new {
                    victories = 1,
                },
                partial = MontageOutcome.new {
                },
                failure = MontageOutcome.new {
                },
            }
        }
    end,
}
]]

--One challenge as the read view shows it: what it is, then what to roll.
local function ChallengeRow(challenge)
    local characteristics = {}
    --the live table.keys (Utils.lua) always returns a list; only the lua-core one can return nil.
    local keys = table.keys(challenge.characteristics) --[[@as string[] ]]
    table.sort(keys,
        function(a, b) return creature.attributesInfo[a].order < creature.attributesInfo[b].order end)
    for _, k in ipairs(keys) do
        characteristics[#characteristics + 1] = creature.attributesInfo[k].description
    end

    local skills = {}
    for k, _ in pairs(challenge.skills) do
        local skillInfo = Skill.SkillsById[k]
        if skillInfo then
            skills[#skills + 1] = skillInfo.name
        end
    end
    table.sort(skills)

    local lines = {}
    if challenge.details ~= "" then
        lines[#lines + 1] = challenge.details
    end
    if #characteristics > 0 then
        lines[#lines + 1] = string.format("*Characteristics:* %s", table.concat(characteristics, ", "))
    end
    if #skills > 0 then
        lines[#lines + 1] = string.format("*Skills:* %s", table.concat(skills, ", "))
    end
    if challenge.maximum > 1 then
        lines[#lines + 1] = string.format("*Can be overcome %d times.*", challenge.maximum)
    end
    return CustomDocument.ReadNamedRow(challenge.name, table.concat(lines, "\n"))
end

--The page body. Rebuilt whole on a save, since a section with nothing in it
--is left out rather than shown empty.
function MontageDocument:ReadSections()
    local children = {}
    local function Section(heading, ...)
        children[#children + 1] = CustomDocument.ReadSectionHeader(heading)
        --select, not ipairs: a caller passes nil for a part it leaves out.
        for i = 1, select("#", ...) do
            children[#children + 1] = (select(i, ...))
        end
    end
    local function Prose(text)
        return gui.Label {
            classes = { "sizeS" },
            width = "95%", height = "auto", halign = "left", vmargin = 4,
            markdown = true, links = true, textWrap = true, textAlignment = "topleft",
            text = text,
        }
    end

    children[#children + 1] = gui.Label {
        classes = { "bold", "sizeXl" },
        width = "auto", height = "auto", halign = "left", vmargin = 4,
        text = self.description,
    }
    if self.summary ~= "" then
        children[#children + 1] = Prose(self.summary)
    end

    --The row Begin would use right now is picked out; none while there are no heroes.
    local heroes = table.count_elements(MontageDocument.Participants())
    local limits = {}
    for i = 3, 6 do
        local difficulty = self.difficulty[i]
        limits[#limits + 1] = string.format("%s heroes: **%d** to succeed, **%d** to fail",
            g_numbers[i], difficulty.success, difficulty.failure)
    end
    children[#children + 1] = CustomDocument.StatChips(limits,
        heroes > 0 and (math.max(3, math.min(6, heroes)) - 2) or nil)

    local sceneImage = self:try_get("sceneImage", "")
    if self.scene ~= "" or sceneImage ~= "" then
        Section("Setting the scene",
            sceneImage ~= "" and gui.Panel {
                classes = { "image" },
                width = 320, height = 180, halign = "left", vmargin = 4,
                bgcolor = "white",
                bgimage = sceneImage,
            } or nil,
            self.scene ~= "" and Prose(self.scene) or nil)
    end

    if #self.challenges > 0 then
        local function Column(first, last)
            local rows = {}
            for i = first, last do
                rows[#rows + 1] = ChallengeRow(self.challenges[i])
            end
            return gui.Panel {
                flow = "vertical", width = "100%", height = "auto", halign = "left",
                children = rows,
            }
        end
        local half = math.ceil(#self.challenges / 2)
        local columns = { Column(1, half) }
        if half < #self.challenges then
            columns[#columns + 1] = Column(half + 1, #self.challenges)
        end
        Section("Challenges", CustomDocument.ReadColumns(columns))
    end

    local outcomes = {}
    for _, entry in ipairs({
        { key = "success", text = "Total Success" },
        { key = "partial", text = "Partial Success" },
        { key = "failure", text = "Total Failure" },
    }) do
        local text = self.outcomes[entry.key].text
        if text ~= "" then
            outcomes[#outcomes + 1] = CustomDocument.ReadNamedRow(entry.text, text)
        end
    end
    if #outcomes > 0 then
        Section("Outcomes", table.unpack(outcomes))
    end

    if self.twist ~= "" then
        Section("Optional twist", Prose(self.twist))
    end

    return children
end

function MontageDocument:DisplayPanel()
    local resultPanel

    --Beginning a montage is the host's to do, so a directorless game's host
    --keeps the button.
    local canBegin = dmhub.isDMOrPlayerHost

    local body = gui.Panel {
        width = "100%",
        height = canBegin and "100%-60" or "100%",
        flow = "vertical",
        valign = "top",
        vscroll = true,
        children = self:ReadSections(),
        savedoc = function(element)
            element.children = self:ReadSections()
        end,
    }

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        body,

        --marks where the scrolling page ends
        canBegin and gui.Divider { width = "100%", tmargin = 0, bmargin = 6 } or nil,
        canBegin and gui.Button {
            classes = { "bold", "sizeXl" },
            valign = "bottom",
            text = "Begin Montage",
            halign = "center",
            click = function(element)
                self:Begin(resultPanel)
                element:FindParentWithClass("framedPanel"):DestroySelf()
            end,
        } or nil,
    }

    return resultPanel
end

--Who takes part in a montage begun now: every hero with an owner.
--- @return table<string, LiveMontageParticipant>
function MontageDocument.Participants()
    local participants = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token.properties:IsHero() and token.ownerId ~= nil then
            participants[token.charid] = LiveMontageParticipant.new {
                tokenid = token.id,
            }
        end
    end
    return participants
end

--Start the montage: the montage dialog is presented to every client.
--hostPanel is any panel in the HUD.
function MontageDocument:Begin(hostPanel)
    local livedata = LiveMontage.new {
        participants = MontageDocument.Participants(),
    }

    GameHud.PresentDialogToUsers(hostPanel, "montage", { montageid = self.id }, livedata)
end

--Begin Montage as a registered action (see CustomDocument.RegisterAction).
CustomDocument.docTypeInfo.montage.actions = { { id = "start", verb = "montage.start" } }
--Only a real montage has Begin; a plain page typed "montage" does not.
CustomDocument.docTypeInfo.montage.declaredFor = function(doc)
    return doc.typeName == "MontageTest" or doc.typeName == "MontageDocument"
end
CustomDocument.RegisterAction{
    id = "montage.start",
    text = "Begin Montage",
    mode = "read",
    run = function(doc, element)
        doc:Begin(element)
        local framed = element:FindParentWithClass("framedPanel")
        if framed ~= nil then
            framed:DestroySelf()
        end
    end,
}

function MontageDocument:EditPanel()
    local resultPanel

    --All section headers share one style so every box is clearly labeled.
    --topMargin adds extra space above a header to delineate major sections.
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

    --All multiline prose boxes (description, scene, twist) share one style.
    local function proseInput(getText, setText, placeholder)
        return gui.Input {
            classes = { "sizeS" },
            width = "90%",
            height = "auto",
            text = getText(),
            maxHeight = 200,
            multiline = true,
            halign = "left",
            textAlignment = "topleft",
            placeholderText = placeholder,
            valign = "top",
            vmargin = 4,
            characterLimit = 4096,
            change = function(element)
                setText(element.text)
                CustomDocument.NotifyEdited(element)
            end,
        }
    end

    local nameInput = gui.Input {
        classes = { "sizeL" },
        halign = "left",
        valign = "top",
        width = 300,
        height = 20,
        text = self.description,
        vmargin = 4,
        placeholderText = "Montage test title",
        change = function(element)
            self.description = element.text
            CustomDocument.NotifyEdited(element)
        end,
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "top",
        vscroll = true,

        --No savedoc handler here on purpose: the inputs above write into the
        --document object directly, so there is nothing to flush. Uploading is
        --the shell's job (CreateInterface autosave / pencil-off / close guard),
        --keyed off the CustomDocument.NotifyEdited calls in every change
        --handler; a savedoc-time Upload here would double-write on every save.

        sectionLabel("## Title"),
        nameInput,

        sectionLabel("## Description"),
        proseInput(
            function() return self.summary end,
            function(text) self.summary = text end,
            "Enter description"),

        sectionLabel("## Setting the Scene"),
        --Scene illustration. IconEditor's picker popup carries an "Upload Image"
        --button, so this is also how a Director brings in their own file.
        gui.IconEditor {
            library = "journal",
            width = 240,
            height = 135,
            halign = "left",
            valign = "top",
            vmargin = 4,
            bgcolor = "white",
            allowNone = true,
            value = self:try_get("sceneImage", ""),
            change = function(element)
                self.sceneImage = element.value or ""
                CustomDocument.NotifyEdited(element)
            end,
        },
        proseInput(
            function() return self.scene end,
            function(text) self.scene = text end,
            "Enter scene description"),

        sectionLabel("## Montage Challenges\nThe following challenges can be part of the montage test:", 24),
        self:ChallengesEditor(),

        sectionLabel("## Optional Twist", 24),
        proseInput(
            function() return self.twist end,
            function(text) self.twist = text end,
            "Enter optional twist"),

        sectionLabel("## Montage Test Outcomes\nThe montage test has the following outcomes:", 24),
        self:OutcomesEditor(),
    }

    return resultPanel
end

function MontageDocument:ChallengesEditor()
    local resultPanel

    local addButton = gui.Button {
        text = "+Add Challenge",
        width = "auto",
        height = "auto",
        halign = "left",
        click = function(element)
            self.challenges[#self.challenges + 1] = MontageChallenge.new {
                characteristics = {},
                skills = {},
            }
            resultPanel:FireEventTree("refreshChallenges")
            CustomDocument.NotifyEdited(element)
        end,
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        addButton,

        refreshChallenges = function(element)
            local children = {}

            for i, challenge in ipairs(self.challenges) do
                --Write to the challenge at this index, not to the table the
                --row was built from: once a save is echoed back, the engine
                --has swapped a newly added challenge for a fresh copy inside
                --the document, and a write into the old one is never saved.
                --The index is stable, since adding or removing one rebuilds
                --every row.
                local function live()
                    return self.challenges[i] or challenge
                end
                local panel = gui.Panel {
                    flow = "vertical",
                    width = 500,
                    height = "auto",
                    gui.Input {
                        classes = { "sizeL" },
                        vmargin = 4,
                        halign = "left",
                        text = challenge.name,
                        characterLimit = 64,
                        change = function(element)
                            live().name = element.text
                            CustomDocument.NotifyEdited(element)
                        end,
                        gui.Button {
                            classes = { "deleteButton", "sizeXs" },
                            halign = "right",
                            x = 32,
                            press = function(element)
                                table.remove(self.challenges, i)
                                --notify BEFORE the rebuild: refreshChallenges
                                --replaces the challenge rows, orphaning this
                                --button, and NotifyEdited walks up from it.
                                CustomDocument.NotifyEdited(element)
                                resultPanel:FireEventTree("refreshChallenges")
                            end,
                        },
                    },
                    gui.Input {
                        classes = { "sizeL" },
                        vmargin = 4,
                        halign = "left",
                        multiline = true,
                        height = "auto",
                        width = 400,
                        characterLimit = 512,
                        textAlignment = "topleft",
                        text = challenge.details,
                        change = function(element)
                            live().details = element.text
                            CustomDocument.NotifyEdited(element)
                        end,
                    },

                    gui.Panel {
                        flow = "horizontal",
                        halign = "left",
                        valign = "center",
                        width = "auto",
                        height = "auto",
                        vmargin = 2,
                        gui.Label {
                            text = "Attempts:",
                            width = "auto",
                            height = "auto",
                            valign = "center",
                            rmargin = 8,
                        },
                        gui.Input {
                            classes = { "sizeS" },
                            width = 40,
                            valign = "center",
                            text = tostring(challenge.maximum),
                            characterLimit = 2,
                            change = function(element)
                                local target = live()
                                target.maximum = math.max(1, tonumber(element.text) or target.maximum)
                                element.text = tostring(target.maximum)
                                CustomDocument.NotifyEdited(element)
                            end,
                        },
                    },
                }
                children[#children + 1] = gui.Panel {
                    flow = "horizontal",
                    halign = "left",
                    width = "auto",
                    height = "auto",

                    panel,

                    gui.Panel {
                        flow = "vertical",
                        halign = "left",
                        width = 400,
                        height = "auto",
                        gui.Multiselect {
                            halign = "left",
                            vmargin = 4,
                            value = challenge.characteristics,
                            addItemText = "Add Characteristic...",
                            options = creature.attributeDropdownOptions,
                            change = function(element, val)
                                live().characteristics = val
                                CustomDocument.NotifyEdited(element)
                            end,
                        },

                        gui.Multiselect {
                            halign = "left",
                            hmargin = 6,
                            vmargin = 4,
                            value = challenge.skills,
                            addItemText = "Add Skill...",
                            options = Skill.skillsDropdownOptions,
                            change = function(element, val)
                                live().skills = val
                                CustomDocument.NotifyEdited(element)
                            end,
                        },
                    },
                }
            end

            children[#children + 1] = addButton
            element.children = children
        end,
    }

    resultPanel:FireEventTree("refreshChallenges")

    return resultPanel
end

function MontageDocument:OutcomesEditor()
    local resultPanel

    local panels = {}

    local entries = {
        {
            key = "success",
            text = "Total Success",
        },
        {
            key = "partial",
            text = "Partial Success",
        },
        {
            key = "failure",
            text = "Total Failure",
        },
    }

    for _, entry in ipairs(entries) do
        local outcome = self.outcomes[entry.key]
        local victoriesPanel
        if entry.key ~= "failure" then
            victoriesPanel = gui.Panel {
                flow = "horizontal",
                halign = "left",
                valign = "center",
                width = "auto",
                height = "auto",
                vmargin = 2,
                gui.Label {
                    text = "Victories:",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    rmargin = 12,
                },
                gui.Label {
                    text = "Hard:",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    rmargin = 6,
                },
                gui.Input {
                    classes = { "sizeS" },
                    width = 40,
                    valign = "center",
                    characterLimit = 1,
                    text = tostring(outcome.victoriesHard),
                    change = function(element)
                        local n = tonumber(element.text) or outcome.victoriesHard
                        outcome.victoriesHard = n
                        element.text = tostring(n)
                        CustomDocument.NotifyEdited(element)
                    end,
                },
                gui.Label {
                    text = "Medium:",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 16,
                    rmargin = 6,
                },
                gui.Input {
                    classes = { "sizeS" },
                    width = 40,
                    valign = "center",
                    characterLimit = 1,
                    text = tostring(outcome.victoriesMedium),
                    change = function(element)
                        local n = tonumber(element.text) or outcome.victoriesMedium
                        outcome.victoriesMedium = n
                        element.text = tostring(n)
                        CustomDocument.NotifyEdited(element)
                    end,
                },
            }
        end
        local panel = gui.Panel {
            flow = "vertical",
            height = "auto",
            width = 800,
            halign = "left",
            valign = "top",
            vmargin = 6,
            gui.Label {
                classes = { "bold", "sizeM" },
                markdown = true,
                text = "### " .. entry.text,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "top",
            },
            gui.Input {
                classes = { "sizeS" },
                multiline = true,
                textAlignment = "topleft",
                width = 700,
                height = "auto",
                maxHeight = 200,
                minHeight = 30,
                halign = "left",
                characterLimit = 512,
                placeholderText = "Describe outcome...",
                text = outcome.text,
                change = function(element)
                    outcome.text = element.text
                    CustomDocument.NotifyEdited(element)
                end,
            },
            victoriesPanel,
        }

        panels[#panels + 1] = panel
    end

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        children = panels,
    }

    return resultPanel
end

local CreateMontageTestUI = function(args)
    local isDM = dmhub.isDM
    local doc = GameHud.GetPresentDialogDoc("montage")
    if doc == nil then
        print("Montage: Error: Could not find montage data")
        return
    end

    local montageDoc = (dmhub.GetTable(CustomDocument.tableName) or {})[args.montageid]
    if montageDoc == nil then
        print("Montage: Error: Could not find montage document")
        return
    end
    ---@cast montageDoc MontageDocument

    ---@type LiveMontage
    local m_montage = nil

    local closeButton
    local addParticipantButton

    if isDM then
        closeButton = gui.Button {
            classes = { "closeButton" },
            halign = "right",
            valign = "top",
            press = function(element)
                GameHud.HidePresentedDialog()
            end,
        }

        addParticipantButton = gui.Button {
            classes = { "addButton", "sizeXs" },
            x = 28,
            halign = "right",
            valign = "bottom",
            floating = true,
            press = function(element)
                local entries = {}
                local tokens = dmhub.allTokens
                for _, token in ipairs(tokens) do
                    if m_montage.participants[token.charid] == nil then
                        entries[#entries + 1] = {
                            text = token.name,
                            click = function()
                                element.popup = nil

                                local doc = GameHud.GetPresentDialogDoc("montage")
                                if doc == nil then
                                    return
                                end

                                local montage = doc.data.livedata
                                if montage == nil then
                                    return
                                end

                                doc:BeginChange()
                                montage.participants[token.charid] = LiveMontageParticipant.new{
                                    tokenid = token.charid,
                                }
                                doc:CompleteChange("Remove character from montage")
                            end,
                        }
                    end
                end

                element.popup = gui.ContextMenu {
                    entries = entries,
                }
            end,
            refreshMontage = function(element, montage)
                local tokens = dmhub.allTokens
                local haveTokens = false
                for _, token in ipairs(tokens) do
                    if montage.participants[token.charid] == nil then
                        haveTokens = true
                        break
                    end
                end

                element:SetClass("hidden", not haveTokens)
            end,
        }
    end

    local m_participants = {}

    local participantsPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        vmargin = 8,

        refreshMontage = function(element, montage)
            local children = {}
            local newParticipants = {}
            for _, participant in pairs(montage.participants) do
                local token = dmhub.GetCharacterById(participant.tokenid)
                if token ~= nil then
                    local panel = m_participants[participant.tokenid] or gui.Panel {
                        flow = "vertical",
                        width = 100,
                        height = 130,
                        gui.Panel {
                            classes = { "image" },
                            width = "78% height",
                            height = 100,
                            halign = "center",
                            valign = "top",

                            token = function(element, token)
                                local portrait = token.offTokenPortrait
                                element.selfStyle.bgimage = portrait
                                element.selfStyle.imageRect = token:GetPortraitRectForAspect(78 * 0.01, portrait)
                            end,

                            rightClick = function(element)
                                element.popup = gui.ContextMenu {
                                    entries = {
                                        {
                                            text = "Remove",
                                            click = function()
                                                element.popup = nil
                                                local doc = GameHud.GetPresentDialogDoc("montage")
                                                if doc == nil then
                                                    return
                                                end

                                                local montage = doc.data.livedata
                                                if montage == nil then
                                                    return
                                                end

                                                doc:BeginChange()
                                                montage.participants[participant.tokenid] = nil
                                                doc:CompleteChange("Remove character from montage")
                                            end,
                                        }
                                    }
                                }
                            end,
                        },
                        gui.Label {
                            classes = { "sizeM" },
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            minFontSize = 10,

                            textAlignment = "center",
                            token = function(element, token)
                                element.text = token.name
                            end,
                        },
                    }

                    panel:FireEventTree("token", token)

                    newParticipants[participant.tokenid] = panel
                    children[#children + 1] = panel
                end
            end

            local scale = 1
            if #children > 8 then
                scale = 8 / #children
            end

            element.selfStyle.uiscale = scale


            children[#children + 1] = addParticipantButton

            m_participants = newParticipants
            element.children = children
        end,

        addParticipantButton,

    }

    local CreateSuccessBar = function(mode)
        local m_value = nil
        local m_animValue = nil
        local m_segments = {}
        local m_fill
        m_fill = gui.Panel{
            classes = { "fillBarFill" },
            floating = true,
            width = "0%",
            height = 20,
            gradient = cond(mode == "success", Styles.healthGradient, Styles.bloodiedGradient),
            halign = "left",

            thinkTime = 0.01,
            think = function(element)
                if m_animValue ~= nil and m_animValue ~= m_value then
                    if m_animValue < m_value then
                        m_animValue = math.min(m_animValue + 0.05, m_value)
                    else
                        m_animValue = math.max(m_animValue - 0.05, m_value)
                    end
                    local difficultyInfo = montageDoc:GetDifficultyInfo(m_montage:HeroCount())
                    m_fill.selfStyle.width = string.format("%f%%", (m_animValue / difficultyInfo[mode]) * 100)
                end
            end,
        }
        local successBar = gui.Panel{
            classes = { "fillBar" },
            width = 100,
            height = 20,
            valign = "center",
            halign = "left",
            flow = "horizontal",
            refreshMontage = function(element, montage)
                local difficultyInfo = montageDoc:GetDifficultyInfo(montage:HeroCount())
                local count = math.min(8, difficultyInfo[mode])
                element.selfStyle.width = count*100
                while #m_segments < count do
                    m_segments[#m_segments + 1] = gui.Panel {
                        classes = { "fillBarSegment" },
                        width = 100,
                        height = 20,
                    }
                end

                while #m_segments > count do
                    m_segments[#m_segments] = nil
                end

                local children = {m_fill}
                for _,seg in ipairs(m_segments) do
                    children[#children + 1] = seg
                end

                element.children = children

                m_value = montage[mode]

                if m_animValue == nil then
                    m_animValue = m_value
                    m_fill.selfStyle.width = string.format("%f%%", (m_value / difficultyInfo[mode]) * 100)
                end
            end,

            m_fill
        }

        local incrementSuccess = function(delta)
            local doc = GameHud.GetPresentDialogDoc("montage")
            if doc == nil then
                return
            end

            local montage = doc.data.livedata
            if montage == nil then
                return
            end

            doc:BeginChange()
            montage[mode] = math.max(0, montage[mode] + delta)
            montage[mode] = math.min(montage[mode], montageDoc:GetDifficultyInfo(montage:HeroCount())[mode])
            doc:CompleteChange("Update montage " .. mode)
        end

        local resultPanel

        resultPanel = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            gui.Button{
                classes = { "sizeXxs" },
                text = "-",
                press = function(element)
                    incrementSuccess(-1)
                end,
            },
            successBar,
            gui.Button{
                classes = { "sizeXxs" },
                text = "+",
                press = function(element)
                    incrementSuccess(1)
                end,
            },
        }

        return resultPanel
    end

    local progressPanel = gui.Panel{
        floating = true,
        halign = "center",
        valign = "center",
        flow = "vertical",
        width = 900,
        height = 100,

        gui.Panel{
            flow = "horizontal",
            width = 900,
            height = 50,
            gui.Label{
                classes = { "bold", "sizeL" },
                halign = "left",
                width = 100,
                height = 24,
                text = "Successes:",
            },
            CreateSuccessBar("success"),
        },

        gui.Panel{
            flow = "horizontal",
            width = 900,
            height = 50,
            gui.Label{
                classes = { "bold", "sizeL" },
                halign = "left",
                width = 100,
                height = 24,
                text = "Failures:",
            },
            CreateSuccessBar("failure"),
        },
    }

    local resultPanel
    resultPanel = gui.Panel {
        styles = ThemeEngine.GetStyles(),
        classes = { "bordered", "bg" },
        width = 1100,
        height = 900,
        blurBackground = true,
        monitorGame = doc.path,

        gui.Label {
            classes = { "bold", "sizeXxl" },
            halign = "center",
            valign = "top",
            width = "auto",
            height = "auto",
            tmargin = 6,
            text = string.format(tr("Montage: %s"), montageDoc.description),
        },

        progressPanel,

        closeButton,
        participantsPanel,

        refreshGame = function(element)
            doc = GameHud.GetPresentDialogDoc("montage")
            if doc == nil then
                return
            end

            m_montage = doc.data.livedata

            element:FireEventTree("refreshMontage", doc.data.livedata)
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    resultPanel:FireEventTree("refreshMontage", doc.data.livedata)

    return resultPanel
end

GameHud.RegisterPresentableDialog {
    id = "montage",
    keeplocal = false,
    create = CreateMontageTestUI,
}

--Prepped montage test. It reuses all of MontageDocument's editor and display
--logic and, like NegotiationDocument, now lives in the shared "documents"
--table so a prepped montage IS a journal document: it sits in journal folders,
--edits in the viewer, carries docType="montage" (its icon), and the live
--runner resolves it (CreateMontageTestUI reads the documents table). Sites
--that iterate the montage set must now filter on docType=="montage" because
--the documents table holds every journal document.
--- @class MontageTest: MontageDocument
--- @field new fun(o?: table): MontageTest
MontageTest = RegisterGameType("MontageTest", "MontageDocument")
MontageTest.tableName = CustomDocument.tableName   --"documents" (was "montageTests")

function MontageTest.CreateNew(args)
    local result = MontageTest.new{
        description = "New Montage Test",
        scene = "",
        difficulty = {
            difficulty = true,
            [3] = { success = 3, failure = 3 },
            [4] = { success = 4, failure = 4 },
            [5] = { success = 5, failure = 5 },
            [6] = { success = 6, failure = 6 },
        },
        challenges = {},
        consequences = {},
        rewards = {},
        outcomes = {
            success = MontageOutcome.new{ victoriesHard = 2, victoriesMedium = 1 },
            partial = MontageOutcome.new{ victoriesHard = 1, victoriesMedium = 1 },
            failure = MontageOutcome.new{},
        },
    }
    if args then
        for k,v in pairs(args) do
            result[k] = v
        end
    end
    return result
end

--Montage creation now lives in the journal's "New Document" palette (the
--compendium montage tab was retired). Creates a MontageTest in the documents
--table with docType="montage"; onNewDocument opens it for editing like any doc.
CustomDocument.Register {
    id = "montage",
    text = "New Montage",
    docType = "montage",
    icon = CustomDocument.docTypeInfo["montage"].icon,
    create = function()
        return MontageTest.CreateNew{}
    end,
}

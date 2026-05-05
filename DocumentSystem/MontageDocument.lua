local mod = dmhub.GetModLoading()

local g_numbers = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight" }

---@class MontageDocument:CustomDocument
---@field scene string
---@field difficulty table<number, {success:number, failure:number}>
---@field challenges MontageChallenge[]
---@field consequences MontageConsequence[]
---@field rewards MontageConsequence[]
MontageDocument = RegisterGameType("MontageDocument", "CustomDocument")
MontageDocument.scene = ""
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

---@class MontageChallenge
---@field name string
---@field details string
---@field characteristics table<string,boolean>
---@field skills table<string,boolean>
MontageChallenge = RegisterGameType("MontageChallenge")
MontageChallenge.name = "Challenge"
MontageChallenge.details = ""
MontageChallenge.maximum = 1

---@class MontageConsequence
MontageConsequence = RegisterGameType("MontageConsequence")

---@class MontageOutcome
---@field text string
---@field victories number
MontageOutcome = RegisterGameType("MontageOutcome")
MontageOutcome.text = ""
MontageOutcome.victories = 0

---@class LiveMontageParticipant
---@field tokenid string
LiveMontageParticipant = RegisterGameType("LiveMontageParticipant")
LiveMontageParticipant.tokenid = ""

--representation of an actual montage test in flight.
---@class LiveMontage
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

function MontageDocument:ChallengesDisplay()
    local m_panels = {}

    local resultPanel
    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 6,
        children = m_panels,
        savedoc = function(element)
            for i, challenge in ipairs(self.challenges) do
                local panel = m_panels[i] or gui.Label {
                    width = "100%",
                    height = "auto",
                    markdown = true,
                    vmargin = 2,
                }

                local characteristics = {}
                local keys = table.keys(challenge.characteristics)
                table.sort(keys,
                    function(a, b) return creature.attributesInfo[a].order < creature.attributesInfo[b].order end)
                for _, k in ipairs(keys) do
                    local attributeInfo = creature.attributesInfo[k]
                    characteristics[#characteristics + 1] = attributeInfo.description
                end

                local skills = {}
                for k, _ in pairs(challenge.skills) do
                    local skillInfo = Skill.SkillsById[k]
                    if skillInfo then
                        skills[#skills + 1] = skillInfo.name
                    end
                end
                table.sort(skills)
                panel.text = string.format("**%s:** %s\n*Suggested Characteristics:* %s.\n*Suggested Skills:* %s.",
                    challenge.name, challenge.details, table.concat(characteristics, ", "), table.concat(skills, ", "))

                panel:SetClass("collapsed", false)
                m_panels[i] = panel
            end

            for i = #self.challenges + 1, #m_panels do
                m_panels[i]:SetClass("collapsed", true)
            end

            element.children = m_panels
        end,
    }

    resultPanel:FireEvent("savedoc")

    return resultPanel
end

function MontageDocument:OutcomesDisplay()
    local resultPanel

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

    local panels = {}
    for i, entries in ipairs(entries) do
        panels[#panels + 1] = gui.Label {
            width = "100%",
            height = "auto",
            markdown = true,
            vmargin = 2,
            savedoc = function(element)
                element.text = string.format("**%s:** %s", entries.text, self.outcomes[entries.key].text)
            end,
        }
    end

    resultPanel = gui.Panel {
        flow = "vertical",
        halign = "left",
        width = "100%",
        height = "auto",
        children = panels,
    }

    resultPanel:FireEventTree("savedoc")

    return resultPanel
end

function MontageDocument:DisplayPanel()
    local resultPanel

    local titleLabel = gui.Label {
        width = "auto",
        height = "auto",
        halign = "center",
        fontSize = 24,
        bold = true,
        text = self.description,
        vmargin = 4,
        savedoc = function(element)
            element.text = self.description
        end,
    }

    local testDifficulty = gui.Panel {
        vmargin = 4,
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        gui.Panel {
            flow = "horizontal",
            height = 24,
            width = 600,
            bgimage = true,
            bgcolor = "white",
            opacity = 0.02,
            gui.Label {
                width = 200,
                bold = true,
                text = "Heroes",
                textAlignment = "left",
            },
            gui.Label {
                width = 200,
                bold = true,
                text = "Success Limit",
                textAlignment = "left",
            },
            gui.Label {
                width = 200,
                bold = true,
                text = "Failure Limit",
                textAlignment = "left",
            },
        },

        create = function(element)
            local children = element.children
            for i = 3, 6 do
                local difficulty = self.difficulty[i]
                children[#children + 1] = gui.Panel {
                    bgimage = true,
                    bgcolor = "white",
                    opacity = cond(i % 2 == 1, 0.01, 0.02),
                    flow = "horizontal",
                    height = 24,
                    width = 600,
                    gui.Label {
                        width = 200,
                        height = 24,
                        text = g_numbers[i],
                        textAlignment = "left",
                    },

                    gui.Label {
                        width = 200,
                        height = 24,
                        valign = "center",
                        halign = "left",
                        vpad = 1,
                        text = difficulty.success,
                        savedoc = function(element)
                            element.text = tostring(difficulty.success)
                        end,
                    },

                    gui.Label {
                        width = 200,
                        height = 24,
                        valign = "center",
                        halign = "left",
                        vpad = 1,
                        text = difficulty.failure,
                        savedoc = function(element)
                            element.text = tostring(difficulty.failure)
                        end,
                    },

                }
            end

            element.children = children
        end,
    }



    local sceneLabel = gui.Label {
        width = "95%",
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 4,
        fontSize = 14,
        text = self.scene,
        textWrap = true,
        textAlignment = "topleft",
        markdown = true,
        links = true,
        savedoc = function(element)
            element.text = self.scene
        end,
    }

    local scrollablePanel = gui.Panel {
        width = "100%",
        height = "100%-50",
        flow = "vertical",
        valign = "top",
        styles = {
            {
                selectors = { "label" },
                fontSize = 14,
                width = "auto",
                height = "auto",
                valign = "center",
                hpad = 6,
            }
        },
        titleLabel,
        testDifficulty,
        gui.Label {
            bold = true,
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Setting the Scene",
        },
        sceneLabel,

        gui.Label {
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Montage Challenges\nThe following challenges can be part of the montage test:",
        },

        self:ChallengesDisplay(),

        gui.Label {
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Montage Test Outcomes\nThe montage test has the following outcomes:",
        },

        self:OutcomesDisplay(),
    }

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        scrollablePanel,

        gui.Button {
            valign = "bottom",
            text = "Begin Montage",
            halign = "center",
            bold = true,
            fontSize = 22,
            click = function(element)
                local livedata = LiveMontage.new {
                    participants = {}
                }

                for _, token in ipairs(dmhub.allTokens) do
                    if token.properties:IsHero() and token.ownerId ~= nil then
                        livedata.participants[token.charid] = LiveMontageParticipant.new {
                            tokenid = token.id,
                        }
                    end
                end

                GameHud.PresentDialogToUsers(resultPanel, "montage", { montageid = self.id }, livedata)
                element:FindParentWithClass("framedPanel"):DestroySelf()
            end,
        },
    }

    return resultPanel
end

function MontageDocument:EditPanel()
    local resultPanel

    local nameInput = gui.Input {
        halign = "center",
        valign = "top",
        width = 300,
        height = 20,
        fontSize = 18,
        text = self.description,
        vmargin = 4,
        change = function(element)
            self.description = element.text
        end,
    }

    local testDifficulty = gui.Panel {
        vmargin = 4,
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        gui.Panel {
            flow = "horizontal",
            height = 24,
            width = 600,
            bgimage = true,
            bgcolor = "white",
            opacity = 0.02,
            gui.Label {
                width = 200,
                bold = true,
                text = "Heroes",
                textAlignment = "left",
            },
            gui.Label {
                width = 200,
                bold = true,
                text = "Success Limit",
                textAlignment = "left",
            },
            gui.Label {
                width = 200,
                bold = true,
                text = "Failure Limit",
                textAlignment = "left",
            },
        },

        create = function(element)
            local children = element.children
            for i = 3, 6 do
                local difficulty = self.difficulty[i]
                children[#children + 1] = gui.Panel {
                    flow = "horizontal",
                    height = 24,
                    width = 600,
                    bgimage = true,
                    bgcolor = "white",
                    opacity = cond(i % 2 == 1, 0.01, 0.02),
                    gui.Label {
                        width = 200,
                        height = 24,
                        text = g_numbers[i],
                        textAlignment = "left",
                    },

                    gui.Panel {
                        width = 200,
                        height = 24,
                        gui.Input {
                            width = 20,
                            height = 16,
                            valign = "center",
                            halign = "left",
                            vpad = 1,
                            fontSize = 14,
                            text = difficulty.success,
                            characterLimit = 1,
                            change = function(element)
                                local n = tonumber(element.text) or difficulty.success
                                difficulty.success = n
                                element.text = tostring(n)
                            end,
                        },
                    },

                    gui.Panel {
                        width = 200,
                        height = 24,
                        gui.Input {
                            width = 20,
                            height = 16,
                            valign = "center",
                            halign = "left",
                            vpad = 1,
                            fontSize = 14,
                            text = difficulty.failure,
                            characterLimit = 1,
                            change = function(element)
                                local n = tonumber(element.text) or difficulty.failure
                                difficulty.failure = n
                                element.text = tostring(n)
                            end,
                        },
                    },
                }
            end

            element.children = children
        end,
    }

    local sceneInput = gui.Input {
        width = "90%",
        height = "auto",
        text = self.scene,
        maxHeight = 200,
        multiline = true,
        halign = "left",
        fontSize = 14,
        textAlignment = "topleft",
        placeholderText = "Enter scene description",
        valign = "top",
        vmargin = 4,
        characterLimit = 4096,
        change = function(element)
            self.scene = element.text
        end,
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "top",
        vscroll = true,
        styles = {
            Styles.Form,
            {
                selectors = { "deleteItemButton" },
                priority = 20,
                width = 12,
                height = 12,
            },
            {
                selectors = { "label" },
                fontSize = 14,
                width = "auto",
                height = "auto",
                valign = "center",
                hpad = 6,
            },
        },

        savedoc = function(element)
            self:Upload()
        end,

        nameInput,
        testDifficulty,

        gui.Label {
            bold = true,
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Setting the Scene",
        },

        sceneInput,

        gui.Label {
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Montage Challenges\nThe following challenges can be part of the montage test:",
        },

        self:ChallengesEditor(),

        gui.Label {
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            markdown = true,
            text = "## Montage Test Outcomes\nThe montage test has the following outcomes:",
        },

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
                local panel = gui.Panel {
                    flow = "vertical",
                    width = 500,
                    height = "auto",
                    gui.Input {
                        fontSize = 18,
                        vmargin = 4,
                        halign = "left",
                        text = challenge.name,
                        characterLimit = 64,
                        change = function(element)
                            challenge.name = element.text
                        end,
                        gui.DeleteItemButton {
                            halign = "right",
                            x = 32,
                            width = 16,
                            height = 16,
                            click = function(element)
                                table.remove(self.challenges, i)
                                resultPanel:FireEventTree("refreshChallenges")
                            end,
                        },
                    },
                    gui.Input {
                        fontSize = 18,
                        vmargin = 4,
                        halign = "left",
                        multiline = true,
                        height = "auto",
                        width = 400,
                        characterLimit = 512,
                        textAlignment = "topleft",
                        text = challenge.details,
                        change = function(element)
                            challenge.details = element.text
                        end,
                    },

                    gui.Panel {
                        classes = { "formPanel" },
                        halign = "left",
                        gui.Label {
                            classes = { "formLabel" },
                            halign = "left",
                            text = "Attempts:",
                        },
                        gui.Input {
                            classes = { "formInput" },
                            halign = "left",
                            text = challenge.maximum,
                            characterLimit = 2,
                            change = function(element)
                                challenge.maximum = math.max(1, tonumber(element.text) or challenge.maximum)
                                element.text = challenge.maximum
                            end,
                        }
                    },
                }
                children[#children + 1] = gui.Divider {
                    width = 700,
                    halign = "left",
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
                                challenge.characteristics = val
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
                                challenge.skills = val
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
                classes = { "formPanel" },
                halign = "left",
                width = 20,
                gui.Label {
                    text = "Victories:",
                    width = 120,
                },
                gui.Input {
                    fontSize = 14,
                    width = 40,
                    characterLimit = 1,
                    text = outcome.victories,
                    change = function(element)
                        local n = tonumber(element.text) or outcome.victories
                        outcome.victories = n
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
            gui.Panel {
                classes = { "formPanel" },
                halign = "left",
                width = 700,
                height = "auto",
                gui.Label {
                    text = entry.text .. ":",
                    height = "auto",
                    width = 120,
                    halign = "left",
                },
                gui.Input {
                    multiline = true,
                    fontSize = 14,
                    textAlignment = "topleft",
                    width = 540,
                    height = "auto",
                    maxHeight = 200,
                    minHeight = 30,
                    halign = "left",
                    characterLimit = 512,
                    placeholderText = "Describe outcome...",
                    text = outcome.text,
                    change = function(element)
                        outcome.text = element.text
                    end,
                },
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

    local m_montage = nil

    local closeButton
    local addParticipantButton

    if isDM then
        closeButton = gui.CloseButton {
            halign = "right",
            valign = "top",
            click = function(element)
                GameHud.HidePresentedDialog()
            end,
        }

        addParticipantButton = gui.AddButton {
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
                            bgcolor = "white",
                            width = "78% height",
                            height = 100,
                            bgimage = true,
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
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            fontSize = 16,
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
            floating = true,
            width = "0%",
            height = 20,
            bgcolor = "white",
            gradient = cond(mode == "success", Styles.healthGradient, Styles.bloodiedGradient),
            bgimage = true,
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
            width = 100,
            height = 20,
            valign = "center",
            halign = "left",
            flow = "horizontal",
            bgimage = true,
            bgcolor = "black",
            refreshMontage = function(element, montage)
                local difficultyInfo = montageDoc:GetDifficultyInfo(montage:HeroCount())
                local count = math.min(8, difficultyInfo[mode])
                element.selfStyle.width = count*100
                while #m_segments < count do
                    m_segments[#m_segments + 1] = gui.Panel {
                        borderWidth = 1,
                        borderColor = "white",
                        bgimage = true,
                        bgcolor = "clear",
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
            styles = {
                {
                    selectors = {"plusButton"},
                    width = 20,
                    height = 20,
                    borderWidth = 1,
                    borderColor = "white",
                    color = "white",
                    bgcolor = "black",
                    bold = true,
                    fontSize = 20,
                    textAlignment = "center",
                },
                {
                    selectors = {"plusButton", "hover"},
                    color = "black",
                    bgcolor = "white",
                },
            },
            gui.Label{
                classes = {"plusButton"},
                text = "-",
                bgimage = true,
                click = function(element)
                    incrementSuccess(-1)
                end,
            },
            successBar,
            gui.Label{
                classes = {"plusButton"},
                text = "+",
                bgimage = true,
                click = function(element)
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
                halign = "left",
                fontSize = 20,
                width = 100,
                height = 24,
                bold = true,
                text = "Successes:",
            },
            CreateSuccessBar("success"),
        },

        gui.Panel{
            flow = "horizontal",
            width = 900,
            height = 50,
            gui.Label{
                halign = "left",
                fontSize = 20,
                width = 100,
                height = 24,
                bold = true,
                text = "Failures:",
            },
            CreateSuccessBar("failure"),
        },
    }

    local resultPanel
    resultPanel = gui.Panel {
        width = 1100,
        height = 900,
        bgcolor = "black",
        bgimage = true,
        opacity = 0.9,
        blurBackground = true,
        monitorGame = doc.path,

        gui.Label {
            halign = "center",
            valign = "top",
            width = "auto",
            height = "auto",
            tmargin = 6,
            fontSize = 26,
            bold = true,
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

    resultPanel:FireEventTree("refreshMontage", doc.data.livedata)

    return resultPanel
end

GameHud.RegisterPresentableDialog {
    id = "montage",
    keeplocal = false,
    create = CreateMontageTestUI,
}

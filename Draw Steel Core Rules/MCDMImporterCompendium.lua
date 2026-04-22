local mod = dmhub.GetModLoading()

local function UnitTestNe(a, b, description)
    if a == b then
        error(string.format("TestNe failed %s: %s ~= %s at %s", description or "unit test", tostring(a), tostring(b), debug.traceback()))
    end
end

local function UnitTestEq(a, b, description)
    if a ~= b then
        error(string.format("TestEq failed %s: %s ~= %s at %s", description or "unit test", tostring(a), tostring(b), debug.traceback()))
    end
end

local function UnitTest(f)
    f()
end

local function WaysToReferToMonster(monsterName)
    monsterName = string.lower(monsterName)
    local result = {"[a-z0-9' ]{3,20}"}
    result[#result+1] = monsterName

    local words = string.split(monsterName, " ")

    for _,word in ipairs(words) do
        if word ~= "the" and word ~= "of" then
            word = string.gsub(word, ",", "")

            if word ~= monsterName then
                result[#result+1] = word
            end
            result[#result+1] = "the " .. word
        end
    end

    return result
end

local function MonsterNameToMatchPattern(monsterName)
    local words = WaysToReferToMonster(monsterName)
    return string.format("(?<monster>%s)", string.join(words, "|"))
end

UnitTest(function()
    UnitTestEq(MonsterNameToMatchPattern("Goblin"), "(?<monster>[a-z0-9' ]{3,20}|goblin|the goblin)")
    UnitTestEq(MonsterNameToMatchPattern("Goblin Boss"), "(?<monster>[a-z0-9' ]{3,20}|goblin boss|goblin|the goblin|boss|the boss)")

    local input = "Today's date is 2024-02-19."
    local pattern = [[(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})]]

    local result = regex.MatchGroups(input, pattern)

    UnitTestNe(result, nil)

    UnitTestEq(result["year"], "2024")
    UnitTestEq(result["month"], "02")
    UnitTestEq(result["day"], "19")
end)

local function CreateMatchPattern(monsterName, pattern)
    monsterName = monsterName or "monster"
    pattern = string.lower(pattern)

    local captures = {}
    for i=1,100 do
        local matchCapture = regex.MatchGroups(pattern, "^(?<prefix>.*?)(?<capture><<[A-Za-z]+>>)(?<suffix>.*)$")
        if matchCapture == nil then
            break
        end

        captures[#captures+1] = matchCapture

        pattern = matchCapture.suffix
    end

    captures[#captures+1] = { prefix = pattern, capture = "", suffix = ""}

    pattern = ""

    for _,capture in ipairs(captures) do
        local text = capture.prefix

        text = regex.ReplaceAll(text, [[\b(square|squares)\b]], "(square|squares)")
        text = regex.ReplaceAll(text, [[\b(edge|edges)\b]], "(edge|edges)")
        text = regex.ReplaceAll(text, [[\b(boon|boons)\b]], "(boon|boons)")
        text = regex.ReplaceAll(text, [[\b(bane|banes)\b]], "(bane|banes)")
        text = regex.ReplaceAll(text, [[\b(she|he|they|it)\b]], "(she|he|they|it)")
        text = regex.ReplaceAll(text, [[\b(is|are)\b]], "(is|are)")

        pattern = pattern .. text .. capture.capture
    end

    pattern = regex.ReplaceAll(pattern, "<<monster>>", MonsterNameToMatchPattern(monsterName))

    pattern = regex.ReplaceAll(pattern, "<<surges>>", "(?<surges>(\\:surge\\: *){1,5})")

    local matchGroupPattern = [[<<(?<identifier>[A-Za-z]+)>>]]
    local matchGroup = regex.MatchGroups(pattern, matchGroupPattern)
    local n = 100
    while matchGroup ~= nil and n > 0 do
        pattern = regex.ReplaceAll(pattern, "<<" .. matchGroup["identifier"] .. ">>", "(?<" .. matchGroup["identifier"] .. ">[0-9d]+|a|an|one|two|three|four|five|six|seven|eight|nine|ten)")
        matchGroup = regex.MatchGroups(pattern, matchGroupPattern)
        n = n-1
    end

    return pattern
end

local numberReplacements = {
    ["a"] = "1",
    ["an"] = "1",
    ["one"] = "1",
    ["two"] = "2",
    ["three"] = "3",
    ["four"] = "4",
    ["five"] = "5",
    ["six"] = "6",
    ["seven"] = "7",
    ["eight"] = "8",
    ["nine"] = "9",
    ["ten"] = "10",
}
local function ReplaceNumbers(str)
    local num = numberReplacements[string.lower(str)]
    return num or str
end

CharacterFeature.patternMatchPrefix = ""

function CharacterFeature:MatchMCDMMonsterTrait(bestiaryEntry, name, description)
    if self:has_key("importMatch") == false then
        return nil
    end

    bestiaryEntry = bestiaryEntry or {}

    local text = name

    if self:try_get("importMatchType", "rules") == "rules" then
        text = description
    end

    text = string.lower(text)

    local pattern = CreateMatchPattern(bestiaryEntry.name, self.importMatch)

    if text == pattern then
        return self, {}
    end

    pattern = self.patternMatchPrefix .. pattern

    local matches = regex.MatchGroups(text, pattern)
    if matches ~= nil then
        local clone = DeepCopy(self)
        matches["trait"] = name

        for key,val in pairs(matches) do
            local keyPattern = "<<" .. key .. ">>"

            local value = val
            if key == "surges" then
                local _, count = val:gsub(":", "")
                value = tostring(count/2)
            end

            MCDMUtils.DeepReplace(clone, keyPattern, ReplaceNumbers(value))
        end

        return clone, matches
    end

    return nil
end

--abilities require any matches to happen at the start of the text.
ActivatedAbility.patternMatchPrefix = "^\\s*"
ActivatedAbility.MatchMCDMEffect = CharacterFeature.MatchMCDMMonsterTrait

local function CreateEditPanel(tableName)
    local m_item = nil
    local editPanel
    editPanel = gui.Panel{
        styles = {
            Styles.Form,
        },
        vscroll = true,
        width = 1000,
        height = "90%",
        halign = "left",
        flow = "vertical",
        
        setdata = function(element, item)
            m_item = item
        end,

        change = function(element)
            if m_item ~= nil then
                dmhub.SetAndUploadTableItem(tableName, m_item)
            end
        end,

        modifiersChanged = function(element)
            editPanel:FireEvent("change")
        end,

        gui.Panel{
            classes = {"collapsed"},
            width = "98%",
            height = "auto",
            flow = "vertical",
            setdata = function(element, item)
                element:SetClass("collapsed", item == nil)
            end,

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Name:",
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 300,
                    halign = "left",
                    setdata = function(element, item)
                        element.text = item:try_get("name", "")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.name = element.text
                            editPanel:FireEvent("change")
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Match Type:",
                },

                gui.Dropdown{
                    options = {
                        {
                            id = "name",
                            text = "Name",
                        },
                        {
                            id = "rules",
                            text = "Rules Text",
                        },
                    },
                    halign = "left",
                    setdata = function(element, item)
                        element.idChosen = item:try_get("importMatchType", "rules")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.importMatchType = element.idChosen
                            editPanel:FireEvent("change")
                            editPanel:FireEventTree("testCasesChanged")
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Match Pattern:",
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 600,
                    halign = "left",
                    multiline = true,
                    height = "auto",
                    maxHeight = 200,
                    setdata = function(element, item)
                        element.text = item:try_get("importMatch", "")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.importMatch = element.text
                            editPanel:FireEvent("change")
                            editPanel:FireEventTree("testCasesChanged")
                        end
                    end,
                },

            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Expression:",
                },

                gui.Label{
                    classes = {"formLabel"},
                    width = 600,
                    height = "auto",
                    halign = "left",
                    setdata = function(element, item)
                        element:FireEvent("testCasesChanged")
                    end,
                    testCasesChanged = function(element)
                        if m_item ~= nil and m_item:has_key("importMatch") then
                            local pattern = CreateMatchPattern("monster", m_item.importMatch)
                            element.text = pattern
                        end
                    end,
                },

                gui.CopyButton{
                    width = 10,
                    height = 10,
                    click = function(element)
                        dmhub.CopyToClipboard(element.parent.children[2].text)
                    end,
                },

            },

            gui.Panel{
                width = 800,
                height = "auto",
                flow = "vertical",
                setdata = function(element, item)
                    local children = element.children

                    local testCases = item:try_get("testCases") or {}

                    for i,testCase in ipairs(testCases) do
                        children[i] = children[i] or gui.Panel{
                            classes = {"formPanel"},
                            width = "100%",

                            gui.Input{
                                classes = {"formInput"},
                                width = 600,
                                halign = "left",
                                multiline = true,
                                height = "auto",
                                maxHeight = 200,
                                settest = function(element, testCase)
                                    element.text = testCase.text
                                end,
                                change = function(element)
                                    if m_item ~= nil then
                                        m_item.testCases[i].text = element.text
                                        editPanel:FireEvent("change")
                                        editPanel:FireEventTree("testCasesChanged")
                                    end
                                end,
                                edit = function(element)
                                    element.parent:FireEventTree("runtest", element.text)
                                end,
                            },

                            gui.Label{
                                text = "---",
                                width = 140,
                                height = "auto",
                                fontSize = 14,
                                halign = "left",
                                settest = function(element, testCase)
                                    element:FireEvent("runtest", testCase.text)
                                end,

                                runtest = function(element, text)
                                    local trait, matches = m_item:MatchMCDMMonsterTrait(nil, text, text)
                                    if matches ~= nil then
                                        element.text = "Match"
                                    else
                                        element.text = "No Match"
                                    end
                                end,
                            },

                            gui.DeleteItemButton{
                                width = 16,
                                height = 16,
                                click = function(element)
                                    local testCases = m_item:try_get("testCases") or {}
                                    table.remove(testCases, i)
                                    editPanel:FireEvent("change")
                                    editPanel:FireEventTree("testCasesChanged")
                                end,
                            }
                        }

                        children[i]:FireEventTree("settest", testCase)
                    end

                    while #children > #testCases do
                        children[#children] = nil
                    end

                    element.children = children
                end,
                testCasesChanged = function(element)
                    element:FireEvent("setdata", m_item)
                end,
            },

            gui.Button{
                width = 100,
                height = 24,
                fontSize = 14,
                text = "Add Test Case",
                click = function(element)
                    m_item.testCases = m_item:try_get("testCases") or {}
                    m_item.testCases[#m_item.testCases+1] = {
                        text = "Sample trait text",
                    }
                    editPanel:FireEvent("change")
                    editPanel:FireEventTree("testCasesChanged")
                end,
            },

        },

        gui.Panel{
            width = "98%",
            halign = "left",
            height = "auto",

            setdata = function(element, item)
                element.children = {
                    item:EditorPanel{
                        noscroll = true,
                        collapseDescription = true,
                        modifierRefreshed = function(element)
                            editPanel:FireEvent("change")
                        end,
                    }
                }
            end,
        }
    }

    return editPanel
end

local function ShowTraitsPanel(parentPanel, tableName, options)
    options = options or {}
    local dataItems = {}
    local editPanel = CreateEditPanel(tableName)
    local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(tableName) or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = tableName,
                    key = k,
					select = element.aliveTime > 0.2,
					click = function()
						editPanel:SetClass("hidden", false)
						editPanel:FireEventTree("setdata", dataTable[k])
					end,
				}

				local desc = item.name
				if desc == nil or desc == "" then
					desc = "(unnamed)"
				end

				newDataItems[k].text = desc

				children[#children+1] = newDataItems[k]
			end

            table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			element.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{

			click = function(element)
                local newData = CharacterFeature.Create{
                    name = options.featureName or "New Trait",
                    source = options.featureSource or "Monster",
                }

                dmhub.SetAndUploadTableItem(tableName, newData)
			end,
		}
	}

	parentPanel.children = {leftPanel, editPanel}	
end

Compendium.Register{
    section = "Import",
    text = "Monster Traits",
    contentType = "importerMonsterTraits",
    click = function(contentPanel)
        ShowTraitsPanel(contentPanel, "importerMonsterTraits", {
            featureName = "New Monster Trait",
            featureSource = "Monster",
        })
    end,
}

Compendium.Register{
    section = "Import",
    text = "Minion With Captain",
    contentType = "minionWithCaptain",
    click = function(contentPanel)
        ShowTraitsPanel(contentPanel, "minionWithCaptain", {
            featureName = "With Captain",
            featureSource = "Monster",
        })
    end,
}

Compendium.Register{
    section = "Import",
    text = "Standard Features",
    contentType = "importerStandardFeatures",
    click = function(contentPanel)
        ShowTraitsPanel(contentPanel, "importerStandardFeatures", {
            featureName = "New Feature",
            featureSource = "Character",
        })
    end,
}

Compendium.Register{
    section = "Import",
    text = "Monster Balance",
    contentType = "importerMonsterBalance",
    click = function(contentPanel)
        ShowTraitsPanel(contentPanel, "importerMonsterBalance", {
            featureName = "Monster Balance",
            featureSource = "Monster",
        })
    end,
}

local function CreateEditAbilityEffectsPanel(tableName)
    local m_item = nil
    local editPanel
    editPanel = gui.Panel{
        styles = {
            Styles.Form,
        },
        vscroll = true,
        width = 1000,
        height = "90%",
        halign = "left",
        flow = "vertical",

        destroy = function(element)
            if m_item ~= nil then
                dmhub.SetAndUploadTableItem(tableName, m_item)
            end
        end,
        
        setdata = function(element, item)
            if m_item ~= nil then
                dmhub.SetAndUploadTableItem(tableName, m_item)
            end

            m_item = item
        end,

        change = function(element)
            if m_item ~= nil then
                dmhub.SetAndUploadTableItem(tableName, m_item)
            end
        end,

        modifiersChanged = function(element)
            editPanel:FireEvent("change")
        end,

        gui.Panel{
            classes = {"collapsed"},
            width = "98%",
            height = "auto",
            flow = "vertical",
            setdata = function(element, item)
                element:SetClass("collapsed", item == nil)
            end,

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Name:",
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 300,
                    halign = "left",
                    characterLimit = 120,
                    setdata = function(element, item)
                        element.text = item:try_get("name", "")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.name = element.text
                            editPanel:FireEvent("change")
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",
                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "GUID:",
                },
                gui.Input{
                    width = 300,
                    halign = "left",
                    classes = {"formInput"},
                    setdata = function(element, item)
                        element.text = item:try_get("id", "")
                    end,
                }
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Documentation:",
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 300,
                    minHeight = 40,
                    maxHeight = 200,
                    height = "auto",
                    characterLimit = 600,
                    multiline = true,
                    textAlignment = "topleft",
                    halign = "left",
                    setdata = function(element, item)
                        element.text = item:try_get("documentation", "")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.documentation = element.text
                            editPanel:FireEvent("change")
                        end
                    end,
                },
            },




            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Match Type:",
                },

                gui.Dropdown{
                    options = {
                        {
                            id = "name",
                            text = "Name",
                        },
                        {
                            id = "rules",
                            text = "Rules Text",
                        },
                    },
                    halign = "left",
                    setdata = function(element, item)
                        element.idChosen = item:try_get("importMatchType", "rules")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.importMatchType = element.idChosen
                            editPanel:FireEvent("change")
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Match Pattern:",
                },

                gui.Input{
                    classes = {"formInput"},
                    width = 600,
                    halign = "left",
                    multiline = true,
                    height = "auto",
                    maxHeight = 200,
                    setdata = function(element, item)
                        element.text = item:try_get("importMatch", "")
                    end,
                    change = function(element)
                        if m_item ~= nil then
                            m_item.importMatch = element.text
                            editPanel:FireEvent("change")
                            editPanel:FireEventTree("testCasesChanged")
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                width = "100%",

                gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = "Expression:",
                },

                gui.Label{
                    classes = {"formLabel"},
                    width = 600,
                    height = "auto",
                    halign = "left",
                    setdata = function(element, item)
                        element:FireEvent("testCasesChanged")
                    end,
                    testCasesChanged = function(element)
                        if m_item ~= nil and m_item:has_key("importMatch") then
                            local pattern = CreateMatchPattern("monster", m_item.importMatch)
                            element.text = pattern
                        end
                    end,
                },

            },

            gui.Panel{
                width = 800,
                height = "auto",
                flow = "vertical",
                setdata = function(element, item)
                    local children = element.children

                    local testCases = item:try_get("testCases") or {}

                    for i,testCase in ipairs(testCases) do
                        children[i] = children[i] or gui.Panel{
                            classes = {"formPanel"},
                            width = "100%",

                            gui.Input{
                                classes = {"formInput"},
                                width = 600,
                                halign = "left",
                                multiline = true,
                                height = "auto",
                                maxHeight = 200,
                                settest = function(element, testCase)
                                    element.text = testCase.text
                                end,
                                change = function(element)
                                    if m_item ~= nil then
                                        m_item.testCases[i].text = element.text
                                        editPanel:FireEvent("change")
                                        editPanel:FireEventTree("testCasesChanged")
                                    end
                                end,
                                edit = function(element)
                                    element.parent:FireEventTree("runtest", element.text)
                                end,
                            },

                            gui.Label{
                                text = "---",
                                width = 140,
                                height = "auto",
                                fontSize = 14,
                                halign = "left",
                                settest = function(element, testCase)
                                    element:FireEvent("runtest", testCase.text)
                                end,

                                runtest = function(element, text)
                                    local trait, matches = m_item:MatchMCDMEffect(nil, text, text)
                                    if matches ~= nil then
                                        element.text = "Match"
                                    else
                                        element.text = "No Match"
                                    end
                                end,
                            },

                            gui.DeleteItemButton{
                                width = 16,
                                height = 16,
                                click = function(element)
                                    local testCases = m_item:try_get("testCases") or {}
                                    table.remove(testCases, i)
                                    editPanel:FireEvent("change")
                                    editPanel:FireEventTree("testCasesChanged")
                                end,
                            }
                        }

                        children[i]:FireEventTree("settest", testCase)
                    end

                    while #children > #testCases do
                        children[#children] = nil
                    end

                    element.children = children
                end,
                testCasesChanged = function(element)
                    element:FireEvent("setdata", m_item)
                end,
            },

            gui.Button{
                width = 100,
                height = 24,
                fontSize = 14,
                text = "Add Test Case",
                click = function(element)
                    m_item.testCases = m_item:try_get("testCases") or {}
                    m_item.testCases[#m_item.testCases+1] = {
                        text = "Sample effect text",
                    }
                    editPanel:FireEvent("change")
                    editPanel:FireEventTree("testCasesChanged")
                end,
            },

            gui.Check{
                text = "Insert Behaviors At Start",
                setdata = function(element, item)
                    if m_item ~= nil then
                        element.value = item:try_get("insertAtStart", false)
                    end
                end,
                change = function(element)
                    m_item.insertAtStart = element.value
                    editPanel:FireEvent("change")
                    editPanel:FireEventTree("testCasesChanged")
                end,
            },

            gui.Check{
                text = "Invoke Surrounding Ability",
                setdata = function(element, item)
                    if m_item ~= nil then
                        element.value = item:try_get("invokeSurroundingAbility", false)
                    end
                end,
                change = function(element)
                    m_item.invokeSurroundingAbility = element.value
                    editPanel:FireEvent("change")
                    editPanel:FireEventTree("testCasesChanged")
                end,
            },
        },

        gui.Panel{
            width = "98%",
            halign = "left",
            lmargin = 12,
            height = "auto",

            setdata = function(element, item)
                element.children = {
                    item:GenerateEditor{
                        embedded = true,
                    }
                }
            end,
        }
    }

    return editPanel
end



local function ShowAbilityEffectsPanel(parentPanel, tableName)
    local dataItems = {}
    local editPanel = CreateEditAbilityEffectsPanel(tableName)
    local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(tableName) or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
                    tableName = tableName,
                    key = k,
					select = element.aliveTime > 0.2,
					click = function()
						editPanel:SetClass("hidden", false)
						editPanel:FireEventTree("setdata", dataTable[k])
					end,
				}

				local desc = item.name
				if desc == nil or desc == "" then
					desc = "(unnamed)"
				end

				newDataItems[k].text = desc

				children[#children+1] = newDataItems[k]
			end
            table.sort(children, function(a,b) return a.text < b.text end)

			dataItems = newDataItems
			element.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{

			click = function(element)
                local newData = ActivatedAbility.Create{
                    name = "New Ability",
                    source = "Monster",
                    categorization = "Hidden",
                }

                dmhub.SetAndUploadTableItem(tableName, newData)
			end,
		}
	}

	parentPanel.children = {leftPanel, editPanel}	
end

Compendium.Register{
    section = "Import",
    text = "Ability Effects",
    contentType = "importerAbilityEffects",
    click = function(contentPanel)
        ShowAbilityEffectsPanel(contentPanel, "importerAbilityEffects")
    end,
}

Compendium.Register{
    section = "Import",
    text = "Power Table Effects",
    contentType = "importerPowerTableEffects",
    click = function(contentPanel)
        ShowAbilityEffectsPanel(contentPanel, "importerPowerTableEffects")
    end,
}

Compendium.Register{
    section = "Import",
    text = "Standard Abilities",
    contentType = "standardAbilities",
    click = function(contentPanel)
        ShowAbilityEffectsPanel(contentPanel, "standardAbilities")
    end,
}
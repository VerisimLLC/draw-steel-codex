local mod = dmhub.GetModLoading()

RegisterGameType("AttributeGenerator")

AttributeGenerator.tableName = "attributeGenerator"
AttributeGenerator.method = "manual"
AttributeGenerator.hiddenFromPlayers = false
AttributeGenerator.ord = 1

AttributeGenerator.standardArray = {15,14,13,12,10,8}

AttributeGenerator.roll = "4d6 keep 3"
AttributeGenerator.extraRolls = 0
AttributeGenerator.lockInPlayerRolls = false

AttributeGenerator.availableMethods = {}
AttributeGenerator.name = "Manual Entry"

AttributeGenerator.points = 27

function AttributeGenerator:GetPointBuyDefaultValue()
    local t = self:GetPointBuyTable()
    local firstValue = nil

    for k,entry in ipairs(t.entries) do
        if firstValue == nil then
            firstValue = entry.threshold
        end
        if ExecuteGoblinScript(entry.script, {}, "") == 0 then
            return entry.threshold
        end
    end

    return firstValue or 0
end

function AttributeGenerator:GetPointBuyTable()
    if self:has_key("pointBuyTable") then
        return self.pointBuyTable
    end

    return GoblinScriptTable.new{
        id = "table",
        field = "Value",
        editableField = false,
        entries = {
            {
                threshold = 8,
                script = "0",
            },
            {
                threshold = 9,
                script = "1",
            },
            {
                threshold = 10,
                script = "2",
            },
            {
                threshold = 11,
                script = "3",
            },
            {
                threshold = 12,
                script = "4",
            },
            {
                threshold = 13,
                script = "5",
            },
            {
                threshold = 14,
                script = "7",
            },
            {
                threshold = 15,
                script = "9",
            },
        }
    }
end

function AttributeGenerator:GetStandardArray()
    local result = {}

    for i=1,#creature.attributeIds do
        local n = self.standardArray[i]
        if n == nil then
            n = self.standardArray[1]
            if n == nil then
                n = 10
            end
        end

        result[i] = n
    end

    return result
end

function AttributeGenerator:SetStandardArrayElement(index, n)
    local array = self:GetStandardArray()
    array[index] = n
    self.standardArray = array
end

local methodsByKey = {}

function AttributeGenerator.Register(options)
    AttributeGenerator.availableMethods[#AttributeGenerator.availableMethods+1] = options
    methodsByKey[options.id] = options
end

AttributeGenerator.Register{
    id = "manual",
    text = "Manual Entry",
    editor = function(self, parentPanel)
    end,
}

AttributeGenerator.Register{
    id = "roll",
    text = "Roll",
    editor = function(self, parentPanel)
        parentPanel.children = {
            gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Roll:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = self.roll,
                    change = function(element)
                        self.roll = element.text
                        parentPanel:FireEvent("change")
                    end,
                }
            },

            gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Extra Rolls:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = tostring(self.extraRolls),
                    change = function(element)
                        local n = tonumber(element.text)
                        if n ~= nil then
                            n = round(n)
                            if n < 0 then
                                n = 0
                            end

                            self.extraRolls = n
                            parentPanel:FireEvent("change")
                        end

                        element.text = tostring(self.extraRolls)
                    end,
                }
            },

            gui.Check{
                linger = gui.Tooltip("After a player makes a roll they won't be able to change it or choose another method."),
                text = "Lock in Player Rolls",
                value = self.lockInPlayerRolls,
                change = function(element)
                    self.lockInPlayerRolls = element.value
                    parentPanel:FireEvent("change")
                end,
            }
        }
    end,
}

AttributeGenerator.Register{
    id = "array",
    text = "Standard Array",
    editor = function(self, parentPanel)
        local array = self:GetStandardArray()

        local children = {}
        for i,n in ipairs(array) do
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = string.format("Item %d:", i)
                },
                gui.Input{
                    classes = {"formInput"},
                    text = tostring(n),
                    change = function(element)
                        local num = tonumber(element.text)
                        if num ~= nil then
                            num = round(num)
                            self:SetStandardArrayElement(i, num)
                            parentPanel:FireEvent("change")
                        else
                            element.text = tostring(n)

                        end


                    end,
                }
            }
        end

        parentPanel.children = children
    end,
}

AttributeGenerator.Register{
    id = "points",
    text = "Points Buy",
    editor = function(self, parentPanel)
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Points:",
            },
            gui.Input{
                classes = {"formInput"},
                text = tostring(self.points),
                change = function(element)
                    local n = tonumber(element.text)
                    if n ~= nil then
                        n = round(n)
                        self.points = n
                        parentPanel:FireEvent("change")
                    else
                        element.text = tostring(self.points)
                    end
                end,
            }
        }

        children[#children+1] = gui.GoblinScriptInput{
            value = self:GetPointBuyTable(),
            fieldName = "Point Cost",
            events = {
                change = function(element)
                    self.pointBuyTable = DeepCopy(element.value)
                    parentPanel:FireEvent("change")
                end,
            },
        }

        parentPanel.children = children
    end,
}

function AttributeGenerator.CreateNew()
    return AttributeGenerator.new{
        id = dmhub.GenerateGuid(),
    }
end

local ShowEditor = function(data, method, resultPanel)

    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        change = function(element)
            resultPanel:FireEvent("change")
        end,
    }

    method.editor(data, panel)

    local children = {

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Name:",
            },
            gui.Input{
                classes = {"formInput"},
                text = data.name,
                change = function(element)
                    data.name = element.text
                    resultPanel:FireEvent("change")
                end,
            },
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Order:",
            },
            gui.Input{
                classes = {"formInput"},
                text = tostring(data.ord),
                change = function(element)
                    if tonumber(element.text) then
                        data.ord = tonumber(element.text)
                        resultPanel:FireEvent("change")
                    else
                        element.text = tostring(data.ord)
                    end
                end,
            },
        },



        gui.Check{
            text = "Hidden from Players",
            value = data.hiddenFromPlayers,
            change = function(element)
                data.hiddenFromPlayers = element.value
                resultPanel:FireEvent("change")
            end,
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Method:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = AttributeGenerator.availableMethods,
                idChosen = data.method,
                change = function(element)
                    data.method = element.idChosen
                    resultPanel:FireEvent("change")
                end,
            }
        },

        panel,
    }



    resultPanel.children = children
end

function AttributeGenerator.CreateEditor()
    local m_key = nil
    local m_data = nil
    local resultPanel

    resultPanel = gui.Panel{
        width = 1200,
        height = 900,
        hpad = 16,
        flow = "vertical",
        vscroll = true,

        styles = {
            Styles.Form,
            {
                selectors = {"formLabel"},
                halign = "left",
            },
            {
                selectors = {"formInput"},
                halign = "left",
            },
            {
                selectors = {"formDropdown"},
                halign = "left",
            },
            {
                --we don't want goblin scripts to have documentation or configurability.
                selectors = {"goblinScriptLogo"},
                priority = 10,
                collapsed = 1,
            }
        },

        data = {
            SetData = function(key)
                m_key = key

                local tbl = dmhub.GetTable(AttributeGenerator.tableName)
                local data = tbl[key]
                m_data = data
                if data == nil then
                    return
                end

                local method = methodsByKey[data.method]

                ShowEditor(data, method, resultPanel)
            end,
        },

        change = function(element)
            dmhub.SetAndUploadTableItem(AttributeGenerator.tableName, m_data)
            resultPanel.data.SetData(m_key)
        end,
    }

    return resultPanel
end
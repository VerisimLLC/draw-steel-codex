local mod = dmhub.GetModLoading()

--- @class CustomField
--- @field name string Display name of the field.
--- @field type string Field value type (currently only "number").
--- @field default number Default value when unset.
--- @field documentation string Human-readable description of the field's purpose.
--- @field display boolean If true, show this field on the creature description panel.
CustomField = RegisterGameType("CustomField")

CustomField.name = "Custom Field"
CustomField.type = "number"
CustomField.default = 0
CustomField.documentation = ""
CustomField.display = true

function CustomField:SymbolName()
    return string.gsub(string.lower(self.name), "[^a-zA-Z]", "")
end

CustomField.typeOptions = {
    {
        id = "number",
        text = "Number",
    }
}

function CustomField:GetValue(obj)
    local customFields = obj:try_get("customFields")
    if customFields ~= nil then
        return customFields:try_get(self.id, self.default)
    end

    return self.default
end

--- @class CustomFieldCollection
--- @field name string Display name ("Custom Fields").
--- @field tableName string Data table name ("customfields").
--- @field fieldTypes string[] Data type ids that support custom fields (e.g. {"spells"}).
--- @field fields table<string, CustomField> Map of field id to CustomField definitions.
CustomFieldCollection = RegisterGameType("CustomFieldCollection")

CustomFieldCollection.name = "Custom Fields"
CustomFieldCollection.tableName = "customfields"
CustomFieldCollection.fieldTypes = {"spells"}

function CustomFieldCollection:Empty()
    for _,_ in pairs(self.fields) do
        return false
    end

    return true
end

function CustomFieldCollection.CreateEditor(dataType)
    local t = dmhub.GetTable(CustomFieldCollection.tableName) or {}
    local data = t[dataType]
    if data == nil then
        data = CustomFieldCollection.new{
            id = dataType,
            fields = {},
        }
    end

    local resultPanel
    resultPanel = gui.Panel{
        flow = "vertical",
        width = 600,
        height = "auto",
        styles = {
            Styles.Form,
            {
                selectors = {"formLabel"},
                textAlignment = "left",
                halign = "left",
            },
            {
                selectors = {"formField"},
                halign = "left",
            },
        },

        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",

            refreshData = function(element)
                element:FireEvent("create")
            end,

            create = function(element)
                local children = {}
                for k,v in pairs(data.fields) do
                    children[#children+1] = gui.Panel{
                        flow = "vertical",
                        width = "100%",
                        height = "auto",

                        gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Name:",
                                minWidth = 160,
                            },

                            gui.Input{
                                classes = {"formInput", "formField"},
                                text = v.name,
                                characterLimit = 32,
                                change = function(element)
                                    local text = trim(string.gsub(element.text, "[^a-zA-Z ]", ""))
                                    if text == "" then
                                        text = v.name
                                    end

                                    element.text = text
                                    v.name = text

                                    dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                                end,
                            },

                            gui.DeleteItemButton{
                                classes = {"formDeleteButton"},
                                click = function(element)
                                    data.fields[k] = nil
                                    dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                                    resultPanel:FireEventTree("refreshData")
                                end,
                            }
                        },

                        gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Type:",
                                minWidth = 160,
                            },

                            gui.Dropdown{
                                classes = {"formDropdown", "formField"},
                                options = CustomField.typeOptions,
                                idChosen = v.type,

                                change = function(element)
                                    v.type = element.idChosen
                                    dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                                end,
                            },
                        },

                        gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{
                                classes = {"formLabel"},
                                text = "Default:",
                                minWidth = 160,
                            },

                            gui.Input{
                                classes = {"formInput", "formField"},
                                text = tostring(v.default),
                                characterLimit = 12,
                                change = function(element)
                                    local num = tonumber(element.text)
                                    if num == nil then
                                        num = v.default
                                    end
                                    v.default = num
                                    dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                                end,
                            },
                        },

                        gui.Check{
                            classes = {"formCheckbox", "formField"},
                            value = v.display,
                            text = "Display in Description",
                            change = function(element)
                                v.display = element.value
                                dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                            end,
                        },

                        gui.Input{
                            text = v.documentation,
                            width = 500,
                            height = "auto",
                            textAlignment = "topleft",
                            placeholderText = "Describe field...",
                            minHeight = 60,
                            maxHeight = 200,
                            multiline = true,
                            characterLimit = 1000,
                            change = function(element)
                                v.documentation = element.text
                                dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                            end,
                        }

                    }
                end

                element.children = children
            end,
        },

        gui.Button{
            classes = {"addButton"},
            halign = "right",
            valign = "bottom",
            click = function(element)
                local id = dmhub.GenerateGuid()
                data.fields[id] = CustomField.new{
                    id = id,
                }

                dmhub.SetAndUploadTableItem(CustomFieldCollection.tableName, data)
                resultPanel:FireEventTree("refreshData")
            end,
        }

    }

    return resultPanel

end

--- @class CustomFieldInstance
--- @field fieldType string Data type id this instance belongs to (e.g. "spells").
--- @field dataType string Id of the CustomFieldCollection schema this instance follows.
--- A live instance of custom field values attached to a game object (stored as `obj.customFields`).
CustomFieldInstance = RegisterGameType("CustomFieldInstance")

CustomFieldInstance.fieldType = "spells"

function CustomFieldInstance.CreateEditor(parentObject, dataType)
    local t = dmhub.GetTable(CustomFieldCollection.tableName) or {}
    local data = t[dataType]
    if data == nil or data:Empty() then
        return nil
    end

    local instance = parentObject:try_get("customFields")
    if instance == nil then
        instance = CustomFieldInstance.new{
            dataType = dataType
        }
    end

    return instance:Editor(parentObject, data)
end

--data is a CustomFieldCollection which describes the schema for this instance.
function CustomFieldInstance:Editor(parentObject, data)

    local resultPanel

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",

        create = function(element)
            local children = {}

            for k,v in pairs(data.fields) do
                children[#children+1] =
                gui.Panel{
                    data = {
                        ord = v.name,
                    },
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = v.name,
                        minWidth = 160,
                    },

                    gui.Input{
                        classes = {"formInput", "formField"},
                        text = tostring(self:try_get(k, v.default)),
                        change = function(element)
                            local num = tonumber(element.text)
                            if num == nil then
                                num = v.default
                            end
                            self[k] = num
                            element.text = tostring(num)
                            parentObject.customFields = self
                        end,
                    },
                }
            end

            table.sort(children, function(a,b) return a.ord < b.ord end)

            element.children = children
        end,

    }

    return resultPanel
end
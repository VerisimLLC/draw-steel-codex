local mod = dmhub.GetModLoading()

--- @class VisionType
--- @field name string Display name (e.g. "Darkvision", "Tremorsense").
--- @field tableName string Data table name ("VisionType").
--- @field type string Vision behavior id: "none", "normal", or "dark".
--- @field penetrateWalls boolean If true, this vision type can see through walls.
--- @field fieldOfView boolean If true, field-of-view rules apply to this vision.
--- @field defaultValue number Default range in world units (0 = not possessed by default).
--- @field hidden boolean If true, hidden from character sheet and UI.
--- @field alwaysShowOnCharacterSheet boolean If true, always shown on character sheet even when 0.
VisionType = RegisterGameType("VisionType")

VisionType.tableName = "VisionType"
VisionType.name = "Vision"
VisionType.type = "none"
VisionType.penetrateWalls = false
VisionType.fieldOfView = false
VisionType.defaultValue = 0
VisionType.hidden = false
VisionType.alwaysShowOnCharacterSheet = false

--- Appends vision attribute entries into the list for use in attribute dropdowns.
--- @param list {id: string, text: string, attributeType: string, category: string}[]
--this populates the CustomAttributes list with vision attributes.
function VisionType.PopulateAttributes(list)
    local t = dmhub.GetTable(VisionType.tableName) or {}

    for k,v in pairs(t) do
        list[#list+1] = {
            id = k,
            text = v.name,
            attributeType = "number",
            category = "Senses",
        }
    end
end

VisionType.availableTypes = {
    {
        id = "none",
        text = "None",
    },
    {
        id = "normal",
        text = "Normal",
    },
    {
        id = "dark",
        text = "Darkvision",
    }
}

--- @param args nil|table
--- @return VisionType
function VisionType.CreateNew(args)
    local options = {
        id = dmhub.GenerateGuid(),
    }

    for k,v in pairs(args or {}) do
        options[k] = v
    end

    return VisionType.new(options)
end

function VisionType.CreateEditor()
    local resultPanel

    local m_vision = nil

    local Upload = function()
        dmhub.SetAndUploadTableItem(VisionType.tableName, m_vision)
    end

    resultPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = 1000,
        height = "auto",

        data = {
            SetData = function(id)
                local t = dmhub.GetTable(VisionType.tableName) or {}
                local vision = t[id]
                if vision ~= nil then
                    m_vision = vision
                    resultPanel:FireEventTree("vision")
                    resultPanel:SetClass("hidden", false)
                else
                    resultPanel:SetClass("hidden", true)
                end
            end,
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Name:",
            },
            gui.Input{
                classes = {"formStacked"},
                text = "",
                characterLimit = 24,
                vision = function(element)
                    element.text = m_vision.name
                end,
                change = function(element)
                    m_vision.name = element.text
                    Upload()
                end,
            }
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Label{
                classes = {"formStacked"},
                text = "Vision:",
            },
            gui.Dropdown{
                classes = {"formStacked"},
                options = VisionType.availableTypes,
                vision = function(element)
                    element.idChosen = m_vision.type
                end,
                change = function(element)
                    m_vision.type = element.idChosen
                    Upload()
                end,
            }
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Check{
                text = "Penetrates Solid",

                vision = function(element)
                    element.value = m_vision.penetrateWalls
                end,
                change = function(element)
                    m_vision.penetrateWalls = element.value
                    Upload()
                end,
            },
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Check{
                text = "Respect Field of View",

                vision = function(element)
                    element.value = m_vision.fieldOfView
                end,
                change = function(element)
                    m_vision.fieldOfView = element.value
                    Upload()
                end,
            },
        },

        gui.Panel{
            classes = {"formStackedRow"},
            gui.Check{
                text = "Always Show on Character Sheet",

                vision = function(element)
                    element.value = m_vision.alwaysShowOnCharacterSheet
                end,
                change = function(element)
                    m_vision.alwaysShowOnCharacterSheet = element.value
                    Upload()
                end,
            },
        },

    }

    return resultPanel
end
local mod = dmhub.GetModLoading()

--- A Downtime Activity definition: a reusable template a Director authors in the
--- compendium and which can later seed a downtime project. Field names mirror
--- DTProject / equipment items so values map straight across.
--- @class DowntimeActivity
--- @field id string GUID identifier (engine-managed for table items)
--- @field name string Display name (also the compendium list label)
--- @field itemPrerequisite string Short text describing any prerequisite
--- @field projectSource string Short text describing the source (book, tutor, etc.)
--- @field projectSourceLanguages string[] Language ids associated with the source
--- @field testCharacteristics string[] DTConstants.CHARACTERISTICS keys usable for the roll
--- @field projectGoal string Short text goal (number first, optional detail in parentheses)
--- @field tableName string Data table name ("downtimeActivities")
DowntimeActivity = RegisterGameType("DowntimeActivity")

DowntimeActivity.tableName = "downtimeActivities"

DowntimeActivity.name = "New Downtime Activity"
DowntimeActivity.itemPrerequisite = ""
DowntimeActivity.projectSource = ""
DowntimeActivity.projectGoal = ""

--- Creates a new downtime activity instance
--- @param args table|nil Optional field overrides (Compendium.GenericEditor calls this as CreateNew{})
--- @return DowntimeActivity instance The new activity instance
function DowntimeActivity.CreateNew(args)
    args = args or {}
    args.projectSourceLanguages = args.projectSourceLanguages or {}
    args.testCharacteristics = args.testCharacteristics or {}
    return DowntimeActivity.new(args)
end

--- Gets the identifier of this activity
--- @return string id GUID id of this activity
function DowntimeActivity:GetID()
    return self:try_get("id") or ""
end

--- Gets the display name of this activity
--- @return string name The activity name
function DowntimeActivity:GetName()
    return self.name or ""
end

--- Sets the display name of this activity
--- @param name string The new name
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetName(name)
    self.name = name or ""
    return self
end

--- Gets the prerequisite for this activity
--- @return string prerequisite The prerequisite text
function DowntimeActivity:GetItemPrerequisite()
    return self.itemPrerequisite or ""
end

--- Sets the prerequisite for this activity
--- @param prerequisite string The prerequisite text
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetItemPrerequisite(prerequisite)
    self.itemPrerequisite = prerequisite or ""
    return self
end

--- Gets the project source for this activity
--- @return string projectSource The project source text
function DowntimeActivity:GetProjectSource()
    return self.projectSource or ""
end

--- Sets the project source for this activity
--- @param source string The project source text
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetProjectSource(source)
    self.projectSource = source or ""
    return self
end

--- Gets the language ids associated with this activity's source
--- @return string[] languageIds The list of language ids
function DowntimeActivity:GetProjectSourceLanguages()
    return self:try_get("projectSourceLanguages") or {}
end

--- Sets the language ids associated with this activity's source
--- @param langIds string[] The list of language ids
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetProjectSourceLanguages(langIds)
    self.projectSourceLanguages = langIds or {}
    return self
end

--- Gets the test characteristics for this activity
--- @return string[] characteristics DTConstants.CHARACTERISTICS keys
function DowntimeActivity:GetTestCharacteristics()
    return self:try_get("testCharacteristics") or {}
end

--- Sets the test characteristics for this activity
--- @param characteristics string[] DTConstants.CHARACTERISTICS keys
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetTestCharacteristics(characteristics)
    self.testCharacteristics = characteristics or {}
    return self
end

--- Gets the goal text for this activity
--- @return string goal The goal text
function DowntimeActivity:GetProjectGoal()
    return self.projectGoal or ""
end

--- Sets the goal text for this activity
--- @param goal string The goal text
--- @return DowntimeActivity self For chaining
function DowntimeActivity:SetProjectGoal(goal)
    self.projectGoal = goal or ""
    return self
end

--- Builds dropdown options for every visible language
--- @return DropdownOption[] options List of { id, text } language options
local function GetLanguageOptions()
    local result = {}
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    for k, language in pairs(langTable) do
        result[#result + 1] = {
            id = k,
            text = language.name,
        }
    end
    return result
end

--- Converts an array of ids into a multiselect value set (id -> true)
--- @param ids string[] The array of ids
--- @return table set The id -> true set
local function ArrayToSet(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do
        set[id] = true
    end
    return set
end

--- Rebuilds the editor form for the selected activity
--- @param editorPanel table The editor root panel
--- @param activityId string The GUID of the activity to edit
local function SetActivity(editorPanel, activityId)
    local activityTable = dmhub.GetTable(DowntimeActivity.tableName) or {}
    local activity = activityTable[activityId]
    if activity == nil then
        editorPanel.children = {}
        return
    end

    local Upload = function()
        dmhub.SetAndUploadTableItem(DowntimeActivity.tableName, activity)
    end

    local children = {}

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Name:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = activity:GetName(),
            editlag = 0.4,
            focus = function(element)
                if element.text == DowntimeActivity.name then
                    element.caretPosition = element.text:len()
                    element.selectionAnchorPosition = 0
                end
            end,
            change = function(element)
                activity:SetName(element.text)
                Upload()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Prerequisite:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = activity:GetItemPrerequisite(),
            editlag = 0.4,
            change = function(element)
                activity:SetItemPrerequisite(element.text)
                Upload()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Project Source:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = activity:GetProjectSource(),
            editlag = 0.4,
            change = function(element)
                activity:SetProjectSource(element.text)
                Upload()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Languages:",
        },
        gui.Multiselect{
            classes = {"formStacked"},
            options = GetLanguageOptions(),
            value = ArrayToSet(activity:GetProjectSourceLanguages()),
            textDefault = "Select languages...",
            sort = true,
            change = function(element)
                activity:SetProjectSourceLanguages(DTHelpers.FlagListToList(element.value))
                Upload()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Characteristics:",
        },
        gui.Multiselect{
            classes = {"formStacked"},
            options = DTHelpers.ListToDropdownOptions(DTConstants.CHARACTERISTICS),
            value = ArrayToSet(activity:GetTestCharacteristics()),
            textDefault = "Select characteristics...",
            sort = true,
            change = function(element)
                activity:SetTestCharacteristics(DTHelpers.FlagListToList(element.value))
                Upload()
            end,
        },
    }

    children[#children + 1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Goal:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = activity:GetProjectGoal(),
            editlag = 0.4,
            change = function(element)
                activity:SetProjectGoal(element.text)
                Upload()
            end,
        },
        gui.Label{
            classes = {"hint"},
            text = "Start with a number. If there is anything else to add, put it in parentheses afterward (e.g. 45 (yields 1d3 darts, or three darts if crafted by a shadow)).",
        },
    }

    editorPanel.children = children
end

--- Creates the compendium editor panel for downtime activities
--- @return table panel The editor root panel exposing data.SetData(id)
function DowntimeActivity.CreateEditor()
    local editor
    editor = gui.Panel{
        data = {
            SetData = function(activityId)
                SetActivity(editor, activityId)
            end,
        },
        styles = {
            {
                selectors = {"hint"},
                bold = false,
                fontSize = 12,
                color = "#bbbbbb",
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                tmargin = 2,
            },
        },
        width = "100%",
        height = "auto",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return editor
end

Compendium.Register{
    section = "Rules",
    text = "Downtime Activities",
    contentType = DowntimeActivity.tableName,
    click = function(contentPanel)
        Compendium.GenericEditor(contentPanel, DowntimeActivity)
    end,
}

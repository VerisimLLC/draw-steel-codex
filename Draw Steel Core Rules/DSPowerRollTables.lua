local mod = dmhub.GetModLoading()

--- @class PowerRollTable: GameType
--- @field name string Display name for this power roll tier table.
--- @field description string Human-readable notes about this table. Not used by any rules.
--- @field entries table[] List of tier entries with outcome descriptions and thresholds.
--- @field characteristics table Set of characteristic ids this test suggests rolling. Empty inherits the group skill's characteristic.
--- A single power roll table (e.g. "Tier 1 / Tier 2 / Tier 3 results") within a PowerRollTableGroup.
PowerRollTable = RegisterGameType("PowerRollTable")

PowerRollTable.description = ""

--- @class PowerRollTableGroup: GameType
--- @field name string Display name for this group of power roll tables.
--- @field description string Human-readable notes about this group. Not used by any rules.
--- @field tableName string Data table name ("powerRolls").
--- @field skill string Id of the Skill these tests belong to, or "none".
--- @field tables PowerRollTable[] Ordered list of PowerRollTable entries in this group.
--- A named collection of PowerRollTable entries (e.g. "Easy", "Medium", "Hard" encounter tables).
PowerRollTableGroup = RegisterGameType("PowerRollTableGroup")

PowerRollTableGroup.name = "Power Rolls"
PowerRollTableGroup.description = ""
PowerRollTableGroup.tableName = "powerRolls"
PowerRollTableGroup.skill = "none"

function PowerRollTableGroup.Create(args)
    return PowerRollTableGroup.new(args)
end

function PowerRollTableGroup.CreateDropdownOptions()
    local result = {}

    for k,v in pairs(dmhub.GetTable(PowerRollTableGroup.tableName) or {}) do
        if not v:try_get("hidden") then
            for i=1,#v.tables do
                result[#result+1] = {
                    id = string.format("%s:%d", k, i),
                    text = string.format("%s - %s", v.name, v.tables[i].name),
                    tableName = v.name,
                }
            end
        end
    end

    --sort by group name, but keep the order within the group so e.g. easy - medium - hard appear in that order.
    table.sort(result, function(a,b)
        return a.tableName < b.tableName
    end)

    return result
end

--Split a "groupid:tableindex" id -- the form CreateDropdownOptions hands out -- into
--the group and the 1-based index of the table within it.
--- @param id string
--- @return nil|PowerRollTableGroup group, nil|number index
function PowerRollTableGroup.GetGroupAndIndex(id)
    if type(id) ~= "string" then
        return nil, nil
    end

    local match = regex.MatchGroups(id, "^(?<groupid>.*):(?<tableindex>[0-9]+)$")
    if match == nil then
        return nil, nil
    end

    local group = dmhub.GetTable(PowerRollTableGroup.tableName)[match.groupid]
    if group == nil then
        return nil, nil
    end

    return group, tonumber(match.tableindex)
end

function PowerRollTableGroup.GetPowerTable(id)
    local group, index = PowerRollTableGroup.GetGroupAndIndex(id)
    if group == nil then
        return nil
    end

    return group.tables[index]
end

--The Skill whose tests this group holds. Heroic test groups are one-per-skill
--(Gymnastics, Endurance, ...); groups that aren't skill-based return nil.
--- @return nil|Skill
function PowerRollTableGroup.GetSkill(self)
    local skillid = self:try_get("skill", "none")
    if skillid == "none" then
        return nil
    end

    return (dmhub.GetTable(Skill.tableName) or {})[skillid]
end

--The characteristic the group's skill is governed by, as a single-entry set, or an
--empty set when the group names no skill. This is what a test that names no
--characteristics of its own falls back to.
--- @return table
function PowerRollTableGroup.GetInheritedCharacteristics(self)
    local skill = PowerRollTableGroup.GetSkill(self)
    local attrid = skill ~= nil and skill:try_get("attribute") or nil
    if attrid == nil then
        return {}
    end

    return { [attrid] = true }
end

--The characteristics one test suggests, as a set of characteristic ids. A test that
--names none inherits the group skill's characteristic, so authoring only has to set
--this on the tests that allow something other than the obvious one.
--- @param index number index into self.tables
--- @return table
function PowerRollTableGroup.GetCharacteristics(self, index)
    local t = self.tables[index]
    local characteristics = t ~= nil and t:try_get("characteristics") or nil
    if characteristics ~= nil and not table.empty(characteristics) then
        return DeepCopy(characteristics)
    end

    return PowerRollTableGroup.GetInheritedCharacteristics(self)
end

--What the Request Rolls dialog should preselect when this test is chosen: the
--suggested characteristics as a SET, and the group's skill as a LIST -- the shapes
--that dialog's characteristic and skill multiselects take.
--- @param id string a "groupid:tableindex" id from CreateDropdownOptions.
--- @return table characteristics, table skills
function PowerRollTableGroup.GetSuggestions(id)
    local group, index = PowerRollTableGroup.GetGroupAndIndex(id)
    if group == nil then
        return {}, {}
    end

    local skills = {}
    local skillid = group:try_get("skill", "none")
    if skillid ~= "none" then
        skills[1] = skillid
    end

    return PowerRollTableGroup.GetCharacteristics(group, index), skills
end

function PowerRollTable.Create(args)
    local params = {
        tiers = {
            "Tier 1 Result",
            "Tier 2 Result",
            "Tier 3 Result",
        },
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return PowerRollTable.new(params)
end

local INHERIT_OPTION = "inherit"

--The per-test characteristic dropdown: "inherit" first, spelling out what it currently
--resolves to, then the characteristics themselves. Rebuilt whenever the group's skill
--changes, since that is what the inherit label names.
local function CharacteristicOptions(group)
    local skill = PowerRollTableGroup.GetSkill(group)
    local attrid = skill ~= nil and skill:try_get("attribute") or nil

    local inheritText = "No characteristic"
    if attrid ~= nil then
        inheritText = string.format("Inherit %s from %s", creature.attributesInfo[attrid].description, skill.name)
    end

    local result = { { id = INHERIT_OPTION, text = inheritText } }
    for _,option in ipairs(creature.attributeDropdownOptions) do
        result[#result+1] = option
    end

    return result
end

--Which option the dropdown should sit on for one test. A test that names nothing sits on
--"inherit"; one that names characteristics sits on the first in canonical order.
local function ChosenCharacteristic(group, index)
    local t = group.tables[index]
    local characteristics = t ~= nil and t:try_get("characteristics") or nil
    if characteristics == nil or table.empty(characteristics) then
        return INHERIT_OPTION
    end

    for _,attrid in ipairs(creature.attributeIds) do
        if characteristics[attrid] then
            return attrid
        end
    end

    return INHERIT_OPTION
end

function PowerRollTableGroup.CreateEditor()
    local m_group

    local function Upload()
        dmhub.SetAndUploadTableItem(PowerRollTableGroup.tableName, m_group)
    end

    local resultPanel

    resultPanel = gui.Panel{
        classes = {"hidden"},
        width = 1200,
        height = "95%",
        flow = "vertical",
        vscroll = true,

        setdata = function(element, group)
            m_group = group
        end,

        gui.Input{
            width = 400,
            height = 24,
            fontSize = 22,
            characterLimit = 60,
            bold = true,
            placeholderText = "Enter Name...",

            change = function(element)
                m_group.name = element.text
                Upload()
            end,

            setdata = function(element)
                element.text = m_group.name
            end,
        },

        gui.Input{
            width = "100%-40",
            height = "auto",
            minHeight = 40,
            halign = "left",
            tmargin = 4,
            bmargin = 8,
            multiline = true,
            lineType = "multilinenewline",
            wrap = true,
            characterLimit = 512,
            fontSize = 16,
            placeholderText = "Enter description...",

            change = function(element)
                m_group.description = element.text
                Upload()
            end,

            setdata = function(element)
                element.text = m_group.description
            end,
        },

        --The skill these tests belong to. Heroic tests are authored one group per
        --skill, and this is what lets Request Rolls preselect both the skill and the
        --characteristic it governs when a test is chosen.
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 4,

            gui.Label{
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 8,
                fontSize = 16,
                color = Styles.textColor,
                text = "Skill:",
            },

            gui.Dropdown{
                width = 260,
                height = 24,
                valign = "center",
                options = Skill.skillsDropdownOptionsWithNone,

                setdata = function(element)
                    element.idChosen = m_group:try_get("skill", "none")
                end,

                change = function(element)
                    ---@cast element Dropdown
                    m_group.skill = element.idChosen
                    Upload()
                    resultPanel:FireEventTree("refreshCharacteristics")
                end,
            },
        },

        gui.Panel{
            flow = "vertical",
            width = "100%-40",
            height = "auto",
            halign = "left",
            data = {
                panels = {},
            },
            setdata = function(element)
                local newPanels = {}

                for i=1,#m_group.tables do
                    local index = i
                    newPanels[i] = element.data.panels[i] or gui.Panel{
                        flow = "vertical",
                        halign = "left",
                        lmargin = 8,
                        width = "100%-40",
                        height = "auto",
                        data = {
                            table = m_group.tables[i],
                        },

                        gui.Input{
                            width = 400,
                            height = 24,
                            fontSize = 18,
                            characterLimit = 60,
                            bold = true,
                            placeholderText = "Enter Name...",

                            change = function(element)
                                m_group.tables[index].name = element.text
                                Upload()
                            end,

                            setdata = function(element)
                                element.text = m_group.tables[index].name
                            end,
                        },

                        gui.Input{
                            width = "100%-40",
                            height = "auto",
                            minHeight = 40,
                            halign = "left",
                            tmargin = 4,
                            bmargin = 4,
                            multiline = true,
                            lineType = "multilinenewline",
                            wrap = true,
                            characterLimit = 512,
                            fontSize = 16,
                            placeholderText = "Enter description...",

                            change = function(element)
                                m_group.tables[index].description = element.text
                                Upload()
                            end,

                            setdata = function(element)
                                element.text = m_group.tables[index].description
                            end,
                        },

                        --Which characteristic this test is rolled with. Left on "inherit" it
                        --follows the group's skill, so only tests that want something other
                        --than the obvious characteristic need touching.
                        gui.Panel{
                            flow = "horizontal",
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            vmargin = 4,

                            gui.Label{
                                width = "auto",
                                height = "auto",
                                valign = "center",
                                rmargin = 8,
                                fontSize = 16,
                                color = Styles.textColor,
                                text = "Characteristic:",
                            },

                            gui.Dropdown{
                                width = 300,
                                height = 24,
                                halign = "left",
                                valign = "center",
                                options = CharacteristicOptions(m_group),
                                idChosen = ChosenCharacteristic(m_group, index),

                                --Panels are cached and reused across groups, and the inherit
                                --label names the current skill, so both are rebuilt on every
                                --setdata rather than only at construction.
                                setdata = function(element)
                                    element:FireEvent("refreshCharacteristics")
                                end,

                                refreshCharacteristics = function(element)
                                    element.options = CharacteristicOptions(m_group)
                                    element.idChosen = ChosenCharacteristic(m_group, index)
                                end,

                                change = function(element)
                                    ---@cast element Dropdown
                                    if element.idChosen == INHERIT_OPTION then
                                        m_group.tables[index].characteristics = nil
                                    else
                                        m_group.tables[index].characteristics = { [element.idChosen] = true }
                                    end
                                    Upload()
                                end,
                            },
                        },

                        gui.Table{
                            flow = "vertical",
                            width = "100%",
                            height = "auto",
                            create = function(element)
                                local children = {}

                                --The three standard tiers, plus an optional 4th "Critical" row for a
                                --natural 19-20. Leaving the Critical row blank stores no 4th tier, which
                                --is how every consumer tells a 3-tier table from a 4-tier one.
                                local tierLabels = {}
                                for j=1,#GameSystem.TierNames do
                                    tierLabels[j] = GameSystem.TierNames[j]
                                end
                                tierLabels[#tierLabels+1] = "Critical"

                                for j=1,#tierLabels do
                                    local tierNumber = j
                                    local name = tierLabels[j]
                                    local isCritical = (j > #GameSystem.TierNames)
                                    local input = gui.Input{
                                        width = "100%-140",
                                        height = "auto",
                                        minHeight = 22,
                                        wrap = true,
                                        lineType = "multilinenewline",
                                        characterLimit = 600,
                                        fontSize = 18,
                                        placeholderText = isCritical and "Leave blank for no critical result (natural 19-20)" or nil,
                                        text = m_group.tables[index].tiers[tierNumber] or "",
                                        setdata = function(element)
                                            element.text = m_group.tables[index].tiers[tierNumber] or ""
                                        end,
                                        change = function(element)
                                            local tiers = m_group.tables[index].tiers
                                            if isCritical and string.match(element.text, "%S") == nil then
                                                table.remove(tiers, tierNumber)
                                            else
                                                tiers[tierNumber] = element.text
                                            end
                                            Upload()
                                        end,
                                    }
        
                                    local panel = gui.TableRow{
                                        width = "100%",
                                        height = "auto",
                                        gui.Label{
                                            width = 120,
                                            height = 22,
                                            valign = "center",
                                            fontSize = 18,
                                            color = Styles.textColor,
                                            text = name,
                                        },
                                        input,
                                    }
        
                                    children[#children+1] = panel
                                end

                                element.children = children
                            end,
                        }

                    }
                end

                element.data.panels = newPanels
                element.children = newPanels
            end,
        },

        gui.Button{
            classes = {"addButton"},
            valign = "top",
            click = function(element)
                m_group.tables[#m_group.tables+1] = PowerRollTable.Create{
                    name = "New Table",
                }

                Upload()
                resultPanel:FireEventTree("setdata", m_group)
            end,
        },
    }

    return resultPanel
end

local function ShowPowerRollPanel(parentPanel)
    local dataItems = {}
    local editPanel = PowerRollTableGroup.CreateEditor()
    local itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)

			local children = {}
			local dataTable = dmhub.GetTable(PowerRollTableGroup.tableName) or {}

			local newDataItems = {}

			for k,item in pairs(dataTable) do
				newDataItems[k] = dataItems[k] or Compendium.CreateListItem{
					select = element.aliveTime > 0.2,
					click = function()
						editPanel:SetClass("hidden", false)
						editPanel:FireEventTree("setdata", dataTable[k])
					end,
                    tableName = PowerRollTableGroup.tableName,
                    key = k,
				}

				newDataItems[k].text = item.name

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
                local newData = PowerRollTableGroup.Create{
                    tables = {},
                }

                dmhub.SetAndUploadTableItem(PowerRollTableGroup.tableName, newData)
			end,
		}
	}

	parentPanel.children = {leftPanel, editPanel}	
end

Compendium.Register{
    section = "Import",
    text = "Power Roll Tables",
    click = function(contentPanel)
        ShowPowerRollPanel(contentPanel)

    end,
}

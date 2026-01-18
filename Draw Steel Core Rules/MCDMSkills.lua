local mod = dmhub.GetModLoading()

RegisterGameType("Skill")
RegisterGameType("SkillSpecialization")

Skill.tableName = "Skills"
Skill.hasPassive = false
Skill.specializations = false
Skill.category = "crafting"
Skill.description = ""

Skill.categories = {
    {
        id = "crafting",
        text = "Crafting",
    },
    {
        id = "exploration",
        text = "Exploration",
    },
    {
        id = "interpersonal",
        text = "Interpersonal",
    },
    {
        id = "intrigue",
        text = "Intrigue",
    },
    {
        id = "lore",
        text = "Lore",
    },
}

Skill.categoriesById = {}

for i,v in ipairs(Skill.categories) do
    Skill.categoriesById[v.id] = v
end

function Skill.CreateNew()
	return Skill.new{
		id = dmhub.GenerateGuid(),
		name = "New Skill",
		attribute = "str",
		specializations = {},
	}
end

function Skill.GetSpecializationDropdownOptions(self)
	local result = {}
	result[#result+1] = {
		id = "all",
		text = "All",
	}

	for _,s in ipairs(Skill.GetSpecializations(self)) do
		result[#result+1] = {
			id = s.id,
			text = s.text,
		}
	end
	return result
end

function Skill.GetSpecializations(self)
	return self.specializations or {}
end

function Skill.AddSpecialization(self)
	local specializations = Skill.GetSpecializations(self)

	specializations[#specializations+1] = SkillSpecialization.CreateNew()

	self.specializations = specializations
end

function Skill.GetSpecializationById(self, id)
	for _,s in ipairs(Skill.GetSpecializations(self)) do
		if s.id == id then
			return s
		end
	end
end

function Skill.DeleteSpecializationById(self, id)
	local specializations = Skill.GetSpecializations(self)
	local newSpecializations = {}
	for _,s in ipairs(specializations) do
		if s.id ~= id then
			newSpecializations[#newSpecializations+1] = s
		end
	end

	self.specializations = newSpecializations
end

function SkillSpecialization.CreateNew()
	return SkillSpecialization.new{
		id = dmhub.GenerateGuid(),
		text = "New Specialization",
	}
end

local ParseAdvantage = function(str)
	if str == nil then
		return nil
	end
	str = string.lower(str)
	if str ~= '' then
		if string.startswith('advantage', str) then
			return 'advantage'
		elseif string.startswith('disadvantage', str) then
			return 'disadvantage'
		end
	end

	return nil
end

local initCategories = false

dmhub.RegisterEventHandler("refreshTables", function()
	local skillTable = dmhub.GetTable(Skill.tableName) or {}
	Skill.SkillsInfo = {}
	for id,info in pairs(skillTable) do
		if rawget(info, "hidden") ~= true then
			Skill.SkillsInfo[#Skill.SkillsInfo+1] = info
		end
	end

	table.sort(Skill.SkillsInfo, function(a,b)
		return string.lower(a.name) < string.lower(b.name)
	end)

	Skill.SkillsById = {}

	for i,skill in ipairs(Skill.SkillsInfo) do
		Skill.SkillsById[skill.id] = skill
	end

	Skill.skillsDropdownOptions = {}
	Skill.skillsDropdownOptionsWithNone = {
		{
			id = 'none',
			text = 'Choose Skill...',
		}
	}
	for i,skillInfo in ipairs(Skill.SkillsInfo) do
		Skill.skillsDropdownOptions[#Skill.skillsDropdownOptions+1] = {
			id = skillInfo.id,
			text = skillInfo.name,
		}
		Skill.skillsDropdownOptionsWithNone[#Skill.skillsDropdownOptionsWithNone+1] = Skill.skillsDropdownOptions[#Skill.skillsDropdownOptions]
	end

	--Passive skills
	Skill.PassiveSkills = {}
	for i,v in pairs(Skill.SkillsInfo) do
		if v.hasPassive then
			Skill.PassiveSkills[#Skill.PassiveSkills+1] = v
		end
	end
	
	--init creature commands for skills.
	for i,v in ipairs(Skill.SkillsInfo) do
		local skillInfo = v
		local commandKey = skillInfo.id
		creature.commands[commandKey] = function(self, str)
			self:RollSkillCheck(skillInfo, ParseAdvantage(str))
		end
	end

    RollCheck.LoadSkills()

	if initCategories then
		return
	end

	initCategories = true

	for i,skill in ipairs(Skill.SkillsInfo) do
		CustomAttribute.RegisterAttribute
		{
			id = skill.id,
			text = string.format("%s Modifier", skill.name),
			attributeType = "number",
			category = "Skills",
		}
	end

	for i,skill in ipairs(Skill.SkillsInfo) do
		if skill.hasPassive then
			CustomAttribute.RegisterAttribute
			{
				id = string.format("PASSIVE-%s", skill.id),
				text = string.format("Passive %s Modifier", skill.name),
				attributeType = "number",
				category = "Senses",
			}
		end
	end

end)

local LibraryStyles = {
	{
		classes = {'mainContentPanel'},
		width = 1200,
		height = '95%',
		halign = 'left',
		flow = 'vertical',
		pad = 20,
	},
	{
		classes = {'label'},
		color = 'white',
		fontSize = 22,
		width = 'auto',
		height = 'auto',
	},
	{
		classes = {"formLabel"},
		width = 240,
		textAlignment = "left",
	},
	{
		classes = {'input'},
		width = 200,
		height = 26,
		fontSize = 18,
		color = 'white',
	},
	{
		classes = {'formPanel'},
		flow = 'horizontal',
		width = 'auto',
		height = 'auto',
		halign = 'left',
		vmargin = 2,
	},
}

local ShowSkillsPanel = function(parentPanel)

	local skillPanel = gui.Panel{
		classes = 'skills-panel',
		styles = {
			{
				classes = {'skills-panel'},
				width = 1200,
				height = '100%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			LibraryStyles,
		},
	}

	local SetSkill = function(skillid)
		local skillTable = dmhub.GetTable(Skill.tableName) or {}
		local skill = skillTable[skillid]
		local UploadSkill = function()
			dmhub.SetAndUploadTableItem(Skill.tableName, skill)
		end

		local children = {}

		--the ID of the skill.
		if dmhub.GetSettingValue("dev") then
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = 'ID:',
					valign = 'center',
					minWidth = 100,
				},
				gui.Label{
					text = skill.id,
				},
			}
		end

		--the name of the skill.

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = skill.name,
				change = function(element)
					skill.name = element.text
					UploadSkill()
				end,
			},
		}

		--the attribute of the skill.

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Attribute:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Dropdown{
				width = 200,
				height = 40,
				fontSize = 20,
				options = creature.attributeDropdownOptions,
				idChosen = skill.attribute,
				change = function(element)
					skill.attribute = element.idChosen
					UploadSkill()
				end,
			},
		}

		--whether this skill has a passive associated with it.
		children[#children+1] = gui.Check{
			text = "Has Passive",
			halign = "left",
			fontSize = 22,
			value = cond(skill.hasPassive, true, false),
			change = function(element)
				skill.hasPassive = element.value
				UploadSkill()
			end,
		}

		--Skill description..
		children[#children + 1] = gui.Panel {
			classes = { 'formPanel' },
			height = 'auto',
			gui.Label {
				text = "Description:",
				valign = "center",
				width = 135,
			},
			gui.Input {
				text = skill.description or "",
				multiline = true,
				minHeight = 50,
				height = 'auto',
				width = 400,
				textAlignment = "topleft",
				change = function(element)
					skill.description = element.text
					UploadSkill()
				end,
			}
		}

		children[#children+1] = gui.Label{
			vmargin = 6,
			fontSize = 24,
			bold = true,
			text = "Specializations",
			width = "auto",
			height = "auto",
		}

		local specializationItems = {}
		children[#children+1] = gui.Panel{
			width = "auto",
			height = "auto",
			flow = "vertical",
			monitorAssets = true,
			create = function(element)
				element:FireEvent("refreshAssets")
			end,
			refreshAssets = function(element)
				local children = {}

				dmhub.Debug(string.format("Refresh specializations: %d", #Skill.GetSpecializations(skill)))
				for i,s in ipairs(Skill.GetSpecializations(skill)) do
					local child = specializationItems[i] or gui.Panel{
						flow = "horizontal",
						width = "auto",
						height = "auto",
						data = {
							id = s.id,
						},
						gui.Label{
							fontSize = 14,
							width = 180,
							height = "auto",
							valign = "center",
							editable = true,
							characterLimit = 24,
							change = function(element)
								local itemPanel = element.parent
								local s = Skill.GetSpecializationById(skill, itemPanel.data.id)
								if s ~= nil then
									s.text = element.text
									UploadSkill()
								end
							end,
						},
						gui.CloseButton{
							valign = "center",
							click = function(element)
								local itemPanel = element.parent

								Skill.DeleteSpecializationById(skill, itemPanel.data.id)

								UploadSkill()
							end
						}
					}

					child.data.id = s.id
					child.children[1].text = s.text

					children[#children+1] = child
				end

				specializationItems = children
				element.children = children
			end,
		}

		children[#children+1] = Compendium.AddButton{
			halign = "left",
			click = function(element)
				dmhub.Debug("Add Specialization")
				Skill.AddSpecialization(skill)
				UploadSkill()
			end,
		}

		skillPanel.children = children

	end

    local CreateItemList = function(catid, catname)

        local itemsListPanel = nil

        local skillItems = {}

        itemsListPanel = gui.Panel{
            classes = {'list-panel'},
            height = "auto",
            vscroll = true,
            monitorAssets = true,
            refreshAssets = function(element)

                local children = {}
                local skillTable = dmhub.GetTableVisible(Skill.tableName) or {}
                local newSkillItems = {}

                for k,item in pairs(skillTable) do
                    if item.category ~= catid then
                        goto continue
                    end
                    newSkillItems[k] = skillItems[k] or Compendium.CreateListItem{
                        select = element.aliveTime > 0.2,
                        tableName = Skill.tableName,
                        key = k,
                        text = item.name,
                        obliterateOnDelete = true,
                        click = function()
                            SetSkill(k)
                        end,
                    }

                    newSkillItems[k].text = item.name

                    children[#children+1] = newSkillItems[k]

                    ::continue::
                end

                table.sort(children, function(a,b) return a.text < b.text end)

                skillItems = newSkillItems
                itemsListPanel.children = children
            end,
        }

        itemsListPanel:FireEvent('refreshAssets')

        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",

            gui.Label{
                text = catname,
                fontSize = 20,
                bold = true,
                width = "auto",
                height = "auto",
                lmargin = 4,
            },

            itemsListPanel,
            Compendium.AddButton{
                hmargin = 24,

                click = function(element)
                    local newSkill = Skill.CreateNew()
                    newSkill.category = catid
                    dmhub.SetAndUploadTableItem(Skill.tableName, newSkill)
                end,
            }
        }
    end

    local children = {}
    for _,cat in ipairs(Skill.categories) do
        children[#children+1] = CreateItemList(cat.id, cat.text)
    end

	local leftPanel = gui.Panel{
		flow = 'vertical',
		height = '100%',
		width = 'auto',
        hmargin = 8,
        vscroll = true,

        children = children,
	}

	parentPanel.children = {leftPanel, skillPanel}
end

Compendium.Register{
	section = "Rules",
    priority = 1, --override any other skills panel.
	text = 'Skills',
	contentType = "Skills",
	click = function(contentPanel)
		ShowSkillsPanel(contentPanel)
	end,
}
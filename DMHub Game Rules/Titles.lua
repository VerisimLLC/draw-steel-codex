local mod = dmhub.GetModLoading()

RegisterGameType("Title", "CharacterFeat")

--standard title fields.
Title.name = "New Title"
Title.description = ""
Title.prerequisite = ""

Title.effect = ""

Title.echelon = "1"

Title.tableName = "titles"

function Title.CreateNew()
    return Title.new {
    }
end

function Title.GetDropdownList()
    local result = {}
    local titlesTable = dmhub.GetTable('titles')
    for k, v in unhidden_pairs(titlesTable) do
        result[#result + 1] = { id = k, text = v.name }
    end
    table.sort(result, function(a, b)
        return a.text < b.text
    end)
    return result
end

function Title:RenderToMarkdown(options)
    options = options or {}

    local name = self.name or "Untitled"
    local echelon = self.echelon or "-"
    local prereq = self.prerequisite or ""
    local effect = self.effect or ""
    local description = self.description or ""

    local content = ""
    content = content .. "## " .. name .. "\n"

    content = content .. description .. "\n"

    content = content .. "\n**Echelon:** " .. echelon .. "\n"

    content = content .. "\n**Prerequisite:** " .. prereq .. "\n"

    content = content .. "\n**Effect:** " .. effect .. "\n"

    if not options.noninteractive then
        content = content .. "\n\n:<>"
        for _,token in ipairs(dmhub.GetTokens{playerControlled = true}) do
            if token.name ~= "" then
                content = content .. string.format("[[/granttitle \"%s\" %s|Grant to %s]]", token.name, self.id, token.name)
            end
        end

        content = content .. "\n"
    end



    return MarkdownDocument.new {
        id = dmhub.GenerateGuid(),
        description = name,
        content = content,
    }
end

MarkdownRender.Register(Title)
MarkdownRender.RegisterTable { tableName = "titles", prefix = "title" }


local SetTitle = function(tableName, titlePanel, titleid)
    local titleTable = dmhub.GetTable(tableName) or {}
    local title = titleTable[titleid]
    local UploadTitle = function()
        dmhub.SetAndUploadTableItem(tableName, title)
    end

    local children = {}

    --the id of the Title.
    if dmhub.GetSettingValue("dev") then
        children[#children+1] = gui.Panel{
            classes = {'formPanel'},
            gui.Label{
                text = 'ID:',
                valign = 'center',
                minWidth = 100,
            },
            gui.Label{
                text = title.id,
            },
        }
    end

    --the name of the title.
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        gui.Label {
            text = 'Name:',
            valign = 'center',
            minWidth = 240,
        },
        gui.Input {
            text = title.name,
            change = function(element)
                title.name = element.text
                UploadTitle()
            end,
        },
    }

    --the name of the title.
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        gui.Label {
            text = 'Echelon:',
            valign = 'center',
            minWidth = 240,
        },
        gui.Input {
            text = title.echelon,
            change = function(element)
                title.echelon = element.text
                UploadTitle()
            end,
        },
    }

    --[[language speakers
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Native Speakers:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = language.speakers,
			change = function(element)
				language.speakers = element.text
				UploadLanguage()
			end,
		},
	}]]

    --title description..
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        height = 'auto',
        gui.Label {
            text = "Description:",
            valign = "center",
            minWidth = 240,
        },
        gui.Input {
            text = title.description,
            multiline = true,
            minHeight = 50,
            height = 'auto',
            width = 400,
            textAlignment = "topleft",
            change = function(element)
                title.description = element.text
                UploadTitle()
            end,
        }
    }


    --prerequisites..
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        height = 'auto',
        gui.Label {
            text = "Prerequisite:",
            valign = "center",
            minWidth = 240,
        },
        gui.Input {
            text = title.prerequisite,
            multiline = true,
            minHeight = 50,
            height = 'auto',
            width = 400,
            textAlignment = "topleft",
            change = function(element)
                title.prerequisite = element.text
                UploadTitle()
            end,
        }
    }

    -- effect..
    children[#children + 1] = gui.Panel {
        classes = { 'formPanel' },
        height = 'auto',
        gui.Label {
            text = "Effect:",
            valign = "center",
            minWidth = 240,
        },
        gui.Input {
            text = title.effect,
            multiline = true,
            minHeight = 50,
            height = 'auto',
            width = 400,
            textAlignment = "topleft",
            change = function(element)
                title.effect = element.text
                UploadTitle()
            end,
        }
    }

    children[#children + 1] = title:GetClassLevel():CreateEditor(title, 0, {
        change = function(element)
            titlePanel:FireEvent("change")
            UploadTitle()
        end,
    })



    titlePanel.children = children
end

function Title.CreateEditor()
    local titleEditor
    titleEditor = gui.Panel {
        data = {
            SetTitle = function(tableName, titleid)
                SetTitle(tableName, titleEditor, titleid)
            end,
        },
        vscroll = true,
        classes = 'class-panel',
        styles = {
            {
                halign = "left",
            },
            {
                classes = { 'class-panel' },
                width = 1200,
                height = '90%',
                halign = 'left',
                flow = 'vertical',
                pad = 20,
            },
            {
                classes = { 'label' },
                color = 'white',
                fontSize = 22,
                width = 'auto',
                height = 'auto',
            },
            {
                classes = { 'input' },
                width = 200,
                height = 26,
                fontSize = 18,
                color = 'white',
            },
            {
                classes = { 'formPanel' },
                flow = 'horizontal',
                width = 'auto',
                height = 'auto',
                halign = 'left',
                vmargin = 2,
            },

        },
    }

    return titleEditor
end

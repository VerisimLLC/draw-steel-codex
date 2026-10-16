local mod = dmhub.GetModLoading()

local CreateTutorialDialog

--[[
LaunchablePanel.Register{
    name = "Tutorial",
    icon = mod.images.help,
    halign = "right",
    valign = "top",
    ord = -1,
    noescape = true,
	filtered = function()
		return not dmhub.isDM
	end,
	content = function()
		return CreateTutorialDialog()
	end,
}
]]

local goblinGuid = "76de605d-434b-4210-905f-5c47caf159cf"

local tutorials = {
    {
        name = "Create a Map",
        entries = {
            {
                target = "#ToolsMenuButton",
                text = "Open the panels menu.",
            },
            {
                target = "#MenuMaps",
                text = "Open the maps panel",
            },
            {
                target = "#map-dialog-button-create-map",
                text = "Click the create new map button",
            },
        },
    },
    {
        name = "Create a Character",
        entries = {
            {
                target = "#PanelsMenuButton",
                text = "Open the panels menu.",
            },
            {
                target = "#MenuCharacter",
                text = "Open the Character panel.",
            },
            {
                target = "#TabIconCharacter",
                text = "Open the Characters tab.",
            },
            {
                target = "#AddCharacterButton",
                text = "Click the add character button",
            },
        },
    },
    {
        name = "Add a Monster",
        completeText = "Excellent! You can easily create all sorts of monsters from the bestiary.",
        complete = function(ev)
            if ev:Get("type") ~= "createMonster" then
                return false
            end

            local focus = gui.GetFocus()
            if focus ~= nil and focus.id == goblinGuid then
                return true
            end

            return false
        end,
        entries = {
            {
                target = "#PanelsMenuButton",
                text = "Open the panels menu.",
            },
            {
                target = "#MenuBestiary",
                text = "Open the Bestiary panel.",
            },
            {
                target = "#TabIconBestiary",
                text = "Open the Bestiary tab.",
            },
            {
                target = "#MonsterSearch",
                text = "Let's add a Goblin Cursespitter. Select the search input and type 'goblin'",
            },
            {
                target = "#" .. goblinGuid,
                text = "Select the Goblin Cursespitter entry in the Bestiary",
            },
            {
                condition = function()
                    local focus = gui.GetFocus()
                    if focus ~= nil and focus.id == goblinGuid then
                        return true
                    end

                    return false
                end,
                
                text = "Now click on a vacant spot on the map to add the Goblin Cursespitter to the map.",
            },
        }

    },
    {
        name = "Import Objects",
        video = "https://www.youtube.com/watch?v=t45iaLiZ_So",

    },
    {
        name = "Add Homebrew Races & Classes",
        video = "homebrew_races",
    },
    {
        name = "Stairways Between Floors",
        video = "stairs",
    },
}

mod.shared.CompleteTutorial = function(name)
    if tutorial.tutorialName == name then
        tutorial.CompleteTutorial()
    end
end

local g_tutorialDialog = nil

CreateTutorialDialog = function()

    ---@type Panel[]
    local tutorialLinks = {
        gui.Label{
            width = "90%",
            height = "auto",
            text = "Learn how to...",
            fontSize = 16,
            hmargin = 2,
        },
    }

    for _,t in ipairs(tutorials) do


        local link = gui.Label{
            width = "auto",
            height = "auto",
            maxWidth = 140,
            classes = {"helpLink"},
            hoverCursor = "hand",
            text = t.name,
            refreshTutorialComplete = function(element)
                element:FireEvent("create")
            end,
            create = function(element)
                element:SetClass("visited", tutorial.IsTutorialComplete(t.name))
            end,
            press = function()
                if t.video ~= nil then
                    dmhub.OpenTutorialVideo(t.video)
                    tutorial.MarkTutorialComplete(t.name)
                else
                    tutorial.SetTutorial(t)
                end
            end,
        }

        local popoutIcon = nil
        if t.video ~= nil then
            popoutIcon = gui.Panel{
                width = 20,
                height = 20,
                valign = "center",
                bgimage = mod.images.popout,
                bgcolor = "white",
            }
        end

        tutorialLinks[#tutorialLinks+1] = gui.Panel{
            flow = "horizontal",
            width = "90%",
            height = "auto",
            hmargin = 2,
            link,
            popoutIcon,
        }
       
    end

    local helpIndex = gui.Panel{
        flow = "vertical",
        width = "90%",
        height = "92%",
        halign = "center",
        valign = "center",
        vscroll = true,

        children = tutorialLinks,
    }

    local instructionsHeading = gui.Label{
        width = "90%",
        height = "auto",
        halign = "center",
        bold = true,
        fontSize = 18,
    }

    local backLabel = gui.Label{
        classes = {"helpLink"},
        hoverCursor = "hand",
        text = "Back",
        width = "90%",
        halign = "center",
        click = function(element)
            tutorial.ClearTutorial()
        end,
    }

    local instructionsText = gui.Label{
        width = "90%",
        height = "auto",
        halign = "center",
        fontSize = 16,
        vmargin = 12,
    }

    local instructionsPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",

        instructionsHeading,
        backLabel,
        instructionsText,

    }

    local resultPanel = gui.Panel{
        halign = "right",
        valign = "top",
        width = 200,
        height = 400,
        flow = "vertical",

        styles = {
            {
                selectors = {"helpLink"},
                fontSize = 16,
                color = "#bbbbff",
                width = "auto",
                height = "auto",
                maxWidth = 180,
                halign = "left",
                vmargin = 6,
            },
            {
                selectors = {"helpLink", "visited"},
                color = "#bbffff",
            },
            {
                selectors = {"helpLink", "hover"},
                color = "#ffbbff",
            },
        },

        gui.Label{
            classes = {"dialogTitle"},
            text = "Tutorial",
        },

        helpIndex,

        instructionsPanel,

        completeTutorial = function(element)
            element:FireEventTree("refreshTutorialComplete")
        end,

        refreshTutorial = function(element)
            local text = tutorial.text
            if text == nil then
                helpIndex:SetClass("collapsed", false)
                instructionsPanel:SetClass("collapsed", true)
                return
            end

            helpIndex:SetClass("collapsed", true)
            instructionsPanel:SetClass("collapsed", false)

            instructionsHeading.text = tutorial.tutorialName
            instructionsText.text = tutorial.text
        end,

        closePanel = function(element)
            dmhub.SetSettingValue("showtutorial", false)
        end,

		create = function(element)
			g_tutorialDialog = element
		end,

		destroy = function(element)
            tutorial.eventSource:Unlisten(element)
            tutorial.ClearTutorial()
			if g_tutorialDialog == element then
				g_tutorialDialog = nil
			end
		end,
    }

    tutorial.eventSource:Listen(resultPanel)

    return resultPanel
end
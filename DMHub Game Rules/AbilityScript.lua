local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityScriptBehavior
ActivatedAbilityScriptBehavior = RegisterGameType("ActivatedAbilityScriptBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityScriptBehavior.summary = "Lua Script"

ActivatedAbility.RegisterType
{
    id = "lua",
    text = "Lua Script",
    createBehavior = function()
        return ActivatedAbilityScriptBehavior.new{
            name = "Script",
            code = [[--Implement your ability here.
--Available variables:
--ability: The ability being used.
--casterToken: The token using the ability.
--targets: A list of target objects (each with a 'token' field in abilities that target tokens).
--symbols: A table of any symbols defined for the ability. Note the "cast" symbol which contains many useful fields and functions.mod
--
--Remember you can print out fields using e.g. print("Token:", casterToken) and get more information about the field in the debug console.
            ]],
        }
    end,
}

function ActivatedAbilityScriptBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Lua Script"
end

function ActivatedAbilityScriptBehavior:Cast(ability, casterToken, targets, options)
    local env = setmetatable({
        ability = ability,
        casterToken = casterToken,
        targets = targets,
        symbols = options.symbols
    }, {__index = _G})
    local f, err = load(self.code, "CustomAbilityScript", "t", env)
    if f ~= nil then
        f()
    end
end

function ActivatedAbilityScriptBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
    
    local errorMessage = gui.Label{
        classes = {"formLabel"},
        text = "",
        height = "auto",
        vmargin = 6,
        refreshCode = function(element)
            if self.code == nil or self.code == "" then
                element.text = ""
                return
            end

            local f, err = load(self.code, "CustomAbilityScript", "t", {ability = false, casterToken = false, targets = false, symbols = false})
            if f ~= nil then
                element.text = "Code compiled successfully"
            else
                element.text = "Error: " .. err
            end
        end,
        create = function(element)
            element:FireEventTree("refreshCode")
        end,
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Script Name:",
        },
        gui.Input{
            classes = {"formInput"},
            characterLimit = 32,
            text = self.name,
            change = function(element)
                local text = element.text:gsub("[^%a]", "")
                if text == "" then
                    text = self.name
                end
                self.name = text
                element.text = text
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Input{
            classes = {"formInput"},
            fontFace = "Courier",
            fontSize = 12,
            width = 560,
            height = "auto",
            minHeight = 100,
            maxHeight = 300,
            halign = "left",
            multiline = true,
            text = self.code,
            characterLimit = 10000,
            textAlignment = "topleft",
            change = function(element)
                self.code = element.text
                errorMessage:FireEventTree("refreshCode")
            end,
        },
    }

    result[#result+1] = errorMessage

	return result
end

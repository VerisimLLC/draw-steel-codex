local mod = dmhub.GetModLoading()


RegisterGameType("ActivatedAbilityMacroBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'Macro',
	text = 'Macro Execution',
	createBehavior = function()
		return ActivatedAbilityMacroBehavior.new{
            macro = "",
		}
	end
}

ActivatedAbilityMacroBehavior.summary = 'Macro Execution'

--Seconds to wait before running the macro. Lets a cosmetic command (e.g. a
--screen shake) line up with a token animation that is still playing when the
--behavior fires, since Cast returns as soon as the logical move completes.
ActivatedAbilityMacroBehavior.delay = 0

function ActivatedAbilityMacroBehavior:Cast(ability, casterToken, targets, options)
    local macro = StringInterpolateGoblinScript(self.macro, casterToken.properties:LookupSymbol(options.symbols))
    print("MACRO:: EXECUTE:", macro)

    local delay = tonumber(self.delay) or 0
    if delay > 0 then
        dmhub.Schedule(delay, function()
            if mod.unloaded then return end
            dmhub.Execute(macro)
        end)
        return
    end

    dmhub.Execute(macro)
end

function ActivatedAbilityMacroBehavior:EditorItems(parentPanel)
    local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Macro:",
        },
        gui.Input{
            classes = {"formInput"},
            width = 320,
            text = self.macro,
            placeholderText = "Enter macro text here...",
            change = function(element)
                self.macro = element.text
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Delay (s):",
        },
        gui.Input{
            classes = {"formInput"},
            width = 100,
            text = tostring(self.delay),
            characterLimit = 16,
            change = function(element)
                self.delay = tonumber(element.text) or self.delay
                if self.delay < 0 then
                    self.delay = 0
                end
                element.text = tostring(self.delay)
            end,
        },
    }
    return result
end

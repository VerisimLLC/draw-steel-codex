local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityPlaySoundBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
    id = 'play_sound',
    text = 'Play Sound',
    createBehavior = function()
        return ActivatedAbilityPlaySoundBehavior.new {
        }
    end
}

ActivatedAbilityPlaySoundBehavior.summary = 'Play Sound'
ActivatedAbilityPlaySoundBehavior.soundEvent = "none"
ActivatedAbilityPlaySoundBehavior.volume = 1
ActivatedAbilityPlaySoundBehavior.delay = 0

function ActivatedAbilityPlaySoundBehavior:Cast(ability, casterToken, targets, options)
    if self.soundEvent == "none" then
        return
    end

    audio.DispatchSoundEvent(self.soundEvent, {
        volume = self.volume,
        delay = self.delay,
    })
end

function ActivatedAbilityPlaySoundBehavior:EditorItems(parentPanel)
    local result = {}

    local soundOptions = {
        {
            id = "none",
            text = "None",
        }
    }

    for name, _ in pairs(audio.soundEvents) do
        soundOptions[#soundOptions+1] = {
            id = name,
            text = name,
        }
    end

    result[#result+1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Sound Event:",
        },

        gui.Dropdown {
            idChosen = self.soundEvent,
            hasSearch = true,
            sort = true,
            options = soundOptions,
            change = function(element)
                self.soundEvent = element.idChosen
            end,
        }
    }

    result[#result+1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Volume:",
        },
        gui.Slider{
            style = {
                height = 30,
                width = 200,
                fontSize = 14,
            },
            sliderWidth = 140,
            labelWidth = 50,
            value = self.volume,
            minValue = 0,
            maxValue = 2,
            formatFunction = function(num)
                return string.format('%d%%', round(num*100))
            end,
            deformatFunction = function(num)
                return num*0.01
            end,
            events = {
                change = function(element)
                    self.volume = element.value
                end,
            },
        },
    }

    result[#result+1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Delay (s):",
        },
        gui.Input {
            classes = { "formInput" },
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

    result[#result+1] = gui.PrettyButton {
        width = 160,
        height = 40,
        fontSize = 14,
        text = "Preview Sound",
        click = function(element)
            if self.soundEvent == "none" then
                return
            end
            audio.FireSoundEvent(self.soundEvent, {
                volume = self.volume,
                delay = self.delay,
            })
        end,
    }

    return result
end

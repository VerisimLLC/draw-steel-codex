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

function ActivatedAbilityPlaySoundBehavior:Cast(ability, casterToken, targets, options)
    if self.soundEvent == "none" then
        return
    end

    audio.DispatchSoundEvent(self.soundEvent)
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

    return result
end

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
ActivatedAbilityPlaySoundBehavior.mode = "builtin"
ActivatedAbilityPlaySoundBehavior.soundEvent = "none"
ActivatedAbilityPlaySoundBehavior.soundAsset = ""
ActivatedAbilityPlaySoundBehavior.volume = 1
ActivatedAbilityPlaySoundBehavior.delay = 0

function ActivatedAbilityPlaySoundBehavior:Cast(ability, casterToken, targets, options)
    if self.mode == "custom" then
        if self.soundAsset == nil or self.soundAsset == "" then
            return
        end

        local asset = assets.audioTable[self.soundAsset]
        if asset == nil then
            return
        end

        local Play = function()
            audio.PlaySoundEvent {
                asset = asset,
                volume = self.volume,
            }
        end

        if self.delay > 0 then
            dmhub.Schedule(self.delay, function()
                if mod.unloaded then return end
                Play()
            end)
        else
            Play()
        end
        return
    end

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

    local builtinPanel
    local customPanel

    result[#result+1] = gui.Panel {
        classes = { "formPanel" },
        gui.Label {
            classes = { "formLabel" },
            text = "Sound Source:",
        },

        gui.Dropdown {
            idChosen = self.mode,
            options = {
                { id = "builtin", text = "Built-in" },
                { id = "custom", text = "Custom" },
            },
            change = function(element)
                self.mode = element.idChosen
                builtinPanel:SetClass("collapsed", self.mode ~= "builtin")
                customPanel:SetClass("collapsed", self.mode ~= "custom")
            end,
        }
    }

    builtinPanel = gui.Panel {
        classes = { "formPanel", cond(self.mode ~= "builtin", "collapsed") },
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
    result[#result+1] = builtinPanel

    customPanel = gui.Panel {
        classes = { "formPanel", cond(self.mode ~= "custom", "collapsed") },
        gui.Label {
            classes = { "formLabel" },
            text = "Custom Sound:",
        },

        gui.AudioEditor {
            width = 64,
            height = 64,
            value = self.soundAsset ~= "" and self.soundAsset or nil,
            change = function(element)
                self.soundAsset = element.value or ""
            end,
        },
    }
    result[#result+1] = customPanel

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
            if self.mode == "custom" then
                if self.soundAsset == nil or self.soundAsset == "" then
                    return
                end
                local asset = assets.audioTable[self.soundAsset]
                if asset == nil then
                    return
                end
                local instance = asset:Play()
                if instance ~= nil then
                    instance.volume = self.volume
                end
                return
            end

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

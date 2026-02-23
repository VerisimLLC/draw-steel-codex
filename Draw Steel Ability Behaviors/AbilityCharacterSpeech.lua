local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCharacterSpeechBehavior:ActivatedAbilityBehavior
ActivatedAbilityCharacterSpeechBehavior = RegisterGameType("ActivatedAbilityCharacterSpeechBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCharacterSpeechBehavior.summary = 'Character Speech'

ActivatedAbility.RegisterType
{
	id = 'character_speech',
	text = 'Character Speech',
	createBehavior = function()
		return ActivatedAbilityCharacterSpeechBehavior.new{
            variations = {},
		}
	end
}

function ActivatedAbilityCharacterSpeechBehavior:Cast(ability, casterToken, targets, options)
    if #self.variations == 0 then
        return
    end
    for _,target in ipairs(targets) do
        local tok = target.token
        if tok ~= nil and tok.valid then
            if not self:has_key("_tmp_shuffle") or #self._tmp_shuffle == 0 then
                self._tmp_shuffle = DeepCopy(self.variations)
                for i=1,#self._tmp_shuffle do
                    local swap = math.random(1, #self._tmp_shuffle)
                    self._tmp_shuffle[i], self._tmp_shuffle[swap] = self._tmp_shuffle[swap], self._tmp_shuffle[i]
                end
            end
            local text = self._tmp_shuffle[#self._tmp_shuffle]
            self._tmp_shuffle[#self._tmp_shuffle] = nil

            local language = tok.properties:CurrentlySpokenLanguage()

            if language ~= nil then
                tok:ModifyProperties{
                    description = "Speech",
                    undoable = false,
                    execute = function()
                        tok.properties:CharacterSpeech{
                            text = text,
                            langid = language, 
                        }
                    end,
                }
            elseif self:has_key("fallbackText") then
                tok:ModifyProperties{
                    description = "Float text",
                    undoable = false,
                    execute = function()
                        tok.properties:FloatLabel(self.fallbackText, "white")
                    end,
                }
            end
        end
    end
end

function ActivatedAbilityCharacterSpeechBehavior:EditorItems(parentPanel)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local Refresh
    Refresh = function()
        local children = {}

    	self:ApplyToEditor(parentPanel, children)
	    self:FilterEditor(parentPanel, children)

        for i,entry in ipairs(self.variations) do
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Input{
                    classes = {"formInput"},
                    width = 280,
                    height = "auto",
                    minHeight = 20,
                    maxHeight = 160,
                    halign = "left",
                    text = entry,
                    change = function(element)
                        self.variations[i] = element.text
                        self._tmp_shuffle = nil
                    end,
                },

                gui.DeleteItemButton{
                    width = 12,
                    height = 12,
                    press = function()
                        table.remove(self.variations, i)
                        Refresh()
                        self._tmp_shuffle = nil
                    end,
                }
            }
        end

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Input{
                classes = {"formInput"},
                width = 280,
                height = "auto",
                minHeight = 20,
                maxHeight = 160,
                halign = "left",
                multiline = true,
                placeholderText = "Add new speech variation...",
                change = function(element)
                    if element.text ~= "" then
                        self.variations[#self.variations+1] = element.text
                        Refresh()
                        self._tmp_shuffle = nil
                    end
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Fallback Text:",
            },
            gui.Input{
                classes = {"formInput"},
                width = 280,
                height = "auto",
                minHeight = 20,
                maxHeight = 160,
                halign = "left",
                placeholderText = "Enter no language text",
                text = self:try_get("fallbackText") or "",
                change = function(element)
                    self.fallbackText = element.text
                    Refresh()
                end,
            }
        }

        panel.children = children
    end

    Refresh()

    return {panel}
end

function creature:CharacterSpeech(params)
    params.guid = dmhub.GenerateGuid()
    params.timestamp = ServerTimestamp()
    local speech = self:try_get("speech", {})
    local newSpeech = {}
    for _,entry in ipairs(speech) do
        if TimestampAgeInSeconds(entry.timestamp) < 10 then
            newSpeech[#newSpeech+1] = entry
        end
    end

    newSpeech[#newSpeech+1] = params
    self.speech = newSpeech
end
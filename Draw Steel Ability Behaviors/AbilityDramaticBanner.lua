local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityDramaticBannerBehavior:ActivatedAbilityBehavior
--- An ability behavior that displays a full-screen DramaticBanner centred
--- on a token. The token is chosen with the standard "Apply To" field,
--- and the banner shows the configured title and subtitle text.
ActivatedAbilityDramaticBannerBehavior = RegisterGameType("ActivatedAbilityDramaticBannerBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityDramaticBannerBehavior.summary = 'Dramatic Banner'

ActivatedAbilityDramaticBannerBehavior.title = ""
ActivatedAbilityDramaticBannerBehavior.subtitle = ""

ActivatedAbility.RegisterType
{
    id = 'dramatic_banner',
    text = 'Dramatic Banner',
    createBehavior = function()
        return ActivatedAbilityDramaticBannerBehavior.new{
        }
    end
}

function ActivatedAbilityDramaticBannerBehavior:Cast(ability, casterToken, targets, options)
    -- 'targets' has already been resolved from the Apply To setting, so
    -- each entry is the token the banner should be centred on.
    local shown = false
    for _,target in ipairs(targets) do
        local tok = target.token
        if tok ~= nil and tok.valid then
            -- Title/subtitle support GoblinScript interpolation: any
            -- {formula} is evaluated against the banner token's symbols.
            DramaticBanner.Show{
                tokenid = tok.charid,
                text = StringInterpolateGoblinScript(self.title, tok.properties),
                subtitle = StringInterpolateGoblinScript(self.subtitle, tok.properties),
            }
            shown = true
        end
    end

    -- Pause ability execution while the banner is on screen. Cast runs
    -- inside a coroutine, so yield in a loop until the banner has
    -- finished displaying.
    if shown then
        while DramaticBanner.TimeUntilDone() > 0 do
            coroutine.yield(0.1)
        end
    end
end

function ActivatedAbilityDramaticBannerBehavior:EditorItems(parentPanel)
    local result = {}

    -- Standard Apply To field: picks the token the banner is centred on.
    self:ApplyToEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Title:",
        },
        gui.Input{
            classes = {"formInput"},
            width = 280,
            text = self.title,
            placeholderText = "Banner title...",
            change = function(element)
                self.title = element.text
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Subtitle:",
        },
        gui.Input{
            classes = {"formInput"},
            width = 280,
            text = self.subtitle,
            placeholderText = "Banner subtitle (optional)...",
            change = function(element)
                self.subtitle = element.text
            end,
        },
    }

    return result
end

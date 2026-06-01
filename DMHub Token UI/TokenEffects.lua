local mod = dmhub.GetModLoading()


TokenEffects = {
	template = {
		image = 'panels/token-effect-template.png',
		x = 0,
		y = 0,
		width = 150,
		height = 150,
	},
	curewounds = {
		video = 'cure-wounds.webm',
		width = 150,
		height = 150,
	},
	redflash = {
		video = mod.images.doubleslash,
        duration = 0.5,
        width = 180,
        height = 180,
	},

	teleport = {
		video = 'teleport.webm',
		width = 150,
		height = 150,
	},

	teleportreverse = {
		video = 'teleportreverse.webm',
		width = 150,
		height = 150,
	},

	sweat = {
		video = 'sweatdrop.webm',
		width = 150,
		height = 150,
	},

	goblinears = {
		video = 'goblinears.webm',
		width = 250,
		height = 250,
	},

	hearts = {
		video = 'hearts.webm',
		width = 150,
		height = 150,
	},

	chat = {
		video = 'chat.webm',
		width = 150,
		height = 150,
		looping = true,
		fadetime = 0.2,
		styles = {
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				y = 40,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				y = -40,
				opacity = 0,
			},
		},
	},

	rage = {
		video = 'rage.webm',
		width = 300,
		height = 300,
		looping = true,
		fadetime = 0.2,
		styles = {
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
	},

	scared = {
		video = 'scaredanimation.webm',
		width = 150,
		height = 150,
		looping = true,
		fadetime = 0.2,
		styles = {
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
	},

	charmed = {
		video = 'charmed.webm',
		width = 150,
		height = 150,
		looping = false,
		fadetime = 0.2,

		styles = {
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
		},

	},

	target = {
		video = 'targetwithoutglow.webm',
		width = 300,
		height = 300,
		looping = true,
		fadetime = 0.2,
		styles = {
			{
				blend = "normal",
				opacity = 1,
				brightness = 0.7,
				saturation = 1,
			},
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'target-active'},
				opacity = 1,
				brightness = 1.3,
				saturation = 1.4,
			},
			{
				selectors = {'target-press'},
				opacity = 0.7,
			},
			{
				selectors = {'invalid'},
				saturation = 0,
                brightness = 0.5,
			},
			{
				selectors = {'target-selected'},
				brightness = 1.5,
				saturation = 1,
			},
			{
				selectors = {'remote', 'invalid'},
				opacity = 0.5,
			},
			{
				selectors = {'remote', 'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
	},

	target2stacks = {
		video = 'targetwithoutglow.webm',
		width = 300,
		height = 300,
		looping = true,
		fadetime = 0.2,
		styles = {
            {
                scale = 0.8,
            },
			{
				blend = "normal",
				opacity = 1,
				brightness = 1,
				saturation = 1,
			},
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'target-press'},
				opacity = 0.7,
			},
			{
				selectors = {'target-selected'},
				brightness = 1.5,
				saturation = 1,
			},
			{
				selectors = {'remote', 'invalid'},
				opacity = 0.5,
			},
			{
				selectors = {'remote', 'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
            {
                selectors = {'~two'},
                priority = 5,
                opacity = 0,
            }
		},
	},

	target3stacks = {
		video = 'targetwithoutglow.webm',
		width = 300,
		height = 300,
		looping = true,
		fadetime = 0.2,
		styles = {
            {
                scale = 0.6,
            },
			{
				blend = "normal",
				opacity = 1,
				brightness = 1,
				saturation = 1,
			},
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'target-press'},
				opacity = 0.7,
			},
			{
				selectors = {'invalid'},
				saturation = 0,
			},
			{
				selectors = {'target-selected'},
				brightness = 1.5,
				saturation = 1,
			},
			{
				selectors = {'remote', 'invalid'},
				opacity = 0.5,
			},
			{
				selectors = {'remote', 'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
            {
                selectors = {'~three'},
                priority = 5,
                opacity = 0,
            }
		},
	},

	targetglow = {
		image = 'panels/token-target-glow.png',
		width = 300,
		height = 300,
		fadetime = 0.2,
		styles = {
			{
				blend = "normal",
				opacity = 0,
			},
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'target-active'},
				opacity = 1,
				brightness = 1,
				transitionTime = 0.2,
			},
			{
				selectors = {'target-press'},
				opacity = 0.7,
			},
			{
				selectors = {'target-selected'},
				brightness = 1.5,
				saturation = 1,
			},
			{
				selectors = {'invalid'},
				saturation = 0.5,
			},
		},
	},

	target2 = {
		video = 'target.webm',
		width = 300,
		height = 300,
		looping = true,
		fadetime = 0.2,
		styles = {
			{
				blend = "add",
			},
			{
				selectors = {'fadein'},
				transitionTime = 0.2,
				opacity = 0,
			},
			{
				selectors = {'fadeout'},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
	},

	wings = {
		video = 'wings3.webm',
		width = 240,
		height = 240,
		looping = true,
	},

	swimming = {
		video = 'swimming.webm',
		width = 150,
		height = 150,
		looping = true,
	},

}

local CreateTokenEffectFromEmoji = function(emoji, looping)
	return {
		video = cond(not emoji.staticImage, emoji.id),
		image = cond(emoji.staticImage, emoji.id),
		x = emoji.x,
		y = emoji.y,
		width = emoji.displayWidth,
		height = emoji.displayHeight,
		looping = looping,
		mask = emoji.mask,
		behind = emoji.behind,
		fadetime = emoji.fadetime,
		styles = emoji.styles,
		finishEmoji = emoji.finishEmoji,
	}
end

function GetTokenEffects(id)
	local result = TokenEffects[id]
	if result ~= nil then
		return { result }
	end

	result = assets:FindEmojiByIdOrName(id)
	if result ~= nil then
		local items = {
			CreateTokenEffectFromEmoji(result, result.looping)
		}

		for i,child in ipairs(result.childEmoji) do
			local childEmoji = assets.emojiTable[child]
			if childEmoji ~= nil then
				items[#items+1] = CreateTokenEffectFromEmoji(childEmoji, result.looping)
			end
		end

		return items
	end

	return nil
end

function TokenEffects.Register(entry)
    TokenEffects[entry.id] = entry
end

Commands.RegisterMacro{
    name = "tokeneffect",
    summary = "play token effect",
    doc = "Usage: /tokeneffect <effect name>\nPlays a visual effect on selected or primary tokens.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        local dataTable = assets.emojiTable
        for k, emoji in pairs(dataTable) do
            result[#result+1] = {text = k, summary = emoji.description or k}
        end
        table.sort(result, function(a, b) return a.summary < b.summary end)
        return result
    end,
    command = function(id)
        local tokens = dmhub.selectedOrPrimaryTokens
        for i,token in ipairs(tokens) do
            token.sheet.data.PlayEffect(id, false)
        end
    end,
}

--Teleport animations. Each entry is a Lua function that the engine calls locally on every
--client when a token with appearance.teleportAnimation == this id teleports. The function
--receives (token, targetLoc, opts) and orchestrates the visual via `token.animation`. See
--CharacterTokenAnimationLua for the primitive surface (Light / Billboard / PlayEffect / Tween
--/ SetVisible) and engine docs for the opts table (crossMap / fromLoc / fromMap).
--
--The engine moves the token's logical position to targetLoc immediately. The animation owns
--only the rendered position via the visual offset; on coroutine exit the engine snaps the
--rendered position back to the logical position. A well-behaved animation ends with the
--visual already at targetLoc (via anim:Tween{translate=targetLoc, duration=...}) so the
--handoff is smooth.

--Default: classic teleport.webm at source + delayed teleport.webm at destination, with a
--purple light burst at each end and a short hold before the visual snaps to the destination.
dmhub.tokenAnimations:RegisterTeleport{
    id = "default",
    name = "Default",
    animation = function(token, targetLoc, opts)
        audio.FireSoundEvent("Ability.Teleport_Generic")
        local anim = token.animation

        anim:Light{
            color = "#7300ff", radius = 2.0, innerRadius = 0.1,
            duration = 1.0, fadein = 0.1, fadeout = 0.1,
        }
        anim:Billboard{ video = "teleport.webm", blend = "add", scale = 1.8 }
        anim:Billboard{ video = "teleport.webm", blend = "add", scale = 1.8,
                        pos = targetLoc, delay = 0.2 }

        sleep(0.4)
        anim:Tween{ duration = 0, translate = targetLoc }

        anim:Light{
            color = "#7300ff", radius = 2.0, innerRadius = 0.1,
            duration = 1.0, fadein = 0.1, fadeout = 0.1,
        }
        anim:Billboard{ video = "teleport.webm", blend = "add", scale = 1.8 }
        sleep(1)
    end,
}

--Ash teleport: token poofs into ash at the source, an invisible travel phase follows with a
--trailing wisp, then the token reappears at the destination.
dmhub.tokenAnimations:RegisterTeleport{
    id = "ashteleport",
    name = "Ash Teleport",
    animation = function(token, targetLoc, opts)
        audio.FireSoundEvent("Dice.Teleport_BlackAsh")
        local anim = token.animation

        anim:PlayEffect{ id = "Ash_Disappear_vfx" }
        anim:Light{ color = "#993377", radius = 2.0, innerRadius = 0.1, duration = 0.3, fadein = 0.1, fadeout = 0.1 }

        sleep(0.3)

        anim:SetVisible(false)
        local trail = anim:PlayEffect{ id = "FloorSmokeTrail_vfx", looping = true }
        anim:Tween{ translate = targetLoc, duration = 0.4 }
        sleep(0.4)
        trail:Stop()

        audio.FireSoundEvent("Dice.Remove_BlackAsh")
        anim:PlayEffect{ id = "Ash_Appearance_vfx" }
        anim:Light{ color = "#993377", radius = 2.0, innerRadius = 0.1, duration = 0.6, fadein = 0.1, fadeout = 0.1 }
        sleep(0.2)
        anim:SetVisible(true)
        sleep(1)
    end,
}

--Ash teleport: token poofs into ash at the source, an invisible travel phase follows with a
--trailing wisp, then the token reappears at the destination.
dmhub.tokenAnimations:RegisterTeleport{
    id = "testteleport",
    name = "Test Teleport",
    animation = function(token, targetLoc, opts)
        audio.FireSoundEvent("Dice.Teleport_BlackAsh")
        local anim = token.animation

        anim:PlayEffect{ id = "Effect_03_ChargeFire", scale = 0.1, rotation = {x = 0, y = 0, z = 0} }
        anim:Light{ color = "#993377", radius = 2.0, innerRadius = 0.1, duration = 0.3, fadein = 0.1, fadeout = 0.1 }

        sleep(0.3)

        anim:SetVisible(false)
        local trail = anim:PlayEffect{ id = "FloorSmokeTrail_vfx", looping = true }
        anim:Tween{ translate = targetLoc, duration = 0.4 }
        sleep(0.4)
        trail:Stop()

        audio.FireSoundEvent("Dice.Remove_BlackAsh")
        anim:PlayEffect{ id = "Effect_03_FireCross", scale = 0.1, rotation = {x = 0, y = 0, z = 0} }
        anim:Light{ color = "#993377", radius = 2.0, innerRadius = 0.1, duration = 0.6, fadein = 0.1, fadeout = 0.1 }
        sleep(0.2)
        anim:SetVisible(true)
        sleep(5)
    end,
}
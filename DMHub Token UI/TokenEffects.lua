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
    command = function(id)
        local tokens = dmhub.selectedOrPrimaryTokens
        for i,token in ipairs(tokens) do
            token.sheet.data.PlayEffect(id, false)
        end
    end,
}

print("IMAGEXXX::", mod.images.doubleslashbw)
local mod = dmhub.GetModLoading()

-- ActivatedAbilityTrackStatBehavior records a named, per-encounter statistic against
-- the creatures the ability applies to. It is a thin authoring front-end over
-- LiveEncounter.TrackHeroStats (Draw Steel Core Rules/MCDMEncounter.lua): for each
-- creature this behavior applies to, it adds an evaluated quantity to a free-form
-- stat id.
--
-- TrackHeroStats is fully self-guarding -- the stat is only recorded for a hero that
-- is participating in the current live encounter (a hero's summon attributes to its
-- summoner), and every other creature (monsters, objects, out-of-combat hits) is
-- silently ignored -- so this behavior is safe to point at any "Apply To" selection.
RegisterGameType("ActivatedAbilityTrackStatBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'track_stat',
	text = 'Track Stat',
	createBehavior = function()
		return ActivatedAbilityTrackStatBehavior.new{
			statid = "",
			quantity = "1",
		}
	end
}

ActivatedAbilityTrackStatBehavior.summary = 'Track Stat'

-- The free-form id of the stat to accumulate (e.g. "kills", "healingDone"). May be a
-- "/"-separated nested path (e.g. "monsterDamage/<monsterid>"). Empty = do nothing.
ActivatedAbilityTrackStatBehavior.statid = ""

-- GoblinScript for how much of the stat to add per creature. Defaults to 1.
ActivatedAbilityTrackStatBehavior.quantity = "1"

function ActivatedAbilityTrackStatBehavior:SummarizeBehavior(ability, creatureLookup)
	local statid = self:try_get("statid", "")
	if type(statid) ~= "string" or trim(statid) == "" then
		return "Track Stat"
	end
	return string.format("Track Stat: %s", trim(statid))
end

function ActivatedAbilityTrackStatBehavior:Cast(ability, casterToken, targets, options)
	local statid = self:try_get("statid", "")
	if type(statid) ~= "string" then
		statid = tostring(statid)
	end
	statid = trim(statid)
	if statid == "" then
		return
	end

	for _,target in ipairs(targets) do
		local token = target.token
		if token ~= nil and token.properties ~= nil then
			-- Evaluate the quantity with the tracked creature in scope as `target`
			-- (the caster remains the GoblinScript subject). DeepCopy so we don't
			-- leak `target` back into the shared casting symbols.
			local symbols = DeepCopy(options.symbols or {})
			symbols.target = token.properties
			local amount = dmhub.EvalGoblinScript(self:try_get("quantity", "1"), casterToken.properties:LookupSymbol(symbols), string.format("Stat quantity for %s", ability.name))
			amount = tonumber(amount) or 0
			if amount ~= 0 then
				LiveEncounter.TrackHeroStats(token.charid, statid, amount)
			end
		end
	end
end

function ActivatedAbilityTrackStatBehavior:EditorItems(parentPanel)
	local result = {}

	-- Standard "Apply To" selector: which creatures this behavior tracks the stat on.
	self:ApplyToEditor(parentPanel, result)

	-- Free-form stat name.
	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Stat:",
		},
		gui.Input{
			classes = {"formInput"},
			width = 320,
			text = self:try_get("statid", ""),
			characterLimit = 64,
			placeholderText = "Name of stat to track, e.g. kills",
			change = function(element)
				self.statid = element.text
			end,
		},
	}

	-- GoblinScript quantity.
	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Quantity:",
		},
		gui.GoblinScriptInput{
			classes = "formInput",
			value = self:try_get("quantity", "1"),
			change = function(element)
				self.quantity = element.value
			end,
			documentation = {
				help = "GoblinScript for how much to add to the stat for each creature this behavior applies to. Defaults to 1.",
				output = "number",
				examples = {
					{
						script = "1",
						text = "Add 1 to the stat (e.g. counting a kill or an event).",
					},
					{
						script = "Might",
						text = "Add the caster's Might score to the stat.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The caster of this ability.",
				symbols = ActivatedAbility.helpCasting,
			},
		},
	}

	return result
end

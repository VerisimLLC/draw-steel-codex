local mod = dmhub.GetModLoading()

--Climbing other creatures (Draw Steel, "Climbing Other Creatures").
--
--A creature climbs another by getting into one of its SADDLES -- the same engine mechanism that
--seats a rider on a mount. A creature that has no saddles of its own (which is nearly all of them)
--gets an AD-HOC saddle created for the climber by CharacterToken.ClimbOntoCreature; it exists only
--while the climber is in it, on every client, and needs no cleanup.
--
--This one behavior covers both ends of the rule:
--  operation "climb"    -- the CASTER climbs each target. Used by the Climb Creature maneuver.
--  operation "dismount" -- each TARGET gets off whatever it is climbing. Used by the Hold On test
--                          the Shake Off maneuver forces its rider to make, where the rider is the
--                          caster and the target is itself.
--
--A dismount either drops the climber from the height of the saddle (dismountFalls, tier 1 of the
--Hold On test: "you fall off the creature ... taking falling damage and landing prone as usual" --
--the engine's own falling rules produce the damage and the prone condition) or climbs it down to
--the ground safely (tier 2: "you slide down the creature ... and don't land prone").
--
--Where the climber ends up depends on how the behavior is targeted, which is how the rule's "into
--an unoccupied adjacent space of your choice" is honoured for the fall without making the safe
--slide-down ask a question nobody cares about:
--  * On an ability whose targetType is EMPTYSPACE, the player has already been prompted for the
--    space and the CASTER lands in it (see the Fall Off Creature standard ability, which the Hold
--    On test invokes on a tier 1).
--  * Otherwise the nearest legal space is picked automatically, and the targets are the creatures
--    getting off (the tier 2 slide, or a DM shoving a rider off directly).

--- @class ActivatedAbilityClimbCreatureBehavior:ActivatedAbilityBehavior
--- @field operation string
--- @field dismountFalls boolean
ActivatedAbilityClimbCreatureBehavior = RegisterGameType("ActivatedAbilityClimbCreatureBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'climb_creature',
	text = 'Climb Creature',
	createBehavior = function()
		return ActivatedAbilityClimbCreatureBehavior.new{
		}
	end
}

ActivatedAbilityClimbCreatureBehavior.summary = 'Climb Creature'

--"climb" = the caster climbs the targets. "dismount" = the targets get off what they are climbing.
ActivatedAbilityClimbCreatureBehavior.operation = "climb"

--Dismount only: leave the creature in the air where the saddle was so it falls (damage and prone
--come from the usual falling rules) instead of climbing down to the ground safely.
ActivatedAbilityClimbCreatureBehavior.dismountFalls = false

--The number of creatures climbing/riding this one. Drives the Shake Off maneuver's availability
--(a suppressabilities modifier in the Climbing Other Creatures global rule) and can be used in any
--GoblinScript. The reverse direction already has the Mounted / Mount symbols.
creature.RegisterSymbol {
	symbol = "climbers",
	lookup = function(c)
		local token = dmhub.LookupToken(c)
		if token == nil or (not token.valid) then
			return 0
		end

		return #token.riders
	end,
	help = {
		name = "Climbers",
		type = "number",
		desc = "The number of creatures currently climbing or riding this creature.",
		seealso = {"mounted", "mount"},
		examples = {"Climbers > 0"},
	}
}

--Whether a creature getting off mountToken can end up at loc: a space the mount itself does not
--occupy, and that nothing else is standing in.
--- @param riderToken CharacterToken
--- @param mountToken CharacterToken
--- @param loc Loc
--- @return boolean
local function IsLegalDismountLoc(riderToken, mountToken, loc)
	for _,mountLoc in ipairs(mountToken.locsOccupying or {}) do
		if mountLoc.xyfloorOnly.str == loc.xyfloorOnly.str then
			return false   --inside the creature we are getting off.
		end
	end

	for _,occupant in ipairs(game.GetTokensAtLoc(loc) or {}) do
		if occupant.id ~= riderToken.id then
			return false
		end
	end

	return true
end

--Where a creature that gets off mountToken ends up when nobody was asked: the legal space adjacent
--to the mount closest to where the climber already is, at altitude (nil = the ground there).
--- @param riderToken CharacterToken
--- @param mountToken CharacterToken
--- @param altitude nil|number
--- @return nil|Loc
local function FindDismountLoc(riderToken, mountToken, altitude)
	local candidates = mountToken:GetLocsWithinRadius(1)
	if candidates == nil then
		return nil
	end

	local bestLoc = nil
	local bestDist = nil
	for _,candidate in ipairs(candidates) do
		if IsLegalDismountLoc(riderToken, mountToken, candidate) then
			local d = candidate:DistanceInTiles(riderToken.loc)
			if bestDist == nil or d < bestDist then
				bestDist = d
				bestLoc = candidate
			end
		end
	end

	if bestLoc == nil then
		return nil
	end

	if altitude == nil then
		return bestLoc.withGroundAltitude
	end

	return bestLoc:WithAltitude(altitude)
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets AbilityTarget[]
--- @param options any
function ActivatedAbilityClimbCreatureBehavior:Cast(ability, casterToken, targets, options)
	if self.operation == "dismount" then
		self:CastDismount(ability, casterToken, targets, options)
		return
	end

	for _,target in ipairs(targets) do
		local mountToken = target.token
		if mountToken ~= nil and mountToken.valid and casterToken.valid then
			if casterToken:ClimbOntoCreature(mountToken) then
				ability:CommitToPaying(casterToken, options)
			end
		end
	end
end

--Get one creature out of the saddle it is in. chosenLoc is the space the player picked (an
--emptyspace ability did the asking); nil means pick the nearest legal one.
--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param riderToken CharacterToken
--- @param chosenLoc nil|Loc
--- @param options any
function ActivatedAbilityClimbCreatureBehavior:DismountCreature(ability, casterToken, riderToken, chosenLoc, options)
	if riderToken == nil or (not riderToken.valid) then
		return
	end

	--saddleMount is the creature directly underneath -- mount would walk the whole chain to the
	--bottom of a stack of riders.
	local mountToken = riderToken.saddleMount
	if mountToken == nil or (not mountToken.valid) then
		return
	end

	local altitude = nil
	if self.dismountFalls then
		--A climber's loc is already on top of the creature it is climbing (the engine puts a rider
		--at its mount's altitude plus the mount's height), so it falls from exactly where it is:
		--keep that altitude for the space it lands over and let the engine's falling rules take it
		--from there. A creature only one square tall costs its climber nothing but its footing --
		--a one-square fall does no damage, which is the rule, not a bug.
		altitude = riderToken.loc.altitude
	end

	local loc = nil
	if chosenLoc ~= nil and IsLegalDismountLoc(riderToken, mountToken, chosenLoc) then
		if altitude == nil then
			loc = chosenLoc.withGroundAltitude
		else
			loc = chosenLoc:WithAltitude(altitude)
		end
	else
		--No choice was made, or the chosen space turned out to be inside the mount -- fall back to
		--the nearest legal space rather than dropping the rider into the creature it was climbing.
		loc = FindDismountLoc(riderToken, mountToken, altitude)
	end

	--Sliding down is a move, so it animates; a fall is a drop, and the fall itself is the animation.
	if loc == nil or (not riderToken:DismountTo(loc, not self.dismountFalls)) then
		return
	end

	ability:CommitToPaying(casterToken, options)

	if self.dismountFalls then
		riderToken:TryFall()
	end
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets AbilityTarget[]
--- @param options any
function ActivatedAbilityClimbCreatureBehavior:CastDismount(ability, casterToken, targets, options)
	--Two shapes:
	--  (a) the targets are LOCS -- the ability's targetType is emptyspace, so the player has
	--      already been prompted for the space to end up in, and it is the CASTER getting off.
	--  (b) the targets are TOKENS -- those creatures get off, into an automatically chosen space.
	for _,target in ipairs(targets) do
		if target.token == nil and target.loc ~= nil then
			self:DismountCreature(ability, casterToken, casterToken, target.loc, options)
			return
		end
	end

	for _,target in ipairs(targets) do
		self:DismountCreature(ability, casterToken, target.token, nil, options)
	end
end

--- @param ability ActivatedAbility
--- @return string
function ActivatedAbilityClimbCreatureBehavior:SummarizeBehavior(ability, creatureLookup)
	if self.operation == "dismount" then
		if self.dismountFalls then
			return "Fall Off Creature"
		end

		return "Climb Down Creature"
	end

	return "Climb Creature"
end

function ActivatedAbilityClimbCreatureBehavior:EditorItems(parentPanel)
	local result = {}

	local dismountPanel

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Operation:",
		},

		gui.Dropdown{
			classes = {"formDropdown"},
			idChosen = self.operation,
			options = {
				{id = 'climb', text = 'Caster climbs the targets'},
				{id = 'dismount', text = 'Targets get off what they are climbing'},
			},
			change = function(element)
				self.operation = element.idChosen
				dismountPanel:SetClass("collapsed", self.operation ~= "dismount")
			end,
		},
	}

	dismountPanel = gui.Panel{
		classes = {"formPanel", cond(self.operation == "dismount", nil, "collapsed")},
		gui.Check{
			text = "Falls from the height of the saddle",
			value = self.dismountFalls,
			change = function(element)
				self.dismountFalls = element.value
			end,
		},
	}

	result[#result+1] = dismountPanel

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	return result
end

local mod = dmhub.GetModLoading()

--- @class Projectile
--- Computes and manages the path and visual behavior of a ranged attack projectile.
Projectile = RegisterGameType("Projectile")

local GetExpectedDamage = function(casterToken, targetToken, ability)
	for _,behavior in ipairs(ability.behaviors) do
		if behavior.typeName == "ActivatedAbilityAttackBehavior" then
			local roll = behavior:ExpectedDamageRoll(ability, casterToken, targetToken, {})
			return dmhub.RollExpectedValue(roll)
		end
	end

	return 1
end

--Calculate how the projectile is going to go down.
--casterToken (token)
--targetToken (token)
--ability (ActivatedAbility)
--rollInfo (RollInfo object)
--properties -- table of properties to populate.
--src -- vector2 containing the source point.
function Projectile.CalculateProperties(casterToken, targetToken, ability, rollInfo, properties, src)

	local tokenDelta = core.Vector2(targetToken.loc.x - src.x, targetToken.loc.y - src.y)
	local maxRange = tokenDelta.length*1.1

	local abilityRange = ability:GetRangeDisadvantage()
	if abilityRange > maxRange then
		maxRange = maxRange + (abilityRange-maxRange)*math.random()*math.random()
	end

	local ReduceToMaxRange = function(p)
		local delta = core.Vector2(p.x - src.x, p.y - src.y)
		if delta.length > maxRange then
			return core.Vector2(src.x + delta.unit.x*maxRange, src.y + delta.unit.y*maxRange)
		end

		return p
	end

	local GetBounceDir = function(destPoint)
		local bounceDelta = core.Vector2(destPoint.x - targetToken.loc.x, destPoint.y - targetToken.loc.y)
		if bounceDelta.length < 0.1 then
			return core.Vector2(-tokenDelta.x, -tokenDelta.y).unit
		end

		return bounceDelta.unit
	end

	local bounceMult = 1 + 4*math.random()


	local matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)
	properties.outcome = matchingOutcome.outcome

	if matchingOutcome.outcome == "Critical" then
		properties.expectedDamage = GetExpectedDamage(casterToken, targetToken, ability)*3/targetToken.properties:MaxHitpoints()
		return {
			target = core.Vector2(targetToken.loc.x, targetToken.loc.y),
		}
	elseif matchingOutcome.outcome == "Hit" then
		local trajectory = dmhub.GetAttackTrajectory(casterToken, targetToken, src, "Hit")
		properties.expectedDamage = GetExpectedDamage(casterToken, targetToken, ability)/targetToken.properties:MaxHitpoints()

		return {
			target = trajectory.destPoint,
		}
	else
		local targetArmorClass = targetToken.properties:ArmorClass()
		local hitRequirement = rollInfo.properties:FindOutcomeRequirement("Hit") or targetArmorClass

		local coverInfo = dmhub.GetCoverInfo(casterToken, targetToken, casterToken.properties:GetPierceWalls())
		local coverModifier = 0
		if coverInfo ~= nil then
			coverModifier = coverInfo.coverModifier
		end

		--a creature with no dex modifier has an AC of 10. Since a negative dex modifier gives negative AC this implies that
		--creatures with +0 dex dodge sometimes. So we'll assume that the 'base' AC without any dex is a 8. So a roll of 8 or 9
		--against such a creature would be a dodge.
		local baseAC = 8

		local dexModifier = targetToken.properties:DexModifierForArmorClass()
		if dexModifier == nil then
			--armor such as plate mail which doesn't allow dex modifiers presumably means these creatures never dodge. But instead,
			--rolls above an 8 will be blocked with armor.
			dexModifier = 0
		else
			dexModifier = dexModifier + 2 --make it so even creatures with negative dex modifier *occasionally* dodge.
			if dexModifier < 0 then
				dexModifier = 0
			end
		end

		if dexModifier < 0 then
			baseAC = baseAC + dexModifier
		end

		--if we have some cover, then hitting the cover is a 'good miss'. So add it on top of the baseAC.
		--the cover is deducted from the roll so we reduce the baseAC to reflect this.
		baseAC = baseAC - coverModifier
		local coverAC = baseAC + coverModifier

		dmhub.Debug(string.format("OUTCOME:: baseAC = %d; coverAC = %d; Dodge = %d", baseAC, coverAC, hitRequirement - dexModifier))

		if dexModifier > 0 and rollInfo.total >= (hitRequirement - dexModifier) then
			--the target dodges the roll.
			local trajectory = dmhub.GetAttackTrajectory(casterToken, targetToken, src, "Dodge")
			properties.dodge = true
			properties.dodgeSpeed = 7
			return {
				target = ReduceToMaxRange(trajectory.obstructionPoint),
			}

		elseif rollInfo.total >= baseAC and rollInfo.total < coverAC then
			dmhub.Debug(string.format("OUTCOME:: COVER"))
			--the attack hits cover.
			local trajectory = dmhub.GetAttackTrajectory(casterToken, targetToken, src, "MissIntoCover")
			return {
				target = trajectory.obstructionPoint,
			}
		elseif rollInfo.total < baseAC then
			--just a plain miss/bad shot.
			dmhub.Debug("OUTCOME:: MISS")
			local trajectory = dmhub.GetAttackTrajectory(casterToken, targetToken, src, "Miss")
			return {
				target = ReduceToMaxRange(trajectory.obstructionPoint),
			}
		else
			--didn't get through defender's armor.
			local trajectory = dmhub.GetAttackTrajectory(casterToken, targetToken, src, "Hit")

			properties.bounce = {
				position = {
					x = GetBounceDir(trajectory.destPoint).x*bounceMult,
					y = GetBounceDir(trajectory.destPoint).y*bounceMult,
				},
				rotation = math.random()*360 - math.random()*360,
				time = math.random()*0.2 + bounceMult*0.1,
			}
			return {
				target = trajectory.destPoint,
			}
		end

	end
end

function Projectile.UpdateProjectileCoroutine(obj, casterToken, targetToken, ability, key, sourcePos)
	local count = 0
	while count < 200 and casterToken ~= nil and casterToken.valid and targetToken ~= nil and targetToken.valid do
		local rollInfo = chat.GetRollInfo(key)

		if rollInfo ~= nil and not rollInfo.waitingOnDice then
			local projectileComponent = obj:GetComponent("Projectile")
			if projectileComponent == nil then
				dmhub.Debug(string.format("PROJECTILEUPDATE:: NO COMPONENT"))
				return
			end
			local propertiesInfo = Projectile.CalculateProperties(casterToken, targetToken, ability, rollInfo, projectileComponent.properties, sourcePos)
			obj.x = propertiesInfo.target.x
			obj.y = propertiesInfo.target.y
			obj:Upload()
			dmhub.Debug(string.format("PROJECTILEUPDATE:: %s", dmhub.ToJson(projectileComponent.properties)))
			return
		end

		count = count+1
		coroutine.yield(0.1)
	end
end

-- rollInfo: a rollInfo object.
-- ability: an ActivatedAbility.
-- casterToken: the caster using the ability.
-- targetToken: the target creature.
-- missileid: itemid of the missile.
function Projectile.Fire(options)

	local windupTime = 10

	local ability = options.ability
	local casterToken = options.casterToken
	local targetToken = options.targetToken
	local rollInfo = options.rollInfo

	local sourcePos = core.Vector2(casterToken.posWithLean.x, casterToken.posWithLean.y)

	local delta = core.Vector2(targetToken.loc.x - casterToken.loc.x, targetToken.loc.y - casterToken.loc.y)

	local floor = game.GetFloor(targetToken.floorid)
	if floor ~= nil then
		local gearTable = dmhub.GetTable('tbl_Gear')
		local itemInfo = gearTable[options.missileid]

		if itemInfo:HasProperty("thrown") then
			windupTime = 0.5
		end

		local propertiesInfo = {
			target = core.Vector2(targetToken.loc.x, targetToken.loc.y)
		}
		local properties = {}
		if not rollInfo.waitingOnDice then
			propertiesInfo = Projectile.CalculateProperties(casterToken, targetToken, options.ability, rollInfo, properties, sourcePos)
		end

		local loot = nil
		
		printf("DestroyChance: %s", json(itemInfo:AmmoDestroyChance()))
		if math.random() >= itemInfo:AmmoDestroyChance() then
			loot = {
				["@class"] = "ObjectComponentLoot",
				destroyOnEmpty = true,
				instantLoot = true,
				locked = false,
				properties = {
					__typeName = "loot",
					inventory = {
						[options.missileid] = {
							quantity = 1,
						},
					},
				},
			}
		end

		local obj = floor:CreateObject{
			asset = {
				description = "Item",
				imageId = dmhub.GetRawImageId(itemInfo.iconid),
				hidden = false,
			},
			components = {
				CORE = {
					["@class"] = "ObjectComponentCore",
					hasShadow = true,
					height = 3,
					pivot_x = 0.5,
					pivot_y = 0.5,
					rotation = itemInfo:try_get("projectileRotation", 0) + delta.angle,
					scale = itemInfo:try_get("projectileScale", Projectile.DefaultScale),
					sprite_invisible_to_players = false,
				},

				PROJECTILE = {
					["@class"] = "ObjectComponentProjectile",
					key = rollInfo.key,
					timestamp = dmhub.serverTime,
					speed = 25,
					srcx = sourcePos.x,
					srcy = sourcePos.y,
					attackerGuid = casterToken.charid,
					defenderGuid = targetToken.charid,
					properties = properties,
					destroyOnFinish = (loot == nil),
					windupTime = windupTime,
				},

				LOOT = loot,
			},

			assetid = "none",
			inactive = false,
			pos = {
				x = propertiesInfo.target.x,
				y = propertiesInfo.target.y,
			},

			zorder = 1,
		}


		if rollInfo.waitingOnDice then
			dmhub.Coroutine(Projectile.UpdateProjectileCoroutine, obj, casterToken, targetToken, options.ability, rollInfo.key, sourcePos)
		end

		if loot == nil then
			dmhub.Schedule(15, function()
				if obj ~= nil then
					obj:Destroy()
				end
			end)
		end
	end
	
end

--used to preview items.
function Projectile.CreateProjectileObj(floor, itemInfo, x, y)

	return floor:CreateObject{
		asset = {
			description = "Item",
			imageId = dmhub.GetRawImageId(itemInfo.iconid),
			hidden = false,
		},
		components = {
			CORE = {
				["@class"] = "ObjectComponentCore",
				hasShadow = true,
				height = 3,
				pivot_x = 0.5,
				pivot_y = 0.5,
				rotation = 0,
				scale = Projectile.DefaultScale,
				sprite_invisible_to_players = false,
			},
		},

		assetid = "none",
		inactive = false,
		pos = {
			x = x,
			y = y,
		},

		zorder = 1,
	}
end

-- ability: an ActivatedAbility.
-- casterToken: the caster using the ability.
-- targetToken: the target creature.
-- objectid: itemid of the object for the missile.
function Projectile.FireObject(options)
	dmhub.Coroutine(Projectile.FireObjectCoroutine, options)
end

function Projectile.FireObjectCoroutine(options)
	local casterToken = options.casterToken
	local targetToken = options.targetToken

	local floor = game.GetFloor(targetToken.floorid)
	if floor == nil then
		return
	end

	coroutine.yield(1)

	local obj = floor:SpawnObjectLocal(options.objectid)
	obj.x = casterToken.loc.x
	obj.y = casterToken.loc.y

	obj:AddComponent("Projectile")

	local proj = obj:ConstructComponent{
		["@class"] = "ObjectComponentMissile",
		duration = 2,
		srcx = casterToken.loc.x,
		srcy = casterToken.loc.y,
		dstx = targetToken.loc.x,
		dsty = targetToken.loc.y,
		targetGuid = targetToken.charid,
		impactEmote = options.ability:try_get("impactEmote"),
	}

	local delta = core.Vector2(targetToken.loc.x - casterToken.loc.x, targetToken.loc.y - casterToken.loc.y)

	local core = obj:GetComponent("Core")

	obj:Upload()
end

Projectile.DefaultScale = 0.4

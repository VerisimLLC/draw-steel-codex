local mod = dmhub.GetModLoading()

--- @class Anim: GameType
--- Namespace for attack animation coroutine utilities (melee, ranged, spell, etc.).
Anim = RegisterGameType("Anim")

--rollInfo: a rollInfo object
--attackerToken: token
--targetToken: target
function Anim.MeleeAttack(options)
	local attackerToken = options.attackerToken
	local targetToken = options.targetToken
	local rollInfo = options.rollInfo

	options.key = rollInfo.key
	dmhub.Coroutine(Anim.MeleeAttackCo, options)
end

function Anim.MeleeAttackCo(options)
	local attackerToken = options.attackerToken
	local targetToken = options.targetToken
	local count = 0
	while count < 200 do
		local rollInfo = chat.GetRollInfo(options.key)
			dmhub.Debug("MELEE:: WAITING... " .. count)

		if rollInfo ~= nil and not rollInfo.waitingOnDice then
			dmhub.Debug("MELEE:: GOT DICE")
			if attackerToken ~= nil and attackerToken.valid and targetToken ~= nil and targetToken.valid then
				local matchingOutcome = rollInfo.properties:GetOutcome(rollInfo)
				local outcome = matchingOutcome.outcome
				if matchingOutcome.outcome == "Critical" then
					options.damage = options.damage*3
				elseif matchingOutcome.outcome == "Hit" then
				else
					local targetArmorClass = targetToken.properties:ArmorClass()
					local hitRequirement = rollInfo.properties:FindOutcomeRequirement("Hit") or targetArmorClass


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

					if dexModifier > 0 and rollInfo.total >= (hitRequirement - dexModifier) then
						--the target dodges the roll.
						outcome = "Dodge"
					elseif rollInfo.total < baseAC then
						--just a plain miss/bad shot.
						outcome = "Miss"
					else
						--blocked by armor.
						outcome = "Block"
					end
				end

				printf("MELEE:: DO ATTACK")
				attackerToken:AnimateAttack{
					targetid = targetToken.charid,
					rollid = rollInfo.key,
					outcome = outcome,
					damage = options.damage,
				}
				
			end

			return
		end

		count = count+1
		coroutine.yield(0.1)
	end
end

local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRemoveCreatureBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field dropsLoot boolean If true, the removed creature drops its loot.
--- @field leavesCorpse boolean If true, a corpse object is left behind.
--- @field waitForAbilitiesToFinish boolean If true, waits for other ability animations to complete before removing.
--- @field waitForTriggers boolean If true, waits for any pending triggered abilities on the target (both UI trigger prompts and executing trigger-ability coroutines) to finish before removing.
ActivatedAbilityRemoveCreatureBehavior = RegisterGameType("ActivatedAbilityRemoveCreatureBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'remove_creature',
	text = 'Remove Creature',
	createBehavior = function()
		return ActivatedAbilityRemoveCreatureBehavior.new{
		}
	end
}

ActivatedAbilityRemoveCreatureBehavior.summary = 'Remove Creatures'
ActivatedAbilityRemoveCreatureBehavior.dropsLoot = false
ActivatedAbilityRemoveCreatureBehavior.leavesCorpse = false
ActivatedAbilityRemoveCreatureBehavior.waitForAbilitiesToFinish = true
ActivatedAbilityRemoveCreatureBehavior.waitForTriggers = false

function ActivatedAbilityRemoveCreatureBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Remove Creatures"
end

function ActivatedAbilityRemoveCreatureBehavior:DropLoot(token, newObj)
	local objects = assets:GetObjectsWithKeyword("corpse")

	if #objects == 0 then
		return newObj
	end

	local inventory = DeepCopy(token.properties:try_get("inventory", {}))


	--drop the held items as well.
    --[[ --In Draw Steel held equipment is only e.g. torches so we don't drop.
	local equip = token.properties:Equipment()
	local sharesSeen = {}
	for slotid,itemid in pairs(equip) do
		
		--make sure this isn't a shared slot.
		local metaslot = token.properties:EquipmentMetaSlot(slotid)
		local seen = false
		if metaslot.share ~= nil then
			if sharesSeen[metaslot.share] then
				seen = true
			else
				sharesSeen[metaslot.share] = true
			end
		end

		if not seen then
			local entry = inventory[itemid]
			if entry == nil then
				entry = {quantity = 0}
				inventory[itemid] = entry
			end

			entry.quantity = entry.quantity + 1
		end
	end
    --]]

	local haveItems = false
	for _,itemid in pairs(inventory) do
		haveItems = true
		break
	end

	if haveItems == false then
		for k,v in pairs(token.properties:try_get("currency", {})) do
			if v ~= nil and v > 0 then
				haveItems = true
				break
			end
		end
	end

	if haveItems == false then
		return newObj
	end



	local floor = game.GetFloor(token.floorid)

    if newObj == nil then
        newObj = floor:CreateLocalObjectFromBlueprint{
            assetid = objects[1].id,
        }

        newObj.scale = newObj.scale * token.radiusInTiles * 2
        newObj.x = token.pos.x
        newObj.y = token.pos.y
    end

    local appearanceComponent = newObj:GetComponent("Appearance")
    if appearanceComponent ~= nil then
        appearanceComponent:SetProperty("imageNumber", 1)
    end


	local loot = {
		["@class"] = "ObjectComponentLoot",
		destroyOnEmpty = false,
		instantLoot = false,
		locked = false,
		properties = {
			__typeName = "loot",
			inventory = inventory,
			currency = DeepCopy(token.properties:try_get("currency", {}))
		}
	}

	newObj:AddComponentFromJson("LOOT", loot)

    return newObj
end

local g_damageTypeToDescription = {
    acid = {"dissolved", "melted", "corroded"},
    cold = {"frozen"},
    corruption = {"rotted away", "withered", "consumed", "defiled"},
    fire = {"incinerated", "reduced to ashes", "immolated", "burned to a crisp"},
    holy = {"smitten", "purified", "cleansed in holy light", "struck down"},
    lightning = {"electrocuted", "struck down", "fried"},
    poison = {"poisoned", "envenomed"},
    psychic = {"mentally obliterated", "mind-shattered"},
    sonic = {"pulverized"},
    untyped = {"slain", "cut down", "felled", "killed"},
    collide = {"crushed", "smashed"},
    fall = {"forced over an edge", "thrown to their death", "hurled to their death"}
}

function ActivatedAbilityRemoveCreatureBehavior:LeaveCorpse(token, newObj)
    local objects = assets:GetObjectsWithKeyword("corpse")

    if #objects == 0 then
        return newObj
    end

    local floor = game.GetFloor(token.floorid)
    if floor == nil then
        return newObj
    end

    if newObj == nil then
        newObj = floor:CreateLocalObjectFromBlueprint{
            assetid = objects[1].id,
        }

        newObj.scale = newObj.scale * token.radiusInTiles * 2
        newObj.x = token.pos.x
        newObj.y = token.pos.y
    end


    newObj:AddComponentFromJson("CORPSE", {
        ["@class"] = "ObjectComponentCorpse",
        properties = {
            __typeName = "CorpseComponent",
            charid = token.charid,
        }
    })

    local message = creature.GetTokenDescription(token)

    if message ~= nil and message ~= "(unknown token)" then
        local q = dmhub.initiativeQueue
        local round = nil
        if q ~= nil and (not q.hidden) then
            round = q.round
        end

        local damageType = token.properties:try_get("_tmp_lastdamagetype", nil)
        local damageOptions = g_damageTypeToDescription[damageType or "untyped"] or g_damageTypeToDescription.untyped
        local damageDescription = damageOptions[math.random(1, #damageOptions)]

        message = string.format("%s, %s", message, damageDescription)

        local attackerName = nil
        local attacker = token.properties:try_get("_tmp_lastattacker", nil)
        print("ATTACKER:: LAST =", attacker, damageType)
        if attacker ~= nil then
            if type(attacker) == "function" then
                attacker = attacker("self")
            end
            attacker = dmhub.LookupToken(attacker)
            print("ATTACKER:: LOOKUP =", attacker ~= nil, attacker ~= nil and attacker.valid)
            if attacker ~= nil and attacker.valid then
                print("ATTACKER:: NAME =", attacker.name)
                attackerName = attacker.name
            end
        end

        if attackerName ~= nil then
            message = string.format("%s by %s", message, attackerName)
        end

        if round ~= nil then
            message = string.format("%s on round %d", message, round)
        end


        newObj:AddComponentFromJson("MESSAGE", {
            ["@class"] = "ObjectComponentHoverText",
            text = message,
        })
        
    end

    return newObj
end

function ActivatedAbilityRemoveCreatureBehavior:Cast(ability, casterToken, targets, options)
    local charids = {}
    for i,target in ipairs(targets) do

        local targetPasses = true
        if self.waitForAbilitiesToFinish and (not target.token.properties.minion) then
            local castInfo = ActivatedAbility.CurrentCastInfo() or {}
            castInfo.activity = "reaping"

            local startTime = dmhub.Time()
            while dmhub.Time() < startTime + 120 and ActivatedAbility.CountActiveCasts{reaping = true} > 0 do
                coroutine.yield(0.1)
            end

            if dmhub.Time() > startTime + 0.5 then
                --wait a little longer just to clear up any forced moves/etc
                coroutine.yield(0.5)
            end

            castInfo.activity = nil

            --guard against token being destroyed/despawned during the coroutine yield.
            if not target.token.valid or target.token.properties == nil then
                targetPasses = false
            end

            --make sure we still pass the filter.
            if targetPasses then
                local filterTarget = trim(self.filterTarget)
                if filterTarget ~= "" then
                    local symbols = table.shallow_copy(options.symbols or {})
                    symbols.target = target.token.properties
                    symbols.caster = casterToken.properties
                    symbols.targetnumber = i
                    symbols.numberoftargets = #targets

                    targetPasses = GoblinScriptTrue(ExecuteGoblinScript(filterTarget, target.token.properties:LookupSymbol(symbols), 1, "Filter remove creature"))
                end
            end
        end

        --Wait for any pending triggered abilities on the target to finish
        --Signals:
        --  hasPrompt = target has entries in availableTriggers (UI prompt
        --              queue for non-mandatory TriggeredAbilities).
        --  hasCast   = target has a CastCoroutine running (ability is
        --              actively executing on/by the target).
        if targetPasses and self.waitForTriggers and target.token.valid and target.token.properties ~= nil then
            local idleRequired = 0.3
            local waitStart = dmhub.Time()
            local waitDeadline = waitStart + 45
            local idleSince = nil
            while dmhub.Time() < waitDeadline do
                if not target.token.valid or target.token.properties == nil then
                    break
                end
                local hasPrompt = target.token.properties:GetAvailableTriggers() ~= nil
                local hasCast = ActivatedAbility.TokenHasOtherActiveCasts(target.token)
                if (not hasPrompt) and (not hasCast) then
                    idleSince = idleSince or dmhub.Time()
                    if dmhub.Time() - idleSince >= idleRequired then
                        break
                    end
                else
                    idleSince = nil
                end
                coroutine.yield(0.1)
            end

            --re-validate after the wait.
            if not target.token.valid or target.token.properties == nil then
                targetPasses = false
            end
        end

        if targetPasses then
            local corpse = nil
            if self.leavesCorpse then
                corpse = self:LeaveCorpse(target.token, corpse)
            end

            if self.dropsLoot then
                corpse = self:DropLoot(target.token, corpse)
            end

            if corpse ~= nil then
                corpse:Upload()
            end

            if target.token.properties:IsMonster() then
                target.token.despawned = true
            else
                charids[#charids+1] = target.token.charid
            end
        end

    end

    if #charids > 0 then
        game.DeleteCharacters(charids)
    end
    ability:CommitToPaying(casterToken, options)
end



function ActivatedAbilityRemoveCreatureBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Check{
		text = "Drops Loot",
		value = self.dropsLoot,
		change = function(element)
			self.dropsLoot = element.value
		end,
	}

    result[#result+1] = gui.Check{
        text = "Leaves Corpse Object",
        value = self.leavesCorpse,
        change = function(element) 
            self.leavesCorpse = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Wait for Abilities to Finish",
        value = self.waitForAbilitiesToFinish,
        change = function(element)
            self.waitForAbilitiesToFinish = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Wait for Triggers",
        value = self.waitForTriggers,
        change = function(element)
            self.waitForTriggers = element.value
        end,
    }

	return result
end

--- @class CorpseComponent
CorpseComponent = RegisterGameType("CorpseComponent")

CorpseComponent.charid = "none"

-- Diagnostic logger used by both the kill (LeaveCorpse path) and the revive
-- (Respawn). Tagged "[CORPSE_REVIVE]" so it's easy to grep out of the logs
-- on either client. Snapshots the fields that matter for the desync where
-- some monsters (Essence of Change, an Elite Mount) revive locally on the
-- DM but never re-appear on player clients despite the corpse-delete arriving.
local function _dumpCorpseTokenState(tag, charid, token)
    if token == nil then
        print(string.format("[CORPSE_REVIVE] %s charid=%s token=NIL", tostring(tag), tostring(charid)))
        return
    end
    local props = token.properties
    local mtype = props and props:try_get("monster_type") or "(non-monster)"
    local locInfo = token.locInfo
    local mountedOn = locInfo and locInfo.mountedOn or ""
    local mountedOnObject = locInfo and locInfo.mountedOnObject or ""
    local mapid = locInfo and locInfo.mapid or "(nil)"
    local mountedByCount = 0
    if token.mountedBy ~= nil then
        for _ in pairs(token.mountedBy) do mountedByCount = mountedByCount + 1 end
    end
    local x, y, fi = "?", "?", "?"
    if token.loc ~= nil then x = token.loc.x; y = token.loc.y; fi = token.loc.floorIndex end
    print(string.format(
        "[CORPSE_REVIVE] %s charid=%s name=%s monster=%s despawned=%s inactive=%s mapid=%s loc=%s,%s,%s mountedOn=%s mountedOnObject=%s mountedByCount=%d valid=%s",
        tostring(tag), tostring(charid), tostring(token.name), tostring(mtype),
        tostring(token.despawned), tostring(token.invisibleToPlayers), tostring(mapid),
        tostring(x), tostring(y), tostring(fi),
        tostring(mountedOn), tostring(mountedOnObject), mountedByCount,
        tostring(token.valid)))
end

function CorpseComponent:Respawn(obj)
    print(string.format("[CORPSE_REVIVE] Respawn invoked: corpseObjid=%s storedCharid=%s",
        tostring(obj and obj.id), tostring(self.charid)))
    local token = dmhub.GetCharacterById(self.charid)
    _dumpCorpseTokenState("BEFORE", self.charid, token)
    if token ~= nil then
        -- Order matters here. We must clear `despawned` BEFORE any
        -- ChangeLocation, not after.
        --
        -- ChangeLocation routes through GameController.SummonTokens, which
        -- (a) locally sets charInfo.locInfo.despawned = false on the
        -- caller and (b) ships a single PATCH of the entire locInfo
        -- object. LocationInfo.despawned is tagged
        -- [NoSerializeValue(false)], so the serialized patch OMITS the
        -- field, and PatchObject's class-merge path on the receiver
        -- preserves the receiver's existing `despawned = true` (set at
        -- kill time). Worse, by the time we then try to set
        -- `token.despawned = false` here, the setter sees the local copy
        -- already false (mutated by SummonTokens) and short-circuits the
        -- upload entirely -- so the despawn=false PUT is never sent and
        -- player clients leave the token hidden.
        --
        -- Writing despawned=false first guarantees the leaf PUT to
        -- /locInfo/despawned goes through (the setter's diff check sees a
        -- real change), and the subsequent SummonTokens PATCH lands on a
        -- receiver whose `despawned` is already false -- the merge then
        -- correctly preserves it.
        --
        -- Affects size>=2 tokens (mounts): for size 1 the corpse position
        -- equals token.loc and ChangeLocation is skipped, so the explicit
        -- setter call has always carried the despawn=false write. Mounts
        -- like the Essence of Change tripped this because the corpse is
        -- at the visual centre (token.pos), not the anchor (token.loc).
        print("[CORPSE_REVIVE] writing token.despawned = false (pre-move)")
        token.despawned = false

        if obj ~= nil then
            local x = round(obj.x)
            local y = round(obj.y)
            if token.loc.x ~= x or token.loc.y ~= y then
                print(string.format("[CORPSE_REVIVE] ChangeLocation -> %d,%d floor %d (was %s,%s,%s)",
                    x, y, obj.floorIndex,
                    tostring(token.loc.x), tostring(token.loc.y), tostring(token.loc.floorIndex)))
                token:ChangeLocation(core.Loc{x = x, y = y, floorIndex = obj.floorIndex}:WithGroundLevelAltitude())
            else
                print("[CORPSE_REVIVE] ChangeLocation skipped (same x,y)")
            end
        end
        _dumpCorpseTokenState("AFTER", self.charid, token)
    else
        print("[CORPSE_REVIVE] WARNING: no token resolved for corpse charid -- nothing to revive")
    end
end

function CorpseComponent:DeadCreatureToken()

    local result = dmhub.GetCharacterById(self.charid)
    print("Dead::", self.charid, result)
    return result
end
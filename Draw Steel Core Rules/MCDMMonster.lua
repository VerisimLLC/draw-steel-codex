local mod = dmhub.GetModLoading()

creature.withCaptain = false

monster.groupid = "none"
monster.role = "soldier"

monster.opportunityAttack = "1"

monster.traitNames = {}

--power roll bonus.
monster.pr = 0

--encounter value.
monster.ev = 1

monster.keywords = {}

function monster:Keywords()
    return self.keywords
end

function creature:PowerRollBonus()
    return 0
end

function monster:PowerRollBonus()
	return self.pr
end

function creature:MonsterGroup()
    return nil
end

function monster:MonsterGroup()
    local cat = self:try_get("monster_category")
    if cat ~= nil and cat ~= "" then
        if string.lower(cat) == "monster" and self.groupid ~= nil then
            return MonsterGroup.Get(self.groupid)
        end
        for id, group in unhidden_pairs(GetTableCached(MonsterGroup.tableName)) do
            --Skip rows with no name, as in MCDMUtils.GetStandardAbility.
            local groupName = group.name
            if type(groupName) == "string" and string.lower(groupName) == string.lower(cat) then
                return MonsterGroup.Get(id)
            end
        end
    else
        return MonsterGroup.Get(self.groupid)
    end
end

function creature:FillMonsterActivatedAbilities(options, result)
end

local g_defaultMonsterMaliceGroup = "69247753-5e1a-43b2-b48e-373c637939a0"

function monster:FillMonsterActivatedAbilities(options, result)
    if options.excludeGlobal then
        return
    end

    self:FillFreeStrikes(options, result)

    if self:try_get("retainer", false) or self:IsFollower() then
        return
    end

    if self:IsHeroSummon() then
        return
    end

    local group = self:MonsterGroup()
    local foundDefaultMalice = false
    local monsterLevel = self:Level()
    if group ~= nil then
        for _,ability in ipairs(group.maliceAbilities) do
            if monsterLevel >= ability:try_get("minLevel", 1) then
                result[#result+1] = ability:MakeTemporaryClone()
            end
        end

        --also get any malice abilities our band inherits. E.g. Bugbears can use Goblin malice abilities.
        local inherits = group:try_get("inherits")
        if inherits ~= nil then
            for key,_ in pairs(inherits) do
                if key == g_defaultMonsterMaliceGroup then
                    foundDefaultMalice = true
                end
                local parentGroup = MonsterGroup.Get(key)
                if parentGroup ~= nil then
                    for _,ability in ipairs(parentGroup.maliceAbilities) do
                        if monsterLevel >= ability:try_get("minLevel", 1) then
                            result[#result+1] = ability:MakeTemporaryClone()
                        end
                    end
                end
            end
        end
    end

    if not foundDefaultMalice then
        local parentGroup = MonsterGroup.Get(g_defaultMonsterMaliceGroup)
        if parentGroup ~= nil then
            for _,ability in ipairs(parentGroup.maliceAbilities) do
                if monsterLevel >= ability:try_get("minLevel", 1) then
                    result[#result+1] = ability:MakeTemporaryClone()
                end
            end
        end
    end
end

function monster:FillFreeStrikes(options, result)
    local signature = self:GetSignatureAbility()

    local powerRoll = nil
    local damageType = "untyped"
    local signatureRange = 1
    if signature ~= nil then
        for _,behavior in ipairs(signature.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                powerRoll = behavior
                break
            end
        end

        if powerRoll ~= nil then
            local matchDamageType = regex.MatchGroups(powerRoll.tiers[3], "[0-9]+ (?<damageType>[a-z]+) damage")
            if matchDamageType ~= nil then
                damageType = matchDamageType.damageType
            end
        end

        signatureRange = signature:GetRange(self) or 1
    end

    local freeStrikeDamage = tostring(self:OpportunityAttack())

    --Build one free strike clone. Forces the ability name to the
    --canonical "Melee Free Strike" / "Ranged Free Strike" so the name
    --match in UsesSquadCoordination
    local function buildFreeStrike(stdName, signatureKeyword, defaultRange)
        local stdAbility = MCDMUtils.GetStandardAbility(stdName)
        if stdAbility == nil then return nil end
        local ability = stdAbility:MakeTemporaryClone()
        ability.name = stdName
        --Force targeting properties so both Melee and Ranged variants
        --behave identically through the squad-strike pipeline
        ability.targetType = "target"
        ability.numTargets = "1"
        if signature ~= nil and signature:HasKeyword(signatureKeyword) then
            ability.range = math.max(defaultRange, signatureRange)
        else
            ability.range = defaultRange
        end
        --No *Charges factor: a free strike's damage is a flat statblock number
        --and never scales with charges. It used to be multiplied by Charges,
        --which broke whenever the free strike was invoked from a channeled
        --ability -- Charges defaults to 0 there (see ActivatedAbility:DefaultCharges)
        --and is forwarded across the invoke boundary, zeroing the whole roll
        --(e.g. the Undead malice feature Dread March). Multi-attacker squads are
        --handled by Cast.NumAttackers(Target), not by Charges.
        ability.behaviors[1].roll = freeStrikeDamage .. "*Cast.NumAttackers(Target)"
        ability.behaviors[1].damageType = damageType
        --Force per-target roll evaluation so Cast.NumAttackers(Target)
        --resolves against the actual target being damaged.
        ability.behaviors[1].separateRolls = true
        if damageType == "untyped" then
            ability.description = string.format("%s damage", freeStrikeDamage)
        else
            ability.description = string.format("%s %s damage", freeStrikeDamage, damageType)
        end
        return ability
    end

    local melee = buildFreeStrike("Melee Free Strike", "Melee", 1)
    if melee ~= nil then
        --Append the flagged-power-modifier applicator AFTER the damage
        --behavior so it lands as a post-strike effect (e.g. Bleeding (EoT)
        --on the target). Skipped if the symbol isn't registered yet, which
        --can happen during early load.
        if ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior ~= nil then
            ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.AppendToFreeStrike(melee)
        end
        result[#result+1] = melee
    end

    local ranged = buildFreeStrike("Ranged Free Strike", "Ranged", 5)
    if ranged ~= nil then
        if ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior ~= nil then
            ActivatedAbilityApplyFreeStrikePowerRollModifiersBehavior.AppendToFreeStrike(ranged)
        end
        result[#result+1] = ranged
    end
end

function creature:MakeFreeStrikeAttack(attackerToken, targetToken, symbols)
    print("Non-monsters don't currently implement automated free strikes.")
end

function monster:MakeFreeStrikeAttack(attackerToken, targetToken, symbols)
    local attacks = {}
    self:FillFreeStrikes({}, attacks)

    local distance = attackerToken:Distance(targetToken)

    for _,ability in ipairs(attacks) do
        local range = ability:GetRange(self)

        if range >= distance then
            ability:Cast(attackerToken, {{ token = targetToken }}, { symbols = symbols })
            return
        end
    end

end

creature.RegisterFeatureCalculation{
    id = "mcdmmonster",
    FillFeatures = function(c, result)
        if c:IsMonster() then
            c:FillTraitsFromGroup(result)
        end
    end,
}

function monster:FillTraitsFromGroup(result)
    local g = self:MonsterGroup()
    if g ~= nil then
        for _,trait in pairs(g.commonTraits) do
            result[#result+1] = trait
        end
        for _,traitName in ipairs(self.traitNames) do
            local trait = g.traits[traitName]
            if trait ~= nil then
                result[#result+1] = trait
            end
        end
    end
end

function monster:GetTraitsFromGroup()
    local result = {}
    self:FillTraitsFromGroup(result)
    return result

end

--- Subclass hook for monster-specific builder-choice sources. Adds
--- monsterGroup traits into the catch-all Choices section. The shared
--- implementation lives on creature:GetBuilderChoiceFeatures().
--- @param result table The accumulating list of { feature = ... } entries.
--- @param levelChoices table The creature's current levelChoices map.
function monster:FillExtraBuilderChoiceFeatures(result, levelChoices)
    for _,trait in ipairs(self:GetTraitsFromGroup()) do
        local nested = {}
        trait:FillFeaturesRecursive(levelChoices, nested)
        for _,f in ipairs(nested) do
            result[#result+1] = { feature = f, monsterGroup = self:MonsterGroup() }
        end
    end
end

function creature:OpportunityAttack()
    return 0
end

function monster:OpportunityAttack()
    return round(tonumber(self.opportunityAttack) + self:CalculateNamedCustomAttribute("Free Strike Bonus"))
end

function monster:OpportunityAttackRange()
    local ability = self:GetSignatureAbility()
    if ability ~= nil then
        return math.max(ability:GetRange(self), 1)
    end

    return 1
end

function monster:GetSignatureAbility()
    for i,ability in ipairs(self.innateActivatedAbilities) do
        if ability.categorization == "Signature Ability" then
            return ability
        end
    end

    return nil
end

--- Per-item accounting of implementation status across this monster's own
--- abilities and traits (group traits are not included). Each entry is
--- { name, kind ("Ability"/"Trait"), implementation } using the
--- gui.ImplementationStatus scale (0 = Narrative ... 4 = Gold). An item with
--- no status set reports Unimplemented, matching the compendium editors.
--- @return {name: string, kind: string, implementation: number}[]
function monster:ImplementationStatusAccounting()
    local entries = {}
    for _,ability in ipairs(self:try_get("innateActivatedAbilities", {})) do
        entries[#entries+1] = {
            name = ability.name,
            kind = "Ability",
            implementation = ability:try_get("implementation", 1),
        }
    end
    for _,feature in ipairs(self:try_get("characterFeatures", {})) do
        entries[#entries+1] = {
            name = feature.name,
            kind = "Trait",
            implementation = feature:try_get("implementation", 1),
        }
    end
    return entries
end

--- The calculated implementation status of this monster: the lowest tier
--- across its abilities and traits. Narrative (0) entries are neutral --
--- they mark content with nothing to automate, so they do not drag the
--- status down and are skipped. A monster with no abilities or traits (or
--- only Narrative ones) reports Gold, since it has nothing left to implement.
--- @return number
function monster:CalculateImplementationStatus()
    local result = nil
    for _,entry in ipairs(self:ImplementationStatusAccounting()) do
        if entry.implementation ~= gui.ImplementationStatus.WontImplement then
            if result == nil or entry.implementation < result then
                result = entry.implementation
            end
        end
    end
    return result or gui.ImplementationStatus.Gold
end

--- The effective implementation status: an explicit override stored on the
--- monster if one is set, otherwise the calculated (lowest-tier) status.
--- @return number
function monster:GetImplementationStatus()
    local override = self:try_get("implementation")
    if override ~= nil then
        return override
    end
    return self:CalculateImplementationStatus()
end

--- @return boolean
function monster:HasImplementationStatusOverride()
    return self:try_get("implementation") ~= nil
end

--- Set or clear (nil) the implementation status override.
--- @param value number|nil
function monster:SetImplementationStatusOverride(value)
    self.implementation = value
end

--- Build a panel summarizing this monster's implementation status: an
--- optional explanation of the status tiers, the calculated/override
--- summary, and a per-ability/trait accounting with colored status dots.
--- Callers wrap the returned panel in gui.TooltipFrame with their own
--- alignment. Theme styles are resolved here because tooltips render
--- outside the caller's style tree.
--- @param args nil|{includeExplanation: boolean}
--- @return Panel
function monster:RenderImplementationSummaryPanel(args)
    args = args or {}

    local rows = {}

    rows[#rows+1] = gui.Label{
        fontSize = 16,
        bold = true,
        width = "auto",
        height = "auto",
        text = "Implementation Status",
    }

    if args.includeExplanation then
        rows[#rows+1] = gui.Label{
            fontSize = 14,
            width = "100%",
            height = "auto",
            wrap = true,
            tmargin = 2,
            text = [[<b>Fully Automated:</b> Everything is handled by the app.
<b>Mostly Automated:</b> Automated, with some table adjudication necessary.
<b>Partly Automated:</b> Some of it is handled; the rest needs adjudication.
<b>Not Automated:</b> Requires manual adjudication.
<b>Narrative:</b> Role play only, no automation.

A monster's status is the lowest tier across its abilities and traits; Narrative entries are neutral and do not lower it.]],
        }
    end

    local entries = self:ImplementationStatusAccounting()
    local calculated = self:CalculateImplementationStatus()

    local summary = string.format("Calculated: %s", gui.ImplementationStatusValues[calculated] or "Unknown")
    if self:HasImplementationStatusOverride() then
        local override = self:GetImplementationStatus()
        summary = string.format("%s  |  Override: %s", summary, gui.ImplementationStatusValues[override] or "Unknown")
    end
    rows[#rows+1] = gui.Label{
        fontSize = 14,
        width = "auto",
        height = "auto",
        tmargin = 4,
        text = summary,
    }

    if #entries == 0 then
        rows[#rows+1] = gui.Label{
            fontSize = 14,
            width = "auto",
            height = "auto",
            tmargin = 6,
            text = "This monster has no abilities or traits.",
        }
    end

    for _,entry in ipairs(entries) do
        rows[#rows+1] = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 4,

            gui.ImplementationStatusIcon{
                halign = "left",
                valign = "center",
                implementation = entry.implementation,
            },
            gui.Label{
                fontSize = 14,
                width = 200,
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 6,
                textWrap = true,
                text = string.format("%s (%s)", entry.name, entry.kind),
            },
            gui.Label{
                classes = { "implStatus" .. tostring(entry.implementation) },
                fontSize = 14,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                text = gui.ImplementationStatusValues[entry.implementation] or "Unknown",
            },
        }
    end

    return gui.Panel{
        styles = ThemeEngine.GetStyles(),
        flow = "vertical",
        width = 340,
        height = "auto",
        pad = 8,
        borderBox = true,
        children = rows,
    }
end

function monster:CharacterLevel()
    return self.cr
end

function monster:Level()
    return self.cr
end

function monster:BaseForcedMoveResistance()
	return self.stability
end

function monster:BaseReach()
--    local g = MonsterGroup.Get(self.groupid)
--    if g ~= nil then
--        return g.reach
--    end
	return self.reach
end

function monster:BaseWeight()
--    local g = MonsterGroup.Get(self.groupid)
--    if g ~= nil then
--        return g.weight
--    end
	return self.weight
end

function monster:GetBaseCreatureSize()
    local defaultSize = "1M"
--    local g = MonsterGroup.Get(self.groupid)
--    if g ~= nil then
--        defaultSize = g.size
--    end
	return self:try_get("creatureSize", defaultSize)
end

function monster:SizeDescription()
    return self:GetBaseCreatureSize()
end

--the statblock's title-line role text, e.g. "Level 1 Horde Harrier" or
--"Level 2 Ruinant minion".
function monster:RoleDescription()
    return string.format("Level %d %s%s", round(tonumber(self.cr) or 0), self.role, cond(self.minion, " minion", ""))
end

--render a 'statblock' for the creature.
function monster:Render(args, options)

    options = options or {}
	args = args or {}

	local summary = args.summary
	args.summary = nil

	local asset = options.asset
	options.asset = nil

	local token = options.token
	options.token = nil
	
	if asset == nil and token == nil then
		return
	end

	if token == nil then
		token = asset.info
	end

	local charName
	if asset ~= nil then
		charName = asset.name
	else
		charName = token.name
	end

	if charName == "" or charName == nil then
		charName = self:try_get("monster_type")
	end


    local portraitBackground
    if not args.noavatar then
        portraitBackground = gui.Panel{
            id = "portrait",
            halign = "center",
            valign = "top",
            floating = true,
            width = "100%",
            height = "100% width",
            bgcolor = "#ffffff06",
            bgimage = token.portrait,
        }
    end

    args.noavatar = nil




	local abilities = self:GetActivatedAbilities{excludeGlobal = true, allLoadouts = true, bindCaster = true}
	local actionsPanel = nil

    local normalActions = {}

    for _,ability in ipairs(abilities) do
        --No extra pad: the card carries its own insets now that it draws as
        --a bordered rounded card.
        normalActions[#normalActions+1] = ability:Render({
            width = "100%",
        }, {
            token = token,

        })
    end

	actionsPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",
		children = normalActions,
	}

    local keywordsSorted = {}
    for k,v in pairs(self.keywords) do
        keywordsSorted[#keywordsSorted+1] = ActivatedAbility.CanonicalKeyword(k)
    end

    table.sort(keywordsSorted)
		
	local options = {
		width = 500,
		height = "auto",
		flow = "vertical",
		styles = {
            Styles.Default,
            SpellRenderStyles,
            {
                selectors = {"description"},
                bold = false,
            },
        },

        portraitBackground,

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",

			gui.Panel{
				flow = "vertical",
				width = "100%",
				height = "auto",
				halign = "left",

                gui.Panel{
                    classes = {"statblockNameRow"},
                    width = "100%",
                    height = 28,
                    flow = "horizontal",
                    gui.Label{
                        classes = {"description"},
                        smallcaps = true,
                        fontSize = 22,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        text = string.format("%s", charName),
                    },

                    gui.Label{
                        classes = {"description"},
                        smallcaps = true,
                        fontSize = 22,
                        bold = true,
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        text = self:RoleDescription(),
                    }
                },

                gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        fontSize = 20,
                        text = string.join(keywordsSorted, ", "),
                    },

                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        fontSize = 20,
                        text = string.format("EV %d%s", self:EV(), cond(self.minion, " for " .. GameSystem.minionsPerSquadText .. " minions", "")),
                    }
                },

                gui.Panel{
                    classes = "divider",
                },

                --stamina and immunity/vulnerability
                gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        fontSize = 16,
                        text = string.format("<b>Stamina</b> %d", self:MaxHitpoints()),
                    },

                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        fontSize = 16,
                        text = "",
                        create = function(element)
                            local resistances = self:try_get("resistances", {})
                            if #resistances == 0 then
                                return
                            end

                            local text = ""
                            local mode = nil

                            local immunityEntries = {}
                            for _,entry in ipairs(resistances) do
                                if entry.dr > 0 then
                                    local damageType = ""
                                    if entry:try_get("damageType", "all") ~= "all" then
                                        damageType = entry.damageType
                                        damageType = damageType:gsub("^%l", string.upper) .. " "
                                    end
                                    
                                    local keywords = {}
                                    for k,_ in pairs(entry:try_get("keywords", {})) do
                                        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
                                    end

                                    table.sort(keywords)
                                    keywords = string.join(keywords)

                                    if keywords ~= "" then
                                        damageType = keywords .. " " .. damageType
                                    end

                                    immunityEntries[#immunityEntries+1] = string.format("%s%d", damageType, entry.dr)
                                end
                            end

                            if #immunityEntries > 0 then
                                text = string.format("<b>Immunity</b> %s", string.join(immunityEntries, ", "))
                            end

                            local weaknessEntries = {}
                            for _,entry in ipairs(resistances) do
                                if entry.dr < 0 then
                                    local damageType = ""
                                    if entry:try_get("damageType", "all") ~= "all" then
                                        damageType = entry.damageType
                                        damageType = damageType:gsub("^%l", string.upper) .. " "
                                    end

                                    local keywords = {}
                                    for k,_ in pairs(entry:try_get("keywords", {})) do
                                        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
                                    end

                                    table.sort(keywords)
                                    keywords = string.join(keywords)

                                    if keywords ~= "" then
                                        damageType = keywords .. " " .. damageType
                                    end

                                    weaknessEntries[#weaknessEntries+1] = string.format("%s%d", damageType, -entry.dr)
                                end
                            end

                            if #weaknessEntries > 0 then
                                if text ~= "" then
                                    text = text .. " / "
                                end

                                text = text .. string.format("<b>Weakness</b> %s", string.join(weaknessEntries, ", "))
                            end

                            element.text = text
                        end,
                    }
                },

                --speed and size/stability
                gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        fontSize = 16,
                        text = string.format("<b>Stamina</b> %d", self:MaxHitpoints()),

                        create = function(element)
                            local str = string.format("<b>Speed</b> %s", tostring(self:WalkingSpeed()))
                            for k,speed in pairs(self:try_get("movementSpeeds", {})) do
                                if speed > 0 then
                                    str = str .. " " .. k
                                end
                            end

                            element.text = str
                        end,
                    },

                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        fontSize = 16,
                        text = string.format("<b>Size</b> %s / <b>Stability</b> %d", self:SizeDescription(), self:BaseForcedMoveResistance()),
                    }
                },

                --with captain & free strike
                gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        fontSize = 16,
                        text = cond(self.withCaptain,
                                    string.format("<b>With Captain</b> <alpha=%s>%s<alpha=#ff>",
                                                  cond(DrawSteelMinion.GetWithCaptainEffect(self.withCaptain) ~= nil, "#ff", "#55"),
                                                  self.withCaptain or ""),
                                    ""),
                    },
                    gui.Label{
                        classes = {"description"},
                        width = "auto",
                        height = "auto",
                        halign = "right",
                        fontSize = 16,
                        text = string.format("<b>Free Strike</b> %d", self:OpportunityAttack()),
                    },
                },

                --attributes.
                gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    create = function(element)
                        local children = {}
			            for i,attrid in ipairs(creature.attributeIds) do
                            local val = self:GetAttribute(attrid):Value()
                            local info = creature.attributesInfo[attrid]

                            local halign = "center"
                            if i == 1 then
                                halign = "left"
                            elseif i == #creature.attributeIds then
                                halign = "right"
                            end

                            children[#children+1] = gui.Label{
                                classes = {"description"},
                                fontSize = 16,
                                bold = true,
                                width = "auto",
                                height = "auto",
                                halign = halign,
                                text = string.format("%s %s", info.description, ModStr(val)),
                            }
                        end

                        element.children = children
                    end,

                },

			},

		},

		gui.Panel{
			classes = "divider",
		},

        --don't show monster attributes?
--	gui.Panel{
--		flow = "horizontal",
--		height = "auto",
--		width = "100%",
--		create = function(element)
--			local children = {}

--               local attributes = {}

--               local maxAttr = -99
--			for i,attrid in ipairs(creature.attributeIds) do
--                   local val = self:GetAttribute(attrid):Value()
--                   attributes[attrid] = val
--                   if val > maxAttr then
--                       maxAttr = val
--                   end
--               end

--			for i,attrid in ipairs(creature.attributeIds) do
--                   local attrMod = attributes[attrid]
--                   if attrMod == maxAttr then
--                       attrMod = string.format("<b>%s</b>", attrMod)
--                   else
--                       attrMod = tostring(attrMod)
--                   end
--				children[#children+1] = gui.Panel{
--					flow = "vertical",
--					width = 50,
--					height = "auto",
--					halign = "center",
--					gui.Label{
--						halign = "center",
--						width = "auto",
--						height = "auto",
--						text = "<b>" .. string.upper(attrid) .. "</b>",
--					},
--					gui.Label{
--						halign = "center",
--						width = "auto",
--						height = "auto",
--                           fontSize = 22,
--						text = attrMod,
--					}
--				}
--			end

--			element.children = children
--		end,
--	},

--	gui.Panel{
--		classes = "divider",
--	},

		--skills.
		gui.Label{
			classes = "description",
			create = function(element)
				local text = ""

				local skillsTable = dmhub.GetTable(Skill.tableName)
				local items = {}
				for k,skillInfo in pairs(skillsTable) do

					local skillMod = self:SkillModStr(skillInfo)
					local attrMod = ModStr(self:GetAttribute(skillInfo.attribute):Modifier())
					if skillMod ~= attrMod then
						items[#items+1] = string.format("%s", skillInfo.name)
					end
				end

				if #items == 0 then
					element:SetClass("collapsed", true)
				else
					table.sort(items)
					element.text = string.format("<b>Skills:</b> <i>[+1 Boon to Tests] %s</i>", string.join(items, ", "))
				end
			end,
		},

		gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "100%",
			create = function(element)
				local children = {}

                for _,feature in ipairs(self:GetTraitsFromGroup()) do
                    if feature.description ~= "" then
                        children[#children+1] = gui.Label{
                            vmargin = 10,
                            text = string.format("<b>%s:</b> <i>%s</i>", feature.name, StringInterpolateGoblinScript(feature.description, self))
                        }
                    end
                end

                for _,feature in ipairs(self:try_get("characterFeatures", {})) do
                    if feature.description ~= "" then
                        children[#children+1] = gui.Label{
                            vmargin = 10,
                            text = string.format("<b>%s:</b> <i>%s</i>", feature.name, StringInterpolateGoblinScript(feature.description, self))
                        }
                    end
                end

				for _,note in ipairs(self:try_get("notes", {})) do
					children[#children+1] = gui.Label{
						vmargin = 10,
						text = string.format("<b>%s:</b> <i>%s</i>", note.title, StringInterpolateGoblinScript(note.text, self))
					}
				end

				element.children = children
			end,
		},


		actionsPanel,


	}

	for k,v in pairs(args or {}) do
		options[k] = v
	end

	return gui.Panel(options)
end

local g_monsterSingularAbilityNames = {
    ["Basic Attack"] = "Free Strike",
    ["Signature Ability"] = "Signature Ability",
    ["Heroic Ability"] = "Malice Ability",
}

local g_monsterAbilityNames = {
    ["Basic Attack"] = "Free Strikes",
    ["Signature Ability"] = "Signature Abilities",
    ["Heroic Ability"] = "Malice Abilities",
}

function monster:AbilityCategorySingular(abilityCategory)
    return g_monsterSingularAbilityNames[abilityCategory] or abilityCategory
end

function monster:AbilityCategoryPlural(abilityCategory)
    return g_monsterAbilityNames[abilityCategory] or abilityCategory
end

monster.RegisterSymbol{
    symbol = "freestrikedamage",
    lookup = function(c)
        if c:IsMonster() then
            return c:OpportunityAttack()
        end

        return 0
    end,
    help = {
        name = "Free Strike Damage",
        type = "number",
        desc = "The free strike damage of the monster.",
        seealso = {},
    }
}

monster.RegisterSymbol{
    symbol = "freestrikerange",
    lookup = function(c)
        if c:IsMonster() then
            return c:OpportunityAttackRange()
        end

        return 0
    end,
    help = {
        name = "Free Strike Range",
        type = "number",
        desc = "The free strike range of the monster.",
        seealso = {},
    }
}

--EV (encounter value). The raw value is stored in `monster.ev`; access it
--through these accessors rather than the raw field so "Modify Attributes"
--CharacterModifiers targeting the "ev" attribute are applied. Registered as
--a modifiable attribute just below so those modifiers can target it.
CustomAttribute.RegisterAttribute{
    id = "ev",
    text = "EV",
    attributeType = "number",
    category = "Basic Attributes",
}

--- @return number the unmodified, stored EV.
function creature:BaseEV()
    return 0
end

--- @return number the unmodified, stored EV.
function monster:BaseEV()
    return self.ev or 1
end

--- @return number the EV with attribute modifiers applied.
function creature:EV()
    return 0
end

--- @return number the EV with attribute modifiers applied.
function monster:EV()
    return self:CalculateAttribute("ev", self:BaseEV())
end

--- @return {key:string,value:string}[] descriptions of the modifiers affecting EV.
function monster:DescribeEVModifications()
    return self:DescribeModifications("ev", self:BaseEV())
end

monster.RegisterSymbol{
    symbol = "ev",
    lookup = function(c)
        return c:EV()
    end,
    help = {
        name = "EV",
        type = "number",
        desc = "The EV of the monster.",
        seealso = {},
    }
}

local g_oldTemporalActiveModifiers = monster.FillTemporalActiveModifiers

function monster:FillTemporalActiveModifiers(result)
    g_oldTemporalActiveModifiers(self, result)

    if mod.unloaded then
        return
    end

    if self.withCaptain and self.minion and self:has_key("_tmp_minionSquad") then
        local squad = self._tmp_minionSquad
        if squad.hasCaptain then
            local feature = DrawSteelMinion.GetWithCaptainEffect(self.withCaptain)
            if feature ~= nil then
                for _,mod in ipairs(feature.modifiers) do
                    result[#result+1] = {
                        mod = mod,
                        temporal = true,
                    }

                end
            end
        end
        
    end

    --if we are the captain of a squad then see if the minions give us any modifiers.
    if (not self.minion) and self:MinionSquad() then
        local squad = self:GetMinionSquadInfo()
        if squad and squad.tokens then
            for _,tok in ipairs(squad.tokens) do
                if tok.valid and tok.properties then
                    local minionCreature = tok.properties
                    for i,mod in ipairs(minionCreature:GetActiveModifiers()) do
                        mod.mod:FillSquadCaptainModifiers(mod, minionCreature, self, result)
                    end
                end
            end
        end
    end
end

function monster:Organization()
    local role = self:try_get("role", "")
    local m = regex.MatchGroups(role, "^(?<org>[a-zA-Z]+).*$")
    if m ~= nil then
        return string.lower(m.org)
    end

    return nil
end

function monster:Role()
    local role = self:try_get("role", "")
    local m = regex.MatchGroups(role, "^(?<org>[a-zA-Z]+) (?<role>[a-zA-Z]+)$")
    if m ~= nil then
        return string.lower(m.role)
    end

    return nil
end

--==============================================================
-- Monster level scaling: lookup tables + math foundation.
--
-- Data ported (EVALUATED values) from the Monsters sheet of
-- "Draw Steel Maker Pro.xlsx" -- the authoritative source for this math.
-- Designer-confirmed rulings and the full design live in
-- .claude/monster-level-scaling.md. These functions are pure (no creature
-- mutation, no UI); the feature builder and the damage hook consume them.
--==============================================================

MCDMMonsterScaling = {}

MCDMMonsterScaling.minLevel = 1
MCDMMonsterScaling.maxLevel = 11

--Indexed by [org][level] for levels 1-11. stamina holds the three stamina
--tiers (low/med/high); normal/dps hold the three power-roll tiers {t1,t2,t3}.
--Leader/Solo rows only populate High stamina and DPS damage (others are nil),
--matching the sheet.
local g_scaleTable = {
    minion = {
        [1] = {ev=3, stamina={low=3, med=4, high=5}, normal={1, 2, 3}, dps={2, 4, 5}},
        [2] = {ev=4, stamina={low=4, med=5, high=7}, normal={2, 3, 5}, dps={3, 4, 6}},
        [3] = {ev=5, stamina={low=5, med=7, high=8}, normal={2, 4, 5}, dps={3, 5, 6}},
        [4] = {ev=6, stamina={low=7, med=8, high=9}, normal={2, 4, 6}, dps={3, 5, 7}},
        [5] = {ev=7, stamina={low=8, med=9, high=10}, normal={3, 5, 6}, dps={3, 6, 7}},
        [6] = {ev=8, stamina={low=9, med=10, high=12}, normal={3, 5, 7}, dps={4, 6, 8}},
        [7] = {ev=9, stamina={low=10, med=12, high=13}, normal={3, 6, 7}, dps={4, 7, 8}},
        [8] = {ev=10, stamina={low=12, med=13, high=14}, normal={3, 6, 8}, dps={4, 7, 9}},
        [9] = {ev=11, stamina={low=13, med=14, high=15}, normal={4, 6, 8}, dps={5, 7, 9}},
        [10] = {ev=12, stamina={low=14, med=15, high=17}, normal={4, 7, 9}, dps={5, 8, 10}},
        [11] = {ev=13, stamina={low=14, med=15, high=18}, normal={5, 7, 9}, dps={5, 8, 10}},
    },
    horde = {
        [1] = {ev=3, stamina={low=10, med=15, high=20}, normal={1, 2, 3}, dps={2, 4, 5}},
        [2] = {ev=4, stamina={low=15, med=20, high=25}, normal={2, 3, 5}, dps={3, 4, 6}},
        [3] = {ev=5, stamina={low=20, med=25, high=30}, normal={2, 4, 5}, dps={3, 5, 6}},
        [4] = {ev=6, stamina={low=25, med=30, high=35}, normal={2, 4, 6}, dps={3, 5, 7}},
        [5] = {ev=7, stamina={low=30, med=35, high=40}, normal={3, 5, 6}, dps={3, 6, 7}},
        [6] = {ev=8, stamina={low=35, med=40, high=45}, normal={3, 5, 7}, dps={4, 6, 8}},
        [7] = {ev=9, stamina={low=40, med=45, high=50}, normal={3, 6, 7}, dps={4, 7, 8}},
        [8] = {ev=10, stamina={low=45, med=50, high=55}, normal={3, 6, 8}, dps={4, 7, 9}},
        [9] = {ev=11, stamina={low=50, med=55, high=60}, normal={4, 6, 8}, dps={5, 7, 9}},
        [10] = {ev=12, stamina={low=55, med=60, high=65}, normal={4, 7, 9}, dps={5, 8, 10}},
        [11] = {ev=13, stamina={low=55, med=60, high=70}, normal={5, 7, 9}, dps={5, 8, 10}},
    },
    platoon = {
        [1] = {ev=6, stamina={low=20, med=30, high=40}, normal={3, 5, 7}, dps={4, 7, 10}},
        [2] = {ev=8, stamina={low=30, med=40, high=50}, normal={4, 7, 10}, dps={5, 8, 11}},
        [3] = {ev=10, stamina={low=40, med=50, high=60}, normal={5, 8, 11}, dps={5, 9, 12}},
        [4] = {ev=12, stamina={low=50, med=60, high=70}, normal={5, 9, 12}, dps={6, 10, 13}},
        [5] = {ev=14, stamina={low=60, med=70, high=80}, normal={6, 10, 13}, dps={6, 11, 14}},
        [6] = {ev=16, stamina={low=70, med=80, high=90}, normal={6, 11, 14}, dps={7, 12, 15}},
        [7] = {ev=18, stamina={low=80, med=90, high=100}, normal={7, 12, 15}, dps={7, 13, 16}},
        [8] = {ev=20, stamina={low=90, med=100, high=110}, normal={7, 13, 16}, dps={8, 13, 17}},
        [9] = {ev=22, stamina={low=100, med=110, high=120}, normal={8, 13, 17}, dps={9, 14, 18}},
        [10] = {ev=24, stamina={low=110, med=120, high=130}, normal={9, 14, 18}, dps={10, 15, 19}},
        [11] = {ev=26, stamina={low=110, med=120, high=140}, normal={10, 15, 19}, dps={10, 16, 20}},
    },
    leader = {
        [1] = {ev=12, stamina={low=nil, med=nil, high=80}, normal=nil, dps={4, 7, 10}},
        [2] = {ev=16, stamina={low=nil, med=nil, high=100}, normal=nil, dps={5, 8, 11}},
        [3] = {ev=20, stamina={low=nil, med=nil, high=120}, normal=nil, dps={5, 9, 12}},
        [4] = {ev=24, stamina={low=nil, med=nil, high=140}, normal=nil, dps={6, 10, 13}},
        [5] = {ev=28, stamina={low=nil, med=nil, high=160}, normal=nil, dps={6, 11, 14}},
        [6] = {ev=32, stamina={low=nil, med=nil, high=180}, normal=nil, dps={7, 12, 15}},
        [7] = {ev=36, stamina={low=nil, med=nil, high=200}, normal=nil, dps={7, 13, 16}},
        [8] = {ev=40, stamina={low=nil, med=nil, high=220}, normal=nil, dps={8, 13, 17}},
        [9] = {ev=44, stamina={low=nil, med=nil, high=240}, normal=nil, dps={9, 14, 18}},
        [10] = {ev=48, stamina={low=nil, med=nil, high=260}, normal=nil, dps={10, 15, 19}},
        [11] = {ev=52, stamina={low=nil, med=nil, high=280}, normal=nil, dps={10, 16, 20}},
    },
    elite = {
        [1] = {ev=12, stamina={low=40, med=60, high=80}, normal={4, 7, 10}, dps={5, 8, 11}},
        [2] = {ev=16, stamina={low=60, med=80, high=100}, normal={5, 8, 11}, dps={5, 9, 12}},
        [3] = {ev=20, stamina={low=80, med=100, high=120}, normal={5, 9, 12}, dps={6, 10, 13}},
        [4] = {ev=24, stamina={low=100, med=120, high=140}, normal={6, 10, 13}, dps={6, 11, 14}},
        [5] = {ev=28, stamina={low=120, med=140, high=160}, normal={6, 11, 14}, dps={7, 12, 15}},
        [6] = {ev=32, stamina={low=140, med=160, high=180}, normal={7, 12, 15}, dps={7, 13, 16}},
        [7] = {ev=36, stamina={low=160, med=180, high=200}, normal={7, 13, 16}, dps={8, 13, 17}},
        [8] = {ev=40, stamina={low=180, med=200, high=220}, normal={8, 13, 17}, dps={9, 14, 18}},
        [9] = {ev=44, stamina={low=200, med=220, high=240}, normal={9, 14, 18}, dps={10, 15, 19}},
        [10] = {ev=48, stamina={low=220, med=240, high=260}, normal={10, 15, 19}, dps={10, 16, 20}},
        [11] = {ev=52, stamina={low=220, med=240, high=280}, normal={10, 16, 20}, dps={11, 17, 21}},
    },
    solo = {
        [1] = {ev=36, stamina={low=nil, med=nil, high=200}, normal=nil, dps={5, 8, 11}},
        [2] = {ev=48, stamina={low=nil, med=nil, high=250}, normal=nil, dps={5, 9, 12}},
        [3] = {ev=60, stamina={low=nil, med=nil, high=300}, normal=nil, dps={6, 10, 13}},
        [4] = {ev=72, stamina={low=nil, med=nil, high=350}, normal=nil, dps={6, 11, 14}},
        [5] = {ev=84, stamina={low=nil, med=nil, high=400}, normal=nil, dps={7, 12, 15}},
        [6] = {ev=96, stamina={low=nil, med=nil, high=450}, normal=nil, dps={7, 13, 16}},
        [7] = {ev=108, stamina={low=nil, med=nil, high=500}, normal=nil, dps={8, 13, 17}},
        [8] = {ev=120, stamina={low=nil, med=nil, high=550}, normal=nil, dps={9, 14, 18}},
        [9] = {ev=132, stamina={low=nil, med=nil, high=600}, normal=nil, dps={10, 15, 19}},
        [10] = {ev=144, stamina={low=nil, med=nil, high=650}, normal=nil, dps={10, 16, 20}},
        [11] = {ev=156, stamina={low=nil, med=nil, high=700}, normal=nil, dps={11, 17, 21}},
    },
}

--Role -> stamina tier and damage type, from the sheet's MonsterIndex.
local g_roleStaminaTier = {
    controller = "low", hexer = "low", artillery = "low",
    harrier = "med", mount = "med", support = "med", ambusher = "med",
    defender = "high", brute = "high",
}
local g_roleDamageType = {
    controller = "normal", hexer = "normal", harrier = "normal",
    mount = "normal", support = "normal", defender = "normal",
    artillery = "dps", ambusher = "dps", brute = "dps",
}

local g_organizationSet = {
    minion = true, horde = true, platoon = true,
    elite = true, leader = true, solo = true,
}
local g_roleSet = {
    controller = true, hexer = true, artillery = true, harrier = true,
    mount = true, support = true, ambusher = true, defender = true, brute = true,
}

--Echelon for a level: 1 (L1-3), 2 (L4-6), 3 (L7-9), 4 (L10-11).
function MCDMMonsterScaling.Echelon(level)
    if level <= 3 then return 1
    elseif level <= 6 then return 2
    elseif level <= 9 then return 3
    else return 4 end
end

--Highest characteristic / power-roll bonus: caps at +5.
function MCDMMonsterScaling.HighestCharacteristic(level, isLeaderSolo)
    return math.min(5, MCDMMonsterScaling.Echelon(level) + (isLeaderSolo and 2 or 1))
end

--Strong-tier potency: caps at 6, and is NOT derived from the (capped)
--characteristic. They diverge for leader/solo at echelon 4 (char +5, potency 6).
function MCDMMonsterScaling.PotencyStrong(level, isLeaderSolo)
    return math.min(6, MCDMMonsterScaling.Echelon(level) + (isLeaderSolo and 2 or 1))
end

--Parse a monster "role" string (which encodes organization and role, e.g.
--"Elite Brute", "Minion Harrier", "Leader", or just "Harrier") into
--(organization, role), both lowercase. Word order is tolerated. With no
--organization keyword the standard organization is Platoon. minionFlag (the
--engine's creature.minion) forces minion. role may be nil (e.g. bare "Leader").
function MCDMMonsterScaling.ParseOrgRole(roleString, minionFlag)
    local org, role
    for word in string.gmatch(string.lower(roleString or ""), "%a+") do
        if g_organizationSet[word] then
            org = word
        elseif g_roleSet[word] then
            role = word
        end
    end
    if minionFlag then org = "minion" end
    if org == nil then org = "platoon" end
    return org, role
end

--Stamina tier to read for an (org, role). Leader/Solo always read High.
function MCDMMonsterScaling.StaminaTier(org, role)
    if org == "leader" or org == "solo" then return "high" end
    return g_roleStaminaTier[role] or "med"
end

--Damage type to read for an (org, role). Leader/Solo always read DPS.
function MCDMMonsterScaling.DamageType(org, role)
    if org == "leader" or org == "solo" then return "dps" end
    return g_roleDamageType[role] or "normal"
end

--Raw table row for an (org, level), or nil if out of range / unknown org.
function MCDMMonsterScaling.RowFor(org, level)
    local orgTbl = g_scaleTable[org]
    if orgTbl == nil then return nil end
    return orgTbl[level]
end

--Per-stat deltas to apply when scaling from baseLevel to targetLevel for an
--(org, role). Deltas are added on top of the creature's authored stats (the
--delta-from-base model), so bespoke / hand-tuned stat blocks keep their offset.
--Returns nil if the org is unknown or either level is out of the 1-11 range.
--Fields:
--  ev             EV delta (creature 'ev' attribute)
--  stamina        Stamina delta (creature 'hitpoints')
--  t1/t2/t3       Per-tier table-damage deltas (Tier N Damage Bonus)
--  freeStrike     Free-strike delta = T1 table delta (no characteristic)
--  characteristic Highest-characteristic / power-roll delta (capped at +5)
--  potency        Potency delta (own value, capped at 6; Potency Bonus)
--  strike         Strike Damage Bonus delta = characteristic delta
function MCDMMonsterScaling.ComputeDeltas(org, role, baseLevel, targetLevel)
    local b = MCDMMonsterScaling.RowFor(org, baseLevel)
    local t = MCDMMonsterScaling.RowFor(org, targetLevel)
    if b == nil or t == nil then return nil end

    local isLeaderSolo = (org == "leader" or org == "solo")
    local tier = MCDMMonsterScaling.StaminaTier(org, role)
    local dtype = MCDMMonsterScaling.DamageType(org, role)
    local bDmg, tDmg = b[dtype], t[dtype]

    local function tierDelta(i)
        if bDmg == nil or tDmg == nil then return 0 end
        return (tDmg[i] or 0) - (bDmg[i] or 0)
    end

    local charBase = MCDMMonsterScaling.HighestCharacteristic(baseLevel, isLeaderSolo)
    local charTarget = MCDMMonsterScaling.HighestCharacteristic(targetLevel, isLeaderSolo)
    local potBase = MCDMMonsterScaling.PotencyStrong(baseLevel, isLeaderSolo)
    local potTarget = MCDMMonsterScaling.PotencyStrong(targetLevel, isLeaderSolo)

    return {
        ev = t.ev - b.ev,
        stamina = (t.stamina[tier] or 0) - (b.stamina[tier] or 0),
        t1 = tierDelta(1),
        t2 = tierDelta(2),
        t3 = tierDelta(3),
        freeStrike = tierDelta(1),
        characteristic = charTarget - charBase,
        potency = potTarget - potBase,
        strike = charTarget - charBase,
    }
end

--==============================================================
-- Retainer level advancement (Draw Steel: Monsters, "Retainers").
--
-- Retainers share the monster level-adjustment machinery (scalingBaseLevel +
-- cr + the generated Level Adjustment feature) but advance on their own track
-- instead of the org/role scale table:
--   * Stamina: +9 at each level.
--   * Free strikes: +2 damage at levels 3, 6, and 9.
--   * Signature ability damage: +1 to the tier-1 outcome every second level,
--     and +1 to the tier-2 and tier-3 outcomes at every level.
-- Characteristic increases (levels 2/5/8) and advancement abilities (levels
-- 4/7/10) are granted through the retainer's creature template as level-gated
-- features and choices, not by this math.
--==============================================================

--Retainers cap at level 10 (the last row of the Retainer Advancement table);
--monsters go to 11.
MCDMMonsterScaling.retainerMaxLevel = 10

--Cumulative retainer advancement bonuses gained from level 1 up to `level`.
--Working from cumulative totals makes the base->target delta symmetric, so
--scaling back down removes exactly what scaling up granted.
local function RetainerCumulative(level)
    local freeStrike = 0
    for _,milestone in ipairs({3, 6, 9}) do
        if level >= milestone then
            freeStrike = freeStrike + 2
        end
    end
    return {
        stamina = 9 * (level - 1),
        freeStrike = freeStrike,
        sig1 = math.floor(level / 2),
        sig23 = level - 1,
    }
end

--Per-stat deltas for a retainer moving from baseLevel to targetLevel. A
--retainer whose stat block starts above level 1 already has the earlier
--bonuses baked into its authored stats, which the delta-from-base model
--handles naturally: only levels after the base grant anything.
--Returns nil when either level is outside the retainer's 1-10 range.
--Fields:
--  stamina    Stamina delta (creature 'hitpoints')
--  freeStrike Free-strike damage delta (Free Strike Bonus)
--  sig1       Signature ability tier-1 damage delta
--  sig23      Signature ability tier-2 and tier-3 damage delta
function MCDMMonsterScaling.ComputeRetainerDeltas(baseLevel, targetLevel)
    local minLevel = MCDMMonsterScaling.minLevel
    local maxLevel = MCDMMonsterScaling.retainerMaxLevel
    if baseLevel < minLevel or baseLevel > maxLevel
        or targetLevel < minLevel or targetLevel > maxLevel then
        return nil
    end

    local b = RetainerCumulative(baseLevel)
    local t = RetainerCumulative(targetLevel)
    return {
        stamina = t.stamina - b.stamina,
        freeStrike = t.freeStrike - b.freeStrike,
        sig1 = t.sig1 - b.sig1,
        sig23 = t.sig23 - b.sig23,
    }
end

--Convenience: parse this monster's organization and role from its data.
function monster:ScalingOrgRole()
    return MCDMMonsterScaling.ParseOrgRole(self:try_get("role", ""), self.minion)
end

--Potency for monsters. The base creature:Potency() returns the highest
--characteristic, which is correct for every monster EXCEPT echelon-4
--leaders/solos: the MCDM monster-math sheet caps the characteristic (power
--roll) at +5 but lets potency reach 6 at that echelon. Detect that one case by
--organization + echelon and lift potency by 1, but only when the characteristic
--is actually at the +5 cap, so a hand-tuned monster with a sub-cap characteristic
--still gets potency = its highest characteristic. Computed live from level/org,
--so any new L10/L11 leader or solo gets the right result with no per-monster data.
function monster:Potency()
    local summonerToken = self:GetPotencySummonerToken()
    if summonerToken ~= nil then
        return summonerToken.properties:Potency()
    end

    local highest = self:HighestCharacteristic()
    local org = self:ScalingOrgRole()
    if (org == "leader" or org == "solo")
        and MCDMMonsterScaling.Echelon(round(tonumber(self.cr) or 0)) == 4
        and highest >= 5 then
        return highest + 1
    end
    return highest
end

--A level-scaled monster's *literal* ability potency gates (e.g. "M < 3") are
--frozen text baked in at the authored level; unlike the Potencies line and
--weak/average/strong gates (which recompute from monster:Potency()), they never
--track the characteristic. So they must be nudged explicitly by the same potency
--delta the Adjust Level modal previews. Returns 0 when unscaled (zero shift), and
--mirrors the summoner redirect that Potency()/CalculatePotencyValue use. Both the
--display pass and the resolution save-check add this, so the shown gate and the
--actual save always agree. Computed live (no stored modifier) so it cannot stale.
function monster:ScaledPotencyGateBonus()
    local summonerToken = self:GetPotencySummonerToken()
    if summonerToken ~= nil then
        return summonerToken.properties:ScaledPotencyGateBonus()
    end
    if not self:HasLevelAdjustment() then
        return 0
    end
    --Retainer potency follows the characteristic increases granted by their
    --creature template, not the monster org/role scale table, so leveling a
    --retainer never shifts literal potency gates.
    if self:IsRetainer() then
        return 0
    end
    local org, role = self:ScalingOrgRole()
    local deltas = MCDMMonsterScaling.ComputeDeltas(org, role, self:GetScalingBaseLevel(), round(tonumber(self.cr) or 0))
    if deltas == nil then
        return 0
    end
    return deltas.potency or 0
end

--==============================================================
-- Monster level scaling: the generated "Level Adjustment" feature.
--
-- The only persistent state is the authored base level (scalingBaseLevel);
-- creature.cr holds the current (target) level. A feature carrying the
-- base->target stat deltas is regenerated on every modifier calculation via
-- RegisterFeatureCalculation, so rescaling just changes cr and restoring just
-- clears scalingBaseLevel -- no stored modifiers to go stale.
--==============================================================

local g_adjustFeatureName = "Level Adjustment"

--Stable guids for the generated feature and its modifiers. The feature is
--regenerated (never persisted) per calculation and is only ever alive inside a
--single creature's modifier list, so these need only be internally distinct.
local g_adjustFeatureGuid = "c3079d4d-f5a8-48a9-8c6e-b4357209b4a9"
local g_adjustModGuids = {
    ev         = "3228246a-90ed-4759-8629-9a967641f6fa",
    hitpoints  = "64069561-1cbb-47b6-bd01-de9a7a9ce467",
    freeStrike = "3852aca2-a776-4744-9f67-a92f48210c80",
    potency    = "831861c3-4d74-4fd1-af15-df1094b2c910",
    t1         = "5557dadd-a1a1-4338-94e4-f2ffb41470ef",
    t2         = "ad13299a-108b-47d3-ac21-c1eda5abda26",
    t3         = "c79b4266-f7c8-49f4-ac52-0a4def6b63b8",
    strike     = "ea86292d-b78d-47ce-9081-14533f341598",
    characteristic = "1f7c4d6e-2b9a-4f08-bb51-6e0a9d2c8b34",
    sig1       = "b3f8a2c1-6d47-4e95-8a30-1c7e94d5f261",
    sig23      = "5e21c7d9-8b04-4f6a-9d58-3a6f10b8e472",
}

--Resolve a custom attribute's GUID (the key an attribute modifier targets) by
--name, so this survives a compendium re-import that changes the GUIDs.
local function ScalingCustomAttrId(name)
    local sym = string.lower(name:gsub("%s+", ""))
    local attr = CustomAttribute.attributeInfoByLookupSymbol[sym]
    if attr == nil then
        return nil
    end
    return attr.id
end

--Build the "Level Adjustment" CharacterFeature from a spec list. Each spec is
--{ key, attribute, value, custom } -- key indexes the stable modifier guid,
--custom marks a named custom attribute (resolved to its guid). Every entry is
--a plain add-operation Modify Attribute modifier; zero deltas are skipped.
--Returns nil if there is nothing to add.
local function BuildAdjustmentFeatureFromSpecs(specs)
    local modifiers = {}
    for _,spec in ipairs(specs) do
        local value = spec.value or 0
        if value ~= 0 then
            local attribute = spec.attribute
            if spec.custom then
                attribute = ScalingCustomAttrId(spec.attribute)
            end
            if attribute ~= nil then
                modifiers[#modifiers+1] = CharacterModifier.new{
                    guid = g_adjustModGuids[spec.key],
                    sourceguid = g_adjustFeatureGuid,
                    name = g_adjustFeatureName,
                    source = g_adjustFeatureName,
                    description = "",
                    behavior = "attribute",
                    operation = "add",
                    attribute = attribute,
                    value = value,
                }
            end
        end
    end

    if #modifiers == 0 then
        return nil
    end

    return CharacterFeature.Create{
        guid = g_adjustFeatureGuid,
        name = g_adjustFeatureName,
        source = g_adjustFeatureName,
        modifiers = modifiers,
    }
end

--Build the generated "Level Adjustment" CharacterFeature from a deltas table
--(see MCDMMonsterScaling.ComputeDeltas). Every entry is a plain add-operation
--Modify Attribute modifier; zero deltas are skipped. Returns nil if there is
--nothing to add.
--
--charScale (optional) = { attr = <characteristic attribute id>, bump = <delta> }
--actually raises the creature's highest characteristic so the sheet reflects it
--and abilities that roll "2d10 + Highest Characteristic" scale. Potency needs no
--modifier of its own: the engine ties monster:Potency() to the highest
--characteristic (plus the echelon-4 leader/solo +1), so the characteristic bump
--and the level change move potency correctly on their own. Strike damage moves
--by the same `bump` (the characteristic part of a strike's per-tier damage); the
--static tier text is not re-derived from the characteristic, so no double count.
function MCDMMonsterScaling.BuildAdjustmentFeature(deltas, charScale)
    if deltas == nil then
        return nil
    end

    local charBump = (charScale ~= nil and charScale.bump) or 0

    -- No Potency Bonus modifier: the computed potency (the Potencies line and
    -- weak/average/strong gates) follows the characteristic via the engine
    -- (monster:Potency() = highest characteristic, +1 at echelon-4 leader/solo),
    -- and scaling already raises both the characteristic and the level, so it
    -- recomputes on its own; a Potency Bonus here would double-count it. The one
    -- thing that does NOT recompute is a *literal* potency gate baked into ability
    -- text (e.g. "M < 3") -- that is nudged separately by monster:ScaledPotencyGateBonus
    -- at the two gate sites in MCDMAbilityBehavior, not by a modifier here.
    local specs = {
        { key = "ev",         attribute = "ev",                  value = deltas.ev },
        { key = "hitpoints",  attribute = "hitpoints",           value = deltas.stamina },
        { key = "freeStrike", attribute = "Free Strike Bonus",   value = deltas.freeStrike, custom = true },
        { key = "t1",         attribute = "Tier 1 Damage Bonus", value = deltas.t1,         custom = true },
        { key = "t2",         attribute = "Tier 2 Damage Bonus", value = deltas.t2,         custom = true },
        { key = "t3",         attribute = "Tier 3 Damage Bonus", value = deltas.t3,         custom = true },
        { key = "strike",     attribute = "Strike Damage Bonus", value = charBump,          custom = true },
    }

    --Raise the actual highest characteristic (skipped when there is no echelon
    --change, or no attribute to target).
    if charScale ~= nil and charScale.attr ~= nil and charBump ~= 0 then
        specs[#specs+1] = { key = "characteristic", attribute = charScale.attr, value = charBump }
    end

    return BuildAdjustmentFeatureFromSpecs(specs)
end

--Build the generated "Level Adjustment" feature for a retainer from a
--ComputeRetainerDeltas table. The signature-ability bonuses land on the
--retainer "Tier 1 Damage" / "Tier 2 and 3 Damage" custom attributes, which
--RollPropertiesPowerTable:ApplyCreatureTierDamage reads at roll time and
--applies only to the creature's signature ability.
function MCDMMonsterScaling.BuildRetainerAdjustmentFeature(deltas)
    if deltas == nil then
        return nil
    end

    local specs = {
        { key = "hitpoints",  attribute = "hitpoints",           value = deltas.stamina },
        { key = "freeStrike", attribute = "Free Strike Bonus",   value = deltas.freeStrike, custom = true },
        { key = "sig1",       attribute = "Tier 1 Damage",       value = deltas.sig1,       custom = true },
        { key = "sig23",      attribute = "Tier 2 and 3 Damage", value = deltas.sig23,      custom = true },
    }

    return BuildAdjustmentFeatureFromSpecs(specs)
end

--Creatures with no authored base level (heroes) report nil, so callers can
--tell "started at this level" apart from "is this level right now".
function creature:GetScalingBaseLevel()
    return nil
end

--The authored (base) level: the stored value if scaled, else the current cr.
function monster:GetScalingBaseLevel()
    return round(tonumber(self:try_get("scalingBaseLevel", self.cr)) or 0)
end

--True if a level adjustment is currently in effect.
function monster:HasLevelAdjustment()
    local base = self:try_get("scalingBaseLevel")
    return base ~= nil and round(tonumber(base) or 0) ~= round(tonumber(self.cr) or 0)
end

--Scale this monster to targetLevel (clamped to 1-11). Stores the authored base
--level on first use; clears the adjustment if targetLevel returns to base.
--Mutates creature properties -- callers outside the character sheet must wrap
--this in token:ModifyProperties.
function monster:SetLevelAdjustment(targetLevel)
    targetLevel = round(tonumber(targetLevel) or 0)
    local maxLevel = MCDMMonsterScaling.maxLevel
    if self:IsRetainer() then
        maxLevel = MCDMMonsterScaling.retainerMaxLevel
    end
    targetLevel = math.max(MCDMMonsterScaling.minLevel, math.min(maxLevel, targetLevel))

    local base = self:GetScalingBaseLevel()
    if targetLevel == base then
        self:ClearLevelAdjustment()
        return
    end

    self.scalingBaseLevel = base
    self.cr = targetLevel
end

--Remove the level adjustment, restoring the monster to its authored level.
function monster:ClearLevelAdjustment()
    if self:has_key("scalingBaseLevel") then
        self.cr = self:GetScalingBaseLevel()
        self.scalingBaseLevel = nil
    end
end

--==============================================================
-- Solo conversion: the "Make Solo" button lifecycle.
--
-- A non-solo monster can be promoted to a Solo in one action: its organization
-- is set to Solo (the role word is dropped -- Solos have no role) and the
-- "Instant Solo" creature template is applied for the stat math (EV x3, Stamina
-- x2.5, extra turns/action, end effect). The conversion is fully reversible: the
-- prior role string and minion flag are remembered so Revert restores them
-- exactly, then the template is removed.
--
-- creature.role is the single source of truth for organization (Organization()
-- regex-parses its first word), so the org->Solo flip is a plain string write. A
-- template MODIFIER cannot write a string field, which is why this lives on a
-- code actor (the button) rather than in the template itself.
--
-- Mutates creature properties -- callers outside the character sheet must wrap
-- these in token:ModifyProperties.
--==============================================================
local INSTANT_SOLO_TEMPLATE_ID = "231c3a1e-1292-4751-bc23-238b26531e61"

--True if this monster was promoted to Solo by the Make Solo button (as opposed
--to being authored as a Solo). Only a button conversion is revertible.
function monster:HasSoloConversion()
    return self:try_get("soloConversionPriorRole") ~= nil
end

--Promote this monster to a Solo: remember the prior role/minion, set the
--organization to Solo (dropping the role word), and apply the Instant Solo
--template. No-op if already converted.
function monster:MakeSolo()
    if self:HasSoloConversion() then
        return
    end

    self.soloConversionPriorRole = self:try_get("role", "")
    self.soloConversionPriorMinion = self:try_get("minion", false)

    --Snapshot the villain actions the creature already has, so Revert removes
    --only the ones added during the solo conversion and leaves any the creature
    --owned beforehand (e.g. a Leader's native villain actions) intact.
    local priorVillainActions = {}
    for _, a in ipairs(self:try_get("innateActivatedAbilities", {})) do
        if a.categorization == "Villain Action" then
            priorVillainActions[#priorVillainActions + 1] = a.guid
        end
    end
    self.soloConversionPriorVillainActions = priorVillainActions

    self.role = "Solo"
    self.minion = false

    --Apply the Instant Solo template, guarding against a stray duplicate.
    local templates = self:try_get("creatureTemplates")
    local hasTemplate = false
    if templates ~= nil then
        for _, id in ipairs(templates) do
            if id == INSTANT_SOLO_TEMPLATE_ID then
                hasTemplate = true
                break
            end
        end
    end
    if not hasTemplate then
        self:AddTemplate(INSTANT_SOLO_TEMPLATE_ID)
    end
end

--Revert a Make Solo conversion: restore the prior role/minion and remove the
--Instant Solo template. No-op if not converted.
function monster:RevertSolo()
    if not self:HasSoloConversion() then
        return
    end

    self.role = self:try_get("soloConversionPriorRole", "")
    self.minion = self:try_get("soloConversionPriorMinion", false)

    --Remove the Instant Solo template we added (RemoveTemplate is index-based,
    --so locate it first; iterate in reverse so the index stays valid).
    local templates = self:try_get("creatureTemplates")
    if templates ~= nil then
        for i = #templates, 1, -1 do
            if templates[i] == INSTANT_SOLO_TEMPLATE_ID then
                self:RemoveTemplate(i)
                break
            end
        end
    end

    --Remove villain actions added during the solo conversion: any villain
    --action whose guid is not in the pre-conversion snapshot. This restores the
    --creature's original villain-action set (none for an Elite, the native ones
    --for a Leader) rather than leaving solo-only actions behind.
    local priorVillainActions = {}
    for _, guid in ipairs(self:try_get("soloConversionPriorVillainActions", {})) do
        priorVillainActions[guid] = true
    end
    local villainActionsToRemove = {}
    for _, a in ipairs(self:try_get("innateActivatedAbilities", {})) do
        if a.categorization == "Villain Action" and not priorVillainActions[a.guid] then
            villainActionsToRemove[#villainActionsToRemove + 1] = a
        end
    end
    for _, a in ipairs(villainActionsToRemove) do
        self:RemoveInnateActivatedAbility(a)
    end

    self.soloConversionPriorRole = nil
    self.soloConversionPriorMinion = nil
    self.soloConversionPriorVillainActions = nil
end

creature.RegisterFeatureCalculation{
    id = "monsterLevelScaling",
    FillFeatures = function(c, result)
        if not c:IsMonster() then
            return
        end
        local base = c:try_get("scalingBaseLevel")
        if base == nil then
            return
        end
        base = round(tonumber(base) or 0)
        local target = round(tonumber(c.cr) or base)
        if target == base then
            return
        end

        --Retainers advance on their own track (see the retainer advancement
        --section above). Characteristic increases and advancement abilities
        --come from the retainer's creature template, so only the flat stat
        --bonuses are generated here.
        if c:IsRetainer() then
            local feature = MCDMMonsterScaling.BuildRetainerAdjustmentFeature(
                MCDMMonsterScaling.ComputeRetainerDeltas(base, target))
            if feature ~= nil then
                result[#result+1] = feature
            end
            return
        end

        --For a monster promoted by the Make Solo button, read the deltas from the
        --organization it was authored as, NOT from Solo. The creature's authored
        --Stamina/EV are still on the pre-conversion curve; the Instant Solo
        --template is what lifts them onto the Solo curve, and it runs AFTER this
        --calculation (templates are filled after custom feature calculations in
        --creature:FillBaseActiveModifiers). Reading the Solo rows here applies a
        --post-multiply delta to a pre-multiply baseline, which drives Stamina and
        --EV negative on a level-down (report TFCBW9MC: a solo'd Force of Earth at
        --level 1 landed on 80 Stamina / -12 EV instead of 230 / 36).
        --
        --This is exact, not an approximation: within a tier the elite/leader rows
        --step by 20 Stamina per level and the solo rows by 50 = 2.5 x 20 (EV: 4
        --and 12 = 3 x 4), so the pre-conversion delta multiplied by the template
        --is identical to the solo delta added after it.
        local roleString = c:try_get("role", "")
        local minionFlag = c:try_get("minion", false)
        local isSoloConversion = false
        pcall(function() isSoloConversion = c:HasSoloConversion() end)
        if isSoloConversion then
            roleString = c:try_get("soloConversionPriorRole", roleString)
            minionFlag = c:try_get("soloConversionPriorMinion", minionFlag)
        end

        local org, role = MCDMMonsterScaling.ParseOrgRole(roleString, minionFlag)
        local deltas = MCDMMonsterScaling.ComputeDeltas(org, role, base, target)

        -- Resolve the characteristic bump. Read the highest characteristic from
        -- the raw stored attributes (GetBaseAttribute -- no modifier pipeline, so
        -- no recursion during this calculation), apply the formula characteristic
        -- delta (deltas.strike), and clamp the result to the +5 power-roll cap so
        -- a hand-tuned monster authored above the curve cannot exceed it.
        local charScale = nil
        if deltas ~= nil then
            local highestAttr, highestVal = nil, nil
            for _, attrid in ipairs(creature.attributeIds) do
                local v = 0
                pcall(function() v = c:GetBaseAttribute(attrid).baseValue or 0 end)
                if highestVal == nil or v > highestVal then
                    highestVal = v
                    highestAttr = attrid
                end
            end
            if highestAttr ~= nil then
                local newHighest = math.min(5, (highestVal or 0) + (deltas.strike or 0))
                charScale = { attr = highestAttr, bump = newHighest - (highestVal or 0) }
            end
        end

        local feature = MCDMMonsterScaling.BuildAdjustmentFeature(deltas, charScale)
        if feature ~= nil then
            result[#result+1] = feature
        end
    end,
}

--==============================================================
-- Custom retainer conversion: the "Make Custom Retainer" button.
--
-- Draw Steel: Monsters, "Retainers": most stat blocks can become retainers,
-- provided the creature is not a minion, a leader, or a solo. Converting:
--   * Stamina: the stat-block value is replaced by the retainer baseline
--     (max_hitpoints = 10, matching how the premade retainers are authored;
--     retainer advancement supplies the per-level bonuses on top).
--   * The signature ability now affects only ONE target within distance if
--     it affected an area or multiple targets.
--   * No creature-specific advancement abilities: the "<Role> Abilities"
--     creature template supplies the role advancement abilities instead.
--   * Can't use abilities that require Malice. Group malice features are
--     already suppressed by the `retainer` flag (see
--     FillMonsterActivatedAbilities); the creature's own malice-cost innate
--     abilities are suppressed at fill time in GetActivatedAbilities, so
--     nothing authored is deleted.
--
-- Mutates creature properties -- callers outside the character sheet must
-- wrap these in token:ModifyProperties.
--==============================================================

--The generic "Retainer" creature template (characteristic increases).
local RETAINER_TEMPLATE_ID = "25263715-cef4-4e25-b4bd-ddedc3a87dea"

--A custom retainer has 21 Stamina at level 1; RetainerCumulative adds the
--+9 per level on top.
local CUSTOM_RETAINER_BASE_STAMINA = 21

--Non-monsters (heroes etc.) can never convert.
function creature:CanBecomeCustomRetainer()
    return false, "Only monsters can become retainers."
end

--True if this monster can become a custom retainer, plus a reason string
--when it cannot. Minions, leaders, and solos are excluded by the book;
--followers and existing retainers have nothing to convert.
function monster:CanBecomeCustomRetainer()
    if self:IsFollower() then
        return false, "Already a follower or retainer."
    end
    if self.minion then
        return false, "Minions can't become retainers."
    end
    local org = self:ScalingOrgRole()
    if org == "leader" or org == "solo" then
        return false, "Leaders and solos can't become retainers."
    end
    return true
end

--Find the "<Role> Abilities" creature template for a role word (e.g.
--"Harrier Abilities" for a Platoon Harrier). Returns the template id, or
--nil when the role has no matching template.
local function RoleAbilitiesTemplateId(roleWord)
    if roleWord == nil or roleWord == "" then
        return nil
    end
    local want = string.lower(roleWord) .. " abilities"
    for id, template in unhidden_pairs(GetTableCached("creatureTemplates") or {}) do
        if string.lower(template:try_get("name", "")) == want then
            return id
        end
    end
    return nil
end

--Attach a creature template unless it is already on the creature.
local function AddTemplateOnce(self, templateid)
    if templateid == nil then
        return
    end
    for _, id in ipairs(self:try_get("creatureTemplates", {})) do
        if id == templateid then
            return
        end
    end
    self:AddTemplate(templateid)
end

--True when an ability affects an area or more than one creature.
local function AbilityHitsMultiple(ability)
    local isArea = ability:IsTargetTypeAOE() or ability.targetType == "map"
    local num = tonumber(ability:try_get("numTargets", "1"))
    --A formula target count (non-numeric) counts as multi-target.
    return isArea or (num == nil) or num > 1
end

--Short human description of what an ability currently targets, e.g.
--"3 Cube", "All Creatures in Encounter", "2 creatures".
local function DescribeTargeting(ability)
    local targetType = ability.targetType
    local typeInfo = ActivatedAbility.TargetTypesById[targetType]
    local typeText = targetType
    if typeInfo ~= nil and typeInfo.text ~= nil then
        typeText = typeInfo.text
    end

    if ability:IsTargetTypeAOE() then
        local radius = ability:try_get("radius")
        if radius ~= nil and tostring(radius) ~= "" then
            return string.format("%s %s", tostring(radius), typeText)
        end
        return tostring(typeText)
    end
    if targetType == "map" then
        return tostring(typeText)
    end

    local num = tostring(ability:try_get("numTargets", "1"))
    if num == "1" then
        return "1 creature"
    end
    return string.format("%s creatures", num)
end

--Bring the keywords back in line with an ability that has just been made
--single-target. "Area" is not just cosmetic: while it stays, the ability keeps
--the area icon and keeps ignoring the Hidden condition (see
--GameSystem.AllowTargeting), so a retainer could still hit a creature hidden
--from it. An ability that used to be an area also has no Melee/Ranged keyword
--to fall back on, so its range line would render as a bare number; give it the
--one its remaining distance implies. Abilities that merely hit several targets
--were already authored Melee or Ranged, so those are left alone.
--Returns a short summary of the keyword changes, or nil if none were needed.
local function FixSingleTargetKeywords(ability, wasArea)
    local changes = {}

    if ability:HasKeyword("Area") then
        ability:RemoveKeyword("Area")
        changes[#changes + 1] = "-Area"
    end

    if wasArea and not (ability:HasKeyword("Melee") or ability:HasKeyword("Ranged")) then
        --Only a reach of one square reads as Melee; a formula range (nil here)
        --falls through to Ranged, which is right for every area in the bestiary.
        local range = tonumber(ability:try_get("range"))
        local keyword = "Ranged"
        if range ~= nil and range <= dmhub.unitsPerSquare then
            keyword = "Melee"
        end
        ability:AddKeyword(keyword)
        changes[#changes + 1] = "+" .. keyword
    end

    if #changes == 0 then
        return nil
    end
    return table.concat(changes, " ")
end

--Rewrite an area or multi-target signature ability to affect a single
--target within distance: range is kept, the area shape and target count
--are replaced, and the keywords are corrected to match. Single-target
--signatures are left untouched. Returns a "before -> after" description
--when it changed anything, else nil.
local function MakeSignatureSingleTarget(ability)
    if not AbilityHitsMultiple(ability) then
        return nil
    end
    local before = DescribeTargeting(ability)
    local wasArea = ability:IsTargetTypeAOE() or ability.targetType == "map"
    ability.targetType = "target"
    ability.numTargets = "1"
    ability.radius = nil

    local result = string.format("%s -> 1 creature", before)
    local keywordChanges = FixSingleTargetKeywords(ability, wasArea)
    if keywordChanges ~= nil then
        result = string.format("%s (%s)", result, keywordChanges)
    end
    return result
end

--The malice abilities this creature's monster group hands it. Free strikes
--are filled first and the group's malice comes after, so everything past
--the free-strike count is group malice. Must be called before the retainer
--flag is set (the flag is what suppresses them).
local function CollectGroupMaliceAbilities(self)
    local result = {}
    pcall(function()
        local strikes = {}
        self:FillFreeStrikes({}, strikes)
        local all = {}
        self:FillMonsterActivatedAbilities({}, all)
        for i = #strikes + 1, #all do
            result[#result + 1] = all[i]
        end
    end)
    return result
end

--All of an ability's rules text, lowercased: its own description plus the
--power roll tiers and command rules on its behaviors.
local function AbilityRulesText(ability)
    local parts = {}
    local function push(value)
        if type(value) == "string" then
            parts[#parts + 1] = value
        end
    end

    push(ability:try_get("description"))
    push(ability:try_get("flavor"))
    for _, behavior in ipairs(ability:try_get("behaviors", {})) do
        push(behavior:try_get("rule"))
        local tiers = behavior:try_get("tiers")
        if type(tiers) == "table" then
            for _, tier in ipairs(tiers) do
                push(tier)
            end
        end
    end

    return string.lower(table.concat(parts, " "))
end

--Comma-joined ability names, for the review lines.
local function JoinAbilityNames(abilities)
    local names = {}
    for _, a in ipairs(abilities) do
        names[#names + 1] = tostring(a:try_get("name", "(unnamed)"))
    end
    return table.concat(names, ", ")
end

--Convert this monster into a custom retainer. No-op returning nil when
--ineligible. Otherwise returns a report of what the conversion did:
--  stats     -- {label, before, after, dir} rows, dir being -1/0/1
--  abilities -- {name, change, detail, ability} for every ability that was
--               retargeted ("retargeted") or now needs Malice it can't spend
--               ("malice"); ability is the live object, for previews
--  review    -- plain-language lines a Director should check by hand
function monster:ConvertToCustomRetainer()
    if not self:CanBecomeCustomRetainer() then
        return nil
    end

    local report = { stats = {}, abilities = {}, review = {} }

    --Snapshot everything the mutation below overwrites or hides.
    local beforeStamina = 0
    pcall(function() beforeStamina = round(tonumber(self:MaxHitpoints()) or 0) end)
    local beforeLevel = round(tonumber(self.cr) or 0)
    local beforeDamage = round(tonumber(self:try_get("damage_taken", 0)) or 0)
    local groupMalice = CollectGroupMaliceAbilities(self)

    --Walk the innate abilities once: villain actions the retainer shouldn't
    --keep, abilities that will stop working for want of Malice, abilities
    --that only mention Malice in their text (suppression won't catch those),
    --and non-signature abilities that still hit more than one creature.
    local villainActions = {}
    local maliceCost = {}
    local maliceTextOnly = {}
    local stillMultiTarget = {}
    for _, ability in ipairs(self:try_get("innateActivatedAbilities", {})) do
        local isMaliceCost = ability.resourceCost == CharacterResource.maliceResourceId
        if ability.categorization == "Villain Action" then
            villainActions[#villainActions + 1] = ability
        end
        if isMaliceCost then
            maliceCost[#maliceCost + 1] = ability
        elseif string.find(AbilityRulesText(ability), "malice", 1, true) ~= nil then
            maliceTextOnly[#maliceTextOnly + 1] = ability
        end
        if ability.categorization ~= "Signature Ability" and AbilityHitsMultiple(ability) then
            stillMultiTarget[#stillMultiTarget + 1] = ability
        end
    end

    --No matching "<Role> Abilities" template means no role advancement
    --abilities at all, so check before anything is written.
    local _, roleWord = self:ScalingOrgRole()
    local roleTemplateId = RoleAbilitiesTemplateId(roleWord)

    --Follower typing, matching the premade retainer convention (see the
    --Angulotl Hopper premade). The role is kept as-is: it drives the role
    --ability template and the retainer advancement track.
    self.__typeName = "follower"
    self.followerType = "retainer"
    self.retainer = true
    self.customRetainer = true
    self.availableRolls = 0

    --Retainers cap at level 10, so clamp before the stamina math. Any monster
    --level adjustment is dropped: the retainer's stat block is now authored at
    --its current level, which is also the starting level the level-gained
    --advancement prerequisites compare against.
    local maxLevel = MCDMMonsterScaling.retainerMaxLevel
    local levelClamped = false
    if round(tonumber(self.cr) or 0) > maxLevel then
        self.cr = maxLevel
        levelClamped = true
    end
    if self:has_key("scalingBaseLevel") then
        self.scalingBaseLevel = nil
    end

    --Retainer stamina: 21 at level 1, +9 per level after that. Taken from the
    --same advancement table the leveler uses, so leveling up from here adds
    --exactly the remaining difference. Wipe damage so the new maximum applies.
    local level = round(tonumber(self.cr) or 1)
    self.max_hitpoints = CUSTOM_RETAINER_BASE_STAMINA + RetainerCumulative(level).stamina
    self.damage_taken = 0

    --Attach the retainer advancement templates: the generic Retainer template
    --and this role's "<Role> Abilities" template (its level 4/7/10 choices are
    --level-gained gated, so a retainer starting above level 1 only gets the
    --levels it actually gains). Premade retainers author their own template
    --wiring and never come through here.
    AddTemplateOnce(self, RETAINER_TEMPLATE_ID)
    AddTemplateOnce(self, roleTemplateId)

    --A retainer's signature ability affects only one target within distance.
    for _, ability in ipairs(self:try_get("innateActivatedAbilities", {})) do
        if ability.categorization == "Signature Ability" then
            local detail = MakeSignatureSingleTarget(ability)
            if detail ~= nil then
                report.abilities[#report.abilities + 1] = {
                    name = tostring(ability:try_get("name", "(unnamed)")),
                    change = "retargeted",
                    detail = detail,
                    ability = ability,
                }
            end
        end
    end

    --Malice-cost abilities survive on the stat block but can never be used.
    for _, ability in ipairs(maliceCost) do
        report.abilities[#report.abilities + 1] = {
            name = tostring(ability:try_get("name", "(unnamed)")),
            change = "malice",
            detail = "Requires Malice - retainers can't spend it",
            ability = ability,
        }
    end

    --Stat rows. Stamina is the headline change; the others only appear when
    --the conversion actually moved them.
    local function addStat(label, before, after, dir)
        report.stats[#report.stats + 1] = { label = label, before = before, after = after, dir = dir }
    end

    local afterStamina = round(tonumber(self.max_hitpoints) or 0)
    local staminaDir = 0
    if beforeStamina > afterStamina then
        staminaDir = -1
    elseif beforeStamina < afterStamina then
        staminaDir = 1
    end
    addStat("Stamina", string.format("%d", beforeStamina), string.format("%d", afterStamina), staminaDir)

    if levelClamped then
        addStat("Level", string.format("%d", beforeLevel), string.format("%d", maxLevel), -1)
    end
    if beforeDamage > 0 then
        addStat("Damage taken", string.format("%d", beforeDamage), "0", -1)
    end

    --Things the conversion can't decide for the Director.
    local function addReview(text)
        report.review[#report.review + 1] = text
    end

    if roleTemplateId == nil then
        local shownRole = roleWord
        if shownRole == nil or shownRole == "" then
            shownRole = self:try_get("role", "(no role)")
        end
        addReview(string.format(
            "No \"%s Abilities\" template matched this creature's role, so it gains NO role advancement abilities. Pick a role with a template, or author one.",
            tostring(shownRole)))
    end

    if #villainActions > 0 then
        addReview(string.format(
            "Retainers don't take villain actions, but this stat block still has %d: %s.",
            #villainActions, JoinAbilityNames(villainActions)))
    end

    if #maliceTextOnly > 0 then
        addReview(string.format(
            "These abilities mention Malice in their text but carry no Malice cost, so nothing suppresses them: %s.",
            JoinAbilityNames(maliceTextOnly)))
    end

    if #groupMalice > 0 then
        addReview(string.format(
            "The monster group contributed %d malice feature(s), now suppressed: %s.",
            #groupMalice, JoinAbilityNames(groupMalice)))
    end

    if #stillMultiTarget > 0 then
        addReview(string.format(
            "Only the signature ability is single-targeted by the rules. These still affect several creatures: %s.",
            JoinAbilityNames(stillMultiTarget)))
    end

    if levelClamped then
        addReview(string.format(
            "Level was reduced from %d to %d, the retainer maximum.", beforeLevel, maxLevel))
    end

    return report
end
local mod = dmhub.GetModLoading()

--if the effect has been implemented by the importer.
ActivatedAbility.effectImplemented = true

local g_hoverableGradient = gui.Gradient{
    point_a = {x=0,y=0},
    point_b = {x=1,y=1},
    stops = {
        {
            position = 0,
            color = Styles.backgroundColor,
        },
        {
            position = 12,
            color = Styles.textColor,
        },
    },
}

local g_highlightGradient = gui.Gradient{
    point_a = {x=0,y=0},
    point_b = {x=1,y=1},
    stops = {
        {
            position = 0,
            color = Styles.backgroundColor,
        },
        {
            position = 4,
            color = Styles.textColor,
        },
    },
}

SpellRenderStyles = {
	gui.Style{
		selectors = "#spellInfo",
		width = "100%",
		height = 'auto',
		flow = 'vertical',
		halign = 'left',
		valign = 'center',
	},
	gui.Style{
		selectors = {"hoverable","#spellInfo"},
        bgcolor = "white",
        gradient = g_hoverableGradient,
    },
	gui.Style{
		selectors = {"hoverable","hovered","#spellInfo"},
        gradient = g_highlightGradient,
        transitionTime = 0.2,
    },

    gui.Style{
        selectors = {"heading", "hovered"},
        brightness = 3,
    },

	gui.Style{
		classes = {"label"},
		fontSize = 14,
		color = 'white',
		width = '100%',
		textAlignment = "left",
		height = 'auto',
		halign = 'left',

		textAlignment = 'left',
	},

	gui.Style{
		classes = {"label","#spellName"},
		color = 'white',
        bgimage = "panels/square.png",
        bgcolor = "clear",
		fontSize = 14,
        fontFace = "Newzald",
		width = '100%',
		height = 'auto',
		halign = 'left',
		valign = 'top',
		wrap = true,
		fontWeight = "black",
	},

	gui.Style{
		classes = {"subheading"},
		color = '#bb6666',
		fontSize = 24,
		bold = true,
	},

	gui.Style{
		classes = {"label","#spellSummary"},

		italics = true,
		color = 'white',
		fontSize = 12,
		width = 'auto',
		height = 'auto',
		halign = 'left',
		valign = 'top',
	},

	gui.Style{
		classes = {"divider"},

		bgimage = 'panels/square.png',
		bgcolor = '#666666',
		halign = "left",
		width = '100%',
		height = 1,
		halign = 'center',
		valign = 'top',
		vmargin = 4,
	},
	gui.Style{
		classes = {"description"},
		color = 'white',
		width = '96%',
	},
    gui.Style{
        classes = {"abilitySection"},
        bgimage = true,
        bgcolor = "clear",
    },
    gui.Style{
        classes = {"abilitySection", "highlight"},
        bgcolor = "red",
    },
    
    -- Implementation chip styles
    gui.Style{
        classes = {"implementationChip"},
        height = "auto",
        width = "auto",
        pad = 5,
        margin = 3,
        fontSize = 14,
        bgimage = "panels/square.png",
        borderColor = Styles.textColor,
        bold = true,
        border = 1,
        cornerRadius = 2,
        color = "black",
    },
    gui.Style{
        classes = {"implementationChip", "wontimplement"},
        bgcolor = Styles.ImplementationStatusColors[0],
    },
    gui.Style{
        classes = {"implementationChip", "unimplemented"},
        bgcolor = Styles.ImplementationStatusColors[1],
    },
    gui.Style{
        classes = {"implementationChip", "bronze"},
        bgcolor = Styles.ImplementationStatusColors[2],
    },
    gui.Style{
        classes = {"implementationChip", "silver"},
        bgcolor = Styles.ImplementationStatusColors[3],
    },
    gui.Style{
        classes = {"implementationChip", "gold"},
        bgcolor = Styles.ImplementationStatusColors[4],
    },
}

local g_damageTypeColors = {
    sonic = "#ff0088",
    fire = "#ff8888",
    lightning = "#ff8800",
}

ActivatedAbility.KeywordRemappings = {
    Attack = "Strike",
}

function ActivatedAbility.OnDeserialize(self)
	if not self:has_key("behaviors") then
		self.behaviors = {}
	end

    for k,v in pairs(ActivatedAbility.KeywordRemappings) do
        if self.keywords[k] then
            self.keywords[v] = true
            self.keywords[k] = nil
        end
    end
end

function ActivatedAbility:AddKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
    self.keywords = DeepCopy(self.keywords)
	self.keywords[keyword] = true
end

function ActivatedAbility:HasKeyword(keyword)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
	return self.keywords[keyword] == true
end

function ActivatedAbility:RemoveKeyword(keyword)
    self.keywords = DeepCopy(self.keywords)
    keyword = ActivatedAbility.KeywordRemappings[keyword] or keyword
	self.keywords[keyword] = nil
end



RegisterGoblinScriptSymbol(ActivatedAbility, {
	name = "Keywords",
	type = "set",
	desc = "The keywords this ability has.",
	examples = {"Ability.Keywords has 'Ranged'", "Ability.Keywords has 'Attack'"},
	calculate = function(c)
		local strings = {}
		for k,v in pairs(c.keywords) do
			strings[#strings+1] = string.lower(k)
		end

		return StringSet.new{
			strings = strings,
		}
	end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "doesdamage",
    type = "boolean",
    desc = "Whether this ability does rolled damage.",
    calculate = function(c)
        for _,behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _,entry in ipairs(tiers) do
                    local damageMatch = regex.MatchGroups(entry, " damage")
                    if damageMatch ~= nil then
                        return true
                    end
                end
            end
        end
    end,
})


RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "haspotency",
    type = "boolean",
    desc = "Whether this ability has potency.",
    calculate = function(c)
        for _,behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _,entry in ipairs(tiers) do
                    if string.find(entry, "<", 1, true) then
                        return true
                    end
                end
            end
        end

        return false
    end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
	name = "hasforcedmovement",
	type = "boolean",
	desc = "Whether this ability has forced movement.",
	calculate = function(c)
		for _, behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityForcedMovementBehavior" then
                return true
            else
                local tiers = behavior:try_get("tiers", {})
                for _, entry in ipairs(tiers) do
                    if regex.MatchGroups(entry, "(push|pull|slide)") ~= nil then
                        return true
                    end
                end
            end
        end

        return false
	end,
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "damagetypes",
    type = "set",
    desc = "The damage types this ability does.",
    calculate = function(c)
		local strings = {}

        for _,behavior in ipairs(c.behaviors) do
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                local tiers = behavior.tiers
                for _,entry in ipairs(tiers) do
                    local damageMatch = regex.MatchGroups(entry, "(?<damage>[0-9 maripd+-]+) +(?<type>[a-z]+)? ?damage")
                    if damageMatch ~= nil then
                        local damageType = damageMatch.type or "untyped"
                        if not table.contains(strings, damageType) then
                            strings[#strings+1] = string.lower(damageType)
                        end
                    end
                end
            end
        end

		return StringSet.new{
			strings = strings,
		}
    end,

    
})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "action",
    type = "boolean",
    desc = "Is this ability an action?",
    calculate = function(c)

        return c:ActionResource() == "d19658a2-4d7b-4504-af9e-1a5410fb17fd" --id of action 

    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "main action",
    type = "boolean",
    desc = "Returns true if this ability is a main action.",
    seealso = {"action"},
    calculate = function(c)

        return c:ActionResource() == "d19658a2-4d7b-4504-af9e-1a5410fb17fd" --id of action 

    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "maneuver",
    type = "boolean",
    desc = "Returns true if this ability is a maneuver.",
    seealso = {"action"},
    calculate = function(c)

        return c:ActionResource() == "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b" --id of maneuver 

    end,

})

RegisterGoblinScriptSymbol(ActivatedAbility, {
    name = "Allegiance",
    type = "string",
    desc = "Alligance of Targets for Ability. Possible values are 'ally', 'enemy', 'dead', and 'all'.",
    calculate = function(c)
        if not c.targetAllegiance then
            if c:try_get("targetFilter") ~= nil then
                if string.lower(c.targetFilter) == "not enemy" then
                    return "ally"
                elseif string.lower(c.targetFilter) == "enemy" then
                    return "enemy"
                end
            end
            return "all"
        else
            return c.targetAllegiance
        end
    end,
})

function ActivatedAbility:HasAttack()
	return self:HasKeyword("Strike")
end

function ActivatedAbility:IsAction()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[self:ActionResource()]
	return resourceInfo ~= nil and resourceInfo.name == "Action"
end

function ActivatedAbility:IsManeuver()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[self:ActionResource()]
	return resourceInfo ~= nil and resourceInfo.name == "Maneuver"
end

--- @return boolean Whether this ability's tooltip render changes depending on the mode.
function ActivatedAbility:RenderVariesWithDifferentModes()
    for _,behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityPowerRollBehavior" and #behavior:try_get("modesSelected", {}) > 0 then
            return true
        elseif self.resourceCost ~= nil and self.resourceCost ~= "" and #behavior:try_get("modesSelected", {}) > 0 then
            return true
        end
    end

    return false
end

function ActivatedAbility:AbilityTypeDescription()
    if self.categorization == "Signature Ability" or self.categorization == "Heroic Ability" then
        return self.categorization
    end

    local actionResource = self:ActionResource()
    local resourceTable = dmhub.GetTable(CharacterResource.tableName)
    local resourceInfo = resourceTable[actionResource or ""]
    if resourceInfo == nil then
        return "Ability"
    end

    return resourceInfo.name
end

function ActivatedAbility.TabBGImage()
    return mod.images.tabbg
end

function ActivatedAbility:Render(options, params)

	params = params or {}
	options = options or {}

    options.noninteractive = nil

    params.symbols = params.symbols or {}
    params.symbols.mode = params.symbols.mode or 1

    local paramMaxHeight = params.maxHeight
    params.maxHeight = nil

	local summary = options.summary
	options.summary = nil

    local selectable = options.selectable
    options.selectable = nil

    local creatureProperties = nil
    local token = nil
    if params.token ~= nil then
        creatureProperties = params.token.properties
        token = params.token
    end

    local attackBehavior = nil
    for _,behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityAttackBehavior" then
            attackBehavior = behavior
            break
        end
    end

	local powerTableBehavior = nil
    for _,behavior in ipairs(self.behaviors) do
        if behavior:IsFiltered(self, params.token, params) then
            --the modes didn't match, so just pass on this one.
        elseif behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            powerTableBehavior = behavior
            break
		elseif behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" and behavior.abilityType == "custom" then
			--if we invoke a power roll ability try to pull that out.
			for _,subbehavior in ipairs(behavior.customAbility.behaviors) do
        		if subbehavior.typeName == "ActivatedAbilityPowerRollBehavior" then
					powerTableBehavior = subbehavior
				end
			end

        end
	end

	local powerRollLabel = nil
	local powerRollTable = nil

    local rulesNotes = {}

	if powerTableBehavior ~= nil then
        local c = nil
        if params.token ~= nil then
            c = params.token.properties
        end

		local roll = powerTableBehavior:DescribeRoll(c, self)

        local triangleBlack = nil
        if not string.find(roll, "2d6") then
            triangleBlack = gui.Panel{
                floating = true,
                rotate = 90,
                width = 6,
                height = 6,
                valign = "center",
                halign = "center",
                bgimage = "panels/triangle.png",
                bgcolor = "black",
            }
        end

        powerRollLabel = gui.Label{
            text = string.format("<b>Roll <u>%s</u></b>:", roll),
			create = function(element)
				if powerTableBehavior:try_get("resistanceRoll", false) then
					element.text = string.format("<b>Target makes a %s resistance roll:</b>", creature.attributesInfo[powerTableBehavior:ResistanceAttr()].description)
				else
            		element.text = string.format("<b>Roll <u>%s</u></b>:", roll)
				end
			end,
			tmargin = 16,

            gui.Panel{
                floating = true,
                rotate = 90,
                width = 8,
                height = 8,
				halign = "left",
                valign = "center",
                x = -10,
                bgimage = "panels/triangle.png",
                bgcolor = "white",
                triangleBlack,
            }
        }

		local rows = {}

		for i,entry in ipairs(powerTableBehavior.tiers) do
			rows[#rows+1] = gui.TableRow{
                width = "100%",
                height = "auto",
				gui.Label{
					text = powerTableBehavior.tierNames[i],
					width = 80,
					valign = "top",
				},

				gui.Label{
					text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, entry, rulesNotes, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                    markdown = true,
					bold = true,
                    hpad = 4,
                    height = "auto",
					width = (tonumber(options.width) or 600)-100,
					valign = "top",
				}
			}
		end

		powerRollTable = gui.Table{
			width = "100%",
			height = "auto",
			flow = "vertical",
			children = rows,
		}
	end

    local damageLabel = nil

	--TODO: Remove this?
    if attackBehavior ~= nil then
        local c = nil
        if params.token ~= nil then
            c = params.token.properties
        end
        local roll = attackBehavior:DescribeRoll(c, self)
        if attackBehavior.damageType ~= "untyped" then
            roll = string.format("%s %s", roll, attackBehavior.damageType)
        end

        local damageColor = g_damageTypeColors[attackBehavior.damageType] or "#ffffff"

        local triangleBlack = nil
        if not string.find(roll, "2d6") then
            triangleBlack = gui.Panel{
                floating = true,
                rotate = 90,
                width = 6,
                height = 6,
                valign = "center",
                halign = "center",
                bgimage = "panels/triangle.png",
                bgcolor = "black",
            }
        end

        damageLabel = gui.Label{
            text = string.format("<b>Damage:</b> <i><color=%s><u>%s</u></color></i>", damageColor, roll),

            gui.Panel{
                floating = true,
                rotate = 90,
                width = 8,
                height = 8,
				halign = "left",
                valign = "center",
                x = -10,
                bgimage = "panels/triangle.png",
                bgcolor = "white",
                triangleBlack,
            }
        }

    end

	--if we have a specific token and there is an aura associated with this ability, add some information about the aura.
	local tokenDependentInfoPanel = nil
	if params.token ~= nil and params.token.properties ~= nil then
		local tokenDependentChildren = {}

		local cost = self:GetCost(params.token)
		if cost.outOfAmmo then
			tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
				color = "#ffaaaa",
				text = "Out of Ammo",
			}
		end

		if cost.moveCost ~= nil then
			local labelColor = cond(cost.cannotMove, "#ffaaaa", "#aaaaaa")
			local text = string.format("Consumes %s %s of movement", MeasurementSystem.NativeToDisplayString(cost.moveCost), MeasurementSystem.Abbrev())
			if params.token.properties:CurrentMovementSpeed() <= 0 then
				text = "Cannot Move"
			end

			tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
				color = labelColor,
				text = text,
			}
		end

		if self:try_get("auraid") ~= nil then
			local aura = params.token.properties:GetAura(self.auraid)
			if aura ~= nil then
				tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
					id = "auraInfo",
					create = function(element)
						local concentrationText = ""
						if params.token.properties:HasConcentration() and params.token.properties.concentration:try_get("auraid") == self.auraid then
							concentrationText = "\nConcentrating on this spell"
						end

						local roundsSince = aura.time:RoundsSince()
						local castTimeText = "this round"
						if roundsSince == 1 then
							castTimeText = "last round"
						elseif roundsSince > 1 then
							castTimeText = string.format("%d rounds ago", roundsSince)
						end
						if aura:try_get("duration") ~= "none" then
							local remainingRounds = aura.duration - roundsSince
							local expiresText = "this round"
							if remainingRounds == 1 then
								expiresText = "next round"
							elseif remainingRounds > 1 then
								expiresText = string.format("in %d rounds", remainingRounds)
							end

							element.text = string.format("Effect cast %s, expires %s%s", castTimeText, expiresText, concentrationText)

						else
							element.text = string.format("Effect cast %s, lasts indefinitely", castTimeText, concentrationText)
						end
					end,
				}
			end
		end

		for _,entry in ipairs(self:try_get("modificationLog", {})) do
			tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
				text = entry,
				color = "#aaaaff",
			}
		end

        local seenRules = {}
        for _,entry in ipairs(rulesNotes) do
            if seenRules[entry] == nil then
                seenRules[entry] = true
                tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
                    text = entry,
				    color = "#aaaaff",
                }
            end
        end

		self:RenderTokenDependent(params.token, tokenDependentChildren)

		if #tokenDependentChildren > 0 then
			tokenDependentInfoPanel = gui.Panel{
                embedRollDialog = function(element, dialog)
                    print("HIDE:: DO HIDE")
                    element:SetClass("collapsed", true)
                end,
				width = "100%",
				height = "auto",
				flow = "vertical",
				tmargin = 6,
				hmargin = 8,
				children = tokenDependentChildren,
			}
		end
	end

	local description = self.description
	if description ~= "" and self.effectImplemented == false and self:try_get("implementation") ~= 3 and ActivatedAbilityDrawSteelCommandBehavior.ValidateRule(description) ~= true then
		description = string.format("<alpha=#55>%s<alpha=#ff>", description)
	end

	if self:try_get("modifyDescriptions") ~= nil then
		for _,desc in ipairs(self.modifyDescriptions) do
			description = string.format("%s\n<color=#aaaaff>%s</color>", description, desc)
		end
	end

    local costText = ""

    local headingColor = "#843030"



	if params.token ~= nil and params.token.properties ~= nil then
        local knownRefreshTypes = {rest = true, encounter = true, day = true}
        --look for a cost with a description, this means an ability that has a specific limit per refresh type.
        local costInfo = self:GetCost(params.token)
		for i,entry in ipairs(costInfo.details) do
            if entry.description ~= nil and knownRefreshTypes[entry.refreshType] then
				--costText is disabled for now. We show recharge instead.
                --costText = string.format(" [%s/%s]", tostring(entry.maxCharges), entry.refreshType)
                headingColor = "#5e4a43"
            end
        end
    end

    local resourceTable = dmhub.GetTable(CharacterResource.tableName)

	if self:has_key("resourceCost") then
		local resourceInfo = resourceTable[self.resourceCost]
		if resourceInfo ~= nil then
			local name = resourceInfo.name
            if self.resourceCost == CharacterResource.heroicResourceId and creatureProperties ~= nil then
                name = creatureProperties:GetHeroicResourceName()
            end
            
			local symbols = table.shallow_copy(params.symbols)
            local resourceNumberValue = rawget(self, "resourceNumber") or "1"
            local resourceNumber = 0
            if tonumber(resourceNumberValue) ~= nil then
                resourceNumber = tonumber(resourceNumberValue)
            elseif creatureProperties ~= nil then
                resourceNumber = ExecuteGoblinScript(resourceNumberValue, creatureProperties:LookupSymbol(symbols), 0, "Determine resource number for " .. self.name)
			end
            if resourceNumber == 0 then
				costText = ""
			else
				costText = string.format(" %d %s", resourceNumber, name)
			end
		end
	end



    local actionText = ""
    local resourceInfo = resourceTable[self:ActionResource()]
	if self:has_key("villainAction") then
		actionText = self.villainAction
	elseif resourceInfo == nil then
        actionText = "Free"
    else
        actionText = resourceInfo.name
    end

    if actionText == "Maneuver" then
        headingColor = "#303084"
    end


    local keywords = {}

    for keyword,_ in pairs(self.keywords) do
        keywords[#keywords+1] = keyword
    end

    table.sort(keywords, function(a,b) return a < b end)

    local keywordText = "-"
    if #keywords > 0 then
        keywordText = table.concat(keywords, ", ")
    end


    local descriptionLabel = nil
    
    if trim(description) ~= "" then
        descriptionLabel = gui.Label{
            markdown = true,
            text = string.format("<b>Effect: </b> %s", description),
        }
    end

    local labels = {
		gui.Label{
			text = string.format("<i>%s</i>", self:try_get("flavor", "")),
			width = "100%-80",
		},
		gui.Label{
			text = string.format("<b>Keywords:</b> <i>%s</i>", keywordText),
		},

		gui.Label{
			text = string.format("<b>Distance:</b> <i>%s</i>", self:DescribeRange(creatureProperties)),
		},

		gui.Label{
			text = string.format("<b>Target:</b> <i>%s</i>", self:DescribeTarget(token)),
		},

        damageLabel,

		powerRollLabel,
		powerRollTable,

        descriptionLabel,
    }

	local rechargeText = ""
	if tonumber(self.recharge) ~= nil then
		rechargeText = string.format("%d/Encounter: ", round(self.recharge))
	elseif self.recharge then
		rechargeText = "Recharge: "
	end

    local meleeOrRangedVariantText = ""
    if self:try_get("isMeleeVariation") then
        meleeOrRangedVariantText = " (Melee)"
    elseif self:try_get("isRangedVariation") then
        meleeOrRangedVariantText = " (Ranged)"
    end

    --Keywords calculation

    local keywords = {}

    for keyword,_ in pairs(self.keywords) do
        keywords[#keywords+1] = keyword
    end

    table.sort(keywords, function(a,b) return a < b end)

    local keywordText = "-"
    if #keywords > 0 then
        keywordText = table.concat(keywords, ", ")
    end

    --Action name calculation

    local actionText = ""
    local resourceInfo = resourceTable[self:ActionResource()]
	if self:has_key("villainAction") then
		actionText = self.villainAction
	elseif resourceInfo == nil then
        actionText = "Free"
    else
        actionText = resourceInfo.name
    end

    local preDescription = self:try_get("preDescription", "")
    local description = self.description

    local powerTableBehavior = nil
    for _,behavior in ipairs(self.behaviors) do
        if behavior:IsFiltered(self, params.token, params) then
            --the modes didn't match, so just pass on this one.
        elseif behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
            powerTableBehavior = behavior
            break
		elseif behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" and behavior.abilityType == "custom" then
			--if we invoke a power roll ability try to pull that out.
			for _,subbehavior in ipairs(behavior.customAbility.behaviors) do
        		if subbehavior.typeName == "ActivatedAbilityPowerRollBehavior" then
					powerTableBehavior = subbehavior
				end
			end

        end
	end

    local powerRollQueenPanel

    if powerTableBehavior ~= nil then
        
        powerRollQueenPanel =  gui.Panel{

                    bgimage = true,
                    bgcolor = "blue",
                    width = "100%",
                    height = "auto",
                    tmargin = 5,
                    flow = "vertical",
                    bgcolor = "clear",

                    --tier 1 roll
                    gui.Panel{

                        bgimage = true,
                        bgcolor = "clear",
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",


                        gui.Label{

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",
                            maxHeight = 22,
                            text = "1",
                            fontFace = "DrawSteelGlyphs",
                            fontSize = 34,
                            halign = "left",
                            valign = "center",

                        },

                        gui.Label{

                            width = "80%",
                            height = "auto",
                            text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[1], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                            fontSize = 16,
                            halign = "left",
                            valign = "center",
                            lmargin = 6,
                            textAlignment = "left",
                            markdown = true,

                        },



                    },

                    --tier 2 roll
                    gui.Panel{

                        bgimage = true,
                        bgcolor = "clear",
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",


                        gui.Label{

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",
                            maxHeight = 22,
                            text = "2",
                            fontFace = "DrawSteelGlyphs",
                            fontSize = 34,
                            halign = "left",
                            valign = "center",

                        },

                        gui.Label{

                            width = "80%",
                            height = "auto",
                            text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[2], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                            fontSize = 16,
                            halign = "left",
                            valign = "center",
                            lmargin = 6,
                            textAlignment = "left",
                            markdown = true,

                        },
                    },

                    --tier 3 roll
                    gui.Panel{

                        bgimage = true,
                        bgcolor = "clear",
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",


                        gui.Label{

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",
                            maxHeight = 22,
                            text = "3",
                            fontFace = "DrawSteelGlyphs",
                            fontSize = 34,
                            halign = "left",
                            valign = "center",

                        },

                        gui.Label{

                            width = "80%",
                            height = "auto",
                            text = ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature(creatureProperties, powerTableBehavior.tiers[3], {}, self:try_get("implementation", 1) >= gui.ImplementationStatus.Bronze),
                            fontSize = 16,
                            halign = "left",
                            valign = "center",
                            lmargin = 6,
                            textAlignment = "left",
                            markdown = true,

                        },



                    },


        }

    end


    local costString
    if costText == "" then
        costString = ""
    else
        costString = "(" .. string.trim(costText) .. ")"
    end

    preDescription = string.trim(preDescription)
    description = string.trim(description)

    local preDescriptionString
    if preDescription == "" then
        preDescriptionString = ""
    else
        preDescriptionString = "<b>Effect: </b>" .. preDescription .. "\n"
    end 

    local descriptionString
    if description == "" then
        descriptionString = ""
    else
        descriptionString = "<b>Effect: </b>" .. description
    end

    if self:has_key("modifyDescriptions") then
        for _,desc in ipairs(self.modifyDescriptions) do
            descriptionString = string.format("%s\n<color=#aaaaff>%s</color>", descriptionString, desc)
        end
    end

    local suppressMessage = self:try_get("suppressExplanation")
    if suppressMessage == nil and creatureProperties ~= nil then
        suppressMessage = self:AbilityFilterFailureMessage(creatureProperties)
    end

    local suppressPanel = nil
    if suppressMessage ~= nil then
        suppressPanel = gui.Label{
            bgimage = true,
            bgcolor = "#C73131", --forbidden color.
            width = "100%",
            height = "auto",
            color = "white",
            fontSize = 14,
            hpad = 16,
            vpad = 4,
            text = suppressMessage,
        }
    end

    --king panel
	local args = {
		id = 'spellInfo',
		styles = SpellRenderStyles,
        hpad = 0,
        vpad = 0,


        --King panel for inside info
		gui.Panel{

			id = "headerPanel",
			flow = "vertical",
			valign = "top",
			width = "90%",
			height = "auto",
            bgimage = true,
            bgcolor = "clear",
            tmargin = 15,
            lmargin = 20,

            maxHeight = paramMaxHeight,
            vscroll = cond(paramMaxHeight ~= nil, true, false),

            --titel and ability and icon type king panel
            gui.Panel{
				
				width = "100%",
				height = "auto",
                valign = "top",
                bgcolor = "clear",
                bgimage = true,

                flow = "vertical",


                --name and icon and type
                gui.Panel{

                    width = "100%",
				    height = "auto",
                    valign = "top",
                    bmargin = 10,
                    bgcolor = "clear",
                    bgimage = true,

                    flow = "horizontal",


                    --name and type
                    gui.Panel{

                        width = "auto",
				        height = "auto",
                        valign = "top",
                        bgcolor = "clear",
                        bgimage = true,

                        flow = "vertical",

                        --name of the ability
				        gui.Label{

					        width = "auto",
					        id = "spellName",
                            fontSize = 24,
                            fontFace = "Newzald",
                            fontWeight = "Light",
                            color = "white",
					        text = string.format("<b>%s</b>%s <size=18>%s</size>", self.name, meleeOrRangedVariantText, costString),
                            height = "auto",
                            markdown = true,



                        },

                        --Type of ability
                        gui.Label{

                            text = string.format("<b>%s</b>", self:AbilityTypeDescription()),
                            color = "red",
                            textAlignment = "left",
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            markdown = true,
                        
                        },

                        --Implementation chip
                        gui.Label{
                            classes = {"implementationChip"},
                            text = gui.ImplementationStatusValues[self:try_get("implementation", 1)] or "Unimplemented",
                            create = function(element)
                                local impl = self:try_get("implementation", 1)
                                -- Set the appropriate class based on implementation status
                                if impl == 0 then
                                    element:SetClass("wontimplement", true)
                                elseif impl == 1 then
                                    element:SetClass("unimplemented", true)
                                elseif impl == 2 then
                                    element:SetClass("bronze", true)
                                elseif impl == 3 then
                                    element:SetClass("silver", true)
                                elseif impl == 4 then
                                    element:SetClass("gold", true)
                                else
                                    element:SetClass("unimplemented", true)
                                end
                            end,
                            hover = function(element)
                                if self:try_get("implementationDetails") ~= nil and self:try_get("implementationDetails") ~= "" then
                                    element.tooltip = gui.TooltipFrame(gui.Label{
                                        text = self:try_get("implementationDetails"),
                                        width = 300,
                                        height = "auto",
                                        wrap = true,
                                        fontSize = 14,
                                    }, {})
                                end
                            end,
                        },
                    
                    },

                    gui.Panel{
                        
                        width = 50,
                        height = 50,
                        halign = "right",
                        bgcolor = "white",
                        bgimage = mod.images.attack,

                        create = function(element)
                            if self.categorization == "Signature Ability" then
                                element.bgimage = mod.images.signature
                            elseif self.categorization == "Basic Attack" then
                                element.bgimage = mod.images.attack
                            else
                                element.bgimage = mod.images.ability
                            end

                        end


                    },




                },






            },



            gui.Label{

                text = string.format("<i>%s</i>", self:try_get("flavor", "")), 
                textAlignment = "left",
                color = "#CBCCCA",
                width = "100%",
                height = "auto",
                bgimage = true,
                bgcolor = "clear",
                markdown = true,

            },

            --divider line between top and bottom info
            gui.Panel{

                tmargin = 8,
                bgimage = true,
                bgcolor = "#CBCCCA",
                opacity = 1,
                width = "100%",
                height = 1.5,
                halign = "left",
            },

            --king panel for keywords and action type
            gui.Panel{

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = 25,
                tmargin = 6,
                flow = "horizontal",

                --keywords
                gui.Label{

                    text = string.format("%s", keywordText),
                    fontSize = 20,
                    minFontSize = 8,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    height = "auto",
                    maxWidth = 200,
                    textWrap = false,
                    halign = "left",
                    markdown = true,


                },

                --acttion type
                gui.Label{

                    text = string.format("%s", actionText),
                    fontSize = 20,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    halign = "right",
                    markdown = true,


                },



            },

            --king panel for ranged and target
            gui.Panel{
                classes = {"abilitySection"},

                width = "100%",
                height = "auto",
                tmargin = 2,
                flow = "vertical",

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClass("highlight", false)
                        return
                    end

                    if options.section == "target" then
                        element:SetClass("highlight", true)
                    else
                        element:SetClass("highlight", false)
                    end
                end,

                --tab panel
                gui.Panel{
                    styles = {
                        {
                            selectors = {"tab"},
                            collapsed = 1,
                        },
                        {
                            selectors = {"tab", "parent:highlight"},
                            collapsed = 0,
                        }
                    },

                    classes = {"tab"},
                    x = -46,
                    floating = true,
                    valign = "top",
                    halign = "left",
                    height = 136*0.8,
                    width = 33*0.8,
                    bgimage = mod.images.tabbg,
                    bgcolor = 'white',

                    gui.Label{
                        color = "black",
                        width = "auto",
                        height = "auto",
                        fontSize = 22,
                        bold = true,
                        text = "Target",
                        y = -18,
                        rotate = 90,
                        halign = "center",
                        valign = "center",
                    },
                },


                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    gui.Label{

                        text = "e",
                        fontFace = "DrawSteelGlyphs",
                        fontSize = 20,
                        width = "auto",
                        halign = "right",
                        valign = "center",
                        lmargin = 5,
                    },

                    
                    gui.Label{

                        text = self:DescribeRange(creatureProperties),
                        fontSize = 18,
                        fontFace = "Newzald",
                        fontWeight = "Light",
                        width = "auto",
                        halign = "left",
                        valign = "center",
                        markdown = true,

                    },
                },

                
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    gui.Label{

                        text = "x",
                        fontFace = "DrawSteelGlyphs",
                        fontSize = 20,
                        width = "auto",
                        halign = "right",
                        valign = "center",
                        lmargin = 5,

                    },

                    gui.Label{

                        text = string.format("<b></b> <i>%s</i>", self:DescribeTarget(token)),
                        fontSize = 18,
                        fontFace = "Newzald",
                        fontWeight = "Light",
                        width = "auto",
                        halign = "right",
                        valign = "center",
                        markdown = true,
                        height = "auto",
                    },
                },
            },

            gui.Label{
                classes = {cond(preDescriptionString == "", "collapsed", nil)},
                text = string.format("%s", preDescriptionString),
                fontSize = 18,
                fontFace = "Newzald",
                fontWeight = "Light",
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 10,
                markdown = true,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                vmargin = 2,
                embedRollDialog = function(element, dialog)
                    element.children = {dialog}
                end,
            },

            --main Power Roll name + rolls king panel
            gui.Panel{
                embedRollDialog = function(element, dialog)
                    element:SetClass("collapsed", true)
                end,

                classes = {"abilitySection", cond(self:GetPowerRollDisplay() == "", "collapsed", nil)},
                width = "100%",
                height = "auto",
                tmargin = 2,
                flow = "vertical",
                bmargin = 2,

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClass("highlight", false)
                        return
                    end

                    if options.section == "main" then
                        element:SetClass("highlight", true)
                    else
                        element:SetClass("highlight", false)
                    end
                end,

                gui.Label{

                    text = self:GetPowerRollDisplay(),
                    fontSize = 18,
                    fontFace = "Newzald",
                    fontWeight = "Light",
                    width = "auto",
                    halign = "left",
                    markdown = true,

                    create = function(element)
                        --Tests shouldn't display power roll information in the tooltip?
                        for _, behavior in ipairs(self.behaviors or {}) do
                            if behavior:try_get("resistanceRoll", false) or behavior:try_get("isTest", false) then
                                element:SetClass("collapsed", true)
                            end
                        end
                    end,

                },

                powerRollQueenPanel,
            },

            gui.Panel{
                classes = {"abilitySection"},
                width = "100%",
                height = "auto",

                showAbilitySection = function(element, options)
                    if options.ability.name ~= self.name then
                        element:SetClass("highlight", false)
                        return
                    end

                    if options.section == "effects" then
                        element:SetClass("highlight", true)
                    else
                        element:SetClass("highlight", false)
                    end
                end,

                gui.DocumentDisplay{
                    text = descriptionString,
                    noninteractive = true,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    bmargin = 4,
                },
            },

			tokenDependentInfoPanel,


            gui.Panel{
                
                collapsed = 1,
				flow = "horizontal",
				valign = "top",
				width = "100%",
				height = "auto",
                bgcolor = "blue",
                bgimage = true,
            
                gui.Panel{
                    flow = "vertical",
                    width = "100%-16",
                    height = "auto",
                    lmargin = 16,

                    children = labels,
                },

                

                
            
            },
		},

        --[[gui.Label{
            smallcaps = true,
            bold = true,
            fontSize = 12,
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "right",
            text = actionText,
        },]]

        --border line right panel
        gui.Panel{

			floating = true,
			valign = "top",
			halign = "left",
			height = 1.2,
			width = 500,
			bgimage = true,
			bgcolor = 'white',
			gradient = gui.Gradient{
				point_a = {x = 0, y = 0},
				point_b = {x = 1, y = 0},
				stops = {
					{
						position = 0,
						color = "white",
					},

					{
						position = 1,
						color = "clear",
					}
				}
			}

		},

        --border line down panel
        gui.Panel{

			floating = true,
			valign = "top",
			halign = "left",
			height = 200,
			width = 1.2,
			bgimage = true,
			bgcolor = 'white',
			gradient = gui.Gradient{
				point_a = {x = 0, y = 1},
				point_b = {x = 0, y = 0},
				stops = {
					{
						position = 0,
						color = "white",
					},

					{
						position = 1,
						color = "clear",
					}
				}
			}

		},

        --tab panel
        gui.Panel{

			floating = true,
			valign = "top",
			halign = "left",
            lmargin = -26,
            tmargin = -1,
			height = 106*0.8,
			width = 33*0.8,
			bgimage = mod.images.tabbg,
			bgcolor = 'white',
            showAbilitySection = function(element, options)
                element:SetClass("collapsed", true)
            end,
		},

        suppressPanel,
	}




    if selectable then
        args.bgimage = "panels/square.png"
        args.hover = function(element)
            element:SetClassTree("hovered", true)
        end
        args.dehover = function(element)
            element:SetClassTree("hovered", false)
        end
    end

	for k,op in pairs(options) do
		args[k] = op
	end

	local result = gui.Panel(args)
    if selectable then
        result:SetClassTree("hoverable", true)
        for _,child in ipairs(result.children) do
            --child:MakeNonInteractiveRecursive()
        end
    else
	    --result:MakeNonInteractiveRecursive()
    end
	return result
end

function ActivatedAbility:DescribeRange(castingCreature)
    if self:try_get("rangeTextOverride", "") ~= "" then
        if castingCreature == nil then
            return self.rangeTextOverride
        end
        return StringInterpolateGoblinScript(self.rangeTextOverride, castingCreature)
    end

	if self.targetType == 'self' then
		return 'Self'
	end

    local range = self:GetRange(castingCreature)
    local radius = self:GetRadius(castingCreature)

    if self.targetType == "cube" then
        return string.format("%s cube within %s", MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.NativeToDisplayStringWithUnits(range))
    elseif self.targetType == "line" then
        local distance = self:GetLineDistance(castingCreature)
        return string.format("%s x %s line within %d square%s", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.NativeToDisplayString(distance), cond(distance ~= 1, "s", ""))
	elseif self.targetType == "all" then
		return string.format("%s burst", MeasurementSystem.NativeToDisplayString(range))
    end

    local result = MeasurementSystem.NativeToDisplayString(range)

    if self:HasKeyword("Melee") and self:HasKeyword("Ranged") then
        local melee = self:try_get("meleeRange", 1)
        result = string.format("Melee %d or ranged %s", tonumber(melee) or 1, result)
    elseif self:HasKeyword("Ranged") then
        result = string.format("Ranged %s", result)
    elseif self:HasKeyword("Melee") then
        result = string.format("Melee %s", result)
    end

    return result
end

function ActivatedAbility:DescribeTarget(casterToken)
    if self:try_get("targetTextOverride", "") ~= "" then
        if casterToken == nil then
            return self.targetTextOverride
        end
        return StringInterpolateGoblinScript(self.targetTextOverride, casterToken.properties)
    end

	local result
    if self:IsTargetTypeAOE() then
		if self.targetAllegiance == "enemy" or string.lower(self:try_get("targetFilter", "")) == "enemy" then
			result =  "Each enemy"
		elseif self.targetAllegiance == "ally" or string.lower(self:try_get("targetFilter", "")) == "not enemy" then
			if self:try_get("selfTarget") then
				result = "Self and each ally"
			else
				result = "Each ally"
			end
		elseif self.objectTarget then
            result = "Each creature or object"
        else
        	result = "Each creature"
		end
    elseif self.targetType == "target" then
        local count = self:GetNumTargets(casterToken, {})
        if count == nil and type(self.numTargets) ~= "table" then
            local m = regex.MatchGroups(self.numTargets, "^\\s*(?<targets>[0-9]+)")
            if m ~= nil then
                count = tonumber(m.targets)
            end
        end
        count = count or 1
        if count <= 1 then
            result = "1 creature"
        else
            result = string.format("%d creatures", round(count))
        end

        if self.objectTarget then
            if self.targetAllegiance == "none" then
                result = string.format("%s", cond(count <= 1, "object", "objects"))
            else
                result = string.format("%s or %s", result, cond(count <= 1, "object", "objects"))
            end
        end
    elseif self.targetType == "self" then
        result = "None/self"
    elseif self.targetType == "emptyspace" then
        local count = tonumber(self.numTargets) or 1
        if count <= 1 then
            return "1 unoccupied space"
        else
            return string.format("%d unoccupied spaces", count)
        end
	else
    	result = "1 square"
    end

	if self:has_key("targetAdditionalCriteria") then
		result = string.format("%s <color=#aaaaaa>%s</color>", result, self.targetAdditionalCriteria)
	end

	return result
end

function ActivatedAbility:IsForcedMovement()
	if self:try_get("invoker") == nil then
		--forced movement is always invoked by another creature.
		return false
	end

	if #self.behaviors == 0 or self.behaviors[1].typeName ~= "ActivatedAbilityRelocateCreatureBehavior" then
		return false
	end

	return true
end

function ActivatedAbility:CanTargetAdditionalTimes(casterToken, symbols, targets, targetToken)
    if self.repeatTargets then
        return true
    end

    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        --signature abilities can 'stack' targeting up to three times.
        local currentTimes = 0
        for _,target in ipairs(targets) do
            if target == targetToken.id then
                currentTimes = currentTimes + 1
            end
        end

        return currentTimes < 3
    end

    return false
end

local function GetTargetsWithTokens(targets)
    local result = {}
    for _,target in ipairs(targets) do
        if target.token ~= nil then
            result[#result+1] = target
        end
    end

    return result
end

---@param squad Token[] The squad of minions who will do the targeting.
---@param squadTargetsPerToken table<string, boolean>[] for each token, the locs that token can target (encoded as strings)
---@param targets table<{token: Token}> the targets.
---@param targetLocsOccupying table<string, boolean>[] the locs that the targets occupy. parallel with "targets".
---@param output Token[][] The permutations of possibly unused tokens who are still available to target.
---@param outputTargetingCombinations table<{a: Token, b: Token}>[][]|nil An array of combinations of possible targeting of minions to targets.
---@param currentCombinationInternal table<{a: Token, b: Token}>[]|nil The current combination of minions to targets. Optional and for internal use only.
local function GetSquadTargetPermutations(squad, squadTargetsPerToken, targets, targetLocsOccupying, output, outputTargetingCombinations, currentCombinationInternal)
    if currentCombinationInternal == nil then
        currentCombinationInternal = {}
    end

    if #targetLocsOccupying == 0 then
        table.sort(squad, function(a,b) return a.charid < b.charid end)
        for _,candidate in ipairs(output) do
            local match = true
            for i=1,#candidate do
                if candidate[i].charid ~= squad[i].charid then
                    match = false
                    break
                end
            end

            if match then
                return
            end
        end
        output[#output+1] = squad

        if outputTargetingCombinations ~= nil then
            outputTargetingCombinations[#outputTargetingCombinations+1] = table.shallow_copy(currentCombinationInternal)
        end
        return
    end

    local targetLocs = targetLocsOccupying[1]

    for i,token in ipairs(squad) do
        local canTarget = false
        for key,_ in pairs(targetLocs) do
            if squadTargetsPerToken[i][key] then
                canTarget = true
                break
            end
        end

        if canTarget then
            --check that we have line of effect to the target.
            if not RuleUtils.HasLineOfEffect(token, targets[1].token) then
                canTarget = false
            end
        end

        if canTarget then
            local newSquad = {}
            local newSquadTargets = {}
            for j,tok in ipairs(squad) do
                if i ~= j then
                    newSquad[#newSquad+1] = tok
                    newSquadTargets[#newSquadTargets+1] = squadTargetsPerToken[j]
                end
            end

            local newTargets = {}
            local newTargetLocsOccupying = {}
            for i=2,#targetLocsOccupying do
                newTargetLocsOccupying[#newTargetLocsOccupying+1] = targetLocsOccupying[i]
                newTargets[#newTargets+1] = targets[i]
            end

            currentCombinationInternal[#currentCombinationInternal+1] = {a = token, b = targets[1].token}

            GetSquadTargetPermutations(newSquad, newSquadTargets, newTargets, newTargetLocsOccupying, output, outputTargetingCombinations, currentCombinationInternal)

            currentCombinationInternal[#currentCombinationInternal] = nil
        end
    end
end

---@param casterToken CharacterToken The token that is casting the ability.
---@param range number The range of the ability.
---@param symbols table<string, any> The symbols for the ability.
---@param targets table<{target: CharacterToken}>[] The targets of the ability.
---@return table<{a: CharacterToken, b: CharacterToken}>[]|nil The possible targeting combinations of minions to targets.
function ActivatedAbility:GetTargetingRays(casterToken, range, symbols, targets)
    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        local locations = {}
        local squad = casterToken.properties._tmp_minionSquad
        local squadTokens = table.shallow_copy(squad.tokens)

        --put the caster token at the front so they'll get priority.
        for i,tok in ipairs(squadTokens) do
            if tok.id == casterToken.id then
                table.remove(squadTokens, i)
                table.insert(squadTokens, 1, tok)
                break
            end
        end

        targets = GetTargetsWithTokens(targets)

        local targetLocsOccupying = {}
        for _,target in ipairs(targets) do
            local locs = {}
            for _,loc in ipairs(target.token.locsOccupying) do
                locs[loc.xyfloorOnly.str] = true
            end

            targetLocsOccupying[#targetLocsOccupying+1] = locs
        end

        local possibleTargetsForEachToken = {}
        for _,tok in ipairs(squadTokens) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape{
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = {}
                for _,loc in ipairs(shape.locations) do
                    locs[loc.xyfloorOnly.str] = true
                end

                possibleTargetsForEachToken[#possibleTargetsForEachToken+1] = locs
            else
                possibleTargetsForEachToken[#possibleTargetsForEachToken+1] = {}
            end
        end

        local possibleSquads = {}
        local targetCombinations = {}
        GetSquadTargetPermutations(squadTokens, possibleTargetsForEachToken, targets, targetLocsOccupying, possibleSquads, targetCombinations)

        local targeting = {}
        if #targetCombinations > 0 then
            for j,target in ipairs(targetCombinations[1]) do
                targeting[#targeting+1] = {a = target.a.id, b = target.b.id}
            end
        end

        if #targetCombinations > 0 then
            return targetCombinations[1]
        end
    end

    return nil
end

function ActivatedAbility:PrepareTargets(casterToken, symbols, targets)
    if casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then
        --minion squad signature abilities will combine multiple instances
        --if the same target into one target with a multiple 'addedStacks' count.
        local result = {}

        for _,target in ipairs(targets) do
            local found = false
            for _,existing in ipairs(result) do
                if target.token ~= nil and existing.token ~= nil and target.token.id == existing.token.id then
                    existing.addedStacks = (existing.addedStacks or 0) + 1
                    found = true
                    break
                end
            end

            if not found then
                result[#result+1] = target
            end
        end

        return result
    end

    return targets
end


local g_customTargetShapeFunction = ActivatedAbility.CustomTargetShape

function ActivatedAbility:CustomTargetShape(casterToken, range, symbols, targets)
    if (not mod.unloaded) and casterToken.properties.minion and self.categorization == "Signature Ability" and casterToken.properties:has_key("_tmp_minionSquad") then

        local locations = {}
        local squad = casterToken.properties._tmp_minionSquad
        local squadTokens = table.shallow_copy(squad.tokens)

        targets = GetTargetsWithTokens(targets)

        local targetLocsOccupying = {}
        for _,target in ipairs(targets) do
            local locs = {}
            for _,loc in ipairs(target.token.locsOccupying) do
                locs[loc.xyfloorOnly.str] = true
            end

            targetLocsOccupying[#targetLocsOccupying+1] = locs
        end

        local possibleTargetsForEachToken = {}
        for _,tok in ipairs(squadTokens) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape{
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = {}
                for _,loc in ipairs(shape.locations) do
                    locs[loc.xyfloorOnly.str] = true
                end

                possibleTargetsForEachToken[#possibleTargetsForEachToken+1] = locs
            else
                possibleTargetsForEachToken[#possibleTargetsForEachToken+1] = {}
            end
        end

        local possibleSquads = {}
        GetSquadTargetPermutations(squadTokens, possibleTargetsForEachToken, targets, targetLocsOccupying, possibleSquads)

        local usableSquadMembers = {}
        for _,memberList in ipairs(possibleSquads) do
            for _,member in ipairs(memberList) do
                local alreadyCounted = false
                for _,existing in ipairs(usableSquadMembers) do
                    if existing.charid == member.charid then
                        alreadyCounted = true
                        break
                    end
                end

                if not alreadyCounted then
                    usableSquadMembers[#usableSquadMembers+1] = member
                end
            end
        end

        for _,tok in ipairs(usableSquadMembers) do
            if tok ~= nil and tok.valid then
                local shape = dmhub.CalculateShape{
                    shape = "radiusfromcreature",
                    token = tok,
                    radius = range,
                }

                local locs = shape.locations
                for _,loc in ipairs(locs) do
                    locations[#locations+1] = loc
                end
            end
        end

        return locations
    end

    return g_customTargetShapeFunction(self, casterToken, range, symbols)
end

local g_numTargetsFunction = ActivatedAbility.GetNumTargets

function ActivatedAbility:GetNumTargets(casterToken, symbols)
    local result = g_numTargetsFunction(self, casterToken, symbols)

    if (not mod.unloaded) and casterToken ~= nil and casterToken.properties.minion and self.categorization == "Signature Ability" and result == 1 and casterToken.properties:has_key("_tmp_minionSquad") then
        --minion signature abilities can target one target for each member of the squad.
        return casterToken.properties._tmp_minionSquad.liveMinions
    end

    return result
end

local g_moreTargetsFunction = ActivatedAbility.CanSelectMoreTargets

function ActivatedAbility:CanSelectMoreTargets(casterToken, targets, symbols)
    if not mod.unloaded then
        if casterToken.properties.minion and self.categorization == "Signature Ability" then

            
        end
        
    end

    return g_moreTargetsFunction(self, casterToken, targets, symbols)
end

function ActivatedAbility:PromptText(casterToken, targets, symbols, synthesizedSpells)
	if self:try_get("promptOverride") ~= nil then
		return self.promptOverride
	end

	if synthesizedSpells ~= nil then
		if #synthesizedSpells == 0 then
			return "No valid abilities"
		else
			if self.meleeAndRanged then
				return "Choose Melee or Ranged"
			end
			return "Choose an ability"
		end
	end

	if self:try_get("attackOverride") ~= nil and self.attackOverride:try_get("ammoType") ~= nil then
		return ""
	end

	if self.targetType == 'all' then
		return ""
	end

	local numTargets = self:GetNumTargets(casterToken, symbols)
	if numTargets == 0 then
		return ""
	end

	if numTargets == 1 and #targets == 0 then
		return nil
	end

	if numTargets >= 99 then
		return "Choose Targets"
	end

	if self.sequentialTargeting and symbols.targetnumber ~= nil and symbols.targetcount ~= nil then
		return string.format("Choose Target %d/%d", symbols.targetnumber, symbols.targetcount)
	end

	return string.format("Choose Target %d/%d", #targets+1, numTargets)
	
end

function ActivatedAbility:AffectedByCover(caster)
	if self.keywords["Ranged"] then
		return true
	end

	local behaviors = self:try_get("behaviors", {})
	for _,behavior in ipairs(behaviors) do
		if behavior:AffectedByCover(caster, self) then
			return true
		end
	end

	return false
end

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,
    name = "Maneuver",
    type = "boolean",
    desc = "True if this ability is a maneuver.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c:IsManeuver()
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,
    name = "Trigger",
    type = "boolean",
    desc = "True if this ability is a trigger.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c:has_key("trigger")
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,
    name = "HeroicResourceCost",
    type = "number",
    desc = "The number of heroic resources this ability costs.",
    seealso = {},
    examples = {},
    calculate = function(c)
        if c.resourceCost ~= CharacterResource.heroicResourceId then
            return 0
        end

        return round(tonumber(c.resourceNumber) or 0)
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,
    name = "MaliceCost",
    type = "number",
    desc = "The number of malice resources this ability costs.",
    seealso = {},
    examples = {},
    calculate = function(c)
        if c.resourceCost ~= CharacterResource.maliceResourceId then
            return 0
        end

        return tonumber(c.resourceNumber) or 0
    end,
}

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,
    name = "Heroic",
    type = "boolean",
    desc = "Is this ability a heroic ability?",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c.categorization == "Heroic Ability" and c.resourceCost == CharacterResource.heroicResourceId
    end,
}

GameSystem.RegisterGoblinScriptField{
	target = ActivatedAbility,
	name = "Categorization",
	type = "text",
	desc = "The categorization of this ability.",
	seealso = {},
	examples = {},
	calculate = function(c)
		return c.categorization
	end,
}

GameSystem.RegisterGoblinScriptField{
	target = ActivatedAbility,
	name = "Keywords",
	type = "set",
	desc = "The keywords this ability has.",
	seealso = {},
	examples = {},
	calculate = function(c)
		local strings = {}

		for keyword,_ in pairs(c.keywords) do
			strings[#strings+1] = keyword
		end

		return StringSet.new{
			strings = strings,
		}
	end,
}

ActivatedAbility.meleeAndRanged = false

function ActivatedAbility:GetTypeIconForActionBar()
    if self:try_get("isMeleeVariation") then
        return "ui-icons/skills/melee-attack-icon.png"
    elseif self:try_get("isRangedVariation") then
        return "ui-icons/skills/ranged-attack-icon.png"
    end
    return nil
end

ActivatedAbility.disableSplitIntoMeleeAndRanged = false

--if this ability is both melee and ranged we create a temporary clone
--which has each variation and return it.
function ActivatedAbility:BifurcateIntoMeleeAndRanged(creature)
	if (not self:HasKeyword("Melee")) or (not self:HasKeyword("Ranged")) or self.disableSplitIntoMeleeAndRanged then
		return self
	end

	if self.meleeAndRanged then
		--already done.
		return self
	end

	local result = self:MakeTemporaryClone()

	local melee = DeepCopy(result)
	local ranged = DeepCopy(result)
	melee.keywords["Ranged"] = nil
	ranged.keywords["Melee"] = nil
    ranged.keywords["Charge"] = nil
	melee.range = self:try_get("meleeRange", 1)

    melee.isMeleeVariation = true
    ranged.isRangedVariation = true

	result.meleeAndRanged = true

	result.meleeVariation = melee
	result.rangedVariation = ranged

	return result
end

--we synthesize melee/ranged abilities into different abilities for each.
function ActivatedAbility:SynthesizeAbilities(creature)

	if #self.behaviors > 0 then
		local result = self.behaviors[1]:SynthesizeAbilities(self, creature)
		if result ~= nil then
			return result
		end
	end

	return nil
end

creature.preferRanged = false

function ActivatedAbility:GetVariations(token)
	if self.meleeAndRanged then
		return {self.meleeVariation, self.rangedVariation}
	end

	return nil
end

function ActivatedAbility:GetActiveVariation(token)
	if self.meleeAndRanged then
		if token.properties.preferRanged then
			return self.rangedVariation
		else
			return self.meleeVariation
		end
	end

	return self
end

function ActivatedAbility:SetActiveVariation(token, variation)
	if self.meleeAndRanged then
		token:ModifyProperties{
			description = "Change stance",
			execute = function()
				if variation == self.meleeVariation then
					token.properties.preferRanged = false
				elseif variation == self.rangedVariation then
					token.properties.preferRanged = true
				end
			end,
		}
	end
end

function ActivatedAbility:DisplayOrder()
    return self:try_get("villainAction", "") .. self.name
end

ActivatedAbility.rangeBonusFromReach = 0

function ActivatedAbility:GetRange(casterCreature, castingSymbols, selfRange)
	if selfRange == nil or selfRange == "" then
		selfRange = self.range
	end

	local result = nil
	if type(selfRange) == "string" and string.lower(selfRange) == "touch" then
		result = dmhub.unitsPerSquare
	elseif type(selfRange) == "number" then
		result = selfRange
	elseif type(selfRange) == "string" then
		local n = tonumber(selfRange)
		if n ~= nil then
			result = n
		end
	end

	if result == nil then
		local caster = casterCreature or self:try_get("_tmp_boundCaster")
		if caster == nil then
			if type(selfRange) == "string" then
				local _,_,range = string.find(selfRange, "^(%d+)")
				if range ~= nil then
					result = tonumber(range)
				end
			end

			--this means we really couldn't work out the range.
			if result == nil then
				result = dmhub.unitsPerSquare
			end
		else

			castingSymbols = castingSymbols or {}
			local symbols = {
				ability = self,
				mode = castingSymbols.mode or 1,
				charges = castingSymbols.charges or 0,
				upcast = castingSymbols.upcast or 0,
                invoker = castingSymbols.invoker,
			}
			result = ExecuteGoblinScript(selfRange, caster:LookupSymbol(symbols))
		end
	end

	if result == nil then
		result = dmhub.unitsPerSquare
	end

    --we get a ranged bonus, but not if we're invoking from a different ability because this
    --e.g. applies the bonus to forced movement.
    if casterCreature ~= nil and self:HasKeyword("Ranged") and self:try_get("invoker") == nil then
        local bonusRange = casterCreature:BonusRange()
        if bonusRange ~= nil then
            result = result + bonusRange
        end
    else
        result = result + self.rangeBonusFromReach
    end

	return result
end


function ActivatedAbility:GetLineDistance(castingCreature, castingSymbols)
    local distance = self.lineDistance
    if tonumber(distance) ~= nil then
        return tonumber(distance)
    end

	castingSymbols = castingSymbols or {}
	local symbols = {
		ability = self,
		mode = castingSymbols.mode or 1,
		charges = castingSymbols.charges or 0,
		upcast = castingSymbols.upcast or 0,
        invoker = castingSymbols.invoker,
	}

    if castingCreature == nil then
		local _,_,range = string.find(selfRange, "^(%d+)")
        return tonumber(range) or 1
    end

    return ExecuteGoblinScript(self.lineDistance, castingCreature:LookupSymbol(symbols))
end

ActivatedAbility.registeredProperties = {}

local g_registeredPropertyToIndex = {}

--activated abilities can have boolean 'properties' that can be registered and
--control how they behave.
--- @param args {id: string, name: string, description: string}
function ActivatedAbility.RegisterProperty(args)
    local index = g_registeredPropertyToIndex[args.id] or #ActivatedAbility.registeredProperties + 1
    g_registeredPropertyToIndex[args.id] = index
    ActivatedAbility.registeredProperties[index] = args
    args.text = args.name

    GameSystem.RegisterGoblinScriptField{
        target = ActivatedAbility,
        name = args.name,
        type = "boolean",
        desc = args.description,
        examples = {"Ability has '" .. args.name .. "'"},
        calculate = function(c)
            local properties = c:try_get("properties")
            if properties == nil then
                return false
            end
        
            return properties[args.id] ~= nil
        end,
    }
end

function ActivatedAbility:HasProperty(id)
    return self:try_get("properties", {})[id] ~= nil
end

ActivatedAbility.RegisterProperty{
    id = "useasstrike",
    name = "Use as Free Strike",
    description = "If true, this ability can be used where a Free Strike can be used.",
}

ActivatedAbility.RegisterProperty{
    id = "useassignature",
    name = "Use as Signature Ability",
    description = "If true, this ability can be used where a Signature Ability can be used.",
}

ActivatedAbility.RegisterProperty{
    id = "remainhidden",
    name = "Remain Hidden",
    description = "If true, this ability will not cause hidden to be lost.",
}
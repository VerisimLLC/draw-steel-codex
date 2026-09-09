local mod = dmhub.GetModLoading()

local g_textTypeDomains = {
    {
        id = "movement",
        text = "Movement",
    },
    {
        id = "initiative",
        text = "Initiative",
    },
    {
        id = "negotiation",
        text = "Negotiation",
    },
    {
        id = "montage",
        text = "Montage",
    },
    {
        id = "respite",
        text = "Respite",
    },
    {
        id = "complications",
        text = "Complications",
    },
}

--controls text showing up when a player is moving.
CharacterModifier.RegisterType('movementtext', "Reminder Text")

CharacterModifier.TypeInfo.movementtext = {
    init = function(modifier)
        modifier.text = ""
        modifier.color = "white"
    end,

    ReminderText = function(modifier, creature, domain, text)
        if (rawget(modifier, "texttype") or "movement") ~= domain then
            return text
        end

        local s = StringInterpolateGoblinScript(modifier.text, creature)
        if text ~= "" then
            text = text .. "\n\n"
        end
        return string.format("%s<color=%s>%s</color>", text, modifier.color, s)
    end,

    MovementAdvisoryText = function(modifier, creature, path, text)
        if (rawget(modifier, "texttype") or "movement") ~= "movement" then
            return text
        end

        if modifier:try_get("movementType", "all") == "shift" and (not path.shifting) then
            return text
        end

        local s = StringInterpolateGoblinScript(modifier.text, creature:LookupSymbol{
            path = PathMoved.new{path = path},
        })

        if text ~= "" then
            text = text .. "\n\n"
        end
        return string.format("%s<color=%s>%s</color>", text, modifier.color, s)
    end,

    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local domain = modifier:try_get("texttype", "movement")

            local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                children = {
                    gui.Label{
                        text = 'Domain:',
                        classes = {'formLabel'},
                    },
                    gui.Dropdown{
                        options = g_textTypeDomains,
                        idChosen = domain,
                        change = function(self)
                            modifier.texttype = self.idChosen
                            Refresh()
                        end,
                    },
                },
            }

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                children = {
                    gui.Label{
                        text = 'Color:',
                        classes = {'formLabel'},
                    },
                    gui.Dropdown{
                        options = {
                            { id = "white", text = "White"},
                            { id = "red", text = "Red"},
                            { id = "green", text = "Green"},
                        },
                        idChosen = modifier.color,
                        change = function(self)
                            modifier.color = self.idChosen
                            Refresh()
                        end,
                    },
                },
            }

            if domain == "movement" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Movement Type:",
                    },
                    gui.Dropdown{
                        classes = {"formDropdown"},
                        options = {
                            {
                                id = "all",
                                text = "All",
                            },
                            {
                                id = "shift",
                                text = "Shift",
                            },
                        },
                        idChosen = modifier:try_get("movementType", "all"),
                        change = function(element)
                            modifier.movementType = element.idChosen
                            Refresh()
                        end,
                    }
                }
            end

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                children = {
                    gui.Label{
                        text = 'Text:',
                        classes = {'formLabel'},
                    },
                    gui.Input{
                        height = "auto",
                        minHeight = 30,
                        maxHeight = 80,
                        width = 400,
                        multiline = true,
                        characterLimit = 2000,
                        text = modifier.text or "",
                        change = function(self)
                            modifier.text = self.text
                            Refresh()
                        end,
                    },
                },
            }

            element.children = children
        end

        Refresh()
    end,
}

CharacterModifier.RegisterType('movementrestriction', "Movement Restriction")

--The two shapes a movement restriction can take. "approach" stops a creature closing
--on something (frightened); "leash" stops it straying too far from something (hooked).
local g_restrictionTypes = {
    {
        id = "approach",
        text = "Cannot Approach Target",
    },
    {
        id = "leash",
        text = "Cannot Stray From Target",
    },
}

--Resolves the modifier's Target formula to a token id. Drawing one movement overlay
--tests hundreds of tiles, so the answer is cached on the creature for the frame -- it
--cannot be cached on the modifier, which is shared by every creature carrying the effect.
local function ResolveRestrictionTarget(modifier, creature)
    local formula = modifier:try_get("targetFormula", "")
    if formula == "" then return nil end

    local currentFrame = dmhub.FrameCount()
    local cache = creature:try_get("_tmp_movementRestrictionTargets")
    if cache == nil or cache.frame ~= currentFrame then
        cache = { frame = currentFrame, targets = {} }
        creature._tmp_movementRestrictionTargets = cache
    end

    local cacheKey = modifier:try_get("guid", formula)
    local cached = cache.targets[cacheKey]
    if cached ~= nil then
        return cached.charid
    end

    local targetCharid = nil
    local result = dmhub.EvalGoblinScriptToObject(formula, creature:LookupSymbol(), "Movement restriction target")
    if type(result) == "string" and result ~= "" then
        targetCharid = result
    elseif type(result) == "number" then
        targetCharid = tostring(math.floor(result))
    elseif result ~= nil and type(result) == "table" then
        local tid = dmhub.LookupTokenId(result)
        if tid ~= nil and tid ~= "" then
            targetCharid = tid
        end
    end

    cache.targets[cacheKey] = { charid = targetCharid }

    return targetCharid
end

--The fixed point a leash is measured from. Draw Steel leashes read "can't move more
--than N squares away from the caster's position when this ability is used", so they
--anchor on where the caster stood when the effect landed -- creature:ApplyOngoingEffect
--records that in casterInfo.loc. Anything without a recorded position (a condition, an
--aura, an effect applied before this was recorded) falls back to where the anchor
--creature is standing right now.
local function GetLeashAnchorLoc(modContext, targetToken, targetCharid)
    local ongoingEffect = modContext ~= nil and modContext.ongoingEffect or nil
    if ongoingEffect ~= nil then
        local casterInfo = ongoingEffect:try_get("casterInfo")
        if casterInfo ~= nil and casterInfo.tokenid == targetCharid and type(casterInfo.loc) == "table" then
            local recorded = casterInfo.loc
            if type(recorded.x) == "number" and type(recorded.y) == "number" then
                return core.Loc{x = recorded.x, y = recorded.y, floorIndex = recorded.floor}
            end
        end
    end

    return targetToken.loc
end

CharacterModifier.TypeInfo.movementrestriction = {
    init = function(modifier)
        modifier.targetFormula = ""
        modifier.restrictionType = "approach"
        modifier.distance = 3
    end,

    -- Returns false if stepping onto loc would break the restriction: for "approach",
    -- getting closer to the target than the creature's starting position; for "leash",
    -- ending up more than 'distance' squares from the anchor point.
    MoveToLocPermitted = function(modifier, modContext, creature, startLoc, loc)
        local targetCharid = ResolveRestrictionTarget(modifier, creature)
        if targetCharid == nil or targetCharid == "" then return true end

        local targetToken = dmhub.GetTokenById(targetCharid)
        if targetToken == nil or (not targetToken.valid) then return true end

        if modifier:try_get("restrictionType", "approach") == "leash" then
            local anchorLoc = GetLeashAnchorLoc(modContext, targetToken, targetCharid)
            if anchorLoc == nil then return true end

            local locDist = loc:DistanceInTiles(anchorLoc)
            if locDist <= modifier:try_get("distance", 3) then
                return true
            end

            -- Already outside the leash -- forced movement can push a creature out, and
            -- the rules give no answer for that. Rather than freezing them in place,
            -- allow any step that does not take them further away still.
            return locDist <= startLoc:DistanceInTiles(anchorLoc)
        end

        local targetLocs = targetToken.locsOccupying
        if targetLocs == nil or #targetLocs == 0 then return true end

        local startDist = math.huge
        for _, tl in ipairs(targetLocs) do
            local d = startLoc:DistanceInTiles(tl)
            if d < startDist then startDist = d end
        end

        local locDist = math.huge
        for _, tl in ipairs(targetLocs) do
            local d = loc:DistanceInTiles(tl)
            if d < locDist then locDist = d end
        end

        return locDist >= startDist
    end,

    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local restrictionType = modifier:try_get("restrictionType", "approach")

            local targetHelp = "A GoblinScript expression that evaluates to the creature the restricted creature cannot approach. Can be a raw token ID number, or a GoblinScript expression such as ConditionCaster(\"Frightened\")."
            if restrictionType == "leash" then
                targetHelp = "A GoblinScript expression that evaluates to the creature the restricted creature must stay near. Distance is measured from where that creature stood when the effect was applied, falling back to where it is now. Can be a raw token ID number, or a GoblinScript expression such as ConditionCaster(\"Hooked\")."
            end

            local children = {}
            children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Restriction:",
                },
                gui.Dropdown{
                    classes = {"formDropdown"},
                    options = g_restrictionTypes,
                    idChosen = restrictionType,
                    change = function(self)
                        modifier.restrictionType = self.idChosen
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Target:",
                },
                gui.GoblinScriptInput{
                    value = modifier:try_get("targetFormula", ""),
                    change = function(self)
                        local v = trim(self.value)
                        if v == "" then
                            modifier.targetFormula = nil
                        else
                            modifier.targetFormula = v
                        end
                        Refresh()
                    end,
                    documentation = {
                        help = targetHelp,
                        output = "creature",
                        examples = {
                            {
                                script = "ConditionCaster(\"Frightened\")",
                                text = "Cannot approach the creature that inflicted Frightened on this creature.",
                            },
                            {
                                script = "ConditionCaster(\"Hooked\")",
                                text = "Cannot stray from the creature that inflicted Hooked on this creature.",
                            },
                        },
                    },
                },
            }

            if restrictionType == "leash" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Squares:",
                    },
                    gui.Input{
                        text = tostring(modifier:try_get("distance", 3)),
                        change = function(self)
                            modifier.distance = math.max(0, math.floor(tonumber(self.text) or 3))
                            Refresh()
                        end,
                    },
                }
            end

            element.children = children
        end

        Refresh()
    end,
}

function CharacterModifier:MovementAdvisoryText(creature, path, text)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.MovementAdvisoryText ~= nil then
        text = typeInfo.MovementAdvisoryText(self, creature, path, text)
	end
    return text
end

function CharacterModifier:ReminderText(creature, domain, text)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.ReminderText ~= nil then
        text = typeInfo.ReminderText(self, creature, domain, text)
	end
    return text
end

function gui.ReminderTextPanel(options)
    local domain = options.domain or "movement"
    options.domain = nil

    local tokens = options.tokens or {}
    options.tokens = nil

    local fontSize = options.fontSize or 14
    options.fontSize = nil

    local params = {
        width = 400,
        height = "auto",
        maxHeight = options.maxHeight or 80,
        vscroll = true,
        bgimage = true,
        flow = "vertical",
        settokens = function(element, tokens)

            local children = {}
            for _,token in ipairs(tokens) do
                local text = ""
                local modifiers = token.properties:GetActiveModifiers()
                for _,mod in ipairs(modifiers) do
                    text = mod.mod:ReminderText(token.properties, domain, text)
                end

                if text ~= "" then
                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "100%-8",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        classes = {"reminderTextPanel"},
                        gui.CreateTokenImage(token, {
                            width = 32,
                            height = 32,
                            valign = "center",
                            lmargin = 4,
                        }),
                        gui.Label{
                            text = text,
                            fontSize = fontSize,
                            color = "white",
                            width = "100%-40",
                            height = "auto",
                            halign = "right",
                            valign = "center",
                        },
                    }
                end
            end
            element.children = children
        end,
    }

    for k,v in pairs(options) do
        params[k] = v
    end

    local resultPanel = gui.Panel(params)
    resultPanel:FireEvent("settokens", tokens)
    return resultPanel
end
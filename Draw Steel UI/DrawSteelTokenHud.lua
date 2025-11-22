local mod = dmhub.GetModLoading()

local g_deadMinionPulseSpeed = 0.5
local g_deadMinionIconStyles = {
    gui.Style{
        width = 48,
        height = 48,
        bgimage = "ui-icons/Pin_Boss.png",
        bgcolor = "red",
        opacity = 0.8,
    },
    gui.Style{
        selectors = {"nondirect"},
        bgcolor = "orange",
    },
    gui.Style{
        selectors = {"big", "~nondirect"},
        scale = 1.2,
        transitionTime = g_deadMinionPulseSpeed,
    },
    gui.Style{
        selectors = {"hover"},
        scale = 1.2,
        opacity = 1,
        transitionTime = 0.2,
    },
    gui.Style{
        selectors = {"press"},
        brightness = 2,
    }
}

--the wounded icon configuration.
TokenUI.RegisterIcon{
    id = "wounded",
    icon = "ui-icons/wounded-border.png",
    Filter = function(creature)
        --this controls if the icon should display.
	    return (not creature.minion) and creature.damage_taken >= creature:MaxHitpoints()/2 and dmhub.GetSettingValue("showwoundedicon")
    end,

    --Only show to those who can't see the health bar.
    showToAll = true,
    showToGM = true,
    showToController = true,
    showToFriends = true,
    showToEnemies = true,
}

TokenUI.RegisterIcon{
    id = "captain",
    Calculate = function(creature)
        if (not creature:has_key("minionSquad")) or creature.minion then
            return nil
        end

        return {
            id = "captain",
            icon = "panels/hud/crown.png",
            style = {
                bgcolor = DrawSteelMinion.GetSquadColor(creature.minionSquad)
            }
        }
    end,

    showToAll = true,
    showToGM = true,
    showToController = true,
    showToFriends = true,
    showToEnemies = true,
}

local g_triggeredResource = ""
local g_triggeredResourceRefreshType = ""
local g_triggeredStyles = {
    gui.Style{
        selectors = {"depleted"},
        transitionTime = 0.4,
        hidden = 1,
        scale = 2,
        opacity = 0,
    },
}

TokenHud.RegisterPanel{
    id = "drawsteel",
    ord = 1,
    layer = "top",
	create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end
        if g_triggeredResource == "" then
            g_triggeredResource = CharacterResource.nameToId["Trigger"] or ""
            g_triggeredResourceRefreshType = CharacterResource.resourceToRefreshType[g_triggeredResource] or ""
        end
       
        local m_haveTrigger = nil
        local m_triggerActivePanel = gui.TriggerPanel{
            classes = {"hidden"},
            text = "!",
            interactable = false,
            styles = Styles.TriggerStyles,
            bgimage = true,
            halign = "center",
            valign = "center",

            updateInitiative = function(element)
                local triggers = token.properties:GetAvailableTriggers(true)
                local notrigger = triggers == nil
                if notrigger ~= element:HasClass("hidden") then
                    element:SetClass("hidden", notrigger)
                end

                if triggers ~= nil then
                    local allfree = true
                    for key,value in pairs(triggers) do
                        if not value:IsFreeTriggeredAbility() then
                            allfree = false
                            break
                        end
                    end

                    element:SetClass("free", allfree)
                end

                if m_haveTrigger == false and notrigger == false and token.canControl and token.activeControllerId == nil then
                    audio.FireSoundEvent("Notify.Trigger")
                end
                
                m_haveTrigger = not notrigger
            end,
        }

        local namebglabel = gui.Label{
                x = 2,
                y = 2,
				text = 'TEXT',
                fontFace = "Newzald",
				interactable = false,
				fontSize = 14,
				minFontSize = 8,
				maxWidth = "80%",
				wrap = false,
				textWrap = false,
				width = "auto",
				height = "auto",
				color = 'white',
				halign = 'center',
				valign = 'center',
				textAlignment = 'center',
				brightness = 1,
			}


        local namelabel = gui.Label{
				text = 'TEXT',
                fontFace = "Newzald",
				interactable = false,
				fontSize = 14,
				minFontSize = 8,
				maxWidth = "80%",
				wrap = false,
				textWrap = false,
				width = "auto",
				height = "auto",
				color = 'white',
				halign = 'center',
				valign = 'center',
				textAlignment = 'center',
				brightness = 1,
				events = {
					refresh = function(element)
						if token.properties ~= nil then
                            local textColor = nil
                            local squad = token.properties:MinionSquad()
                            if squad ~= nil then
							   textColor = DrawSteelMinion.GetSquadColor(squad)
                            else
							    textColor = token.playerColor
                            end

                            local text = token:GetNameMaxLength(30)
                            if (text == nil or text == "") then
                                if token.properties:IsMonster() then
                                    text = token.properties:try_get("monster_type")
                                    if text == "" then
                                        text = "Monster"
                                    end
                                elseif token.properties:IsHero() then
                                    text = "Hero"
                                else
                                    text = "Creature"
                                end
                            end

                            if text ~= nil then
                                local offsetScale = 0.85 ^ math.max(0, #text - 10)
                                namebglabel.x = 1.5 * offsetScale
                                namebglabel.y = 4 - 1.5 * offsetScale
                            end

							element.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
							element.text = text

							namebglabel.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
							namebglabel.text = text

                            local lightbg = TokenHud.UseLightBackgroundColor(core.Color(textColor))
                            if lightbg then
                                namebglabel.selfStyle.color = textColor
                                element.selfStyle.color = "white"
                            else
                                namebglabel.selfStyle.color = "black"
                                element.selfStyle.color = textColor
                            end
						end
					end,
				},
			}



        local m_minionDeathPanel = nil

        return gui.Panel{
            interactable = false,

            width = 96,
            height = 96,
            halign = "center",
            valign = "center",
            flow = "none",

            thinkTime = 0.2,
            think = function(element)
                element:FireEventTree("updateInitiative")

                if token.properties.minion and token.properties:has_key("_tmp_minionSquad") then
                    local squad = token.properties._tmp_minionSquad
                    local death = (not squad.damage_time_pending) and squad.damage_taken >= squad.health_single
                    local death_overflows = squad.damage_taken >= (squad.num_recently_damaged+1) * squad.health_single
                    local is_direct_target = token.properties.minionDamageTime == squad.damage_time
                    local has_direct_targets = squad.num_recently_damaged > 0

                    if death and (is_direct_target or death_overflows) then
                        if m_minionDeathPanel == nil then
                            m_minionDeathPanel = gui.Panel{
                                styles = g_deadMinionIconStyles,
                                click = function(element)
                                    token.properties:TriggerEvent("creaturedeath", {})
                                    token.properties:MinionDeath()
                                    --game.DeleteCharacters{token.charid}
                                end,

                                thinkTime = g_deadMinionPulseSpeed,
                                think = function(element)
                                    element:SetClass("big", not element:HasClass("big"))
                                end,
                            }

                            element:AddChild(m_minionDeathPanel)
                        end

                        m_minionDeathPanel:SetClass("nondirect", has_direct_targets and not is_direct_target)
                    else
                        if m_minionDeathPanel ~= nil then
                            m_minionDeathPanel:DestroySelf()
                            m_minionDeathPanel = nil
                        end
                    end


                    
                end
            end,

            m_triggerActivePanel,

            gui.Panel{
                classes = {"actionBarDrawer", "hidden"},
                interactable = true,
                halign = "center",
                valign = "center",
                width = 120,
                height = 30,
                y = 40,
                flow = "none",

                data = {
                    prevStatus = nil,
                },

                namebglabel,
                namelabel,


                styles = {
                    Styles.ActionBar,

                    gui.Style{
                        selectors = {"big"},
                        scale = 1.2,
                        transitionTime = 0.5,
                        brightness = 1.2,
                        easing = "easeInOutSine",
                    },
                    gui.Style{
                        selectors = {"hover"},
                        scale = 1.2,
                        brightness = 3.0,
                        transitionTime = 0.2,
                    },
                },

                think = function(element)
                    element:SetClass("big", not element:HasClass("big"))
                end,

                updateInitiative = function(element)
                    local status = token.initiativeStatus

                    if status == "OurTurn" and element.data.prevStatus == "ActiveAndReady" and element:HasClass("hidden") == false then
                        element:FireEvent("spawnChild")
                    end

                    local show = status == "ActiveAndReady"
                    if dmhub.Time() < (element.data.clickTime or 0) + 1 then
                        show = false
                    end
                    element:SetClass("hidden", not show)
                    element.thinkTime = cond(show, 0.5)

                    element.data.prevStatus = status
                end,

                hover = function(element)
                    if token.canControl then
                        audio.FireSoundEvent("Mouse.Hover")
                        gui.Tooltip("Click to take your turn now.")(element)
                    end
                end,

                press = function(element)
                    if token.canControl then
                        element.data.clickTime = dmhub.Time()
                        audio.FireSoundEvent("Mouse.Click")
                        element:SetClass("hidden", true)
                        local initiativeid = dmhub.initiativeQueue.GetInitiativeId(token)
                        dmhub.initiativeQueue:SelectTurn(initiativeid)
                        dmhub:UploadInitiativeQueue()

                        local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, initiativeid)
                        for i,tok in ipairs(tokens) do
                            if tok.properties ~= nil then
                                tok.properties:BeginTurn()
                            end
                        end

                        element:FireEvent("spawnChild")
                    end
                end,

                spawnChild = function(element)

                end,
            },
        }
    end,
}

-- Function to calculate relative luminance
local function luminance(r, g, b)
    local function transform(component)
        if component <= 0.03928 then
            return component / 12.92
        else
            return ((component + 0.055) / 1.055) ^ 2.4
        end
    end
    return 0.2126 * transform(r) + 0.7152 * transform(g) + 0.0722 * transform(b)
end

-- Function to calculate contrast ratio
local function contrast_ratio(l1, l2)
    return (l1 + 0.05) / (l2 + 0.05)
end

local luminance_bg_black = luminance(0,0,0)

function TokenHud.UseLightBackgroundColor(color)
    if type(color) == "string" then
        color = core.Color(color)
    end

    local lum = luminance(color.r, color.g, color.b)
    if contrast_ratio(lum, luminance_bg_black) < 3.0 then
        return true
    else
        return false
    end
end

TokenHud.RegisterPanel{
	id = "nameLabel",
	create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end

        local bglabel = gui.Label{
                x = 2,
                y = 2,
				hpad = 16,
				vpad = 8,
				text = '',
                fontFace = "Newzald",
				interactable = false,
				fontSize = 14,
				minFontSize = 8,
				maxWidth = 120,
				wrap = false,
				textWrap = false,
				width = "auto",
				height = "auto",
				color = 'white',
				halign = 'center',
				valign = 'bottom',
				textAlignment = 'center',
				brightness = 1,
				italics = false,
			}


        local label = gui.Label{
				hpad = 16,
				vpad = 8,
				text = '',
                fontFace = "Newzald",
				interactable = false,
				fontSize = 14,
				minFontSize = 8,
				maxWidth = 120,
				wrap = false,
				textWrap = false,
				width = "auto",
				height = "auto",
				y = 4,
				color = 'white',
				halign = 'center',
				valign = 'bottom',
				textAlignment = 'center',
				brightness = 1,
				italics = false,
				events = {
					refresh = function(element)
						if token.properties ~= nil and (token.canControl or not token.namePrivate) then
                            local textColor = nil
                            local squad = token.properties:MinionSquad()
                            if squad ~= nil then
							   textColor = DrawSteelMinion.GetSquadColor(squad)
                            else
							    textColor = token.playerColor
                            end

                            local text = token:GetNameMaxLength(30)

                            if text ~= nil then
                                local offsetScale = 0.85 ^ math.max(0, #text - 10)
                                bglabel.x = 1.5 * offsetScale
                                bglabel.y = 4 - 1.5 * offsetScale
                            end

							element.selfStyle.italics = token.namePrivate
							element.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
							element.text = text

							bglabel.selfStyle.italics = token.namePrivate
							bglabel.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
							bglabel.text = text

                            local lightbg = TokenHud.UseLightBackgroundColor(core.Color(textColor))
                            if lightbg then
                                bglabel.selfStyle.color = textColor
                                element.selfStyle.color = "white"
                            else
                                bglabel.selfStyle.color = "black"
                                element.selfStyle.color = textColor
                            end
						else
							element.text = ''
                            bglabel.text = ''
						end
					end,
				},
			}

	
		return gui.Panel{
			interactable = false,

			valign = "bottom",
			halign = "center",
			width = 120,
			height = 40,

            bglabel,
            label,

		}

	end,
}

dmhub.RegisterRemoteEvent("opportunityAttack", function(info)

    if info == nil then
        print("No info given to opportunity attack")
        return
    end

	local token = dmhub.GetTokenById(info.tokenid)
	if token == nil or token.sheet == nil then
		return
	end

    if info.clear then
        token.sheet:FireEventTree("clearOpportunityAttack", info.displayid)
    else
        token.sheet:FireEventTree("displayOpportunityAttack", info)
    end
end)


TokenHud.RegisterPanel{
    id = "triggers",
    create = function(token)
        if token.isObject then
            return nil
        end
        local m_cache = nil
        local m_calculationCache = nil
        local m_guid = dmhub.GenerateGuid() --used for all broadcast sends.
        return gui.Panel{
            interactable = false,
            width = 1,
            height = 1,
            halign = "center",
            valign = "center",
            bgimage = false,

            data = {
                displayid = nil,
                localid = nil,
                broadcastMessage = nil,
                currentlyDisplayed = nil,
            },

            think = function(element)
                dmhub.BroadcastRemoteEvent("opportunityAttack", element.data.localid, element.data.broadcastMessage)
            end,

            startBroadcasting = function(element, message)
                element.data.broadcastMessage = message
                element.thinkTime = 1
                element:FireEvent("think")
            end,

            stopBroadcasting = function(element)
                element.data.broadcastMessage = nil
                element.thinkTime = nil
            end,

            clearOpportunityAttackLocal = function(element)
                if element.data.localid ~= nil then
                    dmhub.BroadcastRemoteEvent("opportunityAttack", element.data.localid, {
                        tokenid = token.charid,
                        displayid = element.data.localid,
                        clear = true,
                    })
                    element:FireEvent("stopBroadcasting")
                end
                element:FireEvent("clearOpportunityAttack", element.data.localid)
                element.data.localid = nil
            end,

            clearOpportunityAttack = function(element, displayid)
                if element.data.displayid ~= displayid then
                    return
                end

                element.data.currentlyDisplayed = nil
                element.children = {}
            end,

            displayOpportunityAttack = function(element, info, islocal)
                if element.data.localid ~= nil and element.data.localid ~= info.displayid then
                    return
                end

                if element.data.currentlyDisplayed ~= nil and dmhub.DeepEqual(element.data.currentlyDisplayed, info) then
                    element:FireEvent("refreshDisplay")
                    return
                end

                local m_parentElement = element
                local m_local = islocal

                if element.data.currentlyDisplayed == nil then
                    audio.FireSoundEvent("Notify.OpportunityAttackWarn")
                end

                element.data.currentlyDisplayed = DeepCopy(info)
                element.data.displayid = info.displayid
                local angle = 90 + math.atan(info.ydiff, info.xdiff) * (180/math.pi)
                element.children = {
                    gui.Panel{
                        data = {
                            refreshTime = dmhub.Time(),
                        },
                        width = 32,
                        height = 32,
                        rotate = 180 - angle,
                        x = info.xdiff*30,
                        y = info.ydiff*30,
                        bgimage = "panels/triangle.png",
                        bgcolor = "red",
                        refreshTime = function(element)
                            element.data.refreshTime = dmhub.Time()
                        end,
                        thinkTime = 0.3,
                        think = function(element)
                            if (not m_local) and dmhub.Time() > element.data.refreshTime + 3 then
                                m_parentElement:FireEvent("clearOpportunityAttack", m_parentElement.data.displayid)
                                return
                            end
                            local child = gui.Panel{
                                width = 32,
                                height = 32,
                                rotate = element.selfStyle.rotate,
                                x = info.xdiff*30,
                                y = info.ydiff*30,
                                bgimage = "panels/triangle.png",
                                thinkTime = 0.01,

                                --- @param element Panel
                                think = function(element)
                                    element.x = info.xdiff*30*(1+element.aliveTime*5)
                                    element.y = info.ydiff*30*(1+element.aliveTime*5)
                                    if element.aliveTime > 0.5 then
                                        element:DestroySelf()
                                    end
                                end,
                                styles = {
                                    {
                                        bgcolor = "clear",
                                        scale = 1.2,
                                    },
                                    {
                                        selectors = {"create"},
                                        bgcolor = "red",
                                        transitionTime = 0.5,
                                        scale = 1,
                                    },
                                }
                            }

                            element.parent:AddChild(child)
                        end,
                    }
                }
            end,

            --- @param element Panel
            --- @param token CharacterToken
            --- @param movingToken CharacterToken|nil
            --- @param path LuaPath|nil
            --- @param movementType "walk"|"teleport"|"forced"|"shift"|nil
            movementplan = function(element, token, movingToken, path, movementType)
                if movingToken == nil or path == nil or movementType ~= "walk" or token:IsFriend(movingToken) then
                    m_cache = nil
                    m_calculationCache = nil
                    element:FireEvent("clearOpportunityAttackLocal")
                    return
                end

                --see if we'll calculate exactly like we did last time, in which case
                --we just return early and avoid all the recalculation.
                local ngameupdate = dmhub.gameupdateid
                m_calculationCache = m_calculationCache or {updateid = ngameupdate, charid = token.charid}
                if m_calculationCache.updateid ~= ngameupdate or m_calculationCache.charid ~= token.charid then
                    --print("CACHE:: CHANGED STATE", m_calculationCache.updateid, ngameupdate, m_calculationCache.charid, token.charid)
                    m_calculationCache = {updateid = ngameupdate, charid = token.charid}
                end

                if m_calculationCache.path ~= nil and not m_calculationCache.path:Equals(path) then
                    m_calculationCache.path = nil
                end

                element.data.x = (element.data.x or 0) + 1
                if m_calculationCache.path ~= nil then
                    --no changes since last time.
                    --print("CACHE:: ELIDE", element.data.x)
                    return
                end

                    --print("CACHE:: HOMERUN")
                m_calculationCache.path = path

                m_calculationCache.immunity = m_calculationCache.immunity or movingToken.properties:CalculateNamedCustomAttribute("Immunity from Opportunity Attack")
                if m_calculationCache.immunity > 0 then
                    return
                end

                if m_calculationCache.CanUseTriggeredAbilities == nil then
                    m_calculationCache.CanUseTriggeredAbilities = token.properties:CanUseTriggeredAbilities()
                end
                if not m_calculationCache.CanUseTriggeredAbilities then
                    return
                end

                if token.properties._tmp_grabbedby == movingToken.charid then
                    --grabbed tokens will be brought with the grabber.
                    return
                end

                if m_calculationCache.hasBanes == nil then
                    m_calculationCache.hasBanes = token.properties:HasBanesOnGenericFreeStrike(movingToken)
                end

                if m_calculationCache.hasBanes then
                    return
                end

                if m_calculationCache.passesFilter == nil then
                    m_calculationCache.passesFilter = token.properties:TargetPassesFilter("opportunityattack", movingToken.properties)
                end
                if m_calculationCache.passesFilter == false then
                    return
                end

                local adjacent = {}
                if token:Distance(path) <= movingToken.tileSize then
                    local locsOccupying = token.locsOccupying
                    local steps = path.steps
                    local adjacentLocs = token.properties:AdjacentLocations()
                    for i,step in ipairs(steps) do
                        local locs = movingToken:LocsOccupyingWhenAt(step)

                        local isadjacent = false

                        for _,loc in ipairs(locs) do
                            for _,adj in ipairs(adjacentLocs) do
                                if loc.x == adj.x and loc.y == adj.y and loc.floor == adj.floor and (loc.altitude <= adj.altitude + 1) then
                                    isadjacent = true
                                    break
                                end
                            end
                        end

                        --locations directly occupied are also considered 'adjacent'
                        for _,loc in ipairs(locs) do
                            for _,adj in ipairs(locsOccupying) do
                                if loc.x == adj.x and loc.y == adj.y and loc.floor == adj.floor and (loc.altitude <= adj.altitude + 1) then
                                    isadjacent = true
                                    break
                                end
                            end
                        end

                        adjacent[#adjacent+1] = isadjacent
                    end

                    for i=1,#adjacent-1 do
                        if adjacent[i] and not adjacent[i+1] then
                            local targetLoc = steps[i]
                            local xdiff = targetLoc.point2.x - token.pos.x
                            local ydiff = -(targetLoc.point2.y - token.pos.y)
                            local magnitude = math.sqrt(xdiff*xdiff + ydiff*ydiff)
                            xdiff = xdiff/magnitude
                            ydiff = ydiff/magnitude

                            local cache = {
                                xdiff = xdiff,
                                ydiff = ydiff,
                            }

                            if m_cache ~= nil then
                                local different = false
                                for k,v in pairs(cache) do
                                    if m_cache[k] ~= v then
                                        different = true
                                        break
                                    end
                                end

                                if not different then
                                    return
                                end
                            end

                            m_cache = cache

                            local moveid = m_guid
                            element.data.localid = moveid

                            local info = {
                                displayid = moveid,
                                tokenid = token.charid,
                                xdiff = xdiff,
                                ydiff = ydiff,
                            }

                            element:FireEvent("displayOpportunityAttack", info, true)

                            element:FireEvent("startBroadcasting", info)

                            return
                        end
                    end
                end

                element:FireEvent("clearOpportunityAttackLocal")
                m_cache = nil
                element.children = {}
            end,
        }
    end,
}

TokenHud.RegisterPanel{
	id = "flankingPanel",
	create = function(token, sharedInfo)
        if token.isObject then
            return nil
        end
        local m_indicators = {}
		return gui.Panel{
			interactable = false,
            width = 1,
            height = 1,
            valign = "center",
            halign = "center",
            monitorGame = "/characters",
            refreshGame = function(element)
                element:FireEvent("refresh")
            end,
			refresh = function(element)
                if token == nil or (not token.valid) then
                    return
                end
                local flankingTokens = token.properties:GetFlankingTokens()
                if #flankingTokens == 0 then
                    m_indicators = {}
                    element.children = {}
                    element:SetClass("collapsed", true)
                    return
                end

                if #m_indicators == #flankingTokens then
                    local match = true
                    for i=1,#flankingTokens do
                        if flankingTokens[i] ~= m_indicators[i].data.token then
                            match = false
                            break
                        end
                    end

                    if match then
                        return
                    end
                end

                element:SetClass("collapsed", false)

                for i,tok in ipairs(flankingTokens) do
                    m_indicators[i] = gui.Panel{
                        width = 1,
                        height = 80,
                        halign = "center",
                        valign = "center",
                        interactable = false,

                        gui.Panel{
                            halign = "center",
                            valign = "top",
                            interactable = false,
                            bgimage = mod.images.flankarrow,
                            bgcolor = cond(tok.properties:try_get("_tmp_grantsFlanking", "") == token.charid, "#FFFFFF", "#CF1414"),
                            width = 71*0.45,
                            height = 36*0.45,
                            rotate = 180,
                        },                        

                        thinkTime = 0.1,
                        think = function(element)
                            if tok.valid then
                                local a = tok.pos
                                local b = token.pos
                                local deltax = a.x - b.x
                                local deltay = -(a.y - b.y)

                                local angle = math.atan(deltay, deltax)
                                local degrees = angle * (180/math.pi)
                                element.selfStyle.rotate = -degrees-90
                            end
                        end,

                        create = function(element)
                            element:FireEvent("think")
                        end,
                    }
                end

                while #m_indicators > #flankingTokens do
                    m_indicators[#m_indicators] = nil
                end

                element.children = m_indicators

            end,
        }
    end
}

--Draw Steel version of lifebars.
TokenUI.RegisterStatusBar{
    id = "lifebar",

    --showToAll = true,
    showToGM = function() return dmhub.GetSettingValue("hpbarfordm") end,
    showToController = function() return dmhub.GetSettingValue("hpbarforownplayer") end,
    showToFriends = function() return dmhub.GetSettingValue("hpbarforparty") end,
    showToEnemies = function() return dmhub.GetSettingValue("hpbarforenemy") end,

    height = 9,
    width = 1,
    seek = 10, --bar goes up or down 10 hp /second

    tempColor = {
        {
            color = "white",
            gradient = Styles.tempGradient,
        }

    },
    --make the fill color change according to current number of hitpoints.
    fillColor = {
        {
            value = 0.5,
            color = "white",
            gradient = Styles.healthGradient,
        },
        {
            color = "white",
            gradient = Styles.damagedGradient,
        },
    },
    Calculate = function(creature)
        if dmhub.GetSettingValue("hpbarsonlyincombat") then
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                return nil
            end
        end

        if creature.minion then
            return nil
        end

        local showAsPct = false
        if dmhub.isDM == false and dmhub.GetSettingValue("hppctforenemy") then
            local token = dmhub.LookupToken(creature)
            if token then
                showAsPct = not token.isFriendOfPlayer
            end
        end

        return {
            value = creature:CurrentHitpoints(),
            max = creature:MaxHitpoints(),
            temp = creature:TemporaryHitpoints(),
            showAsPct = showAsPct,
            width = 1, --math.min(1, math.max(0.25, (max_hp*0.1)/creature:GetCalculatedCreatureSizeAsNumber())),
        }
    end
}


--force a rebuild of token UI.
dmhub.InvalidateTokenUI()
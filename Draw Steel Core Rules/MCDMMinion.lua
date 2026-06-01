local mod = dmhub.GetModLoading()

local g_docid = "minions"
local g_defaultColor = "#ff0000"

local g_defaultColors = {
    "#ff0000",   -- Red
    "#ff7f00",   -- Orange
    "#ffff00",   -- Yellow
    "#7fff00",   -- Chartreuse
    "#00ff00",   -- Green
    "#00ff7f",   -- Spring Green
    "#00ffff",   -- Cyan
    "#007fff",   -- Sky Blue
    "#0000ff",   -- Blue
    "#7f00ff",   -- Violet
    "#ff00ff",   -- Magenta
    "#ff007f",   -- Rose
    "#ff7f7f",   -- Light Coral
    "#ffcccc",   -- Misty Rose
    "#ccffcc",   -- Honeydew
    "#ccccff",   -- Lavender
    "#ffffcc"    -- Light Yellow
}

-- Simple hash function to get a number from a string
local function hashString(str)
    local hash = 0
    for i = 1, #str do
        local char = string.byte(str, i)
        hash = (hash * 31 + char) % #g_defaultColors
    end
    return hash + 1 -- Lua arrays are 1-based
end

-- Function to get a color based on a string
local function getColorFromString(str)
    local index = hashString(tostring(str))
    return g_defaultColors[index]
end

--- @module DrawSteelMinion

--- @class DrawSteelMinion
--- @field squads nil|table<string, {color: string}> Per-session squad color overrides, keyed by squad name.
--- Manages Draw Steel minion squads, including per-squad color assignment.
DrawSteelMinion = RegisterGameType("DrawSteelMinion")


--- Given the name of a squad get the color we should display for it.
--- @param name string
--- @return Color
DrawSteelMinion.GetSquadColor = function(name)
	local doc = mod:GetDocumentSnapshot(g_docid)
    if doc.data.squads == nil or doc.data.squads[name] == nil then
        return getColorFromString(name)
    end

    local info = doc.data.squads[name]
    return info.color or getColorFromString(name)
end

--- Set the color for a squad.
--- @param name string
--- @return Color
DrawSteelMinion.SetSquadColor = function(name, color)
    local doc = mod:GetDocumentSnapshot(g_docid)
    doc:BeginChange()
    if doc.data.squads == nil then
        doc.data.squads = {}
    end

    doc.data.squads[name] = {
        color = color
    }

    doc:CompleteChange("Set squad color")
end

--- Given a squad name find the logical next available name.
--- @param squad_name string
--- @return string
local function IncrementSquadName(squad_name)
    -- Find the number at the end of the string, if it exists
    local name_part = squad_name:match("^(.-)%d*$")
    local number_part = squad_name:match("(%d+)$")

    if number_part then
        -- Increment the number and return the new name
        local new_number = tonumber(number_part) + 1
        return name_part .. new_number
    else
        -- If there's no number, add " 2" to the name
        return squad_name .. " 2"
    end
end

--- Given a list of tokens, makes them all into a new squad.
--- @param tokens CharacterToken[]
DrawSteelMinion.FormSquad = function(tokens)

    local squad = nil
    for i,token in ipairs(tokens) do
        if token.properties.minion and token.properties._tmp_minionSquad ~= nil then
            squad = token.properties._tmp_minionSquad
        end
    end

    if squad == nil then
        return
    end

    local allTokens = dmhub.GetTokens{}
    local squadNames = {}
    for _,tok in ipairs(allTokens) do
        if tok.valid and tok.properties:MinionSquad() ~= nil then
            squadNames[tok.properties:MinionSquad()] = true
        end
    end

    local newName = squad.name
    for i=1,100 do
        newName = IncrementSquadName(newName)
        if squadNames[newName] == nil then
            break
        end
    end

    for _,tok in ipairs(dmhub.selectedOrPrimaryTokens) do
        if tok.valid and tok.properties.minion then
            tok:ModifyProperties{
                description = "Form Squad",
                undoable = false,
                combine = true,
                execute = function()
                    tok.properties.minionSquad = newName
                    --clear any stale initiativeGrouping from how this minion was
                    --spawned so the squad becomes its authoritative initiative group.
                    tok.properties.initiativeGrouping = false
                    if tok.properties.minion then
                        tok.properties.damage_taken = nil
                        tok.properties.damage_taken_seq = nil
                        tok.properties.squadpos = nil
                    end
                end,
            }
        elseif tok.valid then
            --make this a captain of the squad. Clear any leftover initiativeGrouping
            --so the captain falls through to the shared squad initiative as well.
            tok.properties.minionSquad = newName
            tok.properties.initiativeGrouping = false
        end
    end
end

local g_tileSize = 100
local g_minionHealthGradient = gui.Gradient{
    point_a = {x = 0, y = 0},
    point_b = {x = 1, y = 0},
    stops = {
        {
            position = 0,
            color = "#880000",
        },
        {
            position = 1,
            color = "#cc0000",
        },
    },
}

local g_haveFormSquadButton = false

--- Shows a button to form a new squad.
--- @param floorid string
--- @param squad SquadInfo
DrawSteelMinion.NewSquadButton = function(floorid, squad)
    if dmhub.isDM == false or g_haveFormSquadButton then
        return
    end


    local sheetParent = dmhub.GetWorldSpacePanel(floorid, "add-minions-" .. squad.name)
    if sheetParent ~= nil and sheetParent.sheet == nil then
        local m_selectedTokens = dmhub.selectedOrPrimaryTokens

        local m_BarWidth = 100

        local panel = gui.Button{
            styles = Styles.Default,
            halign = "center",
            valign = "center",
            fontSize = 16,
            text = "Form Squad",
            height = 24,
            width = 120,

            create = function(element)
                g_haveFormSquadButton = true
            end,
            destroy = function(element)
                g_haveFormSquadButton = false
            end,

            press = function(element)

                DrawSteelMinion.FormSquad(dmhub.selectedOrPrimaryTokens)

                sheetParent:Destroy()
            end,

            thinkTime = 0.01,
            think = function(element)
                if squad.liveMinions <= 1 then
                    sheetParent:Destroy()
                    return
                end

                local minionCount = 0
                local foundMinion = false

                local selectedTokens = dmhub.selectedOrPrimaryTokens
                if #selectedTokens ~= #m_selectedTokens then
                    sheetParent:Destroy()
                    return
                end

                for i=1,#selectedTokens do
                    if selectedTokens[i].valid == false or m_selectedTokens[i].valid == false or selectedTokens[i].charid ~= m_selectedTokens[i].charid then
                        sheetParent:Destroy()
                        return
                    end
                end

                local m_tokensBlocking = {}
                local m_tokensBlockingLastThink = 0

                local xpos = 0
                local ypos = 0

                local count = 0
                for _,tok in ipairs(selectedTokens) do
                    local pos = tok.pos
                    xpos = xpos + pos.x
                    ypos = ypos + pos.y
                    count = count + 1
                end

                if count == 0 then
                    sheetParent:Destroy()
                    return
                end

                xpos = xpos / count
                ypos = ypos / count

                if m_tokensBlockingLastThink < dmhub.Time() - 0.5 then
                    m_tokensBlocking = {}
                    m_tokensBlockingLastThink = dmhub.Time()
                    local tokensBlocking = dmhub.GetTokens{
                        position = {
                            x = xpos,
                            y = ypos,
                            radius = 6,
                        },
                    }

                    for _,tok in ipairs(tokensBlocking) do
                        if tok.valid and tok.properties ~= nil then
                            m_tokensBlocking[#m_tokensBlocking+1] = {
                                x = tok.pos.x,
                                y = tok.pos.y,
                                radius = tok.radiusInTiles,
                            }
                        end
                    end
                end

                local blocked = false
                for _,tok in ipairs(m_tokensBlocking) do
                    if math.abs(xpos - tok.x) < (tok.radius + 0.6) and math.abs(ypos - tok.y) < (tok.radius + 0.1) then
                        blocked = true
                    end
                end

                if blocked then
                    local directions = {{1,0},{-1,0},{0,1},{0,-1}}
                    for i=0,5 do
                        local xx = xpos
                        local yy = ypos

                        for _,dir in ipairs(directions) do
                            xpos = xx + dir[1]*i
                            ypos = yy + dir[2]*i
                            blocked = false
                            for _,tok in ipairs(m_tokensBlocking) do
                                if math.abs(xpos - tok.x) < (tok.radius + 0.6) and math.abs(ypos - tok.y) < (tok.radius + 0.1) then
                                    blocked = true
                                end
                            end
                        end

                        if blocked == false then
                            break
                        end

                        xpos = xx
                        ypos = yy
                    end
                end

                element.x = xpos*g_tileSize
                element.y = -ypos*g_tileSize
            end,
        }


        sheetParent.sheet = gui.Panel{
            halign = "center",
            valign = "center",
            x = 1,
            y = 1,
            panel,
        }

        panel:FireEvent("think")
    end
end

local g_squadPanelMovementLag = 0.5

DrawSteelMinion.SquadHud = function(floorid, squad)
    --True when the current user can control any token in this squad
    local function viewerControlsSquad()
        for _, tok in ipairs(squad.tokens or {}) do
            if tok ~= nil and tok.valid and tok.canControl then
                return true
            end
        end
        return false
    end

    if dmhub.isDM == false and not viewerControlsSquad() then
        if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden or (dmhub.GetSettingValue("enemystambardisplay") == "none") then
            return
        end
    end

	local sheetParent = dmhub.GetWorldSpacePanel(floorid, "minions-" .. squad.name)
	if sheetParent ~= nil and sheetParent.sheet == nil then

        local m_BarWidth = 100

        local m_pos = nil
        local m_targetPos = nil

        local m_currentPos = nil

        local m_tokensBlocking = {}
        local m_tokensBlockingLastThink = 0

        local m_fillLast = nil
        local m_colorLast = nil
        local m_nameLast = squad.name
        local m_numTokens = nil

        local m_tokenHovered = false
        local m_panelHovered = false
        local m_panelDragging = false
        local m_hoverState = false

        local m_fill = gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
            halign = "left",
            gradient = g_minionHealthGradient,
            bgcolor = "white",
            bgimage = "panels/square.png",

            thinkTime = 0.2,
            think = function(element)
                if dmhub.isDM == false and not viewerControlsSquad() and (dmhub.GetSettingValue("enemystambardisplay") == "none") then
                    sheetParent:Destroy()
                    return
                end

                if squad.name ~= m_nameLast then
                    m_nameLast = squad.name
                    sheetParent.sheet:FireEventTree("refreshColor")
                end

                local color = squad.color
                if color ~= m_colorLast then
                    m_colorLast = squad.color
                    color = core.Color(color)
                    element.selfStyle.hueshift = color.hue
                    sheetParent.sheet:FireEventTree("refreshColor")

                    --refresh the dividers too.
                    m_numTokens = nil
                end

                --check if we have tokens from this squad selected and if so, offer
                --to create a new squad that is split off.
                if dmhub.isDM and squad.damage_taken < squad.health_single then
                    local selectedTokens = dmhub.selectedOrPrimaryTokens
                    local foundNonMinion = false
                    local matchingMinions = 0
                    local monster_type = nil
                    local haveOtherSquadMembers = false
                    for i,tok in ipairs(selectedTokens) do
                        if not tok.properties.minion then
                            if foundNonMinion then
                                --can't have multiple non-minions
                                return
                            end

                            foundNonMinion = tok
                        elseif monster_type ~= nil and tok.properties.monster_type ~= monster_type then
                            --can't have minions from different squads
                            return
                        elseif tok.properties:MinionSquad() ~= squad.name then
                            if i == 1 then
                                --get one of the minion squads to be responsible for this button. The others bail out.
                                return
                            end
                            haveOtherSquadMembers = true
                        else
                            monster_type = tok.properties.monster_type
                            matchingMinions = matchingMinions + 1
                        end
                    end

                    if matchingMinions > 1 and (matchingMinions < squad.liveMinions or haveOtherSquadMembers) then
                        DrawSteelMinion.NewSquadButton(floorid, squad)
                    end
                end
            end,
        }


        local m_dividerPanel = gui.Panel{
            interactable = false,
            width = "100%",
            height = "100%",
        }

        local m_label = gui.Label{
            text = "",
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "center",
            textAlignment = "center",
            fontSize = 10,
            color = "white",
        }

        local m_skulls = {}

        local m_skullsPanel = gui.Panel{
            floating = true,
            width = m_BarWidth,
            height = 12,
            y = -12,
        }

        local m_UpdateHealth = function()
            local percent = (squad.maximum_health - squad.damage_taken) / squad.maximum_health
            if m_fillLast == nil then
                m_fillLast = percent
            else
                m_fillLast = m_fillLast + (percent - m_fillLast) * 0.1
            end

            m_fill.selfStyle.width = string.format("%.02f%%", m_fillLast * 100)

            if squad.damage_taken >= squad.maximum_health then
                m_label.text = "DEAD"
            else
                local display = dmhub.GetSettingValue("enemystambardisplay") or "none"
                if dmhub.isDM or viewerControlsSquad() or display == "val" then
                    m_label.text = string.format("%d/%d", round(squad.maximum_health - squad.damage_taken), squad.maximum_health)
                elseif display == "pct" then
                    m_label.text = string.format("%d%%", 100 * round((squad.maximum_health - squad.damage_taken) / squad.maximum_health))
                end
            end

            if #squad.tokens ~= m_numTokens then
                m_numTokens = #squad.tokens
                local color = core.Color(squad.color)
                color.v = color.v*0.35
                color = color.tostring
                local children = {}
                if m_numTokens > 1 then
                    for i=1,m_numTokens-1 do
                        children[i] = gui.Panel{
                            interactable = false,
                            width = 1,
                            height = "100%",
                            bgcolor = color,
                            bgimage = "panels/square.png",
                            halign = "left",
                            x = (i / m_numTokens)*m_BarWidth,
                        }
                    end
                end

                m_dividerPanel.children = children
            end

            local deadMinions = math.min(squad.liveMinions, math.floor(squad.damage_taken/squad.health_single))
            if #m_skulls ~= deadMinions then
                while #m_skulls < deadMinions do
                    m_skulls[#m_skulls+1] = gui.Panel{
                        floating = true,
                        width = 16,
                        height = 16,
                        valign = "center",
                        halign = "right",
                        bgimage = "ui-icons/Pin_Boss.png",
                        bgcolor = "red",
                    }
                end

                while #m_skulls > deadMinions do
                    m_skulls[#m_skulls]:DestroySelf()
                    m_skulls[#m_skulls] = nil
                end

                m_skullsPanel.children = m_skulls
            end

            local segmentWidth = m_BarWidth/squad.liveMinions
            for i=1,#m_skulls do
                m_skulls[i].x = 8 + segmentWidth*0.5 - i*segmentWidth
            end
        end

        m_UpdateHealth()

        local m_squadHud
        local m_squadEstablishedPos = nil
        local m_squadLastPos = nil
        local m_squadLastPosTime = nil

        local m_gradient = nil

        local m_linksPanel = gui.Panel{
            width = 1,
            height = 1,
            halign = "center",
            valign = "center",
            floating = true,
            interactable = false,
            showlinks = function(element)
                if m_gradient == nil then
                    m_gradient = gui.Gradient{
                        point_a = {x = 0, y = 0},
                        point_b = {x = 1, y = 0},
                        stops = {
                            {
                                position = 0,
                                color = "#ffffff00",
                            },
                            {
                                position = 0.5,
                                color = "#ffffffff",
                            },
                            {
                                position = 1,
                                color = "#ffffff00",
                            },
                        },
                    }
                end

                local children = {}
                local tokens = squad.tokens
                if squad.captain ~= nil then
                    tokens = shallow_copy_list(tokens)
                    tokens[#tokens+1] = squad.captain
                end
                for _,tok in ipairs(tokens) do
                    if tok.valid then
                        local link = gui.Panel{
                            interactable = false,
                            width = 3,
                            height = 1,
                            bgcolor = squad.color,
                            bgimage = "panels/square.png",
                            gradient = m_gradient,

                            valign = "center",
                            halign = "center",

                            styles = {
                                {
                                    selectors = {"create"},
                                    opacity = 0,
                                    transitionTime = 0.2,
                                },
                            },

                            thinkTime = 0.01,
                            think = function(element)
                                if tok.valid and m_currentPos ~= nil then
                                    local tokenPos = tok.pos
                                    tokenPos = game.GetFloor(floorid):AdjustParallaxPositionOnGround(tokenPos.x, tokenPos.y)

                                    local hudPos = m_currentPos
                                    hudPos = game.GetFloor(floorid):AdjustParallaxPositionOnGround(hudPos.x, hudPos.y)

                                    local dir = core.Vector2(hudPos.x - tokenPos.x, hudPos.y - tokenPos.y).unit

                                    local tokEdgePos = {
                                        x = tokenPos.x + dir.x * tok.radiusInTiles,
                                        y = tokenPos.y + dir.y * tok.radiusInTiles,
                                    }

                                    local dx = tokEdgePos.x - hudPos.x
                                    local dy = tokEdgePos.y - hudPos.y
                                    local angle = math.atan(dy, dx)
                                    element.selfStyle.rotate = math.deg(angle) + 90
                                    element.selfStyle.height = math.sqrt(dx*dx + dy*dy) * g_tileSize
                                    element.x = (tokEdgePos.x + hudPos.x) * g_tileSize / 2
                                    element.y = -(tokEdgePos.y + hudPos.y) * g_tileSize / 2

                                end
                            end,
                        }

                        element:FireEvent("think")

                        children[#children+1] = link
                    end
                end

                element.children = children
            end,

            hidelinks = function(element)
                element.children = {}
            end,
        }

        local m_lock = gui.Panel{
            classes = cond(squad.pos == nil, {"hidden"}),
            width = 8,
            height = 8,
            valign = "center",
            x = -12,
            floating = true,
            bgimage = "icons/icon_tool/icon_tool_30.png",
            bgcolor = "white",
            click = function(element)
                squad.pos = nil
                for _,tok in ipairs(squad.tokens) do
                    if tok.valid and tok.properties:has_key("squadpos") then
                        tok:ModifyProperties{
                            description = "Change squad layout",
                            undoable = false,
                            combine = true,
                            execute = function()
                                tok.properties.squadpos = nil
                            end,
                        }
                    end
                end
                element:SetClass("hidden", true)
            end,
            styles = {
                {
                    brightness = 0.7,
                },
                {
                    selectors = {"hover"},
                    brightness = 1.2,
                },
                {
                    selectors = {"press"},
                    brightness = 2,
                },
                {
                    selectors = {"hidden"},
                    hidden = 1,
                },
            },
        }

        m_squadHud =
            gui.Panel{
                width = m_BarWidth+28,
                height = 46,
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                flow = "vertical",
				bgcolor = "#000000ee",
				borderColor = "#000000ee",
				borderFade = true,
				borderWidth = 12,
                data = {
                    dragstart = nil,

                },
                draggable = true,
                dragging = function(element)
                    local pos = DeepCopy(element.data.dragstart)
                    pos.x = pos.x + (element.xdrag - pos.xdrag) / g_tileSize
                    pos.y = pos.y + -(element.ydrag - pos.ydrag) / g_tileSize
                    m_pos = pos
                end,
                beginDrag = function(element)
                    m_panelDragging = true
                    element.data.dragstart = DeepCopy(m_pos)
                    element.data.dragstart.xdrag = element.xdrag
                    element.data.dragstart.ydrag = element.ydrag
                    sheetParent.sheet:FireEventTree("highlight")
                end,
                drag = function(element)
                    m_panelDragging = false
                    local pos = DeepCopy(element.data.dragstart)
                    pos.x = pos.x + (element.xdrag - pos.xdrag) / g_tileSize
                    pos.y = pos.y + -(element.ydrag - pos.ydrag) / g_tileSize
                    pos.xdrag = nil
                    pos.ydrag = nil
                    squad.pos = pos

                    m_pos = DeepCopy(pos)
                    m_targetPos = DeepCopy(pos)
                    m_currentPos = nil

                    for _,tok in ipairs(squad.tokens) do
                        if tok.valid then
                            tok:ModifyProperties{
                                description = "Change squad layout",
                                undoable = false,
                                combine = true,
                                execute = function()
                                    tok.properties.squadpos = DeepCopy(pos)
                                end,
                            }
                        end
                    end

                    element:ScheduleEvent("highlight", 0.1)
                end,

                hover = function(element)
                    m_panelHovered = true
                    element:FireEvent("highlight")
                end,

                dehover = function(element)
                    m_panelHovered = false
                    element:FireEvent("highlight")
                end,

                highlight = function(element)
                    local newValue = m_tokenHovered or m_panelHovered or m_panelDragging
                    if newValue ~= m_hoverState then
                        m_hoverState = newValue
                        element:SetClassTree("highlight", m_hoverState)
                        m_linksPanel:FireEvent(cond(m_hoverState, "showlinks", "hidelinks"))
                    end
                end,

                gui.Panel{
                    bgimage = "panels/hud/crown.png",
                    bgcolor = squad.color,
                    width = 12,
                    height = 12,
                    halign = "center",
                    valign = "top",
                    floating = true,
                    create = function(element)
                        element:FireEvent("think")
                    end,
                    thinkTime = 0.5,
                    think = function(element)
                        element.selfStyle.opacity = cond(squad.hasCaptain, 1, 0)
                    end,
                },

                gui.Panel{
                    width = m_BarWidth,
                    height = 12,
                    valign = "bottom",
                    halign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = "black",

                    m_fill,
                    m_dividerPanel,
                    m_label,
                    m_skullsPanel,

                    thinkTime = 0.01,
                    think = function(element)
                        if floorid ~= dmhub.floorid then
                            sheetParent:Destroy()
                            return
                        end

                        local valid = false
                        for _,tok in ipairs(squad.tokens) do
                            if tok.valid and tok.floorid == floorid and tok.properties:has_key("_tmp_minionSquad") and tok.properties._tmp_minionSquad == squad then
                                valid = true
                            end
                        end

                        if not valid then
                            sheetParent:Destroy()
                            return
                        end

                        local highlight = false
                        local tokenHovered = dmhub.tokenHovered
                        if tokenHovered ~= nil and (tokenHovered.properties:try_get("_tmp_minionSquad") == squad or tokenHovered == squad.captain) then
                            highlight = true
                        end

                        tokenHovered = dmhub.currentToken
                        if tokenHovered ~= nil and (tokenHovered.properties:try_get("_tmp_minionSquad") == squad or tokenHovered == squad.captain) then
                            highlight = true
                        end

                        if highlight ~= m_tokenHovered then
                            m_tokenHovered = highlight
                            if (m_tokenHovered or m_panelHovered or m_panelDragging) ~= m_hoverState then
                                element.parent:FireEvent("highlight", m_hoverState)
                            end
                        end

                        if element.data.lastCalculate == nil or element.data.lastCalculate < dmhub.Time() - 0.5 then
                            element.data.lastCalculate = dmhub.Time()
                            element:FireEvent("calculate")
                        end

                        m_lock:SetClass("hidden", squad.pos == nil)

                        m_pos.x = m_pos.x + (m_targetPos.x - m_pos.x) * 0.1
                        m_pos.y = m_pos.y + (m_targetPos.y - m_pos.y) * 0.1

                        if m_currentPos == nil then
                            m_currentPos = {
                                x = m_pos.x,
                                y = m_pos.y,
                            }
                        else
                            m_currentPos.x = m_currentPos.x + (m_pos.x - m_currentPos.x) * 0.1
                            m_currentPos.y = m_currentPos.y + (m_pos.y - m_currentPos.y) * 0.1
                        end

                        local parallaxPos = game.GetFloor(floorid):AdjustParallaxPositionOnGround(m_currentPos.x, m_currentPos.y)

                        local parent = element.parent
                        parent.x = parallaxPos.x*g_tileSize
                        parent.y = -parallaxPos.y*g_tileSize

                        m_UpdateHealth()
                    end,

                    calculate = function(element)
                        local squadCenterPoint = nil

                        local xpos = 0
                        local ypos = 0
                        if squad.pos ~= nil then
                            xpos = squad.pos.x
                            ypos = squad.pos.y
                        else

                            local count = 0
                            for _,tok in ipairs(squad.tokens) do
                                if tok.valid then
                                    local pos = tok.pos
                                    xpos = xpos + pos.x
                                    ypos = ypos + pos.y
                                    count = count + 1
                                end
                            end

                            if count == 0 then
                                return
                            end

                            xpos = xpos / count
                            ypos = ypos / count

                            squadCenterPoint = {x = xpos, y = ypos}

                            if m_squadLastPos == nil or (m_squadLastPos.x ~= xpos or m_squadLastPos.y ~= ypos) then
                                if m_squadLastPos ~= nil then
                                    m_squadLastPosTime = dmhub.Time()
                                end
                                m_squadLastPos = {x = xpos, y = ypos}
                            end

                            local movementSettled = false

                            if m_squadEstablishedPos ~= nil and m_squadLastPosTime ~= nil and m_squadLastPosTime > dmhub.Time() - g_squadPanelMovementLag then
                                --wait until moving settles down before establishing a new position.
                                xpos = m_squadEstablishedPos.x
                                ypos = m_squadEstablishedPos.y
                            else
                                --movement has settled, so establish a new position.
                                m_squadEstablishedPos = {x = xpos, y = ypos}
                                m_squadLastPosTime = dmhub.Time()
                                movementSettled = true
                            end


                            if movementSettled and (m_tokensBlockingLastThink < dmhub.Time() - 0.5) then
                                m_tokensBlocking = {}
                                m_tokensBlockingLastThink = dmhub.Time()
                                local tokensBlocking = dmhub.GetTokens{
                                    position = {
                                        x = xpos,
                                        y = ypos,
                                        radius = 6,
                                    },
                                }

                                for _,tok in ipairs(tokensBlocking) do
                                    if tok.valid and tok.properties ~= nil then
                                        m_tokensBlocking[#m_tokensBlocking+1] = {
                                            x = tok.pos.x,
                                            y = tok.pos.y,
                                            radius = tok.radiusInTiles,
                                        }
                                    end
                                end
                            end

                            local blocked = false
                            for _,tok in ipairs(m_tokensBlocking) do
                                if math.abs(xpos - tok.x) < (tok.radius + 0.6) and math.abs(ypos - tok.y) < (tok.radius + 0.1) then
                                    blocked = true
                                end
                            end
                            
                            if blocked then
                                local directions = {{1,0},{-1,0},{0,1},{0,-1}}
                                for i=0,5 do
                                    local xx = xpos
                                    local yy = ypos

                                    for _,dir in ipairs(directions) do
                                        xpos = xx + dir[1]*i
                                        ypos = yy + dir[2]*i
                                        blocked = false
                                        for _,tok in ipairs(m_tokensBlocking) do
                                            if math.abs(xpos - tok.x) < (tok.radius + 0.6) and math.abs(ypos - tok.y) < (tok.radius + 0.1) then
                                                blocked = true
                                            end
                                        end
                                    end

                                    if blocked == false then
                                        break
                                    end

                                    xpos = xx
                                    ypos = yy
                                end
                            end

                        end

                        if m_pos == nil then
                            m_pos = {x = xpos, y = ypos}
                        end

                        --m_targetPos tracks where the hud wants to be. We compare to the new position
                        --and only move it if the new position is substantially better than our
                        --current target position.
                        if m_targetPos == nil or squadCenterPoint == nil then
                            m_targetPos = {x = xpos, y = ypos}
                        elseif m_targetPos.x ~= xpos or m_targetPos.y ~= ypos then
                            --see if the old position is blocked, in which case we should move to the new position.
                            local tokensBlocking = dmhub.GetTokens{
                                position = {
                                    x = m_targetPos.x,
                                    y = m_targetPos.y,
                                    radius = 6,
                                },
                            }

                            --calculate how spread out the squad is. Average distance from the center.
                            local oldDistance = 0
                            local newDistance = 0
                            local squadSpread = 0
                            local validTokens = 0
                            for _,tok in ipairs(squad.tokens) do
                                if tok.valid then
                                    squadSpread = squadSpread + math.sqrt(math.abs(tok.pos.x - squadCenterPoint.x) + math.abs(tok.pos.y - squadCenterPoint.y))
                                    oldDistance = oldDistance + math.sqrt(math.abs(tok.pos.x - m_targetPos.x) + math.abs(tok.pos.y - m_targetPos.y))
                                    newDistance = newDistance + math.sqrt(math.abs(tok.pos.x - squadCenterPoint.x) + math.abs(tok.pos.y - squadCenterPoint.y))
                                    validTokens = validTokens + 1
                                end
                            end

                            squadSpread = squadSpread / math.max(validTokens, 1)
                            oldDistance = oldDistance / math.max(validTokens, 1)
                            newDistance = newDistance / math.max(validTokens, 1)

                            for _,tok in ipairs(tokensBlocking) do
                                if math.abs(m_targetPos.x - tok.pos.x) < (tok.radiusInTiles + 0.6) and math.abs(m_targetPos.y - tok.pos.y) < (tok.radiusInTiles + 0.1) then
                                    oldDistance = 100000
                                    break
                                end
                            end


                            --see if the new position is substantially better than the
                            --old position. If so, move to the new position.
                            if oldDistance > newDistance + 1 + squadSpread*0.1 then
                                m_targetPos = {x = xpos, y = ypos}
                            end
                        end
                    end,
                },

                gui.Label{
                    text = squad.name,
                    color = squad.color,
                    width = m_BarWidth-16,
                    height = 12,
                    textAlignment = "center",
                    fontSize = 10,
                    minFontSize = 6,
                    editable = dmhub.isDM,
                    halign = "center",
                    valign = "top",
                    characterLimit = 24,
                    m_lock,
                    refreshColor = function(element)
                        element.text = squad.name
                        element.selfStyle.color = squad.color
                    end,
                    change = function(element)
                        local text = trim(element.text)
                        if text == "" then
                            element.text = squad.name
                            return
                        end

                        --make sure the new squad keeps a consistent color.
                        DrawSteelMinion.SetSquadColor(text, squad.color)
                        for _,tok in ipairs(squad.tokens) do
                            if tok.valid then
                                tok:ModifyProperties{
                                    description = "Set Squad",
                                    undoable = false,
                                    combine = true,
                                    execute = function()
                                        tok.properties.minionSquad = text
                                    end,
                                }
                            end
                        end

                    end,
                },
            }


        sheetParent.sheet =
        gui.Panel{
            width = 1,
            height = 1,
            halign = "center",
            valign = "center",
            blocksGameInteraction = false,

            styles = {
                gui.Style{
                    --worldspace = true,
                },
                gui.Style{
                    selectors = {"~highlight"},
                    transitionTime = 0.2,
                    opacity = 0.9,
                },
            },

            m_linksPanel,

            m_squadHud,

        }

        m_fill:FireEvent("think")
	end
end

local g_minionWithCaptainTableName = "minionWithCaptain"
DrawSteelMinion.withCaptainEffects = {}

--handle "with captain" traits.

---@param text string
---@return CharacterFeature
function DrawSteelMinion.GetWithCaptainEffect(text)
    if text == nil or text == false or text == "" then
        return nil
    end

    local result = DrawSteelMinion.withCaptainEffects[text]
    if result == nil then
        local traitsTemplates = dmhub.GetTable(g_minionWithCaptainTableName) or {}
        for key,template in pairs(traitsTemplates) do
            local trait = template:MatchMCDMMonsterTrait(nil, text, text)
            if trait ~= nil then
                result = DeepCopy(trait)
                for _,mod in ipairs(result.modifiers) do
                    mod.name = string.format("With Captain: %s", mod.name)
                end
            end
        end

        if result == nil then
            result = false
        end

        DrawSteelMinion.withCaptainEffects[text] = result
    end

    if result == false then
        return nil
    end

    return result
end

--grow any list of tokens to include all tokens in the containing squad.
function DrawSteelMinion.GrowTokensToIncludeSquads(tokens)
    local copied = false
    local TryAdd = function(tok)
        for _,t in ipairs(tokens) do
            if t == tok or t.charid == tok.charid then
                return
            end
        end

        if not copied then
            tokens = table.shallow_copy(tokens)
            copied = true
        end

        tokens[#tokens+1] = tok
    end

    for _,tok in ipairs(tokens) do
        if tok.valid and tok.properties:has_key("_tmp_minionSquad") then
            local squad = tok.properties._tmp_minionSquad
            if squad ~= nil and squad.tokens ~= nil then
                for _,sTok in ipairs(squad.tokens) do
                    if sTok.valid then
                        TryAdd(sTok)
                    end
                end

                if squad.captain ~= nil and squad.captain.valid then
                    TryAdd(squad.captain)
                end
            end
        end
    end

    return tokens
end

dmhub.RegisterEventHandler("refreshTables", function(keys)
    if keys ~= nil and (not keys[g_minionWithCaptainTableName]) then
        return
    end

    DrawSteelMinion.withCaptainEffects = {}
end)
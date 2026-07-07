local mod = dmhub.GetModLoading()

function GameHud:Think()
	if #self.interactionQueue > 0 and self:AvailableToInteract() then
		local f = self.interactionQueue[1]
		table.remove(self.interactionQueue, 1)
		f()
	end
end

function GameHud:QueueInteraction(f)
	self.interactionQueue[#self.interactionQueue+1] = f
end

--is the player currently available to interact with something that pops up?
function GameHud.AvailableToInteract(self)
	if self.dialog.sheet == nil then
		return false
	end
	return ActivatedAbility.IsCasting() == false and not self.dialog.sheet.modalDialog
end

function GameHud.ShowInventory(self, token, options)
	if token == nil then
		return
	end
	self.inventoryDialog.data.open(token, options)
end

function GameHud.ToggleInventory(self, token)
	self.inventoryDialog.data.toggleOpen(token)
end

function GameHud.Refresh(self)
	self.dialog.sheet:FireEventTree('refresh')
end

--function which can be called by dmhub to present a tooltip on the map.
function GameHud.ShowTooltipNearLoc(self, loc, text, options)
	options = options or {}
	self.dialog.sheet:FireEvent("tiletooltip", {
		loc = loc,
		text = text,
		halign = options.halign,
		valign = options.valign,
	})
	
end

--called by dmhub to clear map tooltips.
function GameHud.ClearMapTooltip(self)
	self.dialog.sheet.tooltip = nil
end

-------------------------------------------------------------------------------
-- Movement cross-section diagram.
--
-- A small side-on schematic shown inside the token-drag movement tooltip that
-- illustrates the vertical profile of the proposed move: terraced ground built
-- from per-tile altitudes, a square tile grid, walls climbed over or flown
-- over, the movement arrow, the mover's token avatar plus a ghost at the
-- resting spot, any other tokens the path crosses (red ring when passed
-- through), and a fall at the end of the move.
--
-- The diagram is rendered by a C#/Unity offscreen scene into a RenderTexture
-- (see MovementCrossSection.cs); the Lua side just asks the engine to build it
-- and displays the returned image key. dmhub.SetMovementCrossSection builds/
-- updates the scene and returns { image, width, height } (or nil for a move
-- with no drawable cross-section); dmhub.ClearMovementCrossSection releases it.
--
-- Driven entirely by the LuaPath in the "tiletooltip" event args: TokenMoving
-- adds movingToken/movingPath to the args it fires (see DSHud.lua). Events
-- without those fields (e.g. the ruler tool) just collapse the diagram.
-------------------------------------------------------------------------------

local g_diagramWidth = 300
local g_diagramHeight = 120

--The diagram never displays wider than this; a wider render texture is scaled
--down uniformly (x and y together) so tiles stay square on screen.
local g_diagramMaxWidth = 340

--A cheap identity for the proposed move so the diagram only rebuilds when the
--path actually changes, not every time the tooltip event fires.
local function DiagramPathSignature(token, path)
	local parts = {
		token.charid,
		path.movementType,
		tostring(path.valid),
		tostring(path.teleport),
		tostring(path.fallDistance),
	}

	local steps = path.steps
	if steps ~= nil then
		for _,step in ipairs(steps) do
			parts[#parts+1] = step.str .. "@" .. tostring(step.altitude)
		end
	end

	return table.concat(parts, "|")
end

--Extracts the vertical profile of the path. Returns nil when the path has no
--vertical interest (flat ground, no climbing/walls/falls and no other tokens
--encountered) or when it spans multiple floors (no single cross-section).
local function DiagramProfileFromPath(token, path)
	local steps = path.steps
	if steps == nil or #steps < 2 then
		return nil
	end

	local n = #steps
	for i = 2, n do
		if steps[i].floor ~= steps[1].floor then
			return nil
		end
	end

	local entries = {}
	for i = 1, n do
		local step = steps[i]
		local entry = {
			alt = step.altitude,
			ground = step.withGroundAltitude.altitude,
			flags = {},
		}

		if i > 1 then
			--path.steps is 1-based in lua; the engine's per-step tables are 0-based.
			local flags = path:GetStepFlags(i-1)
			if flags ~= nil then
				for _,f in ipairs(flags) do
					entry.flags[f] = true
				end
			end

			entry.climbWall = path:GetClimbOverWallHeight(i-1)
			entry.wall = path:GetStepWallHeight(i-1)
		end

		entries[i] = entry
	end

	--other tokens whose columns the path passes through, deduped so a token
	--occupying several path tiles gets one marker at the middle of its overlap
	--with the path.
	local othersByCharid = {}
	local others = {}
	for i = 1, n do
		local toks = game.GetTokensAtLoc(steps[i])
		if toks ~= nil then
			for _,tok in ipairs(toks) do
				if tok.charid ~= token.charid then
					local record = othersByCharid[tok.charid]
					if record == nil then
						record = {
							token = tok,
							alt = tok.loc.altitude,
							firstStep = i,
							lastStep = i,
							through = false,
						}
						othersByCharid[tok.charid] = record
						others[#others+1] = record
					else
						record.lastStep = i
					end

					--the path passes through this token's space when their
					--vertical extents overlap at this step; passing above or
					--below is conveyed by the marker's vertical position.
					local moverAlt = entries[i].alt
					if moverAlt < record.alt + 1 and record.alt < moverAlt + 1 then
						record.through = true
					end
				end
			end
		end
	end

	local interesting = #others > 0 or path.fallDistance > 0
	for i = 1, n do
		local e = entries[i]
		if e.ground ~= entries[1].ground or e.alt ~= entries[1].alt or
		   e.climbWall ~= nil or e.wall ~= nil or e.flags.Fall then
			interesting = true
		end
	end

	if not interesting then
		return nil
	end

	return {
		entries = entries,
		others = others,
	}
end

--Rebuilds the diagram from the current move by asking the engine to build the
--offscreen cross-section scene (see MovementCrossSection.cs) and displaying the
--returned render texture. The panel is sized to the render texture, scaled down
--uniformly to fit g_diagramMaxWidth so tiles stay square. Returns true if a
--diagram is shown, false if the move has no drawable cross-section (the caller
--collapses in that case).
local function DiagramRender(diagramPanel, token, path)
	local result = dmhub.SetMovementCrossSection{token = token, path = path}
	if result == nil then
		diagramPanel:SetClass("collapsed", true)
		dmhub.ClearMovementCrossSection()
		return false
	end

	local scale = 1
	if result.width > g_diagramMaxWidth then
		scale = g_diagramMaxWidth / result.width
	end

	diagramPanel:SetClass("collapsed", false)
	diagramPanel.selfStyle.width = result.width * scale
	diagramPanel.selfStyle.height = result.height * scale
	diagramPanel.selfStyle.bgcolor = "white"
	diagramPanel.bgimage = result.image
	return true
end

--The diagram panel that lives inside the map tooltip. Updates (or collapses)
--in response to the "args" event fired on the tooltip tree by the tiletooltip
--handler below.
local function CreateMovementDiagramPanel()
	return gui.Panel{
		classes = {"collapsed"},
		width = g_diagramWidth,
		height = g_diagramHeight,
		halign = "center",
		flow = "none",
		interactable = false,
		bgimage = "panels/square.png",
		bgcolor = "#000000aa",
		cornerRadius = 4,
		vmargin = 2,
		styles = {
			{
				selectors = {"collapsed"},
				collapsed = 1,
			},
		},
		data = {
			signature = nil,
		},
		destroy = function(element)
			--the tooltip (and this panel) is torn down by FinishTokenMoving; release
			--the offscreen render texture so nothing stays resident while idle.
			dmhub.ClearMovementCrossSection()
		end,
		args = function(element, args)
			if args == nil or args.movingToken == nil or args.movingPath == nil or
			   not dmhub.GetSettingValue("showmovementcrosssection") then
				element.data.signature = nil
				element:SetClass("collapsed", true)
				dmhub.ClearMovementCrossSection()
				return
			end

			local sig = DiagramPathSignature(args.movingToken, args.movingPath)
			if sig == element.data.signature then
				return
			end
			element.data.signature = sig

			--DiagramProfileFromPath is the interest gate (skips flat moves and
			--multi-floor paths); the C# harness re-derives what it needs to draw.
			local profile = DiagramProfileFromPath(args.movingToken, args.movingPath)
			if profile == nil then
				element:SetClass("collapsed", true)
				dmhub.ClearMovementCrossSection()
				return
			end

			DiagramRender(element, args.movingToken, args.movingPath)
		end,
	}
end

--functions called by dmhud to indicate that a token is moving or has finished moving.
--[==[ DEAD_CODE - overridden by Draw Steel UI\DSHud.lua:4
function GameHud.TokenMoving(self, token, path)
	
	local diagonals = dmhub.GetSettingValue("truediagonals") and math.floor(path.numDiagonals/2) or 0

	local distance = path.numSteps + diagonals
	distance = distance * dmhub.FeetPerTile

    local forcedText = ""

    if path.forced then
        forcedText = "Forced "
    end

	local text = string.format('%sMovement: %s %s', forcedText, MeasurementSystem.NativeToDisplayString(distance), string.lower(MeasurementSystem.UnitName()))

    local altitudeDelta = path.destination.altitude - path.origin.altitude
    if altitudeDelta < 0 then
        text = string.format("%s (%d elevation)", text, round(altitudeDelta))
    elseif altitudeDelta > 0 then
        text = string.format("%s (+%d elevation)", text, round(altitudeDelta))
    end

    if path.forced then
        if path.collisionSpeed > 0 then
            text = string.format("%s\n<color=#ff0000>Pushing %d tiles, inflicting %d damage.</color>", text, path.forcedMovementTotalDistance, path.collisionSpeed)
        end

        if token.properties:Stability() > 0 then
            text = string.format("%s\nNote: This creature has <b>%d stability</b>", text, token.properties:Stability())
        end
    end

	local walkAndSwim = false

	if token.properties ~= nil then
		if path.mount then
			text = string.format("%s\nMounting or dismounting takes half of movement for the round.", text)
		end

		local moveType = token.properties:CurrentMoveType()
		if moveType == "walk" or moveType == "swim" then

			local waterSteps = math.floor(path.waterSteps) * dmhub.FeetPerTile
			if waterSteps > 0 and waterSteps < distance then
				text = string.format("%s; swim %s %s", text, MeasurementSystem.NativeToDisplayString(waterSteps), string.lower(MeasurementSystem.UnitName()))
				walkAndSwim = true
			end

			local difficultDistance = math.floor(path.difficultSteps) * dmhub.FeetPerTile
			if difficultDistance == distance and distance > 0 then
				text = string.format("%s; all in difficult terrain", text)
			elseif difficultDistance > 0 then
				text = string.format("%s; %s %s in difficult terrain", text, MeasurementSystem.NativeToDisplayString(difficultDistance), string.lower(MeasurementSystem.UnitName()))
			end

			local squeezeDistance = math.floor(path.squeezeSteps) * dmhub.FeetPerTile
			if squeezeDistance == distance and distance > 0 then
				text = string.format("%s; squeezing through a tight space", text)
			elseif squeezeDistance > 0 then
				text = string.format("%s; %s %s squeezing through tight spaces", text, MeasurementSystem.NativeToDisplayString(squeezeDistance), string.lower(MeasurementSystem.UnitName()))
			end
		end
	end

	if path.teleport then
		--completely different rules for teleporting.
		--make an 'approximated pythag theorem' with nice round numbers.
		local xdelta = math.abs(path.origin.x - path.destination.x)
		local ydelta = math.abs(path.origin.y - path.destination.y)
		local larger = cond(xdelta >= ydelta, xdelta, ydelta)
		local smaller = cond(xdelta >= ydelta, ydelta, xdelta)
		distance = (larger + math.floor(smaller*0.5))*5
		text = string.format('Teleport: %s %s', MeasurementSystem.NativeToDisplayString(distance), string.lower(MeasurementSystem.UnitName()))
	end

	local floorDelta = nil

	if path.destination.floor ~= token.loc.floor then
		local diff = token.loc:FloorDifference(path.destination)
		floorDelta = diff
		if diff == 1 then
			text = text .. ' (+1 Floor)'
		elseif diff == -1 then
			text = text .. ' (-1 Floor)'
		else
			local prefix = '+'
			if diff < 0 then
				prefix = '-'
				diff = -diff
			end

			text = text .. ' (' .. prefix .. tostring(diff) .. ' Floors)'
		end
	end

	local creature = token.properties
	if creature ~= nil and (not path.teleport) and (not path.forced) then
		text = string.format('%s\n%s %s %s %s per round', text, creature.GetTokenDescription(token), string.lower(creature:CurrentMoveTypeInfo().tense), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(creature:CurrentMoveType())), string.lower(MeasurementSystem.UnitName()))

		if walkAndSwim then
			local otherMode = "walk"
			if creature:CurrentMoveType() == "walk" then
				otherMode = "swim"
			end

			text = string.format("%s\n%s %s %s %s per round", text, creature.GetTokenDescription(token), string.lower(creature.movementTypeById[otherMode].tense), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(otherMode)), string.lower(MeasurementSystem.UnitName()))
		end

		local distMoved = creature:DistanceMovedThisTurn()
		if distMoved > 0 then
			text = string.format("%s\nAlready moved %s %s this turn.", text, MeasurementSystem.NativeToDisplayString(distMoved*dmhub.FeetPerTile), string.lower(MeasurementSystem.UnitName()))
		end
	end

	if (not path.valid) and (not path.teleport) and (not path.forced) and dmhub.isDM then
		text = string.format('%s\nNo path found, move through walls or hold shift to teleport.', text)
	end

	--calculate how it should be aligned, trying to avoid the tooltip going over the arrow or the creature.
	local halign = 'center'
	local valign = 'center'


	local dest = path.destination

	if dest.x > path.origin.x then
		valign = 'top'
	end

	if dest.x < path.origin.x then
		valign = 'top'
	end

	if dest.y > path.origin.y then
		valign = 'top'
	end

	if dest.y < path.origin.y then
		valign = 'bottom'
	end

	--for large tokens make sure the tooltip appears well off the creature.
	local locsOccupied = token:LocsOccupyingWhenAt(dest)
	if locsOccupied ~= nil and #locsOccupied > 1 then
		for _,loc in ipairs(locsOccupied) do
			if valign == "top" and loc.y > dest.y then
				dest = loc
			end

			if valign == "bottom" and loc.y < dest.y then
				dest = loc
			end
		end
		
	end

	self.dialog.sheet:FireEvent("tiletooltip", {
		loc = dest,
		text = text,
		halign = halign,
		valign = valign,
		floorDelta = floorDelta,
	})
end
--]==]

function GameHud.FinishTokenMoving(self)
	self.dialog.sheet.tooltip = nil
end

--function called by DMHub to indicate that a Loot object is being edited.
function GameHud.EditLoot(self, object)
	local lootobj = object:GetComponent("Loot")
	if lootobj == nil then
		dmhub.Debug('Could not find loot')
		return
	end
	self.inventoryDialog.data.open(lootobj, { isobject = true, isshop = lootobj.shop, showBasic = true })
end

--function called by DMHub to indicate that a Loot object is being looted by a player.
function GameHud.LootContainer(self, token, object)
	local lootobj = object:GetComponent("Loot")
	if lootobj == nil or token == nil then
		dmhub.Debug('Could not find loot')
		return
	end

	if lootobj.instantLoot then
		GameHud.LootAll(lootobj, token)
		if lootobj.destroyOnEmpty then
			lootobj:DestroyObject()
		end
		return
	end

	self.inventoryDialog.data.open(token, {})
	self.tradeInventoryDialog.data.open(lootobj, { isobject = true, isshop = lootobj.shop, title = cond(lootobj.shop, 'Shop', lootobj.objectInstance.description), tradewith = token })
	
end

setting{
	id = "showtips",
	default = true,
	storage = "preference",
}

--Map of tip-id -> true for tips the local user has learned/dismissed.
--Kept Lua-side (not via tutorial.*) so /tipsclear can wipe it in one call.
setting{
	id = "tipsLearned",
	default = {},
	storage = "preference",
}

setting{
	id = "toolbarplayerconfig",
	default = {},
	storage = "preference",
}

setting{
	id = "toolbargmconfig",
	default = {},
	storage = "preference",
}

function GameHud:CreateToolbarPanel()
    local resultPanel

	local settingName = cond(dmhub.isDM, "toolbargmconfig", "toolbarplayerconfig")

	local SerializeToolbar

	local buttons = {}

	local CreateToolbarButton = function(item)
		
		local monitorEventGuid = nil

		local itemName = item.name
		local geticon = item.geticon
		local getdisabled = item.getdisabled
		local button
		button = gui.Button{
			classes = {"sizeM"},
			icon = item.icon,
			monitor = item.setting,
			events = {
				destroy = function()
					dmhub.DeregisterEventHandler(monitorEventGuid)
				end,
				monitor = function(element)
					if item.setting ~= nil then
						button:SetClassTree("selected", dmhub.GetSettingValue(item.setting))
					end
				end,
				create = function(element)
					if geticon ~= nil then
						button:FireEventTree("seticon", geticon())
					end

					if getdisabled ~= nil then
						button:SetClassTree("disabled", getdisabled())
					end
				end,
				press = function()
					local info = Commands.GetCommandInfo(itemName)
					if info ~= nil and info.click ~= nil then
						info.click()
					end
				end,
				popupPositioning = "panel",
				linger = function(element)
					local info = Commands.GetCommandInfo(itemName)
					local text = itemName
					if info ~= nil then
						if info.gettext ~= nil then
							text = info.gettext()
						end

						if info.bind ~= nil then
							text = string.format("%s <color=#999999>(%s)", text, info.bind)
						end
					end
					gui.Tooltip(text)(element)
				end,
				rightClick = function(element)
					if dmhub.GetSettingValue("uilocked") then
						return
					end
					local menuItems = {
						{
							text = "Remove from toolbar",
							click = function()
								element.popup = nil
								local newButtons = {}
								for _,b in ipairs(buttons) do
									if b ~= element then
										newButtons[#newButtons+1] = b
									end
								end
								buttons = newButtons
								resultPanel:FireEvent("update")
								SerializeToolbar()
							end,
						},
						{
							text = "Reset Toolbar",
							click = function()
								element.popup = nil
								dmhub.ResetSetting(settingName)
							end,
						},
					}

					element.popup = gui.Panel{
						width = "auto",
						height = "auto",
						halign = "right",
						valign = "bottom",
						gui.ContextMenu{
							width = 300,
							x = -element.renderedWidth,
							entries = menuItems,
							click = function()
								element.popup = nil
							end,
						}
					}
				end,
			},
			data = {
				name = item.name,
			},
		}

		if item.setting ~= nil then
			button:SetClassTree("selected", dmhub.GetSettingValue(item.setting))
		end

		if item.monitorEvent ~= nil then
			monitorEventGuid = dmhub.RegisterEventHandler(item.monitorEvent, function()
				button:FireEvent("create")
			end)
		end

		return button
	end

	SerializeToolbar = function()
		local doc = {}
		for _,button in ipairs(buttons) do
			doc[#doc+1] = button.data.name
		end

		dmhub.SetSettingValue(settingName, doc)
	end

	local DeserializeToolbar = function()
		buttons = {}
		local menuItems = LaunchablePanel.GetMenuItems()
		local doc = dmhub.GetSettingValue(settingName)
		for _,itemName in ipairs(doc) do
			for _,item in ipairs(menuItems) do
				if item.name == itemName then
                    buttons[#buttons+1] = CreateToolbarButton(item)
				end
			end
		end
	end

	DeserializeToolbar()

    local addButton = gui.Button{
		classes = {"sizeM"},
        icon = "ui-icons/Plus.png",
		popupPositioning = "panel",

		monitor = "uilocked",

		events = {

			create = function(element)
				element:SetClass("collapsed", dmhub.GetSettingValue("uilocked") or #buttons >= 8)
			end,

			monitor = function(element)
				element:FireEvent("create")
			end,

			click = function(element)
				if element.popup ~= nil then
					element.popup = nil
					return
				end

				local menuItems = LaunchablePanel.GetMenuItems()
				local items = {}
				for _,item in ipairs(menuItems) do
					if item.icon then
						local itemCopy = DeepCopy(item)
						local fn = item.click
						itemCopy.disabled = false
						itemCopy.bind = nil
						itemCopy.click = function()
							buttons[#buttons+1] = CreateToolbarButton(itemCopy)

							SerializeToolbar()

							resultPanel:FireEvent("update")
						end

						items[#items+1] = itemCopy
					end
				end

				element.popup = gui.Panel{
					width = "auto",
					height = "auto",
					halign = "right",
					valign = "bottom",
					gui.ContextMenu{
						width = 300,
						x = -element.renderedWidth,
						entries = items,
						click = function()
							element.popup = nil
						end,
					}
				}
			end,

			rightClick = function(element)
				local menuItems = {
					{
						text = "Reset Toolbar",
						click = function()
							element.popup = nil
							dmhub.ResetSetting(settingName)
						end,
					},
				}

				element.popup = gui.Panel{
					width = "auto",
					height = "auto",
					halign = "right",
					valign = "bottom",
					gui.ContextMenu{
						width = 300,
						x = -element.renderedWidth,
						entries = menuItems,
						click = function()
							element.popup = nil
						end,
					}
				}

			end,
		},
    }

    resultPanel = gui.Panel{
        width = "378",
        height = 44,
		x = -6,
		y = -4,
		margin = 0,
        flow = "horizontal",
		monitor = settingName,

        styles = {
			{
				classes = {"hudIconButton"},
				width = 44,
				height = 44,
				hmargin = 2,
				valign = "center",
			}
		},

		events = {
			monitor = function(element)
				DeserializeToolbar()
				element:FireEvent("update")
			end,

			update = function()
				local children = {}
				for _,button in ipairs(buttons) do
					children[#children+1] = button
				end
				children[#children+1] = addButton
				resultPanel.children = children

				addButton:FireEvent("create")
			end,
		},
        addButton,
    }

	resultPanel:FireEvent("update")

    return resultPanel
end

function GameHud:Docks()
    local result = {}
    result[#result+1] = rawget(self, "leftDock")
    result[#result+1] = rawget(self, "rightDock")
    result[#result+1] = rawget(self, "floatingDock")
    return result
end

local g_presentableDialogs = {}

GameHud.instance = false

local function CreateLobbyHud(dialog, tokenInfo)
	local gamehud = GameHud.new{
		dialog = dialog,
		tokenInfo = tokenInfo,
		openInventoryDialogs = {},
		interactionQueue = {},
	}

	GameHud.instance = gamehud

	local mainDialogPanel = gamehud:MainDialogPanel()

    local m_recordedPopup = nil

	local parentPanel = gui.Panel{
		styles = Styles.Default,
		selfStyle = {
			width = dialog.width,
			height = dialog.height,
		},
		thinkTime = 0.1,

		events = {
			think = function(element)
				gamehud:Think()

                m_recordedPopup = element.popup
			end,
			escape = function(element)
				gui.SetFocus(nil)
			end,

			--if this ends up as a host for popups it clears them if clicked.
			press = function(element)
				if element.popup ~= nil and element.popup == m_recordedPopup then
					element.popup = nil
				end
			end,

			refreshResolution = function(element)
				element.selfStyle.width = dialog.width
				element.selfStyle.height = dialog.height
			end,
		},

		children = {

			gamehud:CreateDocumentsPanel(),
			mainDialogPanel,
			gamehud:ModalDialogPanel(),
			gamehud:CreatePopupPanel(),

			gamehud:ConnectionStatusPanel(),
		}
	}

	gamehud.parentPanel = parentPanel

	dialog.sheet = parentPanel

    return gamehud
end

function GameHud:CreateAdventureDocumentsManager()
    local resultPanel

    local m_docs = nil

    --a dummy panel to monitor changes to the adventure documents.
    resultPanel = gui.Panel{
        floating = true,
        width = 1,
        height = 1,

        monitorGame = GetCurrentAdventuresDocument().path,
        refreshGame = function(element)
            local doc = GetCurrentAdventuresDocument()
            local docs = doc.data or {}
            if dmhub.DeepEqual(m_docs, docs) then
                return
            end

            m_docs = DeepCopy(docs)

            local documentids = {}
            for docid,info in pairs(m_docs) do
                if docid ~= "meta" then
                    documentids[#documentids+1] = docid
                end
            end

            table.sort(documentids, function(a,b)
                local ordera = m_docs[a] and m_docs[a].order or 9999
                local orderb = m_docs[b] and m_docs[b].order or 9999
                if ordera == orderb then
                    return a < b
                end
                return ordera < orderb
            end)

            print("AdventureDoc:: MONITOR", docs, "->", documentids)

            local meta = m_docs["meta"] or {
                icon = "panels/drawsteel/delian-tomb.png",
                name = "Delian Tomb",
            }

            TopBar.SetAdventureDocuments(meta, documentids)
        end,

        create = function(element)
            element:FireEvent("refreshGame")
        end,

        destroy = function(element)
            local meta = m_docs["meta"] or {
                icon = "panels/drawsteel/delian-tomb.png",
                name = "Delian Tomb",
            }
            TopBar.SetAdventureDocuments(nil, {})
            print("ADVENTURE:: DESTROY DOC")
        end,
    }

    return resultPanel
end

GameHud.InvalidateGameHud = function()

dmhub.CreateGameHud = function(dialog, tokenInfo)

    if dmhub.isLobbyGame then
        return CreateLobbyHud(dialog, tokenInfo)
    end

	local gamehud = GameHud.new{
		dialog = dialog,
		tokenInfo = tokenInfo,
		openInventoryDialogs = {},
		interactionQueue = {},
	}

	GameHud.instance = gamehud


	gamehud.rollDialog = gamehud:CreateRollDialog()

	gamehud.inventoryDialog = gamehud:CreateInventoryDialog{
		rearrange = true, --the user can rearrange the items in the inventory by dragging it.
		equipment = true,
		currency = false, --switch this to true if we want to enable currencies.
		numRows = 6,
		numCols = 8,
		dialogWidth = 650,
	}
	gamehud.basicInventoryDialog = gamehud:CreateInventoryDialog{
		title = 'Available Items',
		basicInventory = true,
		tooltipAlign = 'right',
	}
	gamehud.basicInventoryDialog.x = 600

	gamehud.tradeInventoryDialog = gamehud:CreateInventoryDialog{
		title = 'Trade',
		tradeInventory = true,
		tooltipAlign = 'right',
		currency = false, --switch this to true if we want to enable currencies.
	}
	gamehud.tradeInventoryDialog.x = 600

	gamehud.createItemDialog = gamehud:CreateAddItemDialog{

	}

	-- Fullscreen host for the shop/inventory screen. CreateShopScreen reads
	-- its host's .data.dialog for sizing and parents the screen here.
	-- interactable = false so the empty host does not eat clicks to the map;
	-- the shop screen child is interactable in its own right.
	gamehud.shopPanel = gui.Panel{
		id = "shop-screen-panel",
		width = "100%",
		height = "100%",
		halign = "center",
		valign = "center",
		interactable = false,
		data = { dialog = dialog },
	}

	local g_settingMapTooltips = setting{
		id = "maptooltips",
		default = true,
		storage = "preference",
	}

	local mainDialogPanel = gamehud:MainDialogPanel()

	mainDialogPanel:AddChild(gamehud.basicInventoryDialog)
	mainDialogPanel:AddChild(gamehud.tradeInventoryDialog)
	mainDialogPanel:AddChild(gamehud.inventoryDialog)

	mainDialogPanel:AddChild(gamehud.createItemDialog)

	local presentDialogDoc = mod:GetDocumentSnapshot("presentdialog")

	local m_tilelabel = nil
	local m_tiletooltip = nil

	--the dialog info that we have read from the cloud.
	local m_presentedDialog = nil
	local m_presentedDialogArgs = nil

    gamehud.GetCurrentlyPresentedDialog = function()
        return m_presentedDialogArgs
    end


	--the dialog info that we have written to the cloud.
	local m_presentDialogParentElement = nil
	local m_presentDialogUpdateTime = nil

    local m_recordedPopup = nil

	local parentPanel = gui.Panel({
		styles = Styles.Default,
		selfStyle = {
			width = dialog.width,
			height = dialog.height,
		},
		thinkTime = 0.1,

		monitorGame = presentDialogDoc.path,

		events = {
			think = function(element)
				gamehud:Think()

                m_recordedPopup = element.popup
			end,
			escape = function(element)
				gui.SetFocus(nil)
			end,

			--if this ends up as a host for popups it clears them if clicked.
			press = function(element)
				if element.popup ~= nil and element.popup == m_recordedPopup then
					element.popup = nil
				end
			end,

			presentDialog = function(element, parentElement, dialog, args, livedata)
				m_presentDialogParentElement = parentElement
				m_presentedDialog = parentElement
				m_presentedDialogArgs = {dialog = dialog, args = args}

                local args = DeepCopy(m_presentedDialogArgs)

                local dialogInfo = g_presentableDialogs[dialog]
                if dialogInfo ~= nil and not dialogInfo.keeplocal then
                    m_presentedDialog = nil
                    m_presentedDialogArgs = nil
                end

				local doc = mod:GetDocumentSnapshot("presentdialog")
				doc:BeginChange()
				doc.data.dialog = args
                doc.data.livedata = livedata
				doc.data.timestamp = ServerTimestamp()
				doc:CompleteChange("Present dialog")

				m_presentDialogUpdateTime = dmhub.Time()
			end,

			clearPresentDialog = function(element)

				local doc = mod:GetDocumentSnapshot("presentdialog")
				doc:BeginChange()
				doc.data.dialog = nil
				doc:CompleteChange("Clear dialog")
			end,

			--update the presentDialogDoc.
			refreshGame = function(element)
				local doc = mod:GetDocumentSnapshot("presentdialog")
				
				local data = doc.data
				--if TimestampAgeInSeconds(doc.timestamp) > 12 then
				--	data = {}
				--end

				if m_presentedDialog ~= nil and ((not m_presentedDialog.valid) or not dmhub.DeepEqual(m_presentedDialogArgs, data.dialog)) then
                    if m_presentedDialog.valid and (not m_presentedDialog.data.persistAfterPresentation) then
					    m_presentedDialog:FireEventTree("closePanel")
					    m_presentedDialog:DestroySelf()
                    end
					m_presentedDialog = nil
					m_presentedDialogArgs = nil
				end

				if data.dialog ~= nil then
                    if data.dialog.args.ttl ~= nil and TimestampAgeInSeconds(data.timestamp) > data.dialog.args.ttl then
                        return
					end

                    if data.dialog.args.mapid ~= nil and data.dialog.args.mapid ~= game.currentMapId then
                        return
                    end

					if m_presentedDialog ~= nil and m_presentedDialog.valid and dmhub.DeepEqual(m_presentedDialogArgs, data.dialog) then
						return
					end

					m_presentedDialogArgs = DeepCopy(data.dialog)
                    local dialogInfo = g_presentableDialogs[m_presentedDialogArgs.dialog]
                    if dialogInfo ~= nil then
                        m_presentedDialog = dialogInfo.create(m_presentedDialogArgs.args)
                        if m_presentedDialog ~= nil then
                            GameHud.instance.documentsPanel:AddChild(m_presentedDialog)
                        end
					elseif LaunchablePanel.LaunchPanelByName(data.dialog.dialog, data.dialog.args) then
						m_presentedDialog = gui.GetFocus()
					end
				end

			end,

			refreshResolution = function(element)
				element.selfStyle.width = dialog.width
				element.selfStyle.height = dialog.height
			end,

			tiletooltip = function(element, args)
				if not g_settingMapTooltips:Get() then
					return
				end

				local loc = args.loc
				local text = args.text

				local halign = args.halign or 'right'
				local valign = args.valign or 'top'

				if m_tiletooltip ~= nil and m_tiletooltip == element.tooltip then
					m_tilelabel.text = text
					m_tiletooltip.selfStyle.halign = halign
					m_tiletooltip.selfStyle.valign = valign
					m_tiletooltip:FireEventTree("args", args)
					element:FloatTooltipNearTile(loc, m_tiletooltip)
					return
				end

				m_tilelabel = gui.Label{
							text = text,
							bgimage = 'panels/square.png',
							destroy = function(element)
								if m_tilelabel == element then
									m_tilelabel = nil
									m_tiletooltip = nil
								end
							end,
							styles = {
								{
									fontSize = '50%',
									color = 'white',
									width = 'auto',
									height = 'auto',
									maxWidth = 300,
								}
							},
						}
					
				
				local floorDeltaArrow = nil
                if (args.floorDelta or 0) ~= 0 then
                    floorDeltaArrow = gui.Panel{
                        styles = {
                            {
                                selectors = {"collapsed"},
                                collapsed = 1,
                            }
                        },
                        width = 212*0.25,
                        height = 217*0.25,
                        bgimage = "ArrowUpLevel.webm",
                        bgcolor = "white",
                        scale = {x = 1, y = cond((args.floorDelta or 0) > 0, 1, -1)},
                        args = function(element, args)
                            element.selfStyle.scale = {x = 1, y = cond((args.floorDelta or 0) > 0, 1, -1)}
                            element:SetClass("collapsed", (args.floorDelta or 0) == 0)
                        end,
                    }
                end

				element:FloatTooltipNearTile(loc,
					gui.TooltipFrame(
						gui.Panel{
							flow = "vertical",
							width = "auto",
							height = "auto",
							gui.Panel{
								flow = "horizontal",
								width = "auto",
								height = "auto",
								halign = "center",
								floorDeltaArrow,
								m_tilelabel,
							},
							CreateMovementDiagramPanel(),
						},
						{
							interactable = false,
							halign = halign,
							valign = valign,
						}
					)
				)

				m_tiletooltip = element.tooltip

				--let the diagram (and the floor arrow) see the initial args;
				--on reuse the FireEventTree above keeps them updated.
				m_tiletooltip:FireEventTree("args", args)

			end,
		},

		children = {
            gamehud:CreateAdventureDocumentsManager(),
		    gamehud:CreateInitiativeBar(tokenInfo),
			gamehud:CreateShapesLayer(),

			gamehud:RequireRollListenerPanel(),
			FullscreenDisplay.Create{belowui = true},
			--gamehud:CreateSidePanel(),
			gamehud:CreateActionBar(dialog, tokenInfo),
			gamehud:CreateReactionBar(dialog, tokenInfo),
			--gamehud:CreateSessionsPanel(),
			--gamehud:CreateChatPanel(),
			gamehud:CreateFrozenLabel(),
			gamehud:CreateDocks(),
            gamehud:CreateAbilityDisplayPanel(),
            gamehud:CreateStandaloneRollHost(),
			gamehud:CreateDocumentsPanel(),
			mainDialogPanel,
			gamehud.shopPanel,
			gamehud:ModalDialogPanel(),
			gamehud:CreatePopupPanel(),
			gamehud:CreateRollResultPanel(),
			gamehud.rollDialog,

			FullscreenDisplay.Create{belowui = false},

			DramaticBanner.Create(),

			DSVictoryScreen.Create(),

			gamehud:CreateTipBanner(),

			gamehud:ConnectionStatusPanel(),
		}
	})

	gamehud.parentPanel = parentPanel

	dialog.sheet = parentPanel

	--if a modding merge has occurred, display info about it here.
	if dmhub.modMergeInfo ~= nil then
		local msg = 'DMHub has been updated, including some lua files which you have changed in your mod.'
		if dmhub.modMergeInfo.conflicts == nil then
			msg = msg .. ' Your changes have been automatically merged with the changes made in DMHub. Happy modding!'
		else
			msg = msg .. ' Unfortunately, we had some trouble automatically merging the changes in these file(s): '
			for i,fname in ipairs(dmhub.modMergeInfo.conflicts) do
				msg = msg .. fname .. ' '
			end

			msg = msg .. '\n\nPlease review these files to make sure everything is in proper order. You can search for the text CONFLICT IN CHANGES in these files to find areas where we had trouble merging the changes automatically. Happy modding!'
		end
		gamehud:ModalMessage{
			title = "Mod Merge",
			message = msg,
		}

		dmhub.ClearMergeInfo()
	end

	return gamehud
end

end

GameHud.InvalidateGameHud()

---@param args {id: string, create: function, keeplocal: nil|boolean}
function GameHud.RegisterPresentableDialog(args)
    g_presentableDialogs[args.id] = args
end

function GameHud:CreateAbilityDisplayPanel()
    self.abilityDisplayPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        height = "100%",
        width = 360,
        rmargin = 364,
        halign = "right",
        valign = "center",
        interactable = false,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if self.abilityDisplayPanel ~= nil and self.abilityDisplayPanel.valid then
            self.abilityDisplayPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    self:InitAbilityDisplayPanel(self.abilityDisplayPanel)

    return self.abilityDisplayPanel
end

--[==[ DEAD_CODE - overridden by Timeline\AbilitySidebar.lua:1080
function GameHud:InitAbilityDisplayPanel(abilityDisplayPanel)
end
--]==]

--Host for the embedded roll dialog when there is no ability context.
--Positioned on the right like the ability sidebar; real init lives in
--Timeline\AbilitySidebar.lua.
function GameHud:CreateStandaloneRollHost()
    self.standaloneRollHostPanel = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = 540,
        height = "auto",
        rmargin = 364,
        halign = "right",
        valign = "center",
        flow = "vertical",
        interactable = true,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if self.standaloneRollHostPanel ~= nil and self.standaloneRollHostPanel.valid then
            self.standaloneRollHostPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    self:InitStandaloneRollHost(self.standaloneRollHostPanel)

    return self.standaloneRollHostPanel
end

--Stub overridden by Timeline\AbilitySidebar.lua.
function GameHud:InitStandaloneRollHost(panel)
end

--return the presented dialog doc, if it exists and matches the given dialogid.
function GameHud.GetPresentDialogDoc(dialogid)
    local result = mod:GetDocumentSnapshot("presentdialog")
    if result == nil or result.data == nil or result.data.dialog == nil or result.data.dialog.dialog ~= dialogid then
        return nil
    end
    return result
end

function GameHud.PresentDialogToUsers(parentElement, dialogid, args, livedata)
	GameHud.instance.parentPanel:FireEvent("presentDialog", parentElement, dialogid, args, livedata)
end

function GameHud.HidePresentedDialog()
    GameHud.instance.parentPanel:FireEventTree("clearPresentDialog")
end

function GameHud:StatusText()
	return gui.Label{
		width = "100%",
		height = 20,
		textAlignment = "left",
		fontSize = 14,
		halign = "left",
		valign = "bottom",
		hmargin = 8,
		vmargin = 4,
		color = "white",
		text = "",

		thinkTime = 0.1,
		think = function(element)
			element.text = dmhub.status
		end,
	}
end

function GameHud.DicePanel()

	local CreateDice = function(faces)
		return gui.Panel{
			
			bgimage = "ui-icons/d" .. faces .. ".png",
			draggable = true,
			
			styles = {
				{
					bgcolor = "white",
					width = 16,
					height = 16,
					borderWidth = 0,
					cornerRadius = 0,
					valign = "center",
				},
				
				{
					selectors = {"hover"},
					bgcolor = "white",
					brightness = 5,
					transitionTime = 0.1,
					scale = 1.1,
					rotate = 0,
				},
				
				{
					selectors = {"press"},
					bgcolor = "#4d4d4d",
				},
			},
		
			events = {
				hover = gui.Tooltip{ text = string.format('D%d', faces), textAlignment = 'center', valign = 'top' },
				click = function(panel)
					dmhub.Roll{
						numDice = 1,
						numFaces = faces,
						description = "Custom Roll",
					}
				end,

				beginDrag = function(panel)
					dmhub.Debug('dragging dice')
					dmhub.DragDice(string.format('%dd%d', 1, faces))
				end,
			},
		}
	end

	return gui.Panel({
	
		bgimage = "panels/diceframe.png",
		
		selfStyle = {
			halign = "right",
			valign = "bottom",
		},
		
		styles = {
			{
				bgcolor = "white",
				cornerRadius = 5,
				pad = 5, 
				width = 200,
				height = 26,
				
				color = "red",
				valign = "bottom",
				halign = "center",
				flow = "horizontal",
				
			},
			
			{
				selectors = {"hover"},
				transitionTime = 0.5,
				
				borderColor = "white",
				brightness = 1,
			}
			
		},
		children = {
			CreateDice(4),
			CreateDice(6),
			CreateDice(8),
			CreateDice(10),
			CreateDice(12),
			CreateDice(20),
		}
	})
	
end

--panel that goes next to the initiative that has some DM controls such as a rest button and require roll button.
function GameHud:DMGameControlsPanel()

	if not dmhub.isDM then
		return gui.Panel{
			halign = "left",
			width = 1,
			height = 1,
		}
	end

	local dmIlluminationButton = gui.Button{
		classes = {"sizeM"},
		icon = "icons/icon_device/icon_device_57.png",
		create = function(element)
			element:SetClass('deselected', not dmhub.GetSettingValue("dmillumination"))
		end,
		click = function(element)
			local hasIllumination = dmhub.GetSettingValue("dmillumination")
			dmhub.SetSettingValue("dmillumination", not hasIllumination)
			element:FireEventTree('create')

			if element.tooltip ~= nil then
				--redisplay tooltip with new setting.
				element:FireEvent('hover')
			end
		end,
		hover = function(element)
			gui.Tooltip(string.format('Director Darkvision: %s', cond(dmhub.GetSettingValue("dmillumination"), 'on', 'off')))(element)
		end,
	}

	self.gameControlsPanel = gui.Panel{
		halign = 'left',
		valign = 'top',
		width = 'auto',
		height = 'auto',
		flow = 'horizontal',

		styles = {
			{
				selectors = {"dmonly", "player"},
				collapsed = 1,
			},
			{
				margin = 4,
				flow = 'horizontal',
			},
			{
				selectors = {'button'},
				priority = 10,
				width = 40,
				height = 40,
			},
			{
				selectors = {'button-icon'},
				width = '80%',
				height = '80%',
				bgcolor = 'white',
				halign = 'center',
				valign = 'center',
			},
		},

		--self:RestButton(),
		--self:RequireRollPanel(),
		dmIlluminationButton,
	}

	return gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		self.gameControlsPanel,
	}

end


function GameHud:CreatePopupPanel()
	self.popupPanel = gui.Panel{
		selfStyle = {
			width = "100%",
			height = "100%",
		}
	}

	return self.popupPanel
end

function GameHud:CreateFrozenLabel()

	local freezebind = dmhub.GetCommandBinding("togglefreeze")
	local bindtext = "(Players cannot move.)"
	if freezebind ~= nil and dmhub.isDM then
		bindtext = string.format("(Players cannot move. %s to toggle.)", freezebind)
	end


	self.freezeLabel = gui.Panel{
		id = "frozenLabel",
		halign = "center",
		valign = "bottom",
		flow = "vertical",
		height = "auto",
		width = "auto",

		styles = {
			{
				opacity = 0,
				y = 50,
			},
			{
				classes = {"frozen"},
				transitionTime = 0.2,
				opacity = 0.9,
				y = -110,
			},
		},

		data = {

			frozen = nil

		},

		monitorGame = "/frozen",
		refreshGame = function(element)
			element:SetClassTree("frozen", dmhub.frozen)
			if element.data.frozen ~= nil and element.data.frozen ~= dmhub.frozen then
				if dmhub.frozen then
					audio.FireSoundEvent("Notify.TimeFreeze_Start")
				else
					audio.FireSoundEvent("Notify.TimeFreeze_End")
				end
			end


			element.data.frozen = dmhub.frozen

		end,

		press = function(element)
			dmhub.frozen = not dmhub.frozen

		end,
		gui.Label{
			text = "FROZEN",
			width = "auto",
			height = "auto",
			halign = "center",
@if MCDM
			fontFace = "Colvillain",
			fontSize = 48,
			fontWeight = "black",
			color = "white",
@else
			fontFace = "sellyoursoul",
			fontSize = 48,
			color = "#bbbbff",
			bold = true,
@end

		},
		gui.Label{
			text = bindtext,
			width = "auto",
			height = "auto",
			halign = "center",
@if MCDM
			uppercase = true,
			fontFace = "Colvillain",
			fontSize = 18,
			bold = false,
@else
			color = "#bbbbff",
			fontSize = 12,
			bold = true,
@end
		},
	}

	return self.freezeLabel
end


--Horizontal alpha-fade so the banner has soft left/right edges.
--Black fill in the middle, transparent at the ends.
local g_tipBannerGradient = gui.Gradient{
	point_a = {x = 0, y = 0.5},
	point_b = {x = 1, y = 0.5},
	stops = {
		{position = 0,    color = "#00000000"},
		{position = 0.12, color = "#000000d8"},
		{position = 0.88, color = "#000000d8"},
		{position = 1,    color = "#00000000"},
	},
}

--Mouse-button bindings come back as "leftclick"/"rightclick"/"middleclick";
--single-letter key bindings come back lowercase. Humanize for tip text so
--the displayed phrase always matches what the user has actually bound.
local function PrettifyBinding(s)
	if s == nil or s == "" then return "?" end
	local mouseMap = {
		leftclick = "left mouse button",
		rightclick = "right mouse button",
		middleclick = "middle mouse button",
	}
	if mouseMap[s] ~= nil then return mouseMap[s] end
	if #s == 1 then return string.upper(s) end
	return s
end

local function TipAudienceOk(target)
	target = target or "all"
	if target == "all" then return true end
	if target == "director" then return dmhub.isDM end
	if target == "player" then return not dmhub.isDM end
	return true
end

--Tip registry. Tips opt in via Tip.Register{...}; the driver inside
--CreateTipBanner's think handler scans every 5s for the highest-priority
--eligible, not-yet-learned tip and displays it. Learned state is persisted
--via the engine's tutorial.* bridge (PlayerPrefs under the hood).
--Registry is stored on the Tip table so hot-reloading this file doesn't
--drop tips registered from other modules.
--rawget here because DMHub's Lua errors on reads of uninitialized globals.
Tip = rawget(_G, "Tip") or {}
Tip.registry = Tip.registry or {}

---@param spec {id: string, priority: nil|number, target: nil|"all"|"director"|"player", text: string|function, eligible: nil|function, whenShown: nil|function, acted: nil|function}
function Tip.Register(spec)
	Tip.registry[spec.id] = spec
end

function Tip.Unregister(id)
	Tip.registry[id] = nil
end

function Tip.IsLearned(id)
	local t = dmhub.GetSettingValue("tipsLearned") or {}
	return t[id] == true
end

function Tip.MarkLearned(id)
	local t = dmhub.GetSettingValue("tipsLearned") or {}
	t[id] = true
	dmhub.SetSettingValue("tipsLearned", t)
end

--Wipe every tip's learned state and pull any currently-displayed tip off
--screen without marking it learned. Used by the /tipsclear macro.
function Tip.ResetAll()
	dmhub.SetSettingValue("tipsLearned", {})
	local gh = GameHud.instance
	if gh == nil then return end
	gh.activeTipId = nil
	gh._tipState = nil
	gh._tipLastScan = nil
	local banner = gh:try_get("tipBanner")
	if banner ~= nil and banner.valid then
		banner:SetClass("visible", false)
		banner.interactable = false
	end
end

--Explicit dismiss from an action site. Marks the tip learned and, if it's
--the one currently showing, takes it off screen immediately (no need to
--wait for the next acted-poll tick).
function Tip.Clear(id)
	Tip.MarkLearned(id)
	local gh = GameHud.instance
	if gh == nil then return end
	if gh:try_get("activeTipId") == id then
		gh:_ClearActiveTip()
	end
end

--First tip: camera movement. Cleared automatically the moment the camera
--position changes (which only happens via the bound inputs or auto-control).
Tip.Register{
	id = "camera-move",
	priority = 100,
	target = "all",
	text = function()
		local up = PrettifyBinding(dmhub.GetCommandBinding("mapup"))
		local left = PrettifyBinding(dmhub.GetCommandBinding("mapleft"))
		local down = PrettifyBinding(dmhub.GetCommandBinding("mapdown"))
		local right = PrettifyBinding(dmhub.GetCommandBinding("mapright"))
		local scroll = PrettifyBinding(dmhub.GetCommandBinding("mapscroll"))
		return string.format(
			"Press %s, %s, %s, or %s to move the camera, or %s and drag.",
			up, left, down, right, scroll)
	end,
	whenShown = function(state)
		state.cameraPos = dmhub.cameraPosition
	end,
	acted = function(state)
		if state.cameraPos == nil then return false end
		local cur = dmhub.cameraPosition
		if cur == nil then return false end
		local dx = cur.x - state.cameraPos.x
		local dy = cur.y - state.cameraPos.y
		return (dx * dx + dy * dy) > 0.01
	end,
}

--Camera zoom: shown after camera-move is learned. Cleared when the
--orthographic size changes (mouse wheel zoom and zoomin/zoomout keys
--all converge on the same camera property). "mouse wheel" stays
--hardcoded -- wheel input isn't a rebindable command in the engine.
Tip.Register{
	id = "camera-zoom",
	priority = 90,
	target = "all",
	text = function()
		local zin = PrettifyBinding(dmhub.GetCommandBinding("zoomin"))
		local zout = PrettifyBinding(dmhub.GetCommandBinding("zoomout"))
		return string.format(
			"Use mouse wheel or press %s/%s to zoom in and out.",
			zin, zout)
	end,
	whenShown = function(state)
		state.zoom = dmhub.cameraZoom
	end,
	acted = function(state)
		if state.zoom == nil then return false end
		local cur = dmhub.cameraZoom
		if cur == nil then return false end
		return math.abs(cur - state.zoom) > 0.0001
	end,
}

--Token movement: shown when the user has a single token selected outside
--of combat or a frozen state. Cleared once that token's location changes.
--If the user deselects or combat starts while the tip is up, the driver's
--eligible re-check suppresses it without marking learned, so it returns
--the next time the context is right.
Tip.Register{
	id = "token-drag-move",
	priority = 80,
	target = "all",
	text = "Click and drag your token to move it.",
	eligible = function()
		if dmhub.frozen then return false end
		local q = dmhub.initiativeQueue
		if q ~= nil and not q.hidden then return false end
		local sel = dmhub.selectedTokens
		if sel == nil or #sel ~= 1 then return false end
		return true
	end,
	whenShown = function(state)
		local tok = dmhub.selectedTokens[1]
		state.tokenId = tok.id
		state.startLoc = { x = tok.loc.x, y = tok.loc.y }
	end,
	acted = function(state)
		if state.startLoc == nil then return false end
		for _, tok in ipairs(dmhub.selectedTokens) do
			if tok.id == state.tokenId then
				local dx = tok.loc.x - state.startLoc.x
				local dy = tok.loc.y - state.startLoc.y
				return (dx * dx + dy * dy) > 0.01
			end
		end
		return false
	end,
}

--Use-light prompt. Eligible when the user has a single token selected
--underground, in a dark area, with a light style configured but not yet
--equipped (selectedLoadout != 1). The {light-btn} tutorial highlight
--draws a cursor around the light toggle button in MCDMCharacterPanel.
--Note: GetEquippedLightSource() returns the *currently chosen* light
--item id even when initLight hasn't been set (it falls back to default).
Tip.Register{
	id = "use-light",
	priority = 70,
	target = "all",
	text = function()
		local lkey = PrettifyBinding(dmhub.GetCommandBinding("light"))
		local lightName = "light"
		local sel = dmhub.selectedTokens
		if sel ~= nil and #sel == 1 then
			local lightId = sel[1].properties:GetEquippedLightSource()
			if lightId ~= nil then
				local gearTable = dmhub.GetTable("tbl_Gear")
				if gearTable ~= nil and gearTable[lightId] ~= nil and gearTable[lightId].name ~= nil then
					lightName = gearTable[lightId].name
				end
			end
		end
		return string.format(
			"Press %s or press the light button to take out your %s.",
			lkey, lightName)
	end,
	eligible = function()
		if dmhub.frozen then return false end
		local sel = dmhub.selectedTokens
		if sel == nil or #sel ~= 1 then return false end
		local tok = sel[1]
		local lightId = tok.properties:GetEquippedLightSource()
		if lightId == nil then return false end
		if tok.properties:try_get("selectedLoadout", 0) == 1 then return false end
		--Above-ground floors use dynamic outdoor lighting; the "very dark"
		--threshold belongs only to the underground illumination setting.
		if game.FloorIsAboveGround(tok.floorid) then return false end
		local ambient = dmhub.GetSettingValue("undergroundillumination") or 1.0
		if ambient >= 0.3 then return false end
		return true
	end,
	whenShown = function(state)
		state.tokenId = dmhub.selectedTokens[1].id
		--Highlight by id, not class: the "light-btn" class is unfortunately
		--reused for the unrelated look-up-between-floors button in
		--MCDMCharacterPanel.lua, so class targeting hits the wrong element
		--(or both) and the cursor lands inconsistently. The id is stable.
		tutorial.SetTutorial{
			name = "tip-use-light",
			entries = {
				{ target = "#char-panel-light-btn", text = "" },
			},
		}
	end,
	whenHidden = function(state)
		tutorial.ClearTutorial()
	end,
	acted = function(state)
		if state.tokenId == nil then return false end
		for _, tok in ipairs(dmhub.selectedTokens) do
			if tok.id == state.tokenId then
				return tok.properties:try_get("selectedLoadout", 0) == 1
			end
		end
		return false
	end,
}

--Beastheart "Call companion" prompt. Eligible when the user has a single
--Beastheart selected with a chosen companion that isn't currently nearby
--(matches the visibility of the Call button in DSBeastheart.lua). Cleared
--when the companion ends up near the beastheart -- which is what pressing
--Call accomplishes via CallCompanion(). CALL_RANGE_TILES is duplicated
--from DSBeastheart.lua (kept in sync deliberately).
local TIP_CALL_RANGE_TILES = 3

local function BeastheartCompanionIsNearby(tok)
	if tok == nil or not tok.valid or tok.properties == nil then return false end
	local companionToken = tok.properties:GetCompanionToken()
	if companionToken == nil or not companionToken.loc.isOnMap then return false end
	return companionToken.loc:DistanceInTiles(tok.loc) <= TIP_CALL_RANGE_TILES
end

Tip.Register{
	id = "beastheart-call",
	priority = 60,
	target = "all",
	text = function()
		local beastname = "companion"
		local sel = dmhub.selectedTokens
		if sel ~= nil and #sel == 1 then
			local companionType = sel[1].properties:GetCompanionType()
			if companionType ~= nil then
				local monster = assets.monsters[companionType]
				if monster ~= nil and monster.name ~= nil then
					beastname = monster.name
				end
			end
		end
		return string.format("Press the Call button to summon your %s.", beastname)
	end,
	eligible = function()
		local sel = dmhub.selectedTokens
		if sel == nil or #sel ~= 1 then return false end
		local tok = sel[1]
		if tok.properties == nil then return false end
		if tok.properties:GetCompanionType() == nil then return false end
		return not BeastheartCompanionIsNearby(tok)
	end,
	whenShown = function(state)
		state.tokenId = dmhub.selectedTokens[1].id
		tutorial.SetTutorial{
			name = "tip-beastheart-call",
			entries = {
				{ target = "#beastheart-call-btn", text = "" },
			},
		}
	end,
	whenHidden = function(state)
		tutorial.ClearTutorial()
	end,
	acted = function(state)
		if state.tokenId == nil then return false end
		for _, tok in ipairs(dmhub.selectedTokens) do
			if tok.id == state.tokenId then
				return BeastheartCompanionIsNearby(tok)
			end
		end
		return false
	end,
}

--Tip banner: a top-of-screen overlay driven by the Tip.* registry.
--The think handler polls the active tip's acted() at thinkTime cadence
--and scans the registry for the next tip when nothing is showing.
function GameHud:CreateTipBanner()
	--Tip text. The {tipBannerContent} class is what the parent-targeted
	--opacity rules in the banner's styles block hook onto so the text
	--fades in/out together with the banner background.
	local tipLabel = gui.Label{
		id = "tipBannerLabel",
		classes = {"tipBannerContent", "sizeM"},
        interactable = false,
		text = "Tip banner ready.",
		color = "white",
		fontSize = 16,
		width = "auto",
		height = "auto",
		maxWidth = 580,
		halign = "center",
		valign = "center",
		textAlignment = "center",
		textWrap = true,
	}

	--Floating so it pins to the right edge regardless of sibling layout.
	local dismissButton = gui.Label{
		id = "tipBannerDismiss",
		classes = {"tipBannerContent", "sizeS"},
		text = "Dismiss",
		color = "white",
		fontSize = 14,
		bold = true,
		width = "auto",
		height = "auto",
		floating = true,
		halign = "right",
		valign = "center",
		hmargin = 24,
		styles = {
			{
				selectors = {"hover"},
				color = "#ffe39a",
				brightness = 1.1,
			},
			{
				selectors = {"press"},
				brightness = 0.7,
			},
		},
		press = function(element)
			GameHud.instance:HideTip()
		end,
	}

	local banner
	banner = gui.Panel{
		id = "tipBanner",
		classes = {"tipBanner"},
		floating = true,
		halign = "center",
		valign = "top",
		vmargin = 240,
		width = 920,
		height = 80,
		bgimage = "panels/square.png",
		bgcolor = "white",
		gradient = g_tipBannerGradient,
		cornerRadius = 4,
		interactable = false,

		--1 Hz tick. The driver is structured so when no tip is active
		--(the common case) the work per tick is a single time compare;
		--the expensive modal-dialog check only runs when a tip is
		--actually displayed or about to be displayed.
		thinkTime = 1.0,
		think = function(element)
			--GameHud.instance is `false` (not nil) before the hud finishes
			--initializing and again during teardown/reload, so a bare `~= nil`
			--check lets a boolean through; a truthy check is correct.
			local gh = GameHud.instance
			if gh then gh:_TipDriverTick() end
		end,

		data = {
			currentText = "",
		},

		--Banner rules target {tipBanner} so the cascade doesn't blanket
		--the children. The {tipBannerContent, parent:visible} pair makes
		--the label and dismiss mirror the banner's opacity transition
		--instead of leaving text on screen after the background fades.
		styles = {
			{
				selectors = {"tipBanner"},
				opacity = 0,
				y = -12,
			},
			{
				selectors = {"tipBanner", "visible"},
				opacity = 1,
				y = 0,
				transitionTime = 0.2,
			},
			{
				selectors = {"tipBannerContent"},
				opacity = 0,
				transitionTime = 0.2,
			},
			{
				selectors = {"tipBannerContent", "parent:visible"},
				opacity = 1,
				transitionTime = 0.2,
			},
		},

		tipLabel,
		dismissButton,
	}

	self.tipBanner = banner
	self.tipBannerLabel = tipLabel

	return banner
end

function GameHud:ShowTip(text)
	local banner = self:try_get("tipBanner")
	if banner == nil or not banner.valid then
		return
	end
	local label = self:try_get("tipBannerLabel")
	if label ~= nil and label.valid then
		label.text = text or ""
	end
	banner.data.currentText = text or ""
	banner:SetClass("visible", true)
	banner.interactable = true
end

--Internal: take the active tip off display, invoking its whenHidden hook
--so per-tip side effects (e.g. tutorial highlights) get torn down.
--Does NOT mark the tip learned; callers decide.
function GameHud:_ClearActiveTip()
	local active = self:try_get("activeTipId")
	if active == nil then return nil end
	local spec = Tip.registry[active]
	local state = self:try_get("_tipState") or {}
	if spec ~= nil and spec.whenHidden ~= nil then
		pcall(spec.whenHidden, state)
	end
	self.activeTipId = nil
	self._tipState = nil
	local banner = self:try_get("tipBanner")
	if banner ~= nil and banner.valid then
		banner:SetClass("visible", false)
		banner.interactable = false
	end
	return active
end

function GameHud:HideTip()
	--Dismiss-button / explicit hide: treat the active tip as learned so it
	--won't reappear next session.
	local active = self:_ClearActiveTip()
	if active ~= nil then
		Tip.MarkLearned(active)
	end
end

--Panel classes that, when present anywhere in the HUD tree, suppress the
--tip banner (and pause acted-polling) so tips don't compete with dialogs
--the user is actively reading. Add more entries here as needed.
local g_tipBlockingClasses = {
	"journalViewer",
}

--Returns true if any tip-blocking dialog is currently in the panel tree.
function GameHud:_TipIsBlockedByDialog()
	local root = self:try_get("parentPanel")
	if root == nil or not root.valid then return false end
	for _, cls in ipairs(g_tipBlockingClasses) do
		local hits = root:GetChildrenWithClassRecursive(cls)
		if hits ~= nil and #hits > 0 then return true end
	end
	return false
end

--Called from the tip banner's think handler at thinkTime cadence.
--Structured so the "no active tip + nothing eligible" path -- which is the
--common case once tips are learned -- does only a single time comparison
--per tick. The panel-tree-walking modal-dialog check is paid for ONLY when
--a tip is actively displayed or when the scan has actually found a tip to
--show; never speculatively.
function GameHud:_TipDriverTick()
	local active = self:try_get("activeTipId")

	if active ~= nil then
		--Active-tip path: full work. Modal check decides visibility,
		--then acted/eligible decide state.
		local banner = self:try_get("tipBanner")
		if self:_TipIsBlockedByDialog() then
			if banner ~= nil and banner.valid and banner:HasClass("visible") then
				banner:SetClass("visible", false)
				banner.interactable = false
			end
			return
		end
		if banner ~= nil and banner.valid and not banner:HasClass("visible") then
			banner:SetClass("visible", true)
			banner.interactable = true
		end

		local spec = Tip.registry[active]
		if spec == nil then
			self:_ClearActiveTip()
			self._tipLastScan = nil
			return
		end

		--acted() before eligible(): acted often invalidates eligible at
		--the same moment (e.g. taking out a torch flips both); checking
		--eligible first would suppress-without-marking and the tip would
		--reappear next session.
		if spec.acted ~= nil then
			local state = self:try_get("_tipState") or {}
			local ok, did = pcall(spec.acted, state)
			if ok and did then
				Tip.Clear(active)
				return
			end
		end

		if spec.eligible ~= nil then
			local ok, v = pcall(spec.eligible)
			if not (ok and v) then
				self:_ClearActiveTip()
				self._tipLastScan = nil
				return
			end
		end

		return
	end

	--No active tip. 4 out of 5 ticks fall through here in near-zero time:
	--just one try_get + one float compare.
	local now = dmhub.Time()
	local last = self:try_get("_tipLastScan", -math.huge)
	if (now - last) < 5 then return end
	self._tipLastScan = now

	--Scan for a candidate. Per-tip eligible() is microseconds; if every
	--tip is learned or none is eligible we bail before touching the
	--expensive modal-dialog check.
	local best = nil
	for _, spec in pairs(Tip.registry) do
		if not Tip.IsLearned(spec.id) and TipAudienceOk(spec.target) then
			local elig = true
			if spec.eligible ~= nil then
				local ok, v = pcall(spec.eligible)
				elig = ok and v
			end
			if elig and (best == nil or (spec.priority or 0) > (best.priority or 0)) then
				best = spec
			end
		end
	end
	if best == nil then return end

	--Only now -- when we actually intend to display something -- pay the
	--cost of walking the panel tree to ask "is a dialog blocking?"
	if self:_TipIsBlockedByDialog() then return end

	local text = best.text
	if type(text) == "function" then
		local ok, t = pcall(text)
		text = (ok and t) or ""
	end

	local state = {}
	if best.whenShown ~= nil then pcall(best.whenShown, state) end
	self._tipState = state
	self.activeTipId = best.id
	self:ShowTip(text)
end

function GameHud:InspectDice()
	if self:try_get("inspectdice") ~= nil then
		self:CloseModal()
		self.inspectdice = nil
		return
	end

	self.inspectdice = gui.Panel{
		width = 1024,
		height = 1024,
		bgcolor = "white",
		bgimage = "#DicePreview",
		halign = "center",
		valign = "center",
	}

	self:ShowModal(self.inspectdice)
end

dmhub.ShowGameContextMenu = function(entries)
	gamehud.dialog.sheet.popupPositioning = "mouse"

	gamehud.dialog.sheet.popup = gui.ContextMenu{
		click = function()
			gamehud.dialog.sheet.popup = nil
		end,
		entries = entries,
	}
end

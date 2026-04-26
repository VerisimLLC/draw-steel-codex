local mod = dmhub.GetModLoading()

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local CreateTerrainEditor
local CreateBuildingEditor

DockablePanel.Register{
	name = "Terrain Editor",
	icon = "icons/standard/Icon_App_TerrainEditor.png",
	vscroll = true,
    dmonly = true,
	minHeight = 200,
	folder = "Map Editing",
	content = function()
		track("panel_open", {
			panel = "Terrain Editor",
			dailyLimit = 30,
		})
		return CreateTerrainEditor{
			title = "Terrain",
			layer = "terrain",
			hasFill = true,
			shapetool = true,
		}
	end,
}

DockablePanel.Register{
	name = "Effects Editor",
	icon = mod.images.effectsIcon,
	vscroll = true,
    dmonly = true,
	minHeight = 200,
	folder = "Map Editing",
	content = function()
		track("panel_open", {
			panel = "Effects Editor",
			dailyLimit = 30,
		})
		return CreateTerrainEditor{
			title = "Effects",
			layer = "effects",
			hasCreateTexture = true,
		}
	end,
}

DockablePanel.Register{
	name = "Building Editor",
	icon = mod.images.buildingIcon,
	vscroll = true,
    dmonly = true,
	minHeight = 200,
	folder = "Map Editing",
	content = function()
		track("panel_open", {
			panel = "Building Editor",
			dailyLimit = 30,
		})
		return CreateBuildingEditor()
	end,
}

local m_buildingHud = nil
local m_terrainHud = nil
local m_effectsHud = nil

local CreateTilesheetContextMenuItems = function(element)

    local tilesheet = element.data.tilesheet
    local entries = {
        {
            text = 'Edit Tilesheet...',
            click = function()
                mod.shared.EditTilesheetAssetDialog(element.data.tileid)
                element.popup = nil
            end,
        },
        {
            text = 'Duplicate Tilesheet',
            click = function()
                mod.shared.DuplicateTilesheetAsset(element.data.tileid)
                element.popup = nil
            end,
        },

        {
            text = 'Delete Tilesheet',
            click = function()
                gui.ModalMessage{
                    title = 'Delete Tilesheet',
                    message = 'Are you sure you want to delete this tilesheet?',
                    options = {
                        {
                            text = 'Delete',
                            execute = function() tilesheet:Delete() end,
                        },
                        {
                            text = 'Cancel',
                        },
                    }
                }
                element.popup = nil
            end,
        },

    }

    if devmode() then
        entries[#entries+1] = {
            text = 'Get Tilesheet Image',
            click = function()
                element.popup = nil
                tilesheet:OpenImageUrl()
            end,
        }
    end

    return entries
end

local CreateWallContextMenuItems = function(element)
    local wall = element.data.wall
    local entries = {
        {
            text = 'Edit Wall Asset...',
            click = function()
                mod.shared.EditWallAssetDialog(element.data.wallid)
                element.popup = nil
            end,
        },
        {
            text = 'Duplicate Wall',
            click = function()
                mod.shared.DuplicateWallAsset(element.data.wallid)
                element.popup = nil
            end,
        },

        {
            text = 'Delete Wall Asset',
            click = function()
                gui.ModalMessage{
                    title = 'Delete Wall Asset',
                    message = 'Are you sure you want to delete this wall asset?',
                    options = {
                        {
                            text = 'Delete',
                            execute = function() wall:Delete() end,
                        },
                        {
                            text = 'Cancel',
                        },
                    }
                }
                element.popup = nil
            end,
        },
    }

    if devmode() then
        entries[#entries+1] = {
            text = 'Get Wall Image',
            click = function()
                element.popup = nil
                wall:OpenImageUrl()
            end,
        }
    end

    return entries
end

local ShowFloorTooltip = function(parentPanel, element)
	local dock = parentPanel:FindParentWithClass("dock")
	assert(dock ~= nil)

	local node = element.data.tilesheet
    
	element.tooltipParent = parentPanel

    local rulesPanels = {}

    if node.rules.water then
        rulesPanels[#rulesPanels+1] = gui.Label{
            classes = {"description"},
            text = "<b>Water</b>: This terrain is water; creatures in it will use rules for traveling in water.",
        }
    end

    if node.rules.difficultTerrain then
        rulesPanels[#rulesPanels+1] = gui.Label{
            classes = {"description"},
            text = string.format("<b>Difficult</b>: This terrain is difficult; creatures in it will use rules for difficult terrain, which typically means that every %s of movement will count as two %s of movement.", string.lower(MeasurementSystem.CurrentSystem().unitSingular), string.lower(MeasurementSystem.CurrentSystem().unitName)),
        }
    end

    element.tooltip = gui.Panel{
		pad = 24,
		cornerRadius = 10,
        halign = dock.data.TooltipAlignment(),
        valign = "center",
		bgimage = 'panels/square.png',
		bgcolor = '#000000f6',
		borderWidth = 10,
		borderFade = true,
		borderColor = '#000000f6',
        width = 300,
        height = "auto",
        flow = "vertical",

        styles = SpellRenderStyles,

        gui.Label{
            text = node.description,
            fontSize = 24,
            bold = true,
            wrap = true,
            height = "auto",
            width = "auto",
            maxWidth = 280,
            vmargin = 8,
        },

        gui.Panel{
            bgimageStreamed = element.data.tileid,
            bgcolor = "white",
            width = 128,
            height = 128,

			hueshift = node.hueshift,
			saturation = 1+node.saturation,
			brightness = 1+node.brightness,

			imageLoaded = function(element)
				if element.bgimageWidth > element.bgimageHeight then
                    element.selfStyle.imageRect = {
                        x1 = 0,
                        x2 = 1,
                        y1 = 0,
                        y2 = element.bgimageWidth/element.bgimageHeight,
                    }
				else
                    element.selfStyle.imageRect = {
                        x1 = 0,
                        x2 = element.bgimageHeight/element.bgimageWidth,
                        y1 = 0,
                        y2 = 1,
                    }
				end
			end,
        },

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
            children = rulesPanels,
		},
    }
end

local ShowWallTooltip = function(parentPanel, element)
	local dock = parentPanel:FindParentWithClass("dock")
	assert(dock ~= nil)

	local node = element.data.wall
    
	element.tooltipParent = parentPanel

    local rulesPanels = {}

    rulesPanels[#rulesPanels+1] = gui.Label{
        classes = {"description"},
        text = cond(node.occludesVision, "<b>Blocks Vision</b>: This wall blocks creature vision.", "<b>Transparent</b>: This wall can be seen through or over easily. It does not block creature vision."),
    }

    rulesPanels[#rulesPanels+1] = gui.Label{
        classes = {"description"},
        text = cond(node.blocksMovement, "<b>Blocks Movement</b>: This is a solid wall, creatures cannot move through it.", "<b>Unobstructive</b>: This wall can be moved over freely. It does not block creature movement."),
    }

    local coverText = "<b>Full Cover</b>: This wall offers full cover to creatures behind it. Projectiles cannot be fired through it and most spells and abilities don't go through it."
    if node.cover == "None" then
        coverText = "<b>No Cover</b>: This wall offers no cover to creatures behind it."
    elseif node.cover == "Half" or node.cover == "ThreeQuarters" then
        local text = cond(node.cover == "Half", "Half", "Three-Quarters")
        coverText = string.format("<b>%s</b>: This wall offers %s cover to creatures behind it. Cover does not apply when an attacking creature is very close to the wall.", text, string.lower(text))
    end

    rulesPanels[#rulesPanels+1] = gui.Label{
        classes = {"description"},
        text = coverText,
    }

    if node.climbable ~= nil and node.climbable ~= "NotClimbable" then
        local climbText
        if node.climbable == "AllCreatures" then
            climbText = "<b>Climbable</b>: Any creature adjacent to this wall can climb it."
        else
            climbText = "<b>Climbable (Climbers Only)</b>: Only creatures with a climb speed can climb this wall."
        end
        rulesPanels[#rulesPanels+1] = gui.Label{
            classes = {"description"},
            text = climbText,
        }
    end

    element.tooltip = gui.Panel{
		pad = 24,
		cornerRadius = 10,
        halign = dock.data.TooltipAlignment(),
        valign = "center",
		bgimage = 'panels/square.png',
		bgcolor = '#000000f6',
		borderWidth = 10,
		borderFade = true,
		borderColor = '#000000f6',
        width = 300,
        height = "auto",
        flow = "vertical",

        styles = SpellRenderStyles,

        gui.Label{
            text = node.description,
            fontSize = 24,
            bold = true,
            wrap = true,
            height = "auto",
            width = "auto",
            maxWidth = 280,
            vmargin = 8,
        },

        gui.Panel{
            bgimageStreamed = element.data.wallid,
            width = 256,
            height = 64,
            bgcolor = node.tint,
			hueshift = node.hueshift,
			saturation = 1+node.saturation,
			brightness = 1+node.brightness,
			imageLoaded = function(element)
				local h = element.bgimageHeight/4
				element.selfStyle.imageRect = {
					x1 = 0,
					x2 = (element.bgimageHeight/element.bgimageWidth)*4,
					y1 = 0,
					y2 = 1,
				}
			end,
        },

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
            children = rulesPanels,
		},
    }
end

CreateTerrainEditor = function(options)
    local terrainItems = {}

    local isCollapsed = true

    local brushPanel = nil

    local selectedTerrainPanel = nil

    local maxTerrain = 4
    local terrainDim = 64

    local contentPanel

    local addTerrainButtonIcon = nil
    if options.hasCreateTexture then
        --for effects we put an icon in the top right to indicate this as using a picture
        --rather than building a brush.
        addTerrainButtonIcon = gui.Panel{
            bgimage = 'game-icons/treasure-map.png',
            selfStyle = {
                x = 10,
                y = -10,
                bgcolor = 'white',
                halign = 'right',
                valign = 'top',
                width = '60%',
                height = '60%',
            }
        }
    end

    local addTerrainButton = gui.AddButton{
        width = terrainDim,
        height = terrainDim,

        events = {
            hover = gui.Tooltip('Create New ' .. options.title .. ' from an image'),
            press = function(element)
                mod.shared.CreateTerrainAsset(options.layer)
            end,
        },

        children = {
            addTerrainButtonIcon,
        },
    }

    local createTextureButton = nil
    if options.hasCreateTexture then
        createTextureButton = gui.AddButton{
            width = terrainDim,
            height = terrainDim,

            events = {
                hover = gui.Tooltip('Build an effects brush from objects'),
                press = function(element)
                    mod.shared.CreateEffectsLayerTexture()
                end,
            },

            children = {

                --paint brush icon in top right corner.
                gui.Panel{
                    bgimage = 'game-icons/large-paint-brush.png',
                    selfStyle = {
                        x = 10,
                        y = -10,
                        bgcolor = 'white',
                        halign = 'right',
                        valign = 'top',
                        width = '60%',
                        height = '60%',
                    }
                }

            },

        }
    end


    local terrainPanelChildren = {}
    local terrainPanel = nil
    terrainPanel = gui.Panel({
        id = options.layer .. "Panel",
        style = {
            margin = 2,
            width = '100%',
            height = 'auto',
            flow = 'horizontal',
            wrap = true,
        },




        styles = {
            {
                selectors = {'terrainItem'},
                width = terrainDim,
                height = terrainDim,
                borderWidth = 4,
                borderColor = 'clear',
                bgcolor = 'white',
                cornerRadius = 6,
            },
            {
                selectors = {'terrainItem', 'selected'},
                borderColor = 'grey',
            },
            {
                selectors = {'terrainItem', 'hover'},
                borderColor = "grey",
            },
            {
                selectors = {'terrainItem', 'focus'},
                borderColor = 'white',
            },
            {
                selectors = {'terrainItem', 'new'},
                transitionTime = 1,
                brightness = 3,
                scale = 1.2,
            },
            {
                selectors = {'terrainItem', 'drag-target'},
                borderColor = 'blue',
            },
            {
                selectors = {'terrainItem', 'drag-target-hover'},
                borderColor = 'yellow',
            },
        },


        monitorAssets = "Tilesheet",

        --monitor if the brush style changes and if it does, make this get selected
        multimonitor = {options.layer .. 'brushstyle', options.layer .. 'tool'},
        events = {
            monitor = function(element)
                if selectedTerrainPanel ~= nil then
                    selectedTerrainPanel:FireEvent('press')
                end
            end,

            refreshAssets = function(element)
                dmhub.Debug('TERRAIN REFRESH ASSETS')
                element.data.init(element)
            end
        },

        data = {
            init = function(element, firstTime)
                local children = {}
                local newTerrainItems = {}
                local firstTimeItems = {} --items being added for the very first time.
                for k,terrain in pairs(assets.tilesheets) do
                    if terrain.layer == options.layer then
                        local childKey = k
                        newTerrainItems[k] = terrainItems[k] or gui.Panel({
                            id = options.layer .. '-panel',
                            bgimageStreamed = k,
                            classes = {'terrainItem', 'accept-' .. options.layer},
                            dragTarget = true,
                            draggable = true,
		                    canDragOnto = function(element, target)
                                return target:HasClass('accept-' .. options.layer)
                            end,
                            selfStyle = {
                                hueshift = terrain.hueshift,
                                saturation = 1+terrain.saturation,
                                brightness = 1+terrain.brightness,
                            },

                            data = {
                                [options.layer .. 'id'] = k, --terrainid or effectsid
                                tileid = k,
                                tilesheet = terrain,
                                ord = terrain.ord,
                            },

                            events = {
			                    drag = function(element, target)
                                    if target == nil then
                                        return
                                    end

                                    --see if we need to 'repair' the ords since there are shared ords.
                                    local needRepair = false
                                    for k,tilesheet in pairs(assets.tilesheets) do
                                        if tilesheet.layer == options.layer and element.data ~= nil and target.data ~= nil then
											if (tilesheet.id ~= element.data.tileid and tilesheet.ord == element.data.ord) or
											   (tilesheet.id ~= target.data.tileid and tilesheet.ord == target.data.ord) then
												needRepair = true
												break
											end
                                        end
                                    end

                                    if needRepair then
                                        local elementIndex = nil
                                        local targetIndex = nil
                                        for i,terrainPanel in ipairs(terrainPanelChildren) do
                                            if terrainPanel == element then
                                                elementIndex = i
                                            end

                                            if terrainPanel == target then
                                                targetIndex = i
                                            end
                                        end

                                        if elementIndex and targetIndex then
                                            local tmp = terrainPanelChildren[elementIndex]
                                            terrainPanelChildren[elementIndex] = terrainPanelChildren[targetIndex]
                                            terrainPanelChildren[targetIndex] = tmp
                                        end

                                        for i,terrainPanel in ipairs(terrainPanelChildren) do
                                            if terrainPanel.data.tilesheet.ord ~= i then
                                                terrainPanel.data.tilesheet.ord = i
                                                terrainPanel.data.tilesheet:Upload()
                                            end
                                        end
                                    else
                                        --just swap the ords of the affected assets and upload
                                        local tmp = element.data.tilesheet.ord
                                        element.data.tilesheet.ord = target.data.tilesheet.ord
                                        target.data.tilesheet.ord = tmp

                                        element.data.tilesheet:Upload()
                                        target.data.tilesheet:Upload()
                                    end

                                end,

                                press = function(element)
                                    if selectedTerrainPanel ~= nil and selectedTerrainPanel.valid then
                                        selectedTerrainPanel:RemoveClass('selected')
                                    end
                                    selectedTerrainPanel = element
                                    element:AddClass('selected')
                                    gui.SetFocus(element)
                                    element.popup = nil
                                end,

                                rightClick = function(element)
                                    element:FireEvent('press')
                                    element.popup = gui.ContextMenu{
                                        entries = CreateTilesheetContextMenuItems(element)
                                    }
                                end,

                                hover = function(element)
                                    ShowFloorTooltip(contentPanel, element)
                                    --gui.Tooltip(assets.tilesheets[element.data.tileid].description)(element)
                                end,

                            },
                        })

                        --Make sure any hue shifting gets updated if it has changed.
                        newTerrainItems[k].selfStyle.hueshift = terrain.hueshift
                        newTerrainItems[k].selfStyle.saturation = 1+terrain.saturation
                        newTerrainItems[k].selfStyle.brightness = 1+terrain.brightness

                        newTerrainItems[k].data.ord = terrain.ord

                        --make new terrain items transition in nicely.
                        if (not firstTime) and terrainItems[k] == nil then
                            newTerrainItems[k]:PulseClass('new')
                            firstTimeItems[#firstTimeItems+1] = newTerrainItems[k]
                        end

                        children[#children+1] = newTerrainItems[k]
                    end
                end

                table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

                terrainPanelChildren = {}
                for i,v in ipairs(children) do
                    terrainPanelChildren[#terrainPanelChildren+1] = v
                end

                children[#children+1] = addTerrainButton
                children[#children+1] = createTextureButton
                

                terrainItems = newTerrainItems
                element.children = children

                for i,child in ipairs(element.children) do
                    child:RemoveClass('hidden')
                end

                if selectedTerrainPanel == nil or (not selectedTerrainPanel.valid) then
                    selectedTerrainPanel = children[1]
                end

                selectedTerrainPanel:SetClass('selected', true)

                --if there is exactly one new item, then force-select it
                if #firstTimeItems == 1 and mod.shared.assetsCreated[firstTimeItems[1].data.tileid] then
                    firstTimeItems[1]:FireEvent('press')
                    mod.shared.EditTilesheetAssetDialog(firstTimeItems[1].data.tileid)
                end
            end,
        },
    })

    terrainPanel.data.init(terrainPanel, true)

    local shapePanel = nil
    
    if options.shapetool then
        shapePanel = CreateSettingsEditor(options.layer .. 'tool')
    end

    local edgeSmoothingEditor = nil
    if options.layer ~= 'building' then
        edgeSmoothingEditor = CreateSettingsEditor(options.layer .. 'edgesmoothing')
    end

    local lockOpacityPanel = nil
    if options.layer == 'terrain' then
        lockOpacityPanel = CreateSettingsEditor("terrain:lockopacity")
    end
    
    brushPanel = gui.Panel({
        id = "TerrainBrushPanel",
        style = {
            width = "100%",
            height = 'auto',
            flow = 'vertical',
        },
        children = {
            CreateSettingsEditor(options.layer .. ':erase'),
            lockOpacityPanel,
            edgeSmoothingEditor,

            gui.Panel{
                classes = {cond(dmhub.GetSettingValue(options.layer .. 'tool') ~= 'brush', 'collapsed')},
                width = "auto",
                height = "auto",
                monitor = options.layer .. 'tool',
                events = {
                    monitor = function(element)
                        element:SetClass("collapsed", dmhub.GetSettingValue(options.layer .. 'tool') ~= 'brush')
                    end,
                },
                mod.shared.BrushEditorPanel('raster' .. options.layer .. 'brush'),
            },

            CreateSettingsEditor(options.layer .. ':stabilization'),
        },
    })

    local fillPanel = nil
    if options.hasFill then
        fillPanel =
            gui.Panel{
                id = 'FillTerrainPanel',
                style = {
                    width = 'auto',
                    height = 'auto',
                    flow = 'horizontal',
                    hmargin = 4,
                    fontSize = '40%',
                },

                children = {

                    gui.Button{
                        id = 'FillTerrainButton',
                        text = 'Set as Background',
                        fontSize = 14,
                        width = "auto",
                        hpad = 4,
                        height = 24,
                        events = {
                            press = function(element)
                                if selectedTerrainPanel ~= nil then
                                    dmhub.FillTerrain(selectedTerrainPanel.data.tileid)
                                end
                            end,

                            hover = gui.Tooltip("Fill the map background with this terrain."),
                        },
                    },

                    gui.Label{
                        classes = {"button"},
                        id = 'ClearTerrainButton',
                        text = 'Clear Background',
                        fontSize = 14,
                        width = "auto",
                        height = 24,
                        hpad = 4,
                        events = {
                            press = function(element)
                                dmhub.FillTerrain(nil)
                            end,

                            hover = gui.Tooltip("Clear the map background to void."),
                        },
                    },
                },
            }
    end

    contentPanel = gui.Panel({
        id = "TerrainContentPanel",
        interactable = false,
        style = {
            width = "100%",
            height = "auto",
            flow = "vertical",
        },


        --erase setting changed.
        childsetting = function(element)
            element:FireEvent("showpanel")
        end,


        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,

        showpanel = function(element)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        hidepanel = function(element)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,
        
        childfocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
        end,

        childdefocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
        end,

        data = {
            selectTerrain = function(terrainid)
                if terrainItems[terrainid] then
                    terrainItems[terrainid]:FireEvent('press')
                end
            end,
            GetSelectedTerrain = function()
                if selectedTerrainPanel ~= nil then
                    return selectedTerrainPanel.data.tileid
                end

                return nil
            end,
        },

        children = {

            shapePanel,
            brushPanel,
            fillPanel,

            terrainPanel,
        },
    })

    dmhub.Debug("QQQ: LAYER: " .. options.layer)
    if options.layer == "terrain" then
        m_terrainHud = contentPanel
    elseif options.layer == "effects" then
        m_effectsHud = contentPanel
        dmhub.Debug("QQQ: SET EFFECTS HUD")
    end

    return contentPanel
end

CreateBuildingEditor = function()
    local contentPanel
    local wallItems = {}
    local floorItems = {}

    local isCollapsed = true

    local triangle = nil

    local selectedFloorPanel = nil
    local selectedWallPanel = nil


    local brushPanel = nil

    local floorsOn = true
    local wallsOn = true

    local GetSelectedFloor = function()
        if floorsOn and selectedFloorPanel ~= nil then
            return selectedFloorPanel.data.floorid
        else
            return nil
        end
    end
    local GetSelectedWall = function()
        if wallsOn and selectedWallPanel ~= nil then
            return selectedWallPanel.data.wallid
        else
            return nil
        end
    end

    local floorDim = 64

    local addWallButton = gui.AddButton{
        width = floorDim,
        height = floorDim,

        events = {
            hover = gui.Tooltip('Create New Wall'),
            press = function(element)
                mod.shared.CreateWallAsset()
            end,
        },
    }

    local addFloorButton = gui.AddButton{
        width = floorDim,
        height = floorDim,

        events = {
            hover = gui.Tooltip('Create New Floor Tileset'),
            press = function(element)
                mod.shared.CreateTerrainAsset('floor')
            end,
        },
    }

    local floorPanel = nil
    floorPanel = gui.Panel({
        id = "FloorPanel",
        style = {
            margin = 0,
            width = "100%",
            height = "auto",
            flow = 'horizontal',
            wrap = true,
        },

        monitorAssets = "Tilesheet",

        --monitor if the brush style changes and if it does, make this get selected
        multimonitor = {'buildingtool'},
        events = {
            monitor = function(element)
                if floorsOn then
                    if selectedFloorPanel ~= nil then
                        selectedFloorPanel:FireEvent('press')
                    end
                end
            end,

            refreshAssets = function(element)
                dmhub.Debug('REFRESH ASSETS: FLOOR')
                element.data.init(element)
            end,
        },

        data = {
            init = function(element, firstTime)
                local newFloorItems = {}
                local children = {}
                local firstTimeItems = {}
                for key,floor in pairs(assets.floors) do
                    local classes = {'floorItem'}

                    newFloorItems[key] = floorItems[key] or gui.Panel({
                        bgimage = 'panels/square.png',
                        classes = classes,
                        wrap = false,
                        children = {
                            gui.Panel{
                                bgimageStreamed = key,
                                bgcolor = 'white',
                                width = floorDim-4,
                                height = floorDim-4,
                                y = 0,
                                vmargin = 0,
                                margin = 0,
                                pad = 0,
                                halign = 'center',
                                valign = 'center',
                                hueshift = floor.hueshift,
                                saturation = 1+floor.saturation,
                                brightness = 1+floor.brightness,
                                events = {

                                    imageLoaded = function(element)
                                        if element.bgimageWidth > element.bgimageHeight then
                                            element.selfStyle.imageRect = {
                                                x1 = 0,
                                                x2 = 1,
                                                y1 = 0,
                                                y2 = element.bgimageWidth/element.bgimageHeight,
                                            }
                                        else
                                            element.selfStyle.imageRect = {
                                                x1 = 0,
                                                x2 = element.bgimageHeight/element.bgimageWidth,
                                                y1 = 0,
                                                y2 = 1,
                                            }
                                        end
                                    end,

                                },
                            }
                        },
                        styles = {
                            {
                                selectors = {'floorItem'},
                                width = floorDim,
                                height = floorDim,
                                hmargin = 2,
                                vmargin = 2,
                                cornerRadius = 0,
                                borderWidth = 2,
                                borderColor = Styles.textColor,
                                bgcolor = 'clear',
                            },
                            {
                                selectors = {'floorItem', 'hover'},
                                brightness = 2.5,
                            },
                            {
                                selectors = {'floorItem', 'selected'},
                                brightness = 2.5,
                            },
                        },

                        data = {
                            tileid = key,
                            tilesheet = floor,
                            floorid = key,
                            floor = floor,
                            GetSelectedFloor = GetSelectedFloor,
                            GetSelectedWall = GetSelectedWall,
                            ord = floor.ord,
                        },

                        events = {

                            press = function(element)
                                if selectedFloorPanel ~= nil then
                                    selectedFloorPanel:RemoveClass('selected')
                                end
                                selectedFloorPanel = element
                                element:AddClass('selected')
                                gui.SetFocus(element)
                                element.popup = nil
                                contentPanel:FireEventTree("changefloor", element.data.floorid)
                            end,
                            rightClick = function(element)
                                element:FireEvent('press')
                                element.popup = gui.ContextMenu{
                                    entries = CreateTilesheetContextMenuItems(element)
                                }
                            end,

                            hover = function(element)
                                ShowFloorTooltip(contentPanel, element)
                                --gui.Tooltip(element.data.floor.description)(element)
                            end,

                        },
                    })

                    --Make sure any hue shifting gets updated if it has changed.
                    newFloorItems[key].children[1].selfStyle.hueshift = floor.hueshift
                    newFloorItems[key].children[1].selfStyle.saturation = 1+floor.saturation
                    newFloorItems[key].children[1].selfStyle.brightness = 1+floor.brightness

                    --make new floor items transition in nicely.
                    if (not firstTime) and floorItems[key] == nil then
                        newFloorItems[key]:PulseClass('new')
                        firstTimeItems[#firstTimeItems+1] = newFloorItems[key]
                    end

                    children[#children+1] = newFloorItems[key]
                end

                table.sort(children, function(a,b) return a.data.ord < b.data.ord or (a.data.ord == b.data.ord and a.data.tileid < b.data.tileid) end)

                children[#children+1] = addFloorButton

                floorItems = newFloorItems
                element.children = children

                --Drop any reference to a floor tile that no longer exists (e.g. the selected floor was deleted).
                --Without this, element.children = children above can destroy the underlying panel, leaving a
                --stale LuaSheetPanel whose AddClass call NREs on a null C# panel.
                if selectedFloorPanel ~= nil and (selectedFloorPanel.data == nil or floorItems[selectedFloorPanel.data.floorid] == nil) then
                    selectedFloorPanel = nil
                end

                if selectedFloorPanel == nil then
                    selectedFloorPanel = children[1]
                end

                if selectedFloorPanel ~= nil then
                    selectedFloorPanel:AddClass('selected')
                end

                --If there is exactly one new item, and we added it this session, then force select and edit it.
                if #firstTimeItems == 1 and mod.shared.assetsCreated[firstTimeItems[1].data.tileid] then
                    firstTimeItems[1]:FireEvent('press')
                    mod.shared.EditTilesheetAssetDialog(firstTimeItems[1].data.tileid)
                end
            end,
        },
    })

    floorPanel.data.init(floorPanel, true)

    local walls = assets.walls

    local wallPanel = nil
    wallPanel = gui.Panel({
        id = "WallPanel",
        x = -2,
        style = {
            margin = 0,
            width = "96%",
            height = "auto",
            halign = "center",
            flow = 'horizontal',
            wrap = true,
        },

        styles = {

            {
                selectors = {"wallContainer"},
                width = 32*10 + 12,
                height = 32,
                borderWidth = 2,
                cornerRadius = 0,
                borderColor = Styles.textColor,
                bgcolor = 'clear',
                vmargin = 3,
            },
            {
                selectors = {"wallContainer", "hover"},
                brightness = 2.5,
            },

            {
                selectors = {"wallContainer", "selected"},
                brightness = 2.5,
            },

            {
                selectors = {'wallContainer', 'drag-target-hover'},
                borderColor = 'white',
            },
        },


        monitorAssets = "Tilesheet",

        --monitor if the brush style changes and if it does, make this get selected
        multimonitor = {'buildingtool'},
        events = {
            monitor = function(element)
                if wallsOn and not floorsOn then
                    if selectedWallPanel ~= nil then
                        selectedWallPanel:FireEvent('press')
                    end
                end
            end,
            refreshAssets = function(element)
                dmhub.Debug('REFRESH ASSETS: WALL')
                walls = assets.walls
                element.data.init(element)
            end,
        },

        data = {
            init = function(element, firstTime)
                local children = {}
                local newWallItems = {}
                local firstTimeItems = {} --items being added for the very first time.
                for key,wall in pairs(walls) do

                    newWallItems[key] = wallItems[key] or gui.Panel{
                        bgimage = 'panels/square.png',
                        classes = {"wallContainer"},
                        dragTarget = true,
                        draggable = true,
		                canDragOnto = function(element, target)
                            return target ~= nil and target ~= element and target:HasClass("wallContainer")
                        end,

			            drag = function(element, target)
                            if target == nil then
                                return
                            end

                            local wallOrd = element.data.wall.ord or 0
                            local targetOrd = target.data.wall.ord or 0

                            element.data.wall.ord = targetOrd
                            target.data.wall.ord = wallOrd

                            element.data.wall:Upload()
                            target.data.wall:Upload()
                        end,

                        children = {
                            gui.Panel({
                                bgimageStreamed = key,
                                bgcolor = wall.tint,
                                hueshift = wall.hueshift,
                                saturation = 1+wall.saturation,
                                brightness = 1+wall.brightness,
                                width = 32*10,
                                height = 32,
                                valign = 'center',
                                halign = 'center',

								imageLoaded = function(element)
									local h = element.bgimageHeight/2
									element.selfStyle.imageRect = {
										x1 = 0,
										x2 = 10 * (element.bgimageHeight/element.bgimageWidth),
										y1 = 0,
										y2 = 1,
									}
								end,
                            })
                        },

                        data = {
                            wallid = key,
                            wall = wall,
                            GetSelectedFloor = GetSelectedFloor,
                            GetSelectedWall = GetSelectedWall,
                        },

                        events = {

                            press = function(element)
                                if selectedWallPanel ~= nil and selectedWallPanel.valid then
                                    selectedWallPanel:RemoveClass('selected')
                                end
                                selectedWallPanel = element
                                element:AddClass('selected')
                                gui.SetFocus(element)
                                contentPanel:FireEventTree("changewall", element.data.wallid)
                            end,

                            rightClick = function(element)
                                element:FireEvent('press')
                                element.popup = gui.ContextMenu{
                                    entries = CreateWallContextMenuItems(element)
                                }
                            end,

                            hover = function(element)
                                ShowWallTooltip(contentPanel, element)
                            end,

                        },
                    }

                    --make new wall items transition in nicely.
                    if (not firstTime) and wallItems[key] == nil then
                        newWallItems[key]:PulseClass('new')
                        firstTimeItems[#firstTimeItems+1] = newWallItems[key]
                    end

                    children[#children+1] = newWallItems[key]
                end

                table.sort(children, function(a,b)
                    local aord = a.data.wall.ord or 0
                    local bord = b.data.wall.ord or 0
                    return aord < bord or (aord == bord and a.data.wallid < b.data.wallid)
                end)

                children[#children+1] = addWallButton

                wallItems = newWallItems

                element.children = children

                if selectedWallPanel == nil then
                    selectedWallPanel = children[1]
                end

                selectedWallPanel:AddClass('selected')

                --if there is exactly one item being added for the very first time, select it.
                if #firstTimeItems == 1 and mod.shared.assetsCreated[firstTimeItems[1].data.wallid] then
                    firstTimeItems[1]:FireEvent('press')
                    --TODO: when there is a way to edit walls, open the wall dialog here.
                end
            end,
        },
    })

    wallPanel.data.init(wallPanel, true)



    local shapePanel = CreateSettingsEditor('buildingtool')
    
    brushPanel = gui.Panel({
        id = "FloorBrushPanel",
        style = {
            width = "100%",
            height = 'auto',
            flow = 'vertical',
        },
        children = {
            CreateSettingsEditor('building:erase', { halign = "center" }),

            gui.Panel{
                classes = {cond(dmhub.GetSettingValue('buildingtool') ~= 'brush', 'collapsed')},
                width = "auto",
                height = "auto",
                monitor = 'buildingtool',
                events = {
                    monitor = function(element)
                        element:SetClass("collapsed", dmhub.GetSettingValue('buildingtool') ~= 'brush')
                    end,
                },
                mod.shared.BrushEditorPanel('buildingbrush'),
            },
            CreateSettingsEditor('building:stabilization'),
        },
    })

    local previewFloor
    local previewWall
    local previewPanels = {}

    local SelectPreviewPanel = function(element)
        for _,panel in ipairs(previewPanels) do
            panel:SetClass("selected", element == panel)
        end

        floorPanel:SetClass('collapsed', element ~= previewFloor)
        wallPanel:SetClass('collapsed', element ~= previewWall)

    end

    --make sure an available preview panel is selected.
    local SelectAvailablePreviewPanel = function()
        local newPanel = nil
        for _,panel in ipairs(previewPanels) do
            if panel:HasClass("selected") and not panel:HasClass("collapsed") then
                --this is already selected and is fine.
                return
            end

            if not panel:HasClass("collapsed") then
                newPanel = panel
            end
        end

        SelectPreviewPanel(newPanel)
    end

    previewFloor = gui.Panel{
        classes = {"previewPanel"},
        bgimage = "panels/square.png",
        press = function(element)
            SelectPreviewPanel(element)
            if selectedFloorPanel ~= nil then
                gui.SetFocus(selectedFloorPanel)
            end
        end,

        gui.Label{
            classes = "previewBuildingLabel",
            text = "Floor",
        },

        gui.Panel{
            floating = true,
            classes = "previewBuildingIcon",
            create = function(element)
                element.children = {
                    gui.Panel{
                        width = "100%",
                        height = "100%",
                        bgimageStreamed = GetSelectedFloor(),
						bgcolor = "white",

						imageLoaded = function(element)
							if element.bgimageWidth > element.bgimageHeight then
                                element.selfStyle.imageRect = {
                                    x1 = 0,
                                    x2 = 1,
                                    y1 = 0,
                                    y2 = element.bgimageWidth/element.bgimageHeight,
                                }
							else
                                element.selfStyle.imageRect = {
                                    x1 = 0,
                                    x2 = element.bgimageHeight/element.bgimageWidth,
                                    y1 = 0,
                                    y2 = 1,
                                }
							end
						end,

                    }
                }
            end,

            changefloor = function(element, floorid)
                element:FireEvent("create")
            end,
        },

    }

    previewWall = gui.Panel{
        classes = {"previewPanel"},
        bgimage = "panels/square.png",

        press = function(element)
            SelectPreviewPanel(element)
            if selectedWallPanel ~= nil then
                gui.SetFocus(selectedWallPanel)
            end
        end,

        gui.Label{
            classes = "previewBuildingLabel",
            text = "Wall",
        },
        gui.Panel{
            floating = true,
            classes = "previewBuildingIcon",
            create = function(element)
                local selectedWall = GetSelectedWall()
                local wallInfo = walls[selectedWall]
                if wallInfo == nil then
                    element.children = {}
                    return
                end

                element.children = {
                    gui.Panel{
                        bgimageStreamed = selectedWall,
                        bgcolor = wallInfo.tint,
                        hueshift = wallInfo.hueshift,
                        saturation = 1+wallInfo.saturation,
                        brightness = 1+wallInfo.brightness,
                        width = "100%",
                        height = "50%",
                        valign = "center",

						imageLoaded = function(element)
                            local h = element.bgimageHeight/2
                            element.selfStyle.imageRect = {
                                x1 = 0,
                                x2 = (element.bgimageHeight/element.bgimageWidth)*2,
                                y1 = 0,
                                y2 = 1,
                            }
						end,

                    }
                }
            end,

            changewall = function(element, wallid)
                element:FireEvent("create")
            end,
        },
    }

    previewPanels = {previewFloor, previewWall}

    SelectPreviewPanel(previewFloor)

    local previewHeader = gui.Panel{
        flow = "horizontal",
        halign = "center",
        valign = "center",
        width = "80%",
        height = "auto",
        vmargin = 12,

        children = previewPanels,

        styles = {
            {
                selectors = {"previewPanel"},
                flow = "vertical",
                width = 120,
                height = 120,
                halign = "center",
                bgcolor = "clear",
                border = 2,
                borderColor = Styles.textColor,
                bgimage = "panels/square.png",
            },
            {
                selectors = {"previewPanel", "selected"},
                brightness = 2.5,
            },
            {
                selectors = {"previewPanel", "hover"},
                brightness = 2.5,
            },
            {
                selectors = {"previewPanel", "press"},
                brightness = 3,
            },
            {
                selectors = {"previewBuildingLabel"},
                fontSize = 18,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                vmargin = 4,
                halign = "center",
                valign = "top",
            },
            {
                selectors = {"previewBuildingIcon"},
                width = 64,
                height = 64,
                halign = "center",
                valign = "center",
            },
        },
    }

    contentPanel = gui.Panel({
        id = "FloorContentPanel",
        interactable = false,
        style = {
            width = "100%",
            height = "auto",
            flow = "vertical",
        },

        --erase setting changed.
        childsetting = function(element)
            element:FireEvent("showpanel")
        end,

        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,

        showpanel = function(element)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        hidepanel = function(element)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end, 

        childfocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
        end,

        childdefocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
        end,

        data = {
            selectWall = function(wallid)
                if wallItems[wallid] then
                    wallItems[wallid]:FireEvent('press')
                end
            end,

            selectFloor = function(floorid)
                if floorItems[floorid] then
                    floorItems[floorid]:FireEvent('press')
                end
            end,

            GetSelectedFloor = GetSelectedFloor,
            GetSelectedWall = GetSelectedWall,
        },

        children = {

            shapePanel,
            brushPanel,

            gui.Panel{
                style = {
                    width = "100%",
                    height = "auto",
                    flow = 'horizontal',
                },
                styles = {
                    {
                        selectors = {"label"},
                        bgimage = "panels/square.png",
                        bgcolor = Styles.backgroundColor,
                        fontSize = 18,
                        color = Styles.textColor,
                        width = 80,
                        height = 24,
                        textAlignment = "center",
                        borderWidth = 2,
                        borderColor = Styles.textColor,
                        halign = "center",
                    },
                    {
                        selectors = {"label", "selected"},
                        color = "black",
                        bgcolor = Styles.textColor,
                    },
                    {
                        selectors = {"label", "hover"},
                        color = "black",
                        bgcolor = Styles.textColor,
                    },

                },

                selectMode = function(element, n)

                            print("INDEX:: in index")
                    floorsOn = n == 1 or n == 2
                    wallsOn = n == 2 or n == 3
                    previewFloor:SetClass('collapsed', not floorsOn)
                    previewWall:SetClass('collapsed', not wallsOn)

                    SelectAvailablePreviewPanel()


                    --when this changes make sure a wall/floor is selected.
                    if floorsOn then
                        floorPanel.events.monitor(floorPanel)
                    else
                        wallPanel.events.monitor(wallPanel)
                    end

                    for i,child in ipairs(element.children) do
                        child:SetClass("selected", child.data.index == n)
                    end
                end,

                children = {
                    gui.Panel{
                        height = 2,
                        width = "100%",
                        valign = "center",
                        bgimage = "panels/square.png",
                        bgcolor = Styles.textColor,
                        floating = true,
                    },

                    gui.Label{
                        data = {index = 1},
                        text = "Floors",
                        press = function(element)
                            print("INDEX::", 1)
                            element.parent:FireEvent("selectMode", 1)
                        end,
                    },
                    gui.Label{
                        classes = {"selected"},
                        data = {index = 2},
                        text = "Both",
                        press = function(element)
                            element.parent:FireEvent("selectMode", 2)
                        end,
                    },
                    gui.Label{
                        data = {index = 3},
                        text = "Walls",
                        press = function(element)
                            element.parent:FireEvent("selectMode", 3)
                        end,
                    },
                }
            },

            previewHeader,

            floorPanel,

            wallPanel,

        },
    })

    m_buildingHud = contentPanel
    return contentPanel
end

dmhub.GetSelectedTerrain = function()
    if m_terrainHud == nil or m_terrainHud:FindParentWithClass("dockablePanel") == nil then
        return
    end
    
	if gui.ChildHasFocus(m_terrainHud) then
        m_terrainHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
		return m_terrainHud.data.GetSelectedTerrain()
	end

    m_terrainHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)

	return nil
end

dmhub.SelectTerrain = function(terrainid)
    if m_terrainHud == nil then
        return
    end

    m_terrainHud.data.selectTerrain(terrainid)
end

dmhub.GetSelectedEffect = function()
    if m_effectsHud == nil or m_effectsHud:FindParentWithClass("dockablePanel") == nil then
        return
    end

	if gui.ChildHasFocus(m_effectsHud) then
        m_effectsHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
		return m_effectsHud.data.GetSelectedTerrain()
	end

    m_effectsHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)

	return nil
end

dmhub.SelectEffect = function(effectid)
    if m_effectsHud == nil then
        return
    end

    m_effectsHud.data.selectTerrain(effectid)
end

dmhub.GetSelectedFloor = function()
    if m_buildingHud == nil or m_buildingHud:FindParentWithClass("dockablePanel") == nil then
        return
    end

	if gui.ChildHasFocus(m_buildingHud) then
        m_buildingHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
		return m_buildingHud.data.GetSelectedFloor()
	end

    m_buildingHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)

	return nil
end

dmhub.SelectFloor = function(floorid)
    if m_buildingHud == nil then
        return
    end

    m_buildingHud.data.selectFloor(floorid)
end

dmhub.GetWallHeight = function()
    return dmhub.GetSettingValue("building:wallheight")
end

dmhub.GetSelectedWall = function()
    if m_buildingHud == nil or m_buildingHud:FindParentWithClass("dockablePanel") == nil then
        return
    end

	if gui.ChildHasFocus(m_buildingHud) then
        m_buildingHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
		return m_buildingHud.data.GetSelectedWall()
	end

    m_buildingHud:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
	return nil
end

dmhub.SelectWall = function(wallid)
    if m_buildingHud == nil then
        return
    end

    m_buildingHud.data.selectWall(wallid)
end

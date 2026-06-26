local mod = dmhub.GetModLoading()

--Game-scoped shared document holding the DM's per-mix-group BROADCAST levels (the table
--mix). The Audio panel "Levels" faders write it; every client mirrors it into the engine
--via audio.SetGroupShared. See the broadcast helpers in CreateSoundPanel and the
--all-clients monitor (AudioMixBroadcast) that keeps non-DM clients in sync.
local audioMixDocId = "audioMix"

--Mix groups whose broadcast level the DM controls from the panel "Levels" faders. Keyed
--by mix-group id so each maps 1:1 to an audio.SetGroupShared call.
local broadcastGroupIds = { "music", "ambience", "effects", "uisounds", "anthem" }

--Keep the DM's broadcast levels in checkpoint backups (game-scoped DM state).
mod:RegisterDocumentForCheckpointBackups(audioMixDocId)

--All-clients broadcast sync. The Audio panel is dmonly, but this file's module-load code
--runs on EVERY client, so this loop keeps each client's engine in sync with the DM's
--broadcast levels even on clients that never open the panel (and on late joiners). The
--doc snapshot syncs from the cloud; there is no panel-less change callback, so we poll it
--and push only changed values into the local engine via audio.SetGroupShared. Cost is a
--table read + a few compares per second. Guarded by mod.unloaded so a hot-reload's stale
--loop stops and the fresh module owns the schedule (see CLAUDE.md module lifecycle).
local broadcastSyncApplied = {}

local function SyncBroadcastLevelsToEngine()
	if mod.unloaded then
		return
	end
	local doc = mod:GetDocumentSnapshot(audioMixDocId)
	local b = doc.data.broadcast or {}
	for _,g in ipairs(broadcastGroupIds) do
		local v = b[g] or 1
		if broadcastSyncApplied[g] ~= v then
			broadcastSyncApplied[g] = v
			audio.SetGroupShared(g, v)
		end
	end
	dmhub.Schedule(1, SyncBroadcastLevelsToEngine)
end

dmhub.Schedule(1, SyncBroadcastLevelsToEngine)

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

local CreateSoundPanel

DockablePanel.Register{
	name = "Audio",
	icon = "icons/standard/Icon_App_Audio.png",
	vscroll = false,
    dmonly = true,
	minHeight = 470,
	maxHeight = 470,
	content = function()
		track("panel_open", {
			panel = "Audio",
			dailyLimit = 30,
		})
		return CreateSoundPanel()
	end,
	hasNewContent = function()
		return module.HasNovelContent("audio")
	end,
}

--Audio Studio: the session-prep power surface. Deliberately a LaunchablePanel
--(a floating window over the table, non-blocking) so it NEVER touches the user's
--dock layout -- the dock Audio panel stays exactly where they put it. Opened from
--the dock panel's "Audio Studio" button. This chunk builds the shell + the
--library LIST; the mixer / ducking / soundboard prep land in later chunks (the
--right column is a labelled skeleton for now).
local CreateAudioStudio

LaunchablePanel.Register{
	name = "Audio Studio",
	icon = "icons/standard/Icon_App_Audio.png",
	halign = "center",
	valign = "center",
	content = function()
		return CreateAudioStudio()
	end,
}

local defaultFolder = "-MyddEFnH5IOto7qCx-3"

local createAudioPanel

local FormatTime = function(value, maxValue)
	if maxValue >= 60 then
		local hours = math.floor(value / (60*60))
		local minutes = math.floor((value / 60)%60)
		local seconds = math.floor(value%60)

		if hours > 0 then
			return string.format("%d:%02d:%02d", hours, minutes, seconds)
		else
			return string.format("%0d:%02d", minutes, seconds)
		end
	elseif maxValue >= 10 then
		return string.format("%d", math.floor(value))
	else
		return string.format("%.1f", value)
	end
end

local ColorStyles = {
	{
		selectors = {"audioItemColor"},
		halign = "left",
		valign = "center",
		width = 12,
		height = 12,
		saturation = 1.5,
		border = 0.5,
		borderColor = "white",
		cornerRadius = 2,
		bgimage = "panels/square.png",
		bgcolor = "red", --data-driven swatch base; hueshifted per asset color
	},
	{
		selectors = {"audioItemColor", "hover"},
		brightness = 1.5,
	},
}



local CreatePlayerSlot = function(params)
	local slot = params.slot
	params.slot = nil

	--Themed slot chrome: {border} paints the @border frame, {bgAlt} the nested
	--surface fill. border width + the square bgimage stay inline (layout / glyph).
	local classes = {"playerSlot", "border", "bgAlt"}
	if params.classes ~= nil then
		for _,c in ipairs(params.classes) do
			classes[#classes+1] = c
		end
	end
	params.classes = nil

	local args = {
		classes = classes,
		width = 113,
		height = 64,
		border = 2,
		flow = "none",
		vmargin = 2,
		cornerRadius = 4,
		halign = "center",
		valign = "center",
		bgimage = "panels/square.png",
	}

	for k,v in pairs(params or {}) do
		args[k] = v
	end

	local slot = gui.Panel(args)

	return slot
end

local CreatePlayerGrid = function()
	local resultPanel

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		wrap = true,
		data = {
			gridNumber = 1,
			SetGridNumber = function(num)
				resultPanel.data.gridNumber = num
				resultPanel:FireEventTree("refreshGrid")
			end,
		},
		styles = {
			{
				selectors = {"playerSlot", "drag-target"},
				brightness = 2,
			},
			{
				selectors = {"playerSlot", "drag-target-hover"},
				brightness = 4,
			},
		},
	}

	local children = {}
	for i=1,12 do
		local previewAudioPanel = nil
		local audioPanel = nil
		local assetid = nil
		local docid = string.format("audiogrid-%d-%d", resultPanel.data.gridNumber, i)
		local doc = mod:GetDocumentSnapshot(docid)
		local slot = CreatePlayerSlot{
			classes = {"playgrid"},
			slot = i,
			dragTarget = true,
			monitorGame = doc.path,

			data = {
				docid = docid,
			},

			preview = function(element, previewAssetid)
				if previewAudioPanel ~= nil then
					dmhub.Debug(string.format("PANEL:: DESTROY: %f", dmhub.Time()))
					previewAudioPanel:DestroySelf()
					if audioPanel ~= nil and assetid ~= nil then
						audioPanel:SetClass("hidden", false)
					end
				end
				previewAudioPanel = nil

				if previewAssetid == nil then
					return
				end

				previewAudioPanel = createAudioPanel(assets.audioTable[previewAssetid], { slot = i, preview = true })
				element.children = {audioPanel, previewAudioPanel}
				if audioPanel ~= nil then
					audioPanel:SetClass("hidden", true)
				end
			end,

			refreshGrid = function(element)
				docid = string.format("audiogrid-%d-%d", resultPanel.data.gridNumber, i)
				element.data.docid = docid
				element:FireEvent("refreshGame")
				element.monitorGame = doc.path
			end,

			refreshGame = function(element)
				doc = mod:GetDocumentSnapshot(docid)
				if previewAudioPanel ~= nil then
					previewAudioPanel:DestroySelf()
					previewAudioPanel = nil
				end
				if assetid ~= doc.data.assetid then
					assetid = doc.data.assetid
					if assetid == nil then
						if audioPanel ~= nil then
							audioPanel:SetClass("hidden", true)
						end
					else
						if audioPanel == nil then
							audioPanel = createAudioPanel(assets.audioTable[assetid], { slot = i })
							element.children = {audioPanel}
						else
							audioPanel:SetClass("hidden", false)
							audioPanel:FireEvent("setAudio", assetid)
						end
					end
				end
			end,

		}
		children[#children+1] = slot
	end

	resultPanel.children = children

	return resultPanel
end

local CreateSoundboardPreviewPanel = function(playerGrid, slotNumber)

	--{bgAlt} supplies the themed base fill; the per-slot hueshift (data-driven
	--asset color) is applied on top at runtime in refreshGame.
	local tinyClasses = {"tinyPanel", "bgAlt"}
	if (slotNumber%2) ~= 0 then
		tinyClasses[#tinyClasses+1] = "odd"
	end

	local children = {}
	for i=1,12 do

		local docid = string.format("audiogrid-%d-%d", slotNumber, i)
		local doc = mod:GetDocumentSnapshot(docid)

		children[#children+1] = gui.Panel{
			classes = tinyClasses,


			create = function(element)
				element:FireEvent("refreshGame")
			end,

			monitorGame = doc.path,

			refreshGame = function(element)

				doc = mod:GetDocumentSnapshot(docid)
				if doc.data.assetid == nil then
					element.selfStyle.hueshift = 0
					element:SetClass("empty", true)
					doc = nil
					return
				end

				element:SetClass("empty", false)
				local audioAsset = assets.audioTable[doc.data.assetid]
				if audioAsset ~= nil then
					element.selfStyle.hueshift = audioAsset.color/8
				end
			end,

			monitorAssets = "audio",
			refreshAssets = function(element)
				if doc == nil then
					return
				end

				doc = mod:GetDocumentSnapshot(docid)

				if doc == nil or doc.data.assetid == nil or assets.audioTable[doc.data.assetid] == nil then
					return
				end

				local audioAsset = assets.audioTable[doc.data.assetid]
				element.selfStyle.hueshift = audioAsset.color/8
			end,
		}
	end

	return gui.Panel{
		classes = {"soundboardPreview"},
		wrap = true,
		children = children,
		press = function(element)
			playerGrid.data.SetGridNumber(slotNumber)
			for i,panel in ipairs(element.parent.children) do
				panel:SetClass("selected", i == slotNumber)
			end
		end,
	}
end

local CreateGridMenu = function(playerGrid)

	local children = {}
	for i=1,5 do
		children[#children+1] = CreateSoundboardPreviewPanel(playerGrid, i)
		if i == playerGrid.data.gridNumber then
			children[#children]:SetClass("selected", true)
		end
	end

	local resultPanel

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		vmargin = 4,
		children = children,
		styles = {
			gui.Style{
				selectors = {"tinyPanel"},
				bgimage = "panels/square.png",
				width = 16,
				height = 11,
				hmargin = 2,
				vmargin = 2,
			},
			gui.Style{
				selectors = {"tinyPanel", "empty"},
				saturation = 0.4,
			},
			gui.Style{
				selectors = {"tinyPanel", "~odd"},
				brightness = 0.3,
			},
			gui.Style{
				selectors = {"tinyPanel", "parent:hover"},
				brightness = 2,
			},
			gui.Style{
				selectors = {"tinyPanel", "parent:selected"},
				brightness = 2,
			},
			gui.Style{
				selectors = {"soundboardPreview"},
				bgimage = "panels/square.png",
				bgcolor = "clear",
				flow = "horizontal",
				halign = "left",
				x = -3,
				hmargin = 4,
				width = 64.6,
				height = "auto",
			},
		}
	}

	return resultPanel

end

local CreateAudioGrid = function()
	local playerGrid = CreatePlayerGrid()
	local resultPanel
	resultPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		playerGrid,
		CreateGridMenu(playerGrid),
	}

	return resultPanel
end

createAudioPanel = function(audioAsset, options)
	options = options or {}

	local resultPanel
	local durationLabel
	local volumeSlider

	local slot = options.slot
	options.slot = nil

	local preview = options.preview
	options.preview = nil

	local soundEventDocId = string.format("soundevent-%s", audioAsset.id)


	local sliderFill
	sliderFill = gui.Panel{
		classes = {"bgAccent"},
		bgimage = 'panels/square.png',
		selfStyle = {
			width = '0%',
			height = '100%',
			halign = 'left',
		},

		refreshPlayingAudio = function(element)
			local soundEvent = audio.currentlyPlaying[audioAsset.id]
			if soundEvent ~= nil then
				element.thinkTime = 0.1
			else
				durationLabel.text = string.format("%s", FormatTime(audioAsset.duration, audioAsset.duration))
				sliderFill.selfStyle.width = "0%"
				element.thinkTime = nil
			end
		end,


		think = function(element)
			local soundEvent = audio.currentlyPlaying[audioAsset.id]
			if soundEvent ~= nil then
				durationLabel.text = string.format("%s/%s", FormatTime(soundEvent.time, audioAsset.duration), FormatTime(audioAsset.duration, audioAsset.duration))
				sliderFill.selfStyle.width = string.format("%f%%", (100*soundEvent.time)/audioAsset.duration)
			else
				durationLabel.text = string.format("%s", FormatTime(audioAsset.duration, audioAsset.duration))
				sliderFill.selfStyle.width = "0%"
				element.thinkTime = nil
			end
		end,

	}

	local playerSlider = gui.Panel{
		classes = {"bgAlt"},
		bgimage = 'panels/square.png',
		floating = true,
		--classes = {'hidden'},
		style = {
			height = 2,
			width = '100%',
			margin = 0,
			pad = 0,
			halign = 'center',
			valign = 'bottom',
			flow = 'none',
		},
		children = {
			sliderFill,
		},
	}


	local titleLabel = gui.Label{
		classes = {"audioItemTitle"},
		editableOnDoubleClick = true,
		text = audioAsset.description,

		change = function(element)
			audioAsset.description = element.text
			audioAsset:Upload()
		end,

		monitorAssets = "audio",
		refreshAssets = function(element)
			element.text = audioAsset.description
		end,

		think = function(element)
			element.x = element.x - 1
			if element.x < -element.renderedWidth then
				element.x = element.parent.renderedWidth
			end
		end,

	}

	local titleLabelContainer = gui.Panel{
		classes = {"audioItemTitleContainer"},
		titleLabel,
		gui.NewContentAlertConditional("audio", audioAsset.id, { x = -8 }),

		bgimage = "panels/square.png",
		clip = true,
		clipHidden = true,

		playerSlider,
	}

	local colorPanel = gui.Panel{
		classes = {"audioItemColor"},
		y = -8,
		hmargin = 24,
		popupPositioning = "panel",

		hueshift = audioAsset.color/8,

		monitorAssets = "audio",
		refreshAssets = function(element)
			element.selfStyle.hueshift = audioAsset.color/8
		end,

		click = function(element)
		end,

		swallowPress = true,
		press = function(element)
			if element.popup ~= nil then
				element.popup = nil
			end

			local parentElement = element

			--Popup: reparented to the popup layer, so it does not inherit the dock
			--cascade -- route its own ThemeEngine snapshot so {framedPanel} themes.
			--Transient (rebuilt each open), so it picks up the active scheme without
			--an OnThemeChanged. ColorStyles is the data-driven swatch (8 hues).
			element.popup = gui.Panel{
				styles = ThemeEngine.MergeStyles{
					ColorStyles[1],
					ColorStyles[2],
					{
						selectors = {"audioItemColor"},
						hmargin = 4,
						vmargin = 4,
					},
				},
				classes = {"framedPanel"},
				width = 80,
				height = "auto",
				halign = "right",
				flow = "horizontal",
				wrap = true,
				create = function(element)
					local children = {}
					for i=0,7 do
						children[#children+1] = gui.Panel{
							classes = {"audioItemColor"},
							hueshift = i/8,
							press = function()
								audioAsset.color = i
								audioAsset:Upload()
								parentElement.popup = nil

							end,
						}

					end

					element.children = children
				end,
			}

		end,
	}

	local playButton

	local hovered = false

	local BeginScroll = function()
		if preview or titleLabel.editing then
			return
		end

		if titleLabel.renderedWidth > titleLabelContainer.renderedWidth then
			titleLabel.thinkTime = 0.01
		end
	end

	local StopScroll = function()
		titleLabel.x = 0
		titleLabel.thinkTime = nil
	end

	local CalculateScroll = function()
		if hovered or (audioAsset.duration > 20 and playButton:HasClass("playing")) then
			BeginScroll()
		else
			StopScroll()
		end
	end


	durationLabel = gui.Label{
		classes = {"durationLabel"},
		text = FormatTime(audioAsset.duration, audioAsset.duration),
		halign = "right",
		valign = "top",
		hmargin = 4,
		vmargin = 0,

		monitorAssets = "audio",
		refreshAssets = function(element)
			element.text = FormatTime(audioAsset.duration, audioAsset.duration)
		end,
	}

	playButton = gui.Panel{
		classes = {"playButton"},
		rotate = 90,
		y = -3,
		halign = "center",
		valign = "center",
		floating = true,
		refreshPlayingAudio = function(element)
			local soundEvent = audio.currentlyPlaying[audioAsset.id]
			element:SetClass("playing", soundEvent ~= nil)

			CalculateScroll()
		end,
	}

	local loopButton = gui.Panel{
		classes = {"loopIcon", cond(audioAsset.loop, nil, "disabled")},
		halign = "left",
		valign = "top",
		floating = true,
		monitorAssets = "audio",
		refreshAssets = function(element)
			element:SetClass("disabled", not audioAsset.loop)
		end,
		click = function(element)
			--swallow click.
		end,
		press = function(element)
			audioAsset.loop = not audioAsset.loop
			audioAsset:Upload()

			element:SetClass("disabled", not audioAsset.loop)
		end,
	}

	local muted = false
	local volumePanel

	if options.volumeSlider ~= false then
		volumeSlider = gui.Slider{
			value = audioAsset.volume,
			minValue = 0,
			maxValue = 1,
			handleSize = "100%",
			sliderWidth = 80,
			style = {
				width = '60%',
				height = 16,
			},
			events = {
				preview = function(element)
					--change to only preview locally?
					audio.SetSoundEventVolume(audioAsset.id, element.value)
				end,
				confirm = function(element)
					audio.SetSoundEventVolume(audioAsset.id, element.value)

					local doc = mod:GetDocumentSnapshot(soundEventDocId)
					doc:BeginChange()
					doc.data.volume = element.value
					doc:CompleteChange("Set audio volume")
				end,
				refreshPlayingAudio = function(element)
					local doc = mod:GetDocumentSnapshot(soundEventDocId)
					element.value = cond(doc.data.volume ~= nil, doc.data.volume, audioAsset.volume)
				end,
			}
		}

		local volumeIcon = nil
		volumeIcon = gui.Panel{
			--Icon glyph: bgcolor "white" is image-tint-neutral so the PNG shows
			--at native colors; {hoverable} supplies token-free hover feedback.
			classes = {"hoverable"},
			bgimage = 'ui-icons/AudioVolumeButton.png',
			bgcolor = "white",
			width = 12,
			height = 12,
			valign = 'center',
			events = {
				click = function(element)
					--swallow
				end,
				press = function(element)
					muted = not muted
					if muted then
						volumeIcon.bgimage = 'ui-icons/AudioMuteButton.png'
						audio.SetSoundEventVolume(audioAsset.id, 0)
					else
						volumeIcon.bgimage = 'ui-icons/AudioVolumeButton.png'
						audio.SetSoundEventVolume(audioAsset.id, volumeSlider.value)
					end

					volumeSlider:SetClass('hidden', muted)
				end,
			},
		}

		volumePanel = gui.Panel{
			style = {
				height = 'auto',
				width = '90%',
				flow = 'horizontal',
			},
			y = 2,
			floating = true,
			valign = "bottom",
			halign = "center",
			children = {
				volumeIcon,

				volumeSlider,

			}
		}
	end

	--Per-track category selector (Music / Ambience / Effects). Phase 1 interim
	--authoring path -- writes asset.category, which routes the library track
	--through the matching mix group. In Phase 2 the categories become the
	--top-level library folders and this dropdown rides the list row. A dropdown
	--(not a chip/segment) so the caret advertises that the category is changeable.
	--Lives in the space the volume slider would occupy, so it is only shown on
	--library tiles (where options.categorySelector is set), never the soundboard.
	local categorySelector = nil
	if options.categorySelector then
		--Normalise the stored category to a dropdown option id. An unset
		--category reads back as nil (never set) OR "" (set to nil through the
		--current AudioAssetLua setter, which stringifies nil to ""); both mean
		--"uncategorised". NB Lua treats "" as truthy, so a bare `category or
		--"none"` would surface a blank option for the empty-string case.
		local CurrentCategoryId = function()
			local c = audioAsset.category
			if c == nil or c == "" then
				return "none"
			end
			return c
		end

		categorySelector = gui.Dropdown{
			floating = true,
			valign = "bottom",
			halign = "center",
			y = 1,
			width = "92%",
			height = 16,
			fontSize = 11,
			options = {
				{ id = "none", text = "-" },
				{ id = "music", text = "Music" },
				{ id = "ambience", text = "Ambience" },
				{ id = "effects", text = "Effects" },
			},
			idChosen = CurrentCategoryId(),

			monitorAssets = "audio",
			refreshAssets = function(element)
				element.idChosen = CurrentCategoryId()
			end,

			change = function(element)
				local newCategory = element.idChosen
				if newCategory == "none" then
					newCategory = nil
				end
				audioAsset.category = newCategory
				audioAsset:Upload()
			end,
		}
	end


	local body = gui.Panel{
		classes = {"audioItemBody"},
		durationLabel,
		playButton,
		loopButton,
		volumePanel,
		categorySelector,
		colorPanel,

		hueshift = audioAsset.color/8,

		monitorAssets = "audio",
		refreshAssets = function(element)
			element.selfStyle.hueshift = audioAsset.color/8
		end,

		click = function(element)

			if playButton:HasClass("playing") then
				audio.StopSoundEvent(audioAsset.id)
			else
				local volume = 1
				
				if volumeSlider ~= nil then
					volume = volumeSlider.value
				end
				audio.PlaySoundEvent{
					asset = audioAsset,
					volume = volume,
				}
			end


		end,
	}

	local currentDragParent = nil --our parent slot when the drag started.
	local currentDragTarget = nil

	resultPanel = gui.Panel{
		classes = {"audioItemPanel"},
		draggable = true,

		data = {
			slot = slot,
		},

		setAudio = function(element, assetid)
			audioAsset = assets.audioTable[assetid]
			soundEventDocId = string.format("soundevent-%s", audioAsset.id)
			element:FireEventTree("refreshAssets")
			element:FireEventTree("refreshPlayingAudio")
		end,

		click = function(element)
			element.popup = nil
		end,

		rightClick = function(element)
			if slot ~= nil then
				return
			end

			local moveEntries = {}
			for k,folder in pairs(assets.audioFoldersTable) do
				if k ~= (audioAsset.parentFolder or defaultFolder) then
					moveEntries[#moveEntries+1] = {
						text = folder.description,
						click = function()
							audioAsset.parentFolder = k
							audioAsset:Upload()
							element.popup = nil
						end
					}
				end
			end

			local popupEntries ={
				{
					text = "Rename",
					click = function()
						element.popup = nil
						StopScroll()
						titleLabel:BeginEditing()
					end,
				},

				{
					text = "Delete",
					click = function()
						audioAsset.hidden = true
						audioAsset:Upload()
					end,

				},
			}

			if dmhub.GetSettingValue("dev") then
				popupEntries[#popupEntries+1] = {
					text = "Copy ID",
					click = function()
						dmhub.CopyToClipboard(audioAsset.id)
						element.popup = nil
					end,
				}
			end

            popupEntries[#popupEntries+1] = {
				text = "Move to...",
				submenu = moveEntries,
            }

			element.popup = gui.ContextMenu{
				width = 180,
				entries = popupEntries,
			}
		end,

		hover = function(element)
			hovered = true
			CalculateScroll()
		end,

		dehover = function(element)
			hovered = false
			CalculateScroll()
		end,

		canDragOnto = function(element, target)
        	return target:HasClass("playgrid") or target:HasClass("audioFolder")
        end,

		beginDrag = function(element)
			currentDragParent = element.parent
			--currentDragParent:FireEvent("preview", audioAsset.id)

			currentDragTarget = nil
		end,

		dragging = function(element, target)
			if target == currentDragParent then
				target = nil
			end

			if currentDragTarget == target then
				return
			end

			if currentDragTarget ~= nil and currentDragTarget.valid then
				currentDragTarget:FireEvent("preview") --clear the preview.
			end

			if target ~= nil then
				target:FireEvent("preview", audioAsset.id)
			end

			currentDragTarget = target
		end,

		drag = function(element, target)
			if currentDragParent ~= nil then
				currentDragParent:FireEvent("preview")
			end

			currentDragParent = nil

			if currentDragTarget ~= nil and currentDragTarget.valid and target ~= currentDragTarget then
				--this shouldn't really happen but just in case we get a drag without a dragging first where
				--the target has changed.
				currentDragTarget:FireEvent("preview") --clear the preview.
			end

			currentDragTarget = nil

			if target == nil then
				return
			end

			if target:HasClass("audioFolder") then
				audioAsset.parentFolder = target.data.folderid
				audioAsset:Upload()
			elseif target:HasClass("playgrid") then
				local doc = mod:GetDocumentSnapshot(target.data.docid)
				local id = audioAsset.id

				if slot ~= nil and resultPanel.parent.data.docid ~= nil then
					--if this is a drag to the same grid, then it exchanges documents.
					if resultPanel.parent == target then
						--just dragging onto ourselves, so a no-op.
						return
					end

					local src = mod:GetDocumentSnapshot(resultPanel.parent.data.docid)
					src:BeginChange()
					src.data.assetid = doc.data.assetid
					src:CompleteChange("Set Sound Slot")
				end

				--only allow a sound to be assigned to one item in the grid.
				for _,sibling in ipairs(target.parent.children) do
					if sibling ~= target and sibling ~= resultPanel.parent and sibling.data.docid ~= nil then
						local siblingdoc = mod:GetDocumentSnapshot(sibling.data.docid)
						if siblingdoc.data.assetid == audioAsset.id then
							siblingdoc:BeginChange()
							siblingdoc.data.assetid = nil
							siblingdoc:CompleteChange("Set Sound Slot")
						end
					end
				end

				doc:BeginChange()
				doc.data.assetid = id
				doc:CompleteChange("Set Sound Slot")
			end
		end,


		titleLabelContainer,
		body,

	}

	return resultPanel
end


CreateSoundPanel = function()
	if not dmhub.isDM then
		return nil
	end
	

	local assetEntries = {}
	local currentlyPlayingEntries = {}

	local CreateAudioFolder = function(folderid)
		local expanded = false
		local body

		local folder = assets.audioFoldersTable[folderid]

		local folderLabel = gui.Label{
				classes = {"folderLabel", "sizeL"},
				text = folder.description,
				change = function(element)
					element.editable = false
					if element.text == "" then
						element.text = folder.description
					end
					folder.description = element.text
					folder:Upload()
				end,
			}

		local beforeSearchExpanded = nil

		local header = gui.Panel{
			classes = {"folderHeader", "bgAlt", "hoverable", cond(expanded, "expanded")},
			gui.Panel{
				classes = {"audioFolderTri", "bgFg"},
			},

			folderLabel,

			setExpanded = function(element, val)
				if cond(val, true, false) ~= element:HasClass("expanded") then
					element:FireEvent("press")
				end
			end,

			search = function(element, info)
				if beforeSearchExpanded == nil then
					beforeSearchExpanded = element:HasClass("expanded")
				end
				element:FireEvent("setExpanded", info.folders[folderid])
				element:SetClass("collapsed", not info.folders[folderid])
			end,

			clearsearch = function(element, info)
				element:SetClass("collapsed", false)
				if beforeSearchExpanded ~= nil then
					element:FireEvent("setExpanded", beforeSearchExpanded)
					beforeSearchExpanded = nil
				end
			end,

			press = function(element)
				expanded = not expanded
				element:SetClass("expanded", expanded)
				body:SetClass("collapseAnim", not expanded)
				if expanded then
					body:FireEvent("refreshAssets")
				end
			end,


			rightClick = function(element)
				local entries = {
					{
						text = "Rename Folder",
						click = function()
							folderLabel.editable = true
							folderLabel:BeginEditing()

							element.popup = nil
						end,
					},
				}

				if #body.children == 0 then
					entries[#entries+1] = {
						text = "Delete Folder",
						hidden = true,
						click = function()
							folder.hidden = true
							folder:Upload()
						end,
					}
				end

				element.popup = gui.ContextMenu{
					width = 180,
					entries = entries,
				}
			end,
		}

		local assetEntries = {}

		body = gui.Panel{
			width = "100%",
			height = "auto",
			halign = "left",
			flow = "horizontal",
			classes = {cond(expanded, nil, "collapseAnim")},
			wrap = true,

			monitorAssets = "audio",
			refreshAssets = function(element)
				if not expanded then
					return
				end


				local newChildren = {}
				local newAssetEntries = {}
				for k,audioAsset in pairs(assets.audioTable) do
					if (not audioAsset.hidden) and (audioAsset.parentFolder or defaultFolder) == folderid then
						newAssetEntries[k] = assetEntries[k] or CreatePlayerSlot{
							halign = "left",
							uiscale = 0.8,
							hmargin = 2,
							createAudioPanel(audioAsset, { volumeSlider = false, categorySelector = true }),
							search = function(element, info)
								element:SetClass("collapsed", not info.assets[k])
							end,
							clearsearch = function(element)
								element:SetClass("collapsed", false)
							end,
						}
							
						newChildren[#newChildren+1] = newAssetEntries[k]
					end
				end

				assetEntries = newAssetEntries
				element.children = newChildren


			end,
		}

		return gui.Panel{
			classes = {"folderContainer", "audioFolder"},

			dragTarget = true,

			data = {
				folderid = folderid,
				ord = function()
					return folder.ord
				end,
			},

			header,
			body,
		}

	end

	local audioFolderPanels = {}

	--Layout-only replacement for the legacy folder-library style global. Colors
	--now ride theme classes on the elements ({bgAlt}+{hoverable} header, {bgFg}
	--triangle, label default @fgStrong). The triangle uses a local class name
	--("audioFolderTri") so it does not collide with the themed DefaultStyles
	--{triangle} rule, while keeping the parent:expanded flip. Drag highlight is
	--handled by the engine's themed {drag-target} classes on the folder container.
	local audioLibraryItems = gui.Panel{
		styles = {
			{
				selectors = {"folderContainer"},
				flow = "vertical",
				width = "100%",
				height = "auto",
				valign = "top",
			},
			{
				selectors = {"folderHeader"},
				width = "100%",
				flow = "horizontal",
				height = 24,
			},
			{
				selectors = {"audioFolderTri"},
				bgimage = "panels/triangle.png",
				width = 16,
				height = 12,
				hmargin = 4,
				valign = "center",
				halign = "left",
			},
			{
				selectors = {"audioFolderTri", "parent:expanded"},
				scale = {x = 1, y = -1},
				transitionTime = 0.1,
			},
			{
				selectors = {"folderLabel"},
				width = "80%",
				height = "100%",
				halign = "left",
				textAlignment = "left",
			},
		},

		height = 500,

		vscroll = true,


		valign = "top",

		monitorAssets = "audio",

		events = {
			create = function(element)
				element:FireEvent('refreshAssets')
			end,

			refreshAssets = function(element)

				local children = {}
				local newAudioFolderPanels = {}
				for k,audioFolder in pairs(assets.audioFoldersTable) do
					newAudioFolderPanels[k] = audioFolderPanels[k] or CreateAudioFolder(k)
					children[#children+1] = newAudioFolderPanels[k]
				end

				table.sort(children, function(a,b) return a.data.ord() < b.data.ord() end)
				element.children = children

				audioFolderPanels = newAudioFolderPanels

			end,
		},
	}

	local audioLibrary = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Panel{
			classes = {"bgFg"},
			width = "100%",
			height = 2,
			bgimage = "panels/square.png",
		},

		gui.Panel{
			width = "auto",
			height = "auto",
			flow = "horizontal",
			vmargin = 4,
			halign = "center",
			gui.SearchInput{
				search = function(element, str)
					if str == "" then
						audioLibraryItems:FireEventTree("clearsearch")
					else
						local clips = {}
						local folders = {}
						for k,audioAsset in pairs(assets.audioTable) do
							if (not audioAsset.hidden) and string.find(string.lower(audioAsset.description), str) then
								clips[k] = true
								folders[audioAsset.parentFolder or defaultFolder] = true
							end
						end
						audioLibraryItems:FireEventTree("search", { assets = clips, folders = folders })
					end
					
				end,
			},

			gui.Button{
				classes = {"addButton", "sizeM"},
				hmargin = 4,
				valign = "center",
				press = function(element)
					mod.shared.ImportAudio()
				end,
			}
		},

		audioLibraryItems,

		gui.Button{
			classes = {"sizeM"},
			icon = "game-icons/open-folder.png",
			halign = "right",
			press = function(element)
				assets:UploadNewAudioFolder{
					description = "Sounds",
				}
			end,
		},

		classes = {"collapsed"},

		maximize = function(element)
			element:SetClass("collapsed", false)
		end,

		minimize = function(element)
			element:SetClass("collapsed", true)
		end,
	}

	local MakeSpectrumSample = function(index)
		return gui.Panel{
			classes = {"bgFg"},
			bgimage = "panels/square.png",
			valign = "center",
			halign = "center",
			width = 3,
			height = 4,
			cornerRadius = 1.5,
		}
	end

	local globalMuteButton = nil
	local sampleMeasures = {}

	--Visible "music ducked" badge (Phase 1 feedback, NOT a control): overlays the
	--now-playing strip whenever an anthem is holding the music duck, so a
	--hard-of-hearing director can see the music has dipped without hearing it. The
	--duck on/off + matrix CONFIG lives in Audio Studio, not here. Driven by the
	--same g_drawSteelAnthemState the anthem node polls.
	--{bgWarning} amber pill + {fgInverse} text track the active scheme; {sizeXxs}
	--= 10pt, {bold} for weight. The square bgimage + corner radius stay inline.
	local duckBadge = gui.Label{
		classes = {"hidden", "bgWarning", "fgInverse", "bold", "sizeXxs"},
		floating = true,
		halign = "center",
		valign = "top",
		y = 2,
		text = "music ducked",
		bgimage = "panels/square.png",
		cornerRadius = 6,
		hpad = 6,
		vpad = 2,
		borderBox = true,
		width = "auto",
		height = "auto",
	}

	local audioVisualize = gui.Panel{
		width = "100%",
		height = 60,
		vmargin = 4,
		flow = "horizontal",

		create = function(element)
			local children = {}

			for i=1,16 do
				children[#children+1] = MakeSpectrumSample(i)
			end

			sampleMeasures = children


			element.children = children


			globalMuteButton = gui.Panel{
				classes = {"hidden"},
				floating = true,
				width = 45,
				height = 40,
				bgcolor = "white",
				halign = "center",
				valign = "center",
				press = function(element)
					audio.muted = not audio.muted
					audio.UploadMuted()
				end,
				rightClick = function(element)
					element.popup = gui.ContextMenu{
						width = 180,
						entries = {
							{
								text = string.format("Stop All Sounds (%d)", audio.numActiveSoundEvents),
								click = function()
									element.popup = nil
									audio.StopAllSoundEvents()
								end,
							},
						}
					}

				end,
				styles = {
					{
						bgimage = 'ui-icons/AudioVolumeButton.png',
					},
					{
						selectors = {"muted"},
						bgimage = 'ui-icons/AudioMuteButton.png',
					},
					{
						selectors = {"hover"},
						brightness = 3,
					},
				}
			}

			element:AddChild(globalMuteButton)
			element:AddChild(duckBadge)

		end,

		thinkTime = 0.01,
		think = function(element)
			local samples = dmhub.GetAudioSpectrum()
			for i,s in ipairs(sampleMeasures) do
				local y = 1 - 1/math.pow(100*i, samples[i])
				s.selfStyle.height = 4 + y*60
			end

			globalMuteButton:SetClass("hidden", audio.numPlayingSounds == 0)
			globalMuteButton:SetClass("muted", audio.muted)

			local anthemState = rawget(_G, "g_drawSteelAnthemState")
			duckBadge:SetClass("hidden", anthemState == nil or not anthemState.duckActive)
		end,
	}

	local masterVolumeSlider = gui.Slider{
		style = {
			width = 170,
			height = 16,
			halign = "right",
			valign = "center",
		},

		sliderWidth = 150,
		labelWidth = 0,
		labelFormat = "",

		minValue = 0,
		maxValue = 1,

		refreshPlayingAudio = function(element)
			element.value = cond(audio.muted, 0, audio.masterVolume)
		end,

		value = cond(audio.muted, 0, audio.masterVolume),

		confirm = function(element)
			audio.masterVolume = element.value
			if audio.masterVolume > 0 and audio.muted then
				audio.muted = false
				audio.UploadMuted()
			end
			audio.UploadMasterVolume()

		end,

		preview = function(element)

			audio.masterVolume = element.value
			if audio.masterVolume > 0 and audio.muted then
				audio.muted = false
				audio.UploadMuted()
				audio.UploadMasterVolume()
			end
		end,

	}

	--"Levels" -- the parent mix-group faders for the table (the one-stop mixing
	--surface, replacing the standalone game-wide master slider). Master is LIVE
	--(writes audio.masterVolume). The category + system faders below are meant to
	--write the shared broadcast layer (GroupShared), which is a deferred engine
	--follow-up, so until that lands they render dimmed + non-interactable. Per-user
	--trims + the granular UI Sounds children live in Settings -> Audio. Default
	--expanded so the master control stays as reachable as it was before.
	--The shared "audio mix" document holds the DM's per-group BROADCAST levels (the table
	--mix), synced to every client. The faders below write it; every client pushes its
	--values into the local engine via audio.SetGroupShared (the GroupShared layer). This
	--is the broadcast half of the two-layer model: final = personal x broadcast x duck;
	--every factor is 0..1, so a player's personal trim can only attenuate below the
	--broadcast (the cap rule self-enforces). Uses the module-scope broadcastGroupIds list.
	local GetBroadcastLevel = function(groupid)
		local doc = mod:GetDocumentSnapshot(audioMixDocId)
		local b = doc.data.broadcast
		if b == nil or b[groupid] == nil then
			return 1
		end
		return b[groupid]
	end

	--Push every broadcast value from the doc into THIS client's engine cache.
	local ApplyBroadcastToEngine = function()
		local doc = mod:GetDocumentSnapshot(audioMixDocId)
		local b = doc.data.broadcast or {}
		for _,g in ipairs(broadcastGroupIds) do
			audio.SetGroupShared(g, b[g] or 1)
		end
	end

	local MakeBroadcastFader = function(groupid)
		return gui.Slider{
			style = {
				width = 170,
				height = 16,
				halign = "right",
				valign = "center",
			},

			sliderWidth = 150,
			labelWidth = 0,
			labelFormat = "",

			minValue = 0,
			maxValue = 1,

			value = GetBroadcastLevel(groupid),

			--A remote change (another client / the loaded doc) repaints the fader and
			--re-pushes the value to the local engine.
			monitorGame = mod:GetDocumentSnapshot(audioMixDocId).path,
			refreshGame = function(element)
				element.value = GetBroadcastLevel(groupid)
				audio.SetGroupShared(groupid, element.value)
			end,

			--Live local feedback while dragging.
			preview = function(element)
				audio.SetGroupShared(groupid, element.value)
			end,

			--Commit to the shared doc so the table mix syncs to all clients.
			confirm = function(element)
				audio.SetGroupShared(groupid, element.value)
				local doc = mod:GetDocumentSnapshot(audioMixDocId)
				doc:BeginChange()
				if doc.data.broadcast == nil then
					doc.data.broadcast = {}
				end
				doc.data.broadcast[groupid] = element.value
				doc:CompleteChange("Set " .. groupid .. " broadcast level")
			end,
		}
	end

	local MakeFaderRow = function(labelText, slider, dimmed)
		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = 22,
			valign = "center",
			vmargin = 1,
			opacity = dimmed and 0.4 or 1,
			gui.Label{
				classes = {"sizeXs"},
				text = labelText,
				width = 76,
				height = "auto",
				halign = "left",
				valign = "center",
			},
			slider,
		}
	end

	local levelsBody
	local levelsArrow

	levelsArrow = gui.ExpandoArrow{ classes = {"expanded"} }

	local levelsHeader = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		vmargin = 2,
		press = function(element)
			--starts expanded; first press collapses.
			local expanding = levelsBody:HasClass("collapsed")
			levelsBody:SetClass("collapsed", not expanding)
			levelsArrow:SetClass("expanded", expanding)
		end,

		levelsArrow,

		gui.Label{
			classes = {"bold"},
			text = "Levels",
			width = "auto",
			height = "auto",
			hmargin = 4,
			halign = "left",
			valign = "center",
		},
	}

	levelsBody = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		gui.Label{
			text = "Adjust the levels of each mix group for your table. More granular controls can be found in Settings->Audio.",
			fontSize = 11,
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 2,
		},

		MakeFaderRow("Master", masterVolumeSlider, false),
		MakeFaderRow("Music", MakeBroadcastFader("music"), false),
		MakeFaderRow("Ambience", MakeBroadcastFader("ambience"), false),
		MakeFaderRow("Effects", MakeBroadcastFader("effects"), false),
		MakeFaderRow("UI Sounds", MakeBroadcastFader("uisounds"), false),
		MakeFaderRow("Anthem", MakeBroadcastFader("anthem"), false),
	}

	--Mirror the persisted broadcast levels into this client's engine as soon as the panel
	--builds (covers the DM opening the panel after a reload). Non-DM clients are handled by
	--the always-on AudioMixBroadcast monitor.
	ApplyBroadcastToEngine()

	local levelsSection = gui.Panel{
		flow = "vertical",
		width = "96%",
		height = "auto",
		halign = "center",
		vmargin = 4,

		levelsHeader,
		levelsBody,
	}

	--Anthem node (Phase 1): a collapsible drawer listing each player hero, the
	--anthem they have loaded, a local preview (audition on the director's own
	--ears -- asset:Play() is local-only, never broadcast), and a broadcast volume
	--that writes token.anthemVolume (the same value the token Appearance tab sets).
	--Now-playing state is polled from g_drawSteelAnthemState, published by the
	--initiative bar's anthem hook (MCDMInitiativeBar.lua).
	local CreateAnthemNode = function()
		local previewingCharid = nil
		local previewInstance = nil

		local StopPreview = function()
			if previewInstance ~= nil then
				pcall(function() previewInstance:Stop() end)
				previewInstance = nil
			end
			previewingCharid = nil
		end

		local CreateAnthemRow = function(charid)
			local token = dmhub.GetTokenById(charid)
			if token == nil then
				return nil
			end

			local anthemNameLabel = gui.Label{
				text = "- no anthem set",
				fontSize = 11,
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 4,
			}

			--{success} green tracks the scheme; {sizeXxs} = 10pt, {bold} weight.
			local nowPlayingLabel = gui.Label{
				classes = {"hidden", "success", "bold", "sizeXxs"},
				text = "now playing",
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 4,
			}

			local previewButton

			--Swap the glyph between a play triangle and a stop square depending on
			--whether THIS row's anthem is the one currently previewing (the square
			--png reads as a stop regardless of the inherited 90deg rotate).
			local UpdatePreviewIcon = function()
				if previewButton == nil then
					return
				end
				local previewing = previewingCharid == charid and previewInstance ~= nil and previewInstance.playing
				previewButton.bgimage = previewing and "panels/square.png" or "panels/triangle.png"
			end

			previewButton = gui.Panel{
				bgimage = "panels/triangle.png",
				bgcolor = "white",
				rotate = 90,
				width = 12,
				height = 12,
				halign = "right",
				valign = "center",
				hmargin = 4,
				press = function(element)
					local t = dmhub.GetTokenById(charid)
					if t == nil then
						return
					end
					local anthemId = t.anthem
					if anthemId == nil or anthemId == "" then
						return
					end
					if previewingCharid == charid and previewInstance ~= nil and previewInstance.playing then
						StopPreview()
						UpdatePreviewIcon()
						return
					end
					StopPreview()
					local asset = assets.audioTable[anthemId]
					if asset == nil then
						return
					end
					previewInstance = asset:Play()
					previewingCharid = charid
					if previewInstance ~= nil then
						previewInstance.volume = t.anthemVolume or 1
					end
					UpdatePreviewIcon()
				end,
			}

			local volumeSlider = gui.Slider{
				value = token.anthemVolume or 1,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 70,
				labelWidth = 0,
				labelFormat = "",
				style = {
					width = 80,
					height = 14,
					halign = "right",
					valign = "center",
				},
				--Live-adjust the local preview while dragging so the change is
				--audible immediately rather than only on stop/start.
				preview = function(element)
					if previewingCharid == charid and previewInstance ~= nil and previewInstance.playing then
						previewInstance.volume = element.value
					end
				end,
				--Commit on release. Writing token.anthemVolume + UploadAppearance also
				--updates a live broadcast anthem via the initiative bar's refreshGame.
				confirm = function(element)
					local t = dmhub.GetTokenById(charid)
					if t == nil then
						return
					end
					t.anthemVolume = element.value
					t:UploadAppearance()
					if previewingCharid == charid and previewInstance ~= nil and previewInstance.playing then
						previewInstance.volume = element.value
					end
				end,
			}

			return gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = 26,
				valign = "center",
				vmargin = 1,
				data = { charid = charid },

				thinkTime = 0.5,
				think = function(element)
					local t = dmhub.GetTokenById(charid)
					if t == nil then
						return
					end
					local anthemId = t.anthem
					local has = anthemId ~= nil and anthemId ~= ""
					if has then
						local a = assets.audioTable[anthemId]
						anthemNameLabel.text = (a ~= nil and a.description) or "(anthem)"
					else
						anthemNameLabel.text = "- no anthem set"
					end
					previewButton:SetClass("hidden", not has)
					volumeSlider:SetClass("hidden", not has)
					--Clear stale preview ownership if this row's preview finished on
					--its own, then keep the play/stop glyph in sync (also reverts this
					--row's glyph when another row takes over the single preview slot).
					if previewingCharid == charid and (previewInstance == nil or not previewInstance.playing) then
						previewInstance = nil
						previewingCharid = nil
					end
					UpdatePreviewIcon()
					--rawget: g_drawSteelAnthemState is published by MCDMInitiativeBar;
					--rawget avoids the uninitialized-global read error if that file is
					--ever absent, instead of erroring every think tick.
					local st = rawget(_G, "g_drawSteelAnthemState")
					nowPlayingLabel:SetClass("hidden", st == nil or st.tokenid ~= charid)
				end,

				gui.CreateTokenImage(token, {
					width = 22,
					height = 22,
					halign = "left",
					valign = "center",
					hmargin = 2,
					interactable = false,
				}),

				gui.Label{
					text = token.name or "Hero",
					fontSize = 13,
					width = 80,
					height = "auto",
					halign = "left",
					valign = "center",
				},

				anthemNameLabel,
				nowPlayingLabel,
				previewButton,
				volumeSlider,
			}
		end

		local rowsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			create = function(element)
				local children = {}
				for _,partyid in ipairs(GetAllParties() or {}) do
					for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
						local row = CreateAnthemRow(charid)
						if row ~= nil then
							children[#children+1] = row
						end
					end
				end
				element.children = children
			end,
		}

		local body
		local arrow

		arrow = gui.ExpandoArrow{}

		local header = gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			press = function(element)
				--expanding when the body is currently collapsed.
				local expanding = body:HasClass("collapsed")
				body:SetClass("collapsed", not expanding)
				arrow:SetClass("expanded", expanding)
			end,

			arrow,

			gui.Label{
				classes = {"bold"},
				text = "Anthems",
				width = "auto",
				height = "auto",
				hmargin = 4,
				halign = "left",
				valign = "center",
			},
		}

		body = gui.Panel{
			classes = {"collapsed"},
			flow = "vertical",
			width = "100%",
			height = "auto",

			gui.Label{
				text = "Preview or adjust volume levels for each player's anthem.",
				fontSize = 11,
				width = "100%",
				height = "auto",
				textWrap = true,
				vmargin = 2,
			},

			rowsPanel,
		}

		return gui.Panel{
			flow = "vertical",
			width = "96%",
			height = "auto",
			halign = "center",
			vmargin = 4,

			destroy = function(element)
				StopPreview()
			end,

			header,
			body,
		}
	end

	local anthemNode = CreateAnthemNode()

	--Content root of the Audio dock panel. It inherits the DockablePanel host's
	--ThemeEngine cascade (DockablePanel.lua runs GetStyles at the dock root), so
	--no GetStyles/OnThemeChanged is declared here. The rules below are component
	--layout plus the data-driven library-tile coloring (asset.color hueshift on a
	--red/black base) -- a deliberate keep, not chrome; the tiles are replaced by
	--the list view in the next chunk.
	local mainPanel = gui.Panel{
		styles = {
			{
				halign = 'left',
				valign = 'top',
				width = "100%",
				height = "auto",
				flow = "vertical",
			},
			{
				selectors = {"audioItemPanel"},
				width = 113,
				height = 64,
				flow = "vertical",
				halign = "center",
				valign = "center",
			},
			{
				selectors = {"audioItemTitleContainer"},
				width = "95%",
				height = "30%",
				flow = "vertical",

			},
			{
				selectors = {"audioItemTitle"},
				fontSize = 14,
				hmargin = 4,
				halign = "left",
				width = "auto",
				textAlignment = "center",
				height = "100%",
			},

			ColorStyles,

			{
				selectors = {"playButton"},
				bgimage = "panels/triangle.png",
				bgcolor = "black",
				width = 45*0.5,
				height = 40*0.5,
				y = 2,
			},
			{
				selectors = {"playButton", "playing"},
				bgimage = "panels/square.png",
				scale = 0.9,
				y = 2,
			},

			{
				selectors = {"loopIcon"},
				bgimage = "game-icons/infinity.png",
				bgcolor = "black",
				width = 16,
				height = 16,
				hmargin = 4,
			},

			{
				selectors = {"loopIcon", "disabled"},
				opacity = 0.7,
			},

			{
				selectors = {"audioItemBody"},
				width = "100%",
				height = "70%",
				halign = "center",
				valign = "bottom",
				bgimage = "panels/square.png",
                saturation = 0.3,
				bgcolor = "red",
				cornerRadius = 4,

			},
			{
				selectors = {"audioItemBody", "hover"},
				brightness = 1.8,
			},
			{
				selectors = {"durationLabel"},
				fontSize = 12,
				bold = true,
				color = "black",
				width = "auto",
				height = "auto",

			},
		},

		refreshAudio = function(element)
			element:FireEventTree("refreshPlayingAudio")
		end,

		children = {
			audioVisualize,

			--Opens the session-prep surface (a floating LaunchablePanel) without
			--disturbing the dock. Library / mixer / soundboard prep live there.
			gui.Button{
				classes = {"sizeS"},
				text = "Audio Studio",
				width = "90%",
				height = 26,
				halign = "center",
				vmargin = 2,
				press = function(element)
					LaunchablePanel.LaunchPanelByName("Audio Studio")
				end,
			},

			levelsSection,

			anthemNode,

			CreateAudioGrid(),

			gui.DockablePanelMaximizeButton(),

			audioLibrary,
			gui.Button{
				classes = {"addButton", "sizeXl", "collapsed"},
				width = 32,
				height = 32,
				valign = 'bottom',
				halign = 'right',
				events = {
					click = function(element)

						dmhub.OpenFileDialog{
							id = 'AudioAssets',
							extensions = {'ogg', 'mp3', 'wav', 'flac'},
							multiFiles = true,
							prompt = "Choose audio to load",
							open = function(path)
	
								local operation
								
							
								local assetid = assets:UploadAudioAsset{
									path = path,
									error = function(text)
										gui.ModalMessage{
											title = 'Error creating audio',
											message = text,
										}
									end,

									upload = function(id)
										if operation ~= nil then
											operation.progress = 1
											operation:Update()
										end
									end,
									progress = function(percent)
										if operation ~= nil then
											operation.progress = percent
											operation:Update()
										end
									end,
								}

								if assetid ~= nil then
									operation = dmhub.CreateNetworkOperation()
									operation.description = "Uploading Audio..."
									operation.status = "Uploading..."
									operation.progress = 0.0
									operation:Update()
								end
							end,
						}
					end,
				},
			}
		}
	}

	audio.events:Listen(mainPanel)

	mainPanel:ScheduleEvent("refreshAudio", 0.01)

	return mainPanel
end


--=== Audio Studio (LaunchablePanel content) ===============================
--A floating session-prep window. It is a STANDALONE surface (not a child of a
--themed dock host), so it owns its ThemeEngine root: GetStyles() + a paired
--OnThemeChanged so it recolors live on a scheme switch.

--Upload action for the Studio toolbar "+ Add audio".
local OpenAudioStudioUpload = function()
	dmhub.OpenFileDialog{
		id = 'AudioAssets',
		extensions = {'ogg', 'mp3', 'wav', 'flac'},
		multiFiles = true,
		prompt = "Choose audio to load",
		open = function(path)
			local operation
			local assetid = assets:UploadAudioAsset{
				path = path,
				error = function(text)
					gui.ModalMessage{ title = 'Error creating audio', message = text }
				end,
				upload = function(id)
					if operation ~= nil then operation.progress = 1; operation:Update() end
				end,
				progress = function(percent)
					if operation ~= nil then operation.progress = percent; operation:Update() end
				end,
			}
			if assetid ~= nil then
				operation = dmhub.CreateNetworkOperation()
				operation.description = "Uploading Audio..."
				operation.status = "Uploading..."
				operation.progress = 0.0
				operation:Update()
			end
		end,
	}
end

--One library row: play/stop + name + per-row category dropdown + volume. Plays
--through the same GameSoundEvent path as the dock tiles.
local CreateAudioStudioRow = function(audioAsset)
	local soundEventDocId = string.format("soundevent-%s", audioAsset.id)

	local playButton = gui.Panel{
		bgimage = "panels/triangle.png",
		bgcolor = "white",
		rotate = 90,
		width = 12,
		height = 12,
		halign = "left",
		valign = "center",
		hmargin = 6,
		refreshPlayingAudio = function(element)
			local playing = audio.currentlyPlaying[audioAsset.id] ~= nil
			element.bgimage = playing and "panels/square.png" or "panels/triangle.png"
		end,
		press = function(element)
			if audio.currentlyPlaying[audioAsset.id] ~= nil then
				audio.StopSoundEvent(audioAsset.id)
			else
				audio.PlaySoundEvent{ asset = audioAsset, volume = audioAsset.volume }
			end
		end,
	}

	local nameLabel = gui.Label{
		text = audioAsset.description,
		width = "100%-240",
		height = "auto",
		halign = "left",
		valign = "center",
		monitorAssets = "audio",
		refreshAssets = function(element)
			element.text = audioAsset.description
		end,
	}

	local CurrentCategoryId = function()
		local c = audioAsset.category
		if c == nil or c == "" then
			return "none"
		end
		return c
	end

	local categorySelector = gui.Dropdown{
		width = 110,
		height = 22,
		fontSize = 12,
		halign = "right",
		valign = "center",
		hmargin = 4,
		options = {
			{ id = "none", text = "-" },
			{ id = "music", text = "Music" },
			{ id = "ambience", text = "Ambience" },
			{ id = "effects", text = "Effects" },
		},
		idChosen = CurrentCategoryId(),
		monitorAssets = "audio",
		refreshAssets = function(element)
			element.idChosen = CurrentCategoryId()
		end,
		change = function(element)
			local newCategory = element.idChosen
			if newCategory == "none" then
				newCategory = nil
			end
			audioAsset.category = newCategory
			audioAsset:Upload()
		end,
	}

	local volumeSlider = gui.Slider{
		value = audioAsset.volume,
		minValue = 0,
		maxValue = 1,
		sliderWidth = 70,
		labelWidth = 0,
		labelFormat = "",
		style = { width = 90, height = 16, halign = "right", valign = "center" },
		events = {
			preview = function(element)
				audio.SetSoundEventVolume(audioAsset.id, element.value)
			end,
			confirm = function(element)
				audio.SetSoundEventVolume(audioAsset.id, element.value)
				local doc = mod:GetDocumentSnapshot(soundEventDocId)
				doc:BeginChange()
				doc.data.volume = element.value
				doc:CompleteChange("Set audio volume")
			end,
			refreshPlayingAudio = function(element)
				local doc = mod:GetDocumentSnapshot(soundEventDocId)
				element.value = cond(doc.data.volume ~= nil, doc.data.volume, audioAsset.volume)
			end,
		},
	}

	return gui.Panel{
		classes = {"bordered", "hoverable"},
		flow = "horizontal",
		width = "100%",
		height = 30,
		valign = "center",
		vmargin = 1,
		playButton,
		nameLabel,
		categorySelector,
		volumeSlider,
	}
end

--Labelled placeholder for the prep controls that arrive in later chunks.
local CreateStudioPlaceholder = function(title)
	return gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		pad = 8,
		borderBox = true,
		vmargin = 4,
		gui.Label{ classes = {"bold", "sizeS"}, text = title, width = "auto", height = "auto", halign = "left" },
		gui.Label{ classes = {"fgMuted"}, text = "Coming in a later chunk", width = "auto", height = "auto", halign = "left", vmargin = 2 },
	}
end

CreateAudioStudio = function()
	if not dmhub.isDM then
		return nil
	end

	--Library list (flat, alphabetical, all non-hidden audio assets).
	local libraryListItems = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "100%-24",
		vscroll = true,
		valign = "top",
		monitorAssets = "audio",
		create = function(element)
			element:FireEvent("refreshAssets")
		end,
		refreshAssets = function(element)
			local entries = {}
			for _,audioAsset in pairs(assets.audioTable) do
				if not audioAsset.hidden then
					entries[#entries+1] = audioAsset
				end
			end
			table.sort(entries, function(a,b) return (a.description or "") < (b.description or "") end)
			local children = {}
			for _,audioAsset in ipairs(entries) do
				children[#children+1] = CreateAudioStudioRow(audioAsset)
			end
			element.children = children
			element:FireEventTree("refreshPlayingAudio")
		end,
	}

	local leftColumn = gui.Panel{
		flow = "vertical",
		width = "58%",
		height = "100%",
		hmargin = 4,
		gui.Label{ classes = {"bold", "sizeS"}, text = "Library", width = "auto", height = "auto", halign = "left", vmargin = 2 },
		libraryListItems,
	}

	local rightColumn = gui.Panel{
		flow = "vertical",
		width = "40%",
		height = "100%",
		hmargin = 4,
		vscroll = true,
		CreateStudioPlaceholder("Mixer"),
		CreateStudioPlaceholder("Ducking"),
		CreateStudioPlaceholder("Soundboard"),
	}

	local body = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "100%-92",
		valign = "top",
		leftColumn,
		rightColumn,
	}

	local header = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		gui.Label{
			classes = {"sizeXl", "bold"},
			text = "Audio Studio",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
		},
		gui.Button{
			classes = {"sizeS"},
			text = "+ Add audio",
			width = 120,
			height = 28,
			halign = "right",
			valign = "center",
			press = function(element)
				OpenAudioStudioUpload()
			end,
		},
	}

	local root
	root = gui.Panel{
		classes = {"launchablePanel"},
		styles = ThemeEngine.GetStyles(),
		width = 960,
		height = 680,
		flow = "vertical",
		pad = 16,
		data = {},
		create = function(element)
			element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.GetStyles()
				end
			end)
		end,
		destroy = function(element)
			if element.data.themeSub ~= nil then
				element.data.themeSub:Deregister()
				element.data.themeSub = nil
			end
		end,

		refreshAudio = function(element)
			element:FireEventTree("refreshPlayingAudio")
		end,

		header,
		gui.MCDMDivider{ bmargin = 8 },
		body,
	}

	audio.events:Listen(root)
	root:ScheduleEvent("refreshAudio", 0.01)

	return root
end


if mod.canedit then
    Commands.RegisterMacro{
        name = "savedefaultaudio",
        summary = "save audio defaults",
        doc = "Usage: /savedefaultaudio\nSaves the current audio configuration as defaults.",
        command = function()
            mod:SaveDefaultDocuments(function()
                dmhub.Debug("Saved audio")
            end)
        end,
    }
end
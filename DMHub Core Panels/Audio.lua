local mod = dmhub.GetModLoading()

local CreateSoundPanel

DockablePanel.Register{
	name = "Audio",
	icon = "icons/standard/Icon_App_Audio.png",
	vscroll = false,
    dmonly = true,
	minHeight = 470,
	maxHeight = 470,
	content = function()
		return CreateSoundPanel()
	end,
	hasNewContent = function()
		return module.HasNovelContent("audio")
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
		bgcolor = "red", --Styles.textColor,
	},
	{
		selectors = {"audioItemColor", "hover"},
		brightness = 1.5,
	},
}



local CreatePlayerSlot = function(params)
	local slot = params.slot
	params.slot = nil

	local classes = {"playerSlot"}
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
		borderColor = Styles.textColor,
		flow = "none",
		vmargin = 2,
		cornerRadius = 4,
		halign = "center",
		valign = "center",
		bgimage = "panels/square.png",
		bgcolor = "black",
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

	local tinyClasses = {"tinyPanel"}
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
				bgcolor = Styles.textColor,
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
		bgimage = 'panels/square.png',
		selfStyle = {
			bgcolor = '#cc0000',
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
		bgimage = 'panels/square.png',
		floating = true,
		--classes = {'hidden'},
		style = {
			bgcolor = 'grey',
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

			element.popup = gui.Panel{
				styles = {
					Styles.Panel,
					ColorStyles,
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
			bgimage = 'ui-icons/AudioVolumeButton.png',
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
			styles = {
				{
					bgcolor = 'black',
					width = 12,
					height = 12,
					valign = 'center',
				},
				{
					selectors = 'hover',
					bgcolor = '#880000',
				},
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


	local body = gui.Panel{
		classes = {"audioItemBody"},
		durationLabel,
		playButton,
		loopButton,
		volumePanel,
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
				classes = {"folderLabel"},
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
			classes = {"folderHeader", cond(expanded, "expanded")},
			gui.Panel{
				classes = {"triangle"},
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
				body:SetClass("collapsed-anim", not expanded)
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
			classes = {cond(expanded, nil, "collapsed-anim")},
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
							createAudioPanel(audioAsset, { volumeSlider = false }),
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

	local audioLibraryItems = gui.Panel{
		styles = {
			Styles.FolderLibrary,
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
			width = "100%",
			height = 2,
			bgimage = "panels/square.png",
			bgcolor = Styles.textColor,
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

			gui.AddButton{
				width = 24,
				height = 24,
				valign = "center",
				press = function(element)
					mod.shared.ImportAudio()
				end,
			}
		},

		audioLibraryItems,

		gui.Panel{
			classes = {"clickableIcon"},
			width = 24,
			height = 24,
			halign = "right",
			bgimage = "game-icons/open-folder.png",
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
			bgimage = "panels/square.png",
			bgcolor = Styles.textColor,
			valign = "center",
			halign = "center",
			width = 3,
			height = 4,
			cornerRadius = 1.5,
		}
	end

	local globalMuteButton = nil
	local sampleMeasures = {}

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
				bgcolor = Styles.textColor,
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
		end,
	}

	local masterVolumeSlider = gui.Slider{
		style = {
			width = 200,
			height = 20,
			halign = "center",
		},

		sliderWidth = 200,
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

	local mainPanel = gui.Panel{
		styles = {
			Styles.Default,
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
				color = Styles.textColor,
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
			masterVolumeSlider,

			CreateAudioGrid(),

			gui.DockablePanelMaximizeButton(),

			audioLibrary,
			gui.AddButton{
				classes = {"collapsed"},
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
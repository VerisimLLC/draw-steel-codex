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

--Game-scoped doc holding the manual order of clips within each library folder.
--AudioAssetLua has no writable `ord` (folders do, clips don't), so the Audio
--Studio library keeps per-folder clip order here: data.order[folderid] = { assetid,
--... }. Clips not listed sort after the listed ones, alphabetically.
local audioClipOrderDocId = "audioClipOrder"
mod:RegisterDocumentForCheckpointBackups(audioClipOrderDocId)

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

--Parent mix-group faders, shared by the dock panel and the Audio Studio Mixer card.
--Hoisted to module scope so both surfaces build from ONE implementation and cannot
--drift. The category faders write the shared "audio mix" doc (the broadcast/GroupShared
--layer); every client mirrors the doc into its engine via the SyncBroadcastLevelsToEngine
--poll above, so the dock and Studio stay in lockstep automatically.

--Broadcast level (0..1) the DM set for a group, 1.0 if untouched.
local function GetBroadcastLevel(groupid)
	local doc = mod:GetDocumentSnapshot(audioMixDocId)
	local b = doc.data.broadcast
	if b == nil or b[groupid] == nil then
		return 1
	end
	return b[groupid]
end

--Push every broadcast value from the doc into THIS client's engine cache.
local function ApplyBroadcastToEngine()
	local doc = mod:GetDocumentSnapshot(audioMixDocId)
	local b = doc.data.broadcast or {}
	for _,g in ipairs(broadcastGroupIds) do
		audio.SetGroupShared(g, b[g] or 1)
	end
end

--Master fader: live, writes audio.masterVolume (and un-mutes on a raise). A gui element
--has a single parent, so each surface needs its OWN master slider -- this is a factory,
--not a shared instance.
local function MakeMasterFader()
	return gui.Slider{
		style = {
			width = 170,
			height = 16,
			halign = "right",
			valign = "center",
		},

		sliderWidth = 150,
		labelWidth = 30,
		labelFormat = "percent",

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
end

--A broadcast (table-mix) fader for one mix group. Writes the shared doc on confirm,
--previews live while dragging, and repaints + re-pushes on a remote change.
local function MakeBroadcastFader(groupid)
	return gui.Slider{
		style = {
			width = 170,
			height = 16,
			halign = "right",
			valign = "center",
		},

		sliderWidth = 150,
		labelWidth = 30,
		labelFormat = "percent",

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

--One "label + fader" row. dimmed renders the row muted (used for faders whose backing
--engine layer is not wired yet). A few px of horizontal padding keeps the fader + its
--editable readout off any scrollbar on the right.
local function MakeFaderRow(labelText, slider, dimmed)
	return gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 22,
		valign = "center",
		vmargin = 1,
		hpad = 10,
		borderBox = true,
		opacity = dimmed and 0.4 or 1,
		--Match the editable readout to the row's Level title (12pt, not the slider's
		--default 14) and add a couple px gap between the slider and the number.
		styles = {
			{ selectors = {"sliderLabel"}, fontSize = 12, lmargin = 5, priority = 6 },
		},
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

--Per-user remembered collapse state for each dock section. Replaces the old
--Compact/Expanded binary: the panel is now a "Controls" drawer over individually
--collapsible sections (Levels / Anthems / Soundboard), each persisting its own
--open/closed so collapsing one to cut scrolling sticks across reopens. Collapsing
--"Controls" itself is the new "compact". Defaults: Controls + Levels open, the
--rest closed (glanceable on first open, the desk one tap away).
local audioSectionSettings = {
	controls = setting{ id = "audiosec_controls", description = "Audio Controls drawer collapsed", storage = "preference", default = false },
	levels = setting{ id = "audiosec_levels", description = "Audio Levels section collapsed", storage = "preference", default = false },
	anthems = setting{ id = "audiosec_anthems", description = "Audio Anthems section collapsed", storage = "preference", default = true },
	soundboard = setting{ id = "audiosec_soundboard", description = "Audio Soundboard section collapsed", storage = "preference", default = true },
}

local function GetSectionCollapsed(id)
	local s = audioSectionSettings[id]
	if s == nil then return false end
	return s:Get() == true
end

local function SetSectionCollapsed(id, collapsed)
	local s = audioSectionSettings[id]
	if s ~= nil then s:Set(collapsed) end
end

--A collapsible section: an UPPERCASE title header with a disclosure chevron on the
--RIGHT over a body panel, persisting its open/closed to the per-user section setting
--(id). `prominent` gives the header a filled bar (used for the top-level Controls
--umbrella); the inner sections (Levels/Anthems/Soundboard) are light headers and are
--separated by dividers instead. All sections share this one builder for a consistent
--look. Returns the section panel + its body so callers can wrap pre-built content.
local MakeCollapsibleSection = function(id, title, body, prominent)
	local SetArrowState
	local headerChildren

	if prominent then
		--Prominent header (the Controls umbrella) mirrors the HEROIC RESOURCES section
		--bar: a hamburger glyph left, a larger uppercase title, and a chevron (NOT the
		--filled triangle) on the right that rotates with the open/closed state.
		--gui.CollapseArrow is the SAME chevron the tactical panel uses: a down-arrow
		--that flips to point UP when collapsed (collapseSet). Same visual language as the
		--TacPanel headers; sized up so it is not dwarfed by the sub-section triangles.
		local chevron = gui.CollapseArrow{
			width = 20,
			height = 13,
			halign = "right",
			valign = "center",
		}
		SetArrowState = function(collapsed)
			chevron:SetClass("collapseSet", collapsed)
		end
		headerChildren = {
			gui.Panel{
				bgimage = "icons/icon_common/icon_common_4.png",
				bgcolor = "#999999",
				width = 14,
				height = 14,
				halign = "left",
				valign = "center",
				hmargin = 2,
			},
			gui.Label{
				classes = {"bold", "sizeS"},
				text = string.upper(title),
				width = "100%-44",
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 4,
			},
			chevron,
		}
	else
		local arrow = gui.ExpandoArrow{ halign = "right", valign = "center" }
		SetArrowState = function(collapsed)
			arrow:SetClass("expanded", not collapsed)
		end
		headerChildren = {
			gui.Label{
				classes = {"bold", "sizeXs"},
				text = string.upper(title),
				width = "100%-20",
				height = "auto",
				halign = "left",
				valign = "center",
			},
			arrow,
		}
	end

	local function Apply(collapsed)
		body:SetClass("collapsed", collapsed)
		SetArrowState(collapsed)
	end

	local headerClasses = { "hoverable" }
	if prominent then headerClasses[#headerClasses+1] = "bgAlt" end
	local header = gui.Panel{
		classes = headerClasses,
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		vmargin = 1,
		hpad = 8,
		vpad = 4,
		borderBox = true,
		press = function(element)
			local collapsed = not body:HasClass("collapsed")
			Apply(collapsed)
			SetSectionCollapsed(id, collapsed)
		end,
		children = headerChildren,
	}
	Apply(GetSectionCollapsed(id))
	return gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		header,
		body,
	}
end

--Max height of the dock's scrollable body (everything below the pinned now-playing
--strip + view toggle). The dock host is a fixed 470px (minHeight=maxHeight in the
--registration, vscroll=false); the pinned top eats ~100px, leaving ~360 for the
--body. Compact content is shorter than this so it never scrolls; Expanded (with an
--expanded Anthems drawer / many heroes) scrolls past it instead of clipping.
local audioScrollMaxHeight = 360

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

	--The folder library used to live here as a maximize-to-reveal drawer in the
	--dock. It has moved to the Audio Studio (the "Audio Studio" button opens it),
	--keeping the dock to live controls only. CreateAudioFolder above is kept
	--dormant for the Studio's later nested-folder rebuild; audioFolderPanels is its
	--cache. No in-dock library panel is built anymore.

	--Master mute / stop-all. Click toggles mute; right-click opens stop-all. Lives in
	--the now-playing header so it is always reachable (it used to float on the
	--spectrum strip, which this section replaces).
	local globalMuteButton = gui.Panel{
		bgcolor = "white",
		width = 18,
		height = 18,
		halign = "right",
		valign = "center",
		hmargin = 4,
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
		linger = function(element)
			gui.Tooltip("Mute (right-click: stop all)")(element)
		end,
		styles = {
			{ bgimage = "ui-icons/AudioVolumeButton.png" },
			{ selectors = {"muted"}, bgimage = "ui-icons/AudioMuteButton.png" },
			{ selectors = {"hover"}, brightness = 2 },
		},
	}

	--The clip currently playing for a category (Music/Ambience), found by scanning
	--audio.currentlyPlaying; one track per channel is the norm, so the first match wins.
	local function PlayingTrackForCategory(cat)
		for assetid,_ in pairs(audio.currentlyPlaying) do
			local a = assets.audioTable[assetid]
			if a ~= nil and a.category == cat then
				return assetid, a
			end
		end
		return nil, nil
	end

	--Now-playing hero card. Music is the lead channel (big title + read-only progress +
	--Stop); Ambience is a slim always-visible footer line (name + stop). Seek (a
	--draggable scrubber) and pause/resume need engine work -- .time is read-only and
	--there is no pause API -- so the transport is display-only progress + Stop for now;
	--the sleek look ships, seek/pause land with the engine pass. m_musicId/m_ambienceId
	--hold the resolved channel ids so the stop buttons act on the live track.
	local m_musicId = nil
	local m_ambienceId = nil

	local statusDot = gui.Panel{
		classes = {"npStatusDot"},
		bgimage = "panels/square.png",
		width = 8,
		height = 8,
		cornerRadius = 4,
		valign = "center",
		hmargin = 4,
	}
	local statusLabel = gui.Label{
		classes = {"sizeXxs", "fgMuted"},
		text = "Nothing playing",
		width = "100%-72",
		height = "auto",
		halign = "left",
		valign = "center",
	}

	local titleLabel = gui.Label{
		classes = {"sizeL", "bold"},
		text = "Nothing playing",
		width = "100%-8",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
		textWrap = false,
		textOverflow = "ellipsis",
	}
	local subtitleLabel = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = "",
		width = "100%-8",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
	}

	local stopButton = gui.Panel{
		classes = {"hidden"},
		bgimage = "panels/square.png",
		bgcolor = "white",
		width = 14,
		height = 14,
		valign = "center",
		hmargin = 4,
		press = function(element)
			if m_musicId ~= nil then
				audio.StopSoundEvent(m_musicId)
			end
		end,
		linger = function(element)
			gui.Tooltip("Stop")(element)
		end,
	}
	local timeCurrent = gui.Label{
		classes = {"sizeXxs", "fgMuted"},
		text = "",
		width = 32,
		height = "auto",
		halign = "right",
		valign = "center",
		textAlignment = "right",
	}
	local progressFill = gui.Panel{
		classes = {"bgAccent"},
		bgimage = "panels/square.png",
		width = "0%",
		height = "100%",
		halign = "left",
		valign = "center",
	}
	local progressBar = gui.Panel{
		classes = {"bgAlt"},
		bgimage = "panels/square.png",
		width = "100%-104",
		height = 5,
		valign = "center",
		hmargin = 6,
		cornerRadius = 2.5,
		borderBox = true,
		progressFill,
	}
	local timeTotal = gui.Label{
		classes = {"sizeXxs", "fgMuted"},
		text = "",
		width = 32,
		height = "auto",
		halign = "left",
		valign = "center",
	}

	local transportRow = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 18,
		valign = "center",
		vmargin = 2,
		stopButton,
		timeCurrent,
		progressBar,
		timeTotal,
	}

	local ambienceName = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = "silent",
		width = "100%-110",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
		textWrap = false,
		textOverflow = "ellipsis",
	}
	local ambienceStop = gui.Panel{
		classes = {"hidden"},
		bgimage = "panels/square.png",
		bgcolor = "white",
		width = 12,
		height = 12,
		halign = "right",
		valign = "center",
		hmargin = 4,
		press = function(element)
			if m_ambienceId ~= nil then
				audio.StopSoundEvent(m_ambienceId)
			end
		end,
		linger = function(element)
			gui.Tooltip("Stop ambience")(element)
		end,
	}
	local ambienceFooter = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 18,
		valign = "center",
		vmargin = 1,
		gui.Label{
			classes = {"sizeXs", "bold"},
			text = "Ambience",
			width = 66,
			height = "auto",
			halign = "left",
			valign = "center",
			hmargin = 4,
		},
		ambienceName,
		ambienceStop,
	}

	local function UpdateNowPlaying()
		--Duck state rides the status dot/line (amber dot + "Music ducked for Anthem")
		--instead of a separate badge, now that the dot already signals play state.
		local anthemState = rawget(_G, "g_drawSteelAnthemState")
		local ducked = anthemState ~= nil and anthemState.duckActive == true

		local mid, ma = PlayingTrackForCategory("music")
		m_musicId = mid
		if ma ~= nil then
			local ev = audio.currentlyPlaying[mid]
			local t = (ev ~= nil and ev.time) or 0
			local dur = ma.duration or 0
			statusDot:SetClass("playing", not ducked)
			statusDot:SetClass("ducked", ducked)
			statusLabel.text = ducked and "Music ducked for Anthem" or "Playing to your table"
			titleLabel.text = ma.description or "(unnamed)"
			titleLabel:SetClass("fgMuted", false)
			subtitleLabel.text = "Music"
			stopButton:SetClass("hidden", false)
			timeCurrent.text = FormatTime(t, dur)
			timeTotal.text = FormatTime(dur, dur)
			progressFill.selfStyle.width = (dur > 0) and string.format("%f%%", math.min(100, (100*t)/dur)) or "0%"
		else
			statusDot:SetClass("playing", false)
			statusDot:SetClass("ducked", false)
			statusLabel.text = "Nothing playing"
			titleLabel.text = "Nothing playing"
			titleLabel:SetClass("fgMuted", true)
			subtitleLabel.text = ""
			stopButton:SetClass("hidden", true)
			timeCurrent.text = ""
			timeTotal.text = ""
			progressFill.selfStyle.width = "0%"
		end

		local aid, aa = PlayingTrackForCategory("ambience")
		m_ambienceId = aid
		if aa ~= nil then
			ambienceName.text = aa.description or "(unnamed)"
			ambienceName:SetClass("fgMuted", false)
			ambienceStop:SetClass("hidden", false)
		else
			ambienceName.text = "silent"
			ambienceName:SetClass("fgMuted", true)
			ambienceStop:SetClass("hidden", true)
		end

		globalMuteButton:SetClass("muted", audio.muted)
	end

	--Now-playing section -- replaces the decorative spectrum (brief flagged it as
	--reclaimable space). UpdateNowPlaying runs on a light poll (progress, natural
	--track-ends, duck state -- none guaranteed to fire an audio event) and on the
	--dock's refreshAudio -> refreshPlayingAudio tree fire for instant play/stop.
	local nowPlayingSection = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		vmargin = 4,
		styles = {
			{ selectors = {"npStatusDot"}, bgcolor = "#888888" },
			{ selectors = {"npStatusDot", "playing"}, bgcolor = "#5cb85c" },
			{ selectors = {"npStatusDot", "ducked"}, bgcolor = "#d9a441" },
		},

		create = function(element)
			UpdateNowPlaying()
		end,
		refreshPlayingAudio = function(element)
			UpdateNowPlaying()
		end,
		thinkTime = 0.2,
		think = function(element)
			UpdateNowPlaying()
		end,

		--Status row: status dot + line, with the Studio launch + mute buttons hard right.
		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			statusDot,
			statusLabel,
			globalMuteButton,
			gui.Button{
				icon = "icons/standard/Icon_App_GameControls.png",
				width = 18,
				height = 18,
				halign = "right",
				valign = "center",
				hmargin = 4,
				press = function(element)
					LaunchablePanel.LaunchPanelByName("Audio Studio")
				end,
				linger = function(element)
					gui.Tooltip("Open Audio Studio")(element)
				end,
			},
		},

		titleLabel,
		subtitleLabel,
		transportRow,
		ambienceFooter,
	}

	--Master fader + the broadcast Levels faders. The fader helpers (MakeMasterFader /
	--MakeBroadcastFader / MakeFaderRow) are module-scoped so the dock and the Audio
	--Studio Mixer card build from ONE implementation; both write the same shared
	--"audio mix" doc, so the two surfaces stay in lockstep.
	local masterVolumeSlider = MakeMasterFader()

	--Master fader -- the always-visible level; reuses masterVolumeSlider, which
	--writes audio.masterVolume live. A gui element has one parent, so master lives
	--here and NOT in categoryFaders below.
	local masterRow = MakeFaderRow("Master", masterVolumeSlider, false)

	--Category broadcast faders -- the body of the "Levels" section. These write the
	--shared "audio mix" doc (the GroupShared table-mix layer). The Levels header
	--(MakeCollapsibleSection) drives the collapsed state and persists it.
	local categoryFaders = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		MakeFaderRow("Music", MakeBroadcastFader("music"), false),
		MakeFaderRow("Ambience", MakeBroadcastFader("ambience"), false),
		MakeFaderRow("Effects", MakeBroadcastFader("effects"), false),
		MakeFaderRow("UI Sounds", MakeBroadcastFader("uisounds"), false),
		MakeFaderRow("Anthem", MakeBroadcastFader("anthem"), false),

		gui.Label{
			text = "More granular controls can be found in Settings->Audio.",
			fontSize = 11,
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 2,
		},
	}

	--Mirror the persisted broadcast levels into this client's engine as soon as the panel
	--builds (covers the DM opening the panel after a reload). Non-DM clients are handled by
	--the always-on AudioMixBroadcast monitor.
	ApplyBroadcastToEngine()

	--"Levels" section: collapsible header over the category faders, inside Controls.
	--Master stays out of it (always visible above Controls).
	local levelsSection = MakeCollapsibleSection("levels", "Levels", categoryFaders)

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

		--Return just the BODY; the collapsible header + persistence come from
		--MakeCollapsibleSection at the call site, so every section looks identical.
		return gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",

			destroy = function(element)
				StopPreview()
			end,

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
	end

	--Each section uses MakeCollapsibleSection so the headers look identical and all
	--persist their own state. ("Anthem ducks music" has moved to the Studio Anthem
	--controls, so it no longer lives on the dock.)
	local anthemsSection = MakeCollapsibleSection("anthems", "Anthems", CreateAnthemNode())

	local soundboardBody = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		CreateAudioGrid(),
	}
	local soundboardSection = MakeCollapsibleSection("soundboard", "Soundboard", soundboardBody)

	--"Controls" -- the single drawer that replaces the Compact/Expanded toggle, with a
	--prominent (filled-bar) header. Collapsing it is the new "compact"; expanding it
	--reveals the inner sections, each individually collapsible (state persisted) and
	--set off by a thin divider so each reads as its own area.
	local controlsInner = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		levelsSection,
		gui.MCDMDivider{ width = "100%", halign = "left", vmargin = 4 },
		anthemsSection,
		gui.MCDMDivider{ width = "100%", halign = "left", vmargin = 4 },
		soundboardSection,
	}

	local controlsSection = MakeCollapsibleSection("controls", "Controls", controlsInner, true)

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
			--Pinned top: the now-playing section stays put. Everything below scrolls so
			--an expanded Controls drawer (esp. an open Anthems section with many heroes)
			--scrolls rather than clipping the fixed 470px dock. With Controls collapsed
			--the body is short (now-playing + master only) and does not scroll.
			nowPlayingSection,

			gui.Panel{
				vscroll = true,
				width = "100%",
				height = "auto",
				maxHeight = audioScrollMaxHeight,
				flow = "vertical",
				halign = "center",

				--A divider under the now-playing "Player" sets it off as its own area.
				gui.MCDMDivider{ width = "100%", halign = "left", vmargin = 4 },

				--Master is always visible above the collapsible Controls drawer.
				masterRow,
				controlsSection,
			},
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
--through the same GameSoundEvent path as the dock tiles. opts carries the library
--tree's drag wiring (draggable / canDragOnto / drag) so a clip can be dragged into
--a folder; it is nil when the row is used outside the tree.
--DM-only audition ("cue"): only one library clip previews at a time. asset:Play()
--is local-only (never broadcast) and bypasses the mix groups/master, so a cue is raw
--local playback for "does this track fit", not a level-matched monitor. Tracked at
--module scope so starting a cue in one row stops the cue in another.
local g_studioCueInstance = nil
local g_studioCueAssetId = nil
local function StopStudioCue()
	if g_studioCueInstance ~= nil then
		pcall(function() g_studioCueInstance:Stop() end)
	end
	g_studioCueInstance = nil
	g_studioCueAssetId = nil
end
local function StudioCueActive(assetid)
	return g_studioCueAssetId == assetid and g_studioCueInstance ~= nil and g_studioCueInstance.playing
end

local CreateAudioStudioRow = function(audioAsset, opts)
	opts = opts or {}
	local soundEventDocId = string.format("soundevent-%s", audioAsset.id)

	--Broadcast Play/Stop (heard by the whole table via PlaySoundEvent). A dedicated
	--play glyph -- NOT the chevron-like triangle, which read as a folder expander.
	--Playing state swaps to a stop square tinted "live" (amber via the playing class).
	local playButton = gui.Panel{
		classes = {"audioBroadcastButton"},
		bgimage = "ui-icons/AudioPlayButton.png",
		width = 18,
		height = 18,
		valign = "center",
		hmargin = 3,
		refreshPlayingAudio = function(element)
			local playing = audio.currentlyPlaying[audioAsset.id] ~= nil
			element.bgimage = playing and "panels/square.png" or "ui-icons/AudioPlayButton.png"
			element:SetClass("playing", playing)
		end,
		press = function(element)
			if audio.currentlyPlaying[audioAsset.id] ~= nil then
				audio.StopSoundEvent(audioAsset.id)
			else
				audio.PlaySoundEvent{ asset = audioAsset, volume = audioAsset.volume }
			end
		end,
		linger = function(element)
			gui.Tooltip("Play to the table")(element)
		end,
	}

	--DM-only audition (the eye glyph stands in for a headphone -- no headphone icon
	--ships). Local asset:Play(); turns "active" (green) while this row is cueing and
	--polls so it clears when the clip ends or another row takes over.
	local cueButton
	cueButton = gui.Panel{
		classes = {"audioCueButton"},
		bgimage = "icons/standard/Icon_App_Visible.png",
		width = 18,
		height = 18,
		valign = "center",
		hmargin = 3,
		press = function(element)
			if StudioCueActive(audioAsset.id) then
				StopStudioCue()
			else
				StopStudioCue()
				g_studioCueInstance = audioAsset:Play()
				g_studioCueAssetId = audioAsset.id
				if g_studioCueInstance ~= nil then
					g_studioCueInstance.volume = audioAsset.volume
				end
			end
			element:FireEvent("refreshCue")
		end,
		refreshCue = function(element)
			local active = StudioCueActive(audioAsset.id)
			element:SetClass("active", active)
			element.thinkTime = active and 0.3 or nil
		end,
		think = function(element)
			--Stop polling (and clear the active tint) once this row is no longer the
			--cueing one -- clip finished, or another row started its own cue.
			if not StudioCueActive(audioAsset.id) then
				element:SetClass("active", false)
				element.thinkTime = nil
			end
		end,
		create = function(element)
			element:FireEvent("refreshCue")
		end,
		linger = function(element)
			gui.Tooltip("Preview (Director Only)")(element)
		end,
	}

	--Title is the leftmost scan anchor and flexes to fill; the controls sit to its
	--right. Width is the column minus the fixed control cluster (play+cue+category+
	--volume+margins) -- a deterministic complement, since "100% available" collapses.
	local nameLabel = gui.Label{
		text = audioAsset.description,
		width = "100%-240",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
		textWrap = false,
		textOverflow = "ellipsis",
		monitorAssets = "audio",
		refreshAssets = function(element)
			element.text = audioAsset.description
		end,
		linger = function(element)
			gui.Tooltip(audioAsset.description)(element)
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
		width = 90,
		height = 22,
		fontSize = 12,
		valign = "center",
		hmargin = 3,
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
		style = { width = 80, height = 16, valign = "center" },
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

	--Floating drop-spacer at the row's top edge: a thin drag target that means
	--"insert before this row" for reorder. Invisible until the tree marks it active
	--during a drag, when it shows an accent line in the gap above the row.
	local reorderSpacer = nil
	if opts.draggable then
		reorderSpacer = gui.Panel{
			classes = {"audioClipSpacer"},
			floating = true,
			dragTarget = true,
			width = "100%",
			height = 6,
			y = -3,
			valign = "top",
			halign = "center",
			bgimage = "panels/square.png",
		}
	end

	return gui.Panel{
		classes = {"bordered", "hoverable", "audioClipRow"},
		flow = "horizontal",
		width = "100%",
		height = 30,
		valign = "center",
		vmargin = 1,
		data = { assetid = audioAsset.id },
		draggable = opts.draggable,
		canDragOnto = opts.canDragOnto,
		drag = opts.drag,
		dragging = opts.dragging,
		beginDrag = opts.beginDrag,
		--Click selects (drag is distinguished by movement). Lives on the whole row so
		--the click target is reliable; the play button / dropdown / volume keep their
		--own handlers.
		click = opts.onSelect and function(element)
			opts.onSelect(audioAsset.id)
		end or opts.click,
		refreshSelection = function(element, selectedSet)
			element:SetClass("selected", selectedSet ~= nil and selectedSet[audioAsset.id] == true)
		end,
		reorderSpacer,
		nameLabel,
		playButton,
		cueButton,
		categorySelector,
		volumeSlider,
	}
end

--Studio Soundboard curation card (right column). Five boards of twelve buttons,
--sharing the same audiogrid-<board>-<slot> documents the dock soundboard plays
--from: this surface ASSIGNS and CLEARS clips, the dock surface fires them. A clip
--occupies at most one button per board (de-duped on assign, matching the dock rule
--at the createAudioPanel drag handler). Clicking a filled button plays/stops it;
--clicking an empty one opens a searchable clip picker (all clips, Effects first).
local STUDIO_BOARDS = 5
local STUDIO_SLOTS = 12

local CreateStudioSoundboard = function()
	local m_board = 1
	local gridPanel
	local boardButtons = {}

	local function SlotDocId(board, slot)
		return string.format("audiogrid-%d-%d", board, slot)
	end

	--Every non-hidden library clip, Effects-category first then the rest, each group
	--alphabetical by name. The picker shows them all (inform, do not enforce); the
	--Effects-first ordering honours the soundboard's intent without hard-blocking.
	local function AssignableClips()
		local out = {}
		for _,asset in pairs(assets.audioTable) do
			if not asset.hidden then
				out[#out+1] = asset
			end
		end
		table.sort(out, function(a, b)
			local ae = (a.category == "effects")
			local be = (b.category == "effects")
			if ae ~= be then return ae end
			return (a.description or "") < (b.description or "")
		end)
		return out
	end

	local function ClearSlot(board, slot)
		local doc = mod:GetDocumentSnapshot(SlotDocId(board, slot))
		doc:BeginChange()
		doc.data.assetid = nil
		doc:CompleteChange("Clear soundboard button")
	end

	local function AssignSlot(board, slot, assetid)
		--De-dupe: a clip lives in only one button per board.
		for s = 1, STUDIO_SLOTS do
			if s ~= slot then
				local sd = mod:GetDocumentSnapshot(SlotDocId(board, s))
				if sd.data.assetid == assetid then
					sd:BeginChange()
					sd.data.assetid = nil
					sd:CompleteChange("Clear soundboard button")
				end
			end
		end
		local doc = mod:GetDocumentSnapshot(SlotDocId(board, slot))
		doc:BeginChange()
		doc.data.assetid = assetid
		doc:CompleteChange("Assign soundboard button")
	end

	--Searchable clip picker, anchored to the clicked button. Popups are reparented to
	--the popup layer and do not inherit the Studio cascade, so route their own
	--ThemeEngine snapshot (transient -- rebuilt each open, no OnThemeChanged needed).
	local function OpenAssignPopup(buttonElement, board, slot)
		local searchText = ""
		local listPanel

		local function MatchClip(asset)
			if searchText == "" then return true end
			return string.find(string.lower(asset.description or ""), searchText, 1, true) ~= nil
		end

		local function RebuildList()
			local children = {}
			for _,asset in ipairs(AssignableClips()) do
				if MatchClip(asset) then
					local a = asset
					children[#children+1] = gui.Label{
						classes = {"sizeS", "hoverable"},
						text = a.description or "(unnamed)",
						width = "100%",
						height = 22,
						halign = "left",
						valign = "center",
						hpad = 6,
						borderBox = true,
						textWrap = false,
						textOverflow = "ellipsis",
						press = function()
							AssignSlot(board, slot, a.id)
							buttonElement.popup = nil
						end,
					}
				end
			end
			if #children == 0 then
				children[1] = gui.Label{
					classes = {"fgMuted", "sizeXs"},
					text = "No clips match.",
					width = "100%",
					height = 22,
					hpad = 6,
					halign = "left",
					valign = "center",
				}
			end
			listPanel.children = children
		end

		listPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			maxHeight = 260,
			vscroll = true,
			vmargin = 4,
		}

		local searchInput = gui.Input{
			placeholderText = "Search clips...",
			text = "",
			width = "100%",
			height = 24,
			editlag = 0.1,
			edit = function(element)
				searchText = string.lower(element.text or "")
				RebuildList()
			end,
			change = function(element)
				searchText = string.lower(element.text or "")
				RebuildList()
			end,
		}

		buttonElement.popup = gui.Panel{
			styles = ThemeEngine.MergeStyles{},
			classes = {"framedPanel"},
			width = 240,
			height = "auto",
			flow = "vertical",
			pad = 8,
			borderBox = true,
			gui.Label{
				classes = {"bold", "sizeXs"},
				text = "Assign clip",
				width = "auto",
				height = "auto",
				halign = "left",
				vmargin = 1,
			},
			searchInput,
			listPanel,
			--Focus the search field on open so the DM can type straight away.
			create = function()
				RebuildList()
				searchInput.hasInputFocus = true
			end,
		}
	end

	--One soundboard button. board/slot are captured at build time; the grid is fully
	--rebuilt on a board switch so each button monitors its own board's document.
	local function CreateSlotButton(board, slot)
		local docid = SlotDocId(board, slot)
		local assetid = nil

		local nameLabel = gui.Label{
			classes = {"sizeXs", "collapsed"},
			text = "",
			width = "100%-4",
			height = "auto",
			halign = "center",
			valign = "center",
			textAlignment = "center",
			textWrap = true,
			maxVisibleLines = 2,
			textOverflow = "ellipsis",
		}

		local emptyLabel = gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "+ Assign",
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "center",
		}

		--Clear "x": a plain NON-floating child (floating children render in a separate
		--layer, so the cursor moving onto them drops the parent's hover state and the
		--style reveal thrashes in/out). Kept in the flow="none" button via halign/valign
		--so it overlays the top-right corner. Visibility is style-driven (base hidden;
		--shown only when the button is filled AND hovered -- parent:hover stays true while
		--the cursor is anywhere over the button, including over the x).
		local clearButton = gui.Panel{
			classes = {"audioStudioClearBtn"},
			bgimage = "panels/square.png",
			bgcolor = "clear",
			width = 16,
			height = 16,
			halign = "right",
			valign = "top",
			swallowPress = true,
			press = function()
				ClearSlot(board, slot)
			end,
			gui.Label{
				classes = {"sizeXs", "audioStudioClearGlyph"},
				text = "x",
				bgcolor = "clear",
				bold = true,
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "center",
			},
		}

		local button
		button = gui.Panel{
			classes = {"bordered", "hoverable"},
			flow = "none",
			width = 104,
			height = 46,
			margin = 4,
			pad = 4,
			borderBox = true,
			popupPositioning = "panel",
			monitorGame = mod:GetDocumentSnapshot(docid).path,
			monitorAssets = "audio",

			create = function(element)
				element:FireEvent("refreshGame")
			end,

			refreshGame = function(element)
				local doc = mod:GetDocumentSnapshot(docid)
				assetid = doc.data.assetid
				local asset = (assetid ~= nil) and assets.audioTable[assetid] or nil
				if asset ~= nil then
					nameLabel.text = asset.description or "(unnamed)"
					nameLabel:SetClass("collapsed", false)
					emptyLabel:SetClass("collapsed", true)
					clearButton:SetClass("filled", true)
				else
					assetid = nil
					nameLabel:SetClass("collapsed", true)
					emptyLabel:SetClass("collapsed", false)
					clearButton:SetClass("filled", false)
				end
				element:FireEvent("refreshPlayingAudio")
			end,

			refreshAssets = function(element)
				element:FireEvent("refreshGame")
			end,

			refreshPlayingAudio = function(element)
				element:SetClass("playing", assetid ~= nil and audio.currentlyPlaying[assetid] ~= nil)
			end,

			click = function(element)
				if assetid == nil then
					OpenAssignPopup(element, board, slot)
				elseif audio.currentlyPlaying[assetid] ~= nil then
					audio.StopSoundEvent(assetid)
				else
					local asset = assets.audioTable[assetid]
					if asset ~= nil then
						audio.PlaySoundEvent{ asset = asset, volume = asset.volume }
					end
				end
			end,

			nameLabel,
			emptyLabel,
			clearButton,
		}
		return button
	end

	local function BuildGrid()
		local children = {}
		for slot = 1, STUDIO_SLOTS do
			children[#children+1] = CreateSlotButton(m_board, slot)
		end
		gridPanel.children = children
	end

	gridPanel = gui.Panel{
		flow = "horizontal",
		wrap = true,
		width = "100%",
		height = "auto",
		halign = "center",
		vmargin = 4,
	}

	--Board selector: "Board" label + five segmented buttons. The active board carries
	--{selected} (themed fill). Switching rebuilds the grid for the new board.
	local boardRow = { }
	boardRow[#boardRow+1] = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = "Board",
		width = "auto",
		height = "auto",
		hmargin = 4,
		valign = "center",
	}
	for i = 1, STUDIO_BOARDS do
		local idx = i
		local btn = gui.Button{
			classes = {"sizeXs"},
			text = tostring(idx),
			width = 28,
			height = 22,
			hmargin = 2,
			valign = "center",
			press = function()
				if m_board == idx then return end
				m_board = idx
				for j, b in ipairs(boardButtons) do
					b:SetClass("selected", j == idx)
				end
				BuildGrid()
			end,
		}
		btn:SetClass("selected", idx == m_board)
		boardButtons[idx] = btn
		boardRow[#boardRow+1] = btn
	end

	local boardSelector = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		vmargin = 4,
		children = boardRow,
	}

	BuildGrid()

	return gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		pad = 8,
		borderBox = true,
		vmargin = 4,

		--Clear "x": shown on every filled button (dim), brightening on its own hover.
		--Deliberately NOT gated on parent:hover -- a hover-reveal that overlaps the
		--button via flow="none" lets the engine's per-frame hover resolution oscillate
		--between the x and the button when the cursor sits on the x (the flicker). An
		--always-on dim glyph sidesteps that entirely and reads as a clearer affordance.
		styles = {
			{ selectors = {"audioStudioClearBtn"}, hidden = 1, opacity = 0.4 },
			{ selectors = {"audioStudioClearBtn", "filled"}, hidden = 0 },
			{ selectors = {"audioStudioClearBtn", "hover"}, opacity = 1 },
		},

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			gui.Panel{
				flow = "horizontal",
				width = "100%-110",
				height = "auto",
				halign = "left",
				valign = "center",
				gui.Label{ classes = {"bold", "sizeS"}, text = "Soundboard", width = "auto", height = "auto", halign = "left", valign = "center" },
			},
			gui.Label{ classes = {"fgMuted", "sizeXs"}, text = "", width = "auto", height = "auto", halign = "right", valign = "center" },
		},

		boardSelector,
		gridPanel,

		gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "Click an empty button to assign a clip from your library; hover a filled button to clear it.",
			width = "100%",
			height = "auto",
			halign = "left",
			vmargin = 2,
		},
	}
end

--Studio Mixer card (right column): a full duplicate of the dock's parent faders so a DM
--who works from the Studio finds the core table mix here too. Same faders + same shared
--"audio mix" doc / SetGroupShared wiring as the dock (module-scoped helpers), so the two
--surfaces stay in lockstep. Master is live (audio.masterVolume); the five category faders
--write the broadcast layer.
local CreateStudioMixerCard = function()
	--Mirror the persisted broadcast levels into this client's engine on build.
	ApplyBroadcastToEngine()

	return gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		pad = 8,
		borderBox = true,
		vmargin = 4,

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			gui.Label{ classes = {"bold", "sizeS"}, text = "Mixer", width = "auto", height = "auto", halign = "left", valign = "center" },
		},

		gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "These are the broadcast levels (what the table hears). Players can manage their own mixing levels but the above levels set the ceiling.",
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 2,
		},

		gui.Label{ classes = {"bold", "sizeXs"}, text = "Broadcast Mixer Group Levels", width = "auto", height = "auto", halign = "left", vmargin = 2 },

		MakeFaderRow("Master", MakeMasterFader(), false),
		MakeFaderRow("Music", MakeBroadcastFader("music"), false),
		MakeFaderRow("Ambience", MakeBroadcastFader("ambience"), false),
		MakeFaderRow("Effects", MakeBroadcastFader("effects"), false),
		MakeFaderRow("UI Sounds", MakeBroadcastFader("uisounds"), false),
		MakeFaderRow("Anthem", MakeBroadcastFader("anthem"), false),
	}
end

--Studio Ducking card (right column). P1 = the "Duck Music Under Anthems" toggle (the
--anthemduckmusic game setting, also surfaced in Settings->Audio and read by the anthem
--hook) plus a depth control setting how far music dips while an anthem plays
--(anthemduckdepth, read live by the anthem hook). The per-target duck matrix is Phase 3-4,
--shown as a dimmed placeholder. Both settings are game-scoped/DM-owned; the toggle is
--think-synced so it tracks changes made from Settings->Audio.
local CreateStudioDuckingCard = function()
	local duckCheck
	duckCheck = gui.Check{
		text = "Duck Music Under Anthems",
		value = dmhub.GetSettingValue("anthemduckmusic"),
		change = function(element)
			dmhub.SetSettingValue("anthemduckmusic", element.value)
		end,
		--Track changes made elsewhere (Settings->Audio) so the toggle stays truthful.
		thinkTime = 0.5,
		think = function(element)
			local v = dmhub.GetSettingValue("anthemduckmusic")
			if v ~= element.value then
				element.value = v
			end
		end,
	}

	--Depth: the target level (0..1) music dips to while an anthem plays. Read on build;
	--committed on release (no think-sync, so it never fights an in-progress drag). The
	--editable percent readout is the source of truth for the current dip.
	local depthSlider = gui.Slider{
		style = {
			width = 170,
			height = 16,
			halign = "right",
			valign = "center",
		},
		sliderWidth = 130,
		labelWidth = 30,
		labelFormat = "percent",
		minValue = 0,
		maxValue = 1,
		value = dmhub.GetSettingValue("anthemduckdepth") or 0.15,
		confirm = function(element)
			dmhub.SetSettingValue("anthemduckdepth", element.value)
		end,
	}

	--A "label + seconds slider" row (0..5s) for the two duck fade times. Reads the game
	--setting on build; commits on release. The readout is editable (type a number).
	local function MakeSecondsRow(labelText, settingId, defaultVal)
		local slider = gui.Slider{
			style = { width = 170, height = 16, halign = "right", valign = "center" },
			sliderWidth = 130,
			labelWidth = 34,
			labelFormat = "%.1f",
			minValue = 0,
			maxValue = 5,
			value = dmhub.GetSettingValue(settingId) or defaultVal,
			confirm = function(element)
				dmhub.SetSettingValue(settingId, element.value)
			end,
		}
		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = 22,
			valign = "center",
			vmargin = 2,
			hpad = 4,
			borderBox = true,
			styles = {
				{ selectors = {"sliderLabel"}, fontSize = 12, lmargin = 5, priority = 6 },
			},
			gui.Label{ classes = {"sizeXs"}, text = labelText, width = 96, height = "auto", halign = "left", valign = "center" },
			slider,
		}
	end

	local depthRow = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 22,
		valign = "center",
		vmargin = 2,
		hpad = 4,
		borderBox = true,
		styles = {
			{ selectors = {"sliderLabel"}, fontSize = 12, lmargin = 5, priority = 6 },
		},
		gui.Label{ classes = {"sizeXs"}, text = "Music ducks to", width = 96, height = "auto", halign = "left", valign = "center" },
		depthSlider,
	}

	--Per-target duck matrix: Phase 3-4. Dimmed, non-interactive placeholder for now.
	local matrixPlaceholder = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		vmargin = 4,
		opacity = 0.4,
		gui.Label{ classes = {"bold", "sizeXs"}, text = "Manage Ducking", width = "auto", height = "auto", halign = "left" },
		gui.Label{ classes = {"fgMuted", "sizeXs"}, text = "Anthem -> Music", width = "auto", height = "auto", halign = "left", vmargin = 1 },
		gui.Label{ classes = {"fgMuted", "sizeXs"}, text = "Anthem -> Ambience", width = "auto", height = "auto", halign = "left", vmargin = 1 },
		gui.Label{ classes = {"fgMuted", "sizeXs"}, text = "Per-target duck depth + fade. Placement only - depends on the duck-settings document & asymmetric-fade engine work.", width = "100%", height = "auto", textWrap = true, vmargin = 2 },
	}

	return gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		pad = 8,
		borderBox = true,
		vmargin = 4,

		--Match the toggle label to the rest of the studio text (12pt); the default
		--checkbox label renders larger than everything else on the card.
		styles = {
			{ selectors = {"checkboxLabel"}, fontSize = 12, priority = 20 },
		},

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			gui.Label{ classes = {"bold", "sizeS"}, text = "Ducking", width = "auto", height = "auto", halign = "left", valign = "center" },
		},

		duckCheck,

		gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "While an Anthem plays, music automatically ducks to the level set below.",
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 2,
		},

		depthRow,
		MakeSecondsRow("Fade in (s)", "anthemduckfadein", 1.0),
		MakeSecondsRow("Fade out (s)", "anthemduckfadeout", 2.5),

		matrixPlaceholder,
	}
end

--Nested folder library tree (Studio left column), replacing the old flat
--alphabetical list. Folders nest via parentFolder (the engine persists the chain);
--a clip lives in its parentFolder, or the default "Sounds" folder when unset. The
--tree is rebuilt eagerly on refreshAssets (the library is small, so no lazy-expand
--needed). This base renders folders + clip rows with expand/collapse and inline
--rename; folder ops, drag-move, reorder and multi-select are layered on below.
local CreateAudioLibraryTree = function()
	local m_root
	local CreateFolderNode
	local CreateFolderContents
	--Trigger a local tree rebuild right after a drag applies its change, instead of
	--waiting for the cloud to echo the upload/doc-change back through the monitors
	--(that round-trip is the post-drop delay). Assigned once m_root + ScheduleRebuild
	--exist; the data is mutated locally first, so an immediate rebuild reflects it.
	local RequestRebuild = function() end

	--Persisted manual clip order (per folder) lives in the audioClipOrder doc since
	--AudioAssetLua has no writable ord. These read/write data.order[folderid].
	local function GetFolderOrderList(folderid)
		local doc = mod:GetDocumentSnapshot(audioClipOrderDocId)
		local order = doc.data.order
		local src = (order ~= nil and order[folderid]) or nil
		local out = {}
		if src ~= nil then
			for _,id in ipairs(src) do out[#out+1] = id end
		end
		return out
	end

	local function SetFolderOrderList(folderid, list)
		local doc = mod:GetDocumentSnapshot(audioClipOrderDocId)
		doc:BeginChange()
		if doc.data.order == nil then doc.data.order = {} end
		doc.data.order[folderid] = list
		doc:CompleteChange("Reorder audio clips")
	end

	--Group folders by parentFolder ("__root__" for top level) and clips by their
	--owning folder. Each folder entry carries its id (the table key) since the folder
	--object itself is not guaranteed to expose one. Folders sort by their own ord then
	--name; clips sort by the persisted per-folder order (audioClipOrder doc), with
	--unlisted clips after the listed ones, alphabetically.
	local function BuildMaps()
		local foldersByParent = {}
		local clipsByFolder = {}
		for id,folder in pairs(assets.audioFoldersTable) do
			if not folder.hidden then
				local pk = folder.parentFolder or "__root__"
				local t = foldersByParent[pk]
				if t == nil then t = {} foldersByParent[pk] = t end
				t[#t+1] = { id = id, folder = folder }
			end
		end
		for _,asset in pairs(assets.audioTable) do
			if not asset.hidden then
				local fk = asset.parentFolder or defaultFolder
				local t = clipsByFolder[fk]
				if t == nil then t = {} clipsByFolder[fk] = t end
				t[#t+1] = asset
			end
		end
		local function cmpFolder(a,b)
			local ao,bo = a.folder.ord or 0, b.folder.ord or 0
			if ao ~= bo then return ao < bo end
			return (a.folder.description or "") < (b.folder.description or "")
		end
		for _,t in pairs(foldersByParent) do table.sort(t, cmpFolder) end
		for fid,t in pairs(clipsByFolder) do
			local idx = {}
			local list = GetFolderOrderList(fid)
			for i,assetid in ipairs(list) do idx[assetid] = i end
			table.sort(t, function(a,b)
				local ia, ib = idx[a.id], idx[b.id]
				if ia ~= nil and ib ~= nil then return ia < ib end
				if ia ~= nil then return true end
				if ib ~= nil then return false end
				return (a.description or "") < (b.description or "")
			end)
		end
		return foldersByParent, clipsByFolder
	end

	--Remembered expansion per folderid, so a tree rebuild (any asset/folder change,
	--including a drag-move) does not collapse everything. Captured from the live
	--nodes just before each rebuild.
	local m_expanded = {}

	--Multi-selection state. m_selected is a set of clip assetids; m_anchor is the
	--last single-clicked clip (the pivot for shift-range). m_folderClips maps each
	--folderid to its clips in visible order, captured each rebuild so a shift-range
	--can resolve the slice between anchor and target within one folder.
	local m_selected = {}
	local m_anchor = nil
	local m_folderClips = {}

	local function RefreshSelectionVisuals()
		if m_root ~= nil and m_root.valid then
			m_root:FireEventTree("refreshSelection", m_selected)
		end
	end

	local function FolderOfClip(assetid)
		local a = assets.audioTable[assetid]
		if a == nil then return defaultFolder end
		return a.parentFolder or defaultFolder
	end

	--Select every clip between anchor and target in the same folder's visible order.
	--If they are in different folders, just add the target (range is undefined).
	local function SelectRange(anchorId, targetId)
		local fa = FolderOfClip(anchorId)
		if fa ~= FolderOfClip(targetId) then
			m_selected[targetId] = true
			return
		end
		local list = m_folderClips[fa] or {}
		local ai, ti = nil, nil
		for i,id in ipairs(list) do
			if id == anchorId then ai = i end
			if id == targetId then ti = i end
		end
		if ai == nil or ti == nil then
			m_selected[targetId] = true
			return
		end
		if ai > ti then ai, ti = ti, ai end
		for i = ai, ti do m_selected[list[i]] = true end
	end

	local function ClipSelectClick(assetid)
		if dmhub.modKeys['shift'] and m_anchor ~= nil then
			SelectRange(m_anchor, assetid)
		elseif dmhub.modKeys['ctrl'] then
			if m_selected[assetid] then m_selected[assetid] = nil else m_selected[assetid] = true end
			m_anchor = assetid
		else
			m_selected = {}
			m_selected[assetid] = true
			m_anchor = assetid
		end
		RefreshSelectionVisuals()
	end

	--The clips a drag should move: the whole selection when the dragged clip is part
	--of it, otherwise just the dragged clip. Ordered by ord so a multi-move keeps the
	--clips' relative order.
	local function SelectionForDrag(draggedId)
		if not m_selected[draggedId] then return { draggedId } end
		local ids = {}
		for id,_ in pairs(m_selected) do ids[#ids+1] = id end
		if #ids <= 1 then return { draggedId } end
		--Order the block by visible position so a multi-move keeps relative order.
		local rank = {}
		local r = 0
		for _,list in pairs(m_folderClips) do
			for _,id in ipairs(list) do r = r + 1 rank[id] = r end
		end
		table.sort(ids, function(a,b) return (rank[a] or 1e9) < (rank[b] or 1e9) end)
		return ids
	end

	--Resolve the folder a drop landed on: the nearest enclosing folder node, or
	--"__root__" when dropped on the library root (top level). nil = invalid drop.
	local function ResolveDrop(target)
		if target == nil then return nil end
		local node = target:FindParentWithClass("audioFolderNode")
		if node ~= nil then return node.data.folderid end
		if target:FindParentWithClass("audioLibraryRoot") ~= nil then return "__root__" end
		return nil
	end

	--True if maybeAncestorId is folderid itself or any ancestor of it -- used to
	--block dropping a folder into its own subtree (which would make a cycle).
	local function IsAncestorOrSelf(folderid, maybeAncestorId)
		local cur = folderid
		local guard = 0
		while cur ~= nil and guard < 50 do
			if cur == maybeAncestorId then return true end
			local f = assets.audioFoldersTable[cur]
			if f == nil then return false end
			cur = f.parentFolder
			guard = guard + 1
		end
		return false
	end

	local function MoveClipToFolder(assetid, dest)
		local asset = assets.audioTable[assetid]
		if asset == nil or dest == nil then return end
		--"__root__" for a clip means the default "Sounds" folder (parentFolder nil).
		asset.parentFolder = cond(dest == "__root__", nil, dest)
		asset:Upload()
	end

	local function MoveFolderToFolder(draggedId, dest)
		local folder = assets.audioFoldersTable[draggedId]
		if folder == nil or dest == nil then return end
		if dest ~= "__root__" and IsAncestorOrSelf(dest, draggedId) then
			return  --dropping a folder into its own subtree would cycle.
		end
		folder.parentFolder = cond(dest == "__root__", nil, dest)
		folder:Upload()
	end

	--Move one or more clips to sit just before targetRow, persisting the new order in
	--the audioClipOrder doc (clips have no writable ord). Rebuilds the dest folder's
	--ordered id list with the dragged ids removed and re-inserted before the target,
	--then reparents the dragged clips into that folder so a selection can be reordered
	--across folders in one drag.
	local function ReorderClipsBefore(ids, targetRow, container)
		local draggedSet = {}
		for _,id in ipairs(ids) do draggedSet[id] = true end
		local folderNode = container:FindParentWithClass("audioFolderNode")
		local destFolderId = folderNode ~= nil and folderNode.data.folderid or defaultFolder
		local targetAssetId = (targetRow ~= nil and targetRow.data ~= nil) and targetRow.data.assetid or nil

		--The dest folder's clips in current visible order (captured each rebuild).
		local current = m_folderClips[destFolderId] or {}
		local newOrder = {}
		local inserted = false
		for _,assetid in ipairs(current) do
			if assetid == targetAssetId then
				for _,id in ipairs(ids) do newOrder[#newOrder+1] = id end
				inserted = true
			end
			if not draggedSet[assetid] then
				newOrder[#newOrder+1] = assetid
			end
		end
		if not inserted then
			for _,id in ipairs(ids) do newOrder[#newOrder+1] = id end
		end

		for _,id in ipairs(ids) do
			local a = assets.audioTable[id]
			if a ~= nil then
				a.parentFolder = cond(destFolderId == defaultFolder, nil, destFolderId)
				a:Upload()
			end
		end
		SetFolderOrderList(destFolderId, newOrder)
	end

	--Drop-line indicator: the spacer the drag is currently hovering, lit while held.
	local m_activeSpacer = nil
	local function ClearDropIndicator()
		if m_activeSpacer ~= nil and m_activeSpacer.valid then
			m_activeSpacer:SetClass("active", false)
		end
		m_activeSpacer = nil
	end

	--Drag wiring shared by clip rows: a drop on a sibling row's spacer reorders;
	--any other drop that resolves to a folder moves the clip into that folder.
	local clipCanDragOnto = function(element, target)
		if target ~= nil and target:HasClass("audioClipSpacer") then
			return true
		end
		return ResolveDrop(target) ~= nil
	end
	local clipDragging = function(element, target)
		local spacer = (target ~= nil and target:HasClass("audioClipSpacer")) and target or nil
		if spacer ~= m_activeSpacer then
			ClearDropIndicator()
			if spacer ~= nil then
				spacer:SetClass("active", true)
				m_activeSpacer = spacer
			end
		end
	end
	local clipDrag = function(element, target)
		ClearDropIndicator()
		if target == nil then return end
		--Drag the whole selection when the grabbed clip is part of it.
		local ids = SelectionForDrag(element.data.assetid)
		if target:HasClass("audioClipSpacer") then
			local row = target.parent
			if row ~= nil and row.parent ~= nil then
				ReorderClipsBefore(ids, row, row.parent)
				RequestRebuild()
			end
			return
		end
		local dest = ResolveDrop(target)
		if dest == nil then return end
		for _,id in ipairs(ids) do
			MoveClipToFolder(id, dest)
		end
		RequestRebuild()
	end

	--contentPanel for one folder: its child folders (recursive) then its clips. It
	--is a drag target so a clip/folder can be dropped into the folder's body.
	--Lazy: build a folder's child nodes/rows only the first time it expands, and keep
	--them once built (a re-collapse just hides them). A collapsed folder costs only its
	--header, so a deep/large library no longer spawns every row up front. Returns the
	--container panel, whether it is empty (computed from the maps, not from built
	--children), and a builder the node calls when it should be open.
	CreateFolderContents = function(folderid, foldersByParent, clipsByFolder)
		local built = false
		local panel
		local function BuildChildren()
			if built then return end
			built = true
			local children = {}
			for _,sub in ipairs(foldersByParent[folderid] or {}) do
				children[#children+1] = CreateFolderNode(sub, foldersByParent, clipsByFolder)
			end
			for _,asset in ipairs(clipsByFolder[folderid] or {}) do
				children[#children+1] = CreateAudioStudioRow(asset, {
					draggable = true,
					canDragOnto = clipCanDragOnto,
					drag = clipDrag,
					dragging = clipDragging,
					onSelect = ClipSelectClick,
				})
			end
			panel.children = children
			--Newly built rows missed the root's post-rebuild refresh, so sync them now.
			panel:FireEventTree("refreshPlayingAudio")
			panel:FireEventTree("refreshSelection", m_selected)
		end
		panel = gui.Panel{
			classes = {"contentPanel"},
			width = "100%-12",
			height = "auto",
			flow = "vertical",
			lmargin = 12,
			dragTarget = true,
			--Fired by TreeNode when the node opens (initial-open and toggle-open).
			expand = function(element)
				BuildChildren()
			end,
		}
		local empty = (#(foldersByParent[folderid] or {}) == 0) and (#(clipsByFolder[folderid] or {}) == 0)
		return panel, empty, BuildChildren
	end

	CreateFolderNode = function(entry, foldersByParent, clipsByFolder)
		local folderid = entry.id
		local folder = entry.folder
		local contents, empty, buildContents = CreateFolderContents(folderid, foldersByParent, clipsByFolder)
		local isDefault = folderid == defaultFolder

		local node
		node = gui.TreeNode{
			classes = {"audioFolderNode"},
			text = folder.description or "Folder",
			width = "100%",
			editable = true,
			expanded = m_expanded[folderid] == true,
			--dragTarget is consumed by TreeNode and applied to the folder HEADER, so
			--a clip/folder can be dropped onto the header. All folders are draggable
			--(incl. the default "Sounds"): a non-draggable folder header would let the
			--drag fall through to the launchable window and move the whole panel. The
			--default folder is still protected from DELETE below.
			dragTarget = true,
			draggable = true,
			data = { folderid = folderid },
			contentPanel = contents,

			canDragOnto = function(element, target)
				local dest = ResolveDrop(target)
				return dest ~= nil and not IsAncestorOrSelf(dest, folderid)
			end,
			drag = function(element, target)
				local dest = ResolveDrop(target)
				if dest == nil then return end
				MoveFolderToFolder(folderid, dest)
				RequestRebuild()
			end,

			create = function(element)
				element:FireEvent("setempty", empty)
			end,

			change = function(element, text)
				text = trim(text)
				if text == "" then
					element:FireEventTree("text", folder.description or "Folder")
					return
				end
				folder.description = text
				folder:Upload()
			end,

			contextMenu = function(element)
				if isDefault then
					return  --the default "Sounds" folder is not deletable.
				end
				element.popup = gui.ContextMenu{
					width = 180,
					entries = {
						{
							text = "Delete Folder",
							click = function()
								element.popup = nil
								if not empty then
									gui.ModalMessage{
										title = "Folder Not Empty",
										message = "Move or delete its contents before deleting this folder.",
									}
									return
								end
								folder.hidden = true
								folder:Upload()
							end,
						},
					},
				}
			end,
		}
		--A folder that starts expanded (remembered state) builds its contents now;
		--collapsed folders defer until first opened. The expand event covers the
		--toggle-open case.
		if m_expanded[folderid] == true then
			buildContents()
		end
		return node
	end

	--Walk the live tree and record each folder's expansion before a rebuild.
	local function CaptureExpansion(panel)
		if panel == nil then return end
		for _,c in ipairs(panel.children or {}) do
			if c.data ~= nil and c.data.folderid ~= nil and c.data.isCollapsed ~= nil then
				m_expanded[c.data.folderid] = not c.data.isCollapsed()
			end
			CaptureExpansion(c)
		end
	end

	local function DoRebuild(element)
		CaptureExpansion(element)
		local foldersByParent, clipsByFolder = BuildMaps()
		--Capture each folder's clips in visible (sorted) order for shift-range, and
		--drop any selected ids that no longer exist.
		m_folderClips = {}
		local live = {}
		for fid,list in pairs(clipsByFolder) do
			local ordered = {}
			for _,a in ipairs(list) do
				ordered[#ordered+1] = a.id
				live[a.id] = true
			end
			m_folderClips[fid] = ordered
		end
		for id,_ in pairs(m_selected) do
			if not live[id] then m_selected[id] = nil end
		end
		local children = {}
		for _,entry in ipairs(foldersByParent["__root__"] or {}) do
			children[#children+1] = CreateFolderNode(entry, foldersByParent, clipsByFolder)
		end
		element.children = children
		element:FireEventTree("refreshPlayingAudio")
		element:FireEventTree("refreshSelection", m_selected)
	end

	--Coalesce rebuilds: a single drag/reorder uploads several assets at once, each of
	--which fires monitorAssets. Rebuilding the whole recursive tree per upload chugs,
	--so collapse a burst of changes into one deferred rebuild on the next tick.
	local m_rebuildPending = false
	local function ScheduleRebuild(element)
		if m_rebuildPending then return end
		m_rebuildPending = true
		dmhub.Schedule(0.01, function()
			m_rebuildPending = false
			if mod.unloaded then return end
			if element ~= nil and element.valid then
				DoRebuild(element)
			end
		end)
	end

	RequestRebuild = function()
		if m_root ~= nil and m_root.valid then
			ScheduleRebuild(m_root)
		end
	end

	m_root = gui.Panel{
		classes = {"audioLibraryRoot"},
		flow = "vertical",
		width = "100%",
		height = "100%-24",
		vscroll = true,
		valign = "top",
		dragTarget = true,
		monitorAssets = "audio",
		--Also rebuild when the persisted clip order changes (an intra-folder reorder
		--may not change any asset, only the order doc).
		monitorGame = mod:GetDocumentSnapshot(audioClipOrderDocId).path,
		create = function(element)
			DoRebuild(element)
		end,
		refreshAssets = function(element)
			ScheduleRebuild(element)
		end,
		refreshGame = function(element)
			ScheduleRebuild(element)
		end,
	}

	return m_root
end

CreateAudioStudio = function()
	if not dmhub.isDM then
		return nil
	end

	local leftColumn = gui.Panel{
		flow = "vertical",
		width = "58%",
		height = "100%",
		hmargin = 4,

		--Library header row: label left, the add buttons right-aligned to this column
		--(these become glyph buttons later). The label sits in a fixed-width flex
		--panel since "100% available" collapses to 0 here.
		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			gui.Panel{
				flow = "horizontal",
				width = "100%-180",
				height = "auto",
				halign = "left",
				valign = "center",
				gui.Label{ classes = {"bold", "sizeS"}, text = "Library", width = "auto", height = "auto", halign = "left", valign = "center" },
			},
			gui.Button{
				classes = {"sizeXs"},
				text = "+ New Folder",
				width = "auto",
				height = 24,
				valign = "center",
				hmargin = 3,
				press = function(element)
					assets:UploadNewAudioFolder{ description = "New Folder" }
				end,
			},
			gui.Button{
				classes = {"sizeXs"},
				text = "+ Add audio",
				width = "auto",
				height = 24,
				valign = "center",
				hmargin = 3,
				press = function(element)
					OpenAudioStudioUpload()
				end,
			},
		},

		CreateAudioLibraryTree(),
	}

	local rightColumn = gui.Panel{
		flow = "vertical",
		width = "40%",
		height = "100%",
		hmargin = 4,
		vscroll = true,
		CreateStudioMixerCard(),
		CreateStudioDuckingCard(),
		CreateStudioSoundboard(),
	}

	local body = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "100%-92",
		valign = "top",
		leftColumn,
		rightColumn,
	}

	--Title centred across the top of the panel.
	local header = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		gui.Label{
			classes = {"sizeXl", "bold"},
			text = "Audio Studio",
			width = "100%",
			height = "auto",
			textAlignment = "center",
			halign = "center",
			valign = "center",
		},
	}

	--Library-tree rules added on top of the base theme: the multi-select row
	--highlight and the reorder drop-line. Routed through MergeStyles so the @tokens
	--resolve against the active scheme (re-applied on a scheme switch below).
	local studioExtraStyles = {
		{ selectors = {"audioClipRow", "selected"}, bgcolor = "@bgAlt", borderColor = "@accent" },
		{ selectors = {"audioClipSpacer"}, bgcolor = "clear" },
		{ selectors = {"audioClipSpacer", "active"}, bgcolor = "@accent", opacity = 0.6 },
		--Broadcast Play/Stop: neutral glyph; brighter on hover; "live" amber when playing.
		{ selectors = {"audioBroadcastButton"}, bgcolor = "white" },
		{ selectors = {"audioBroadcastButton", "hover"}, brightness = 1.4 },
		{ selectors = {"audioBroadcastButton", "playing"}, bgcolor = "@warning" },
		--DM cue (eye): dim until hovered; green while this row is auditioning locally.
		{ selectors = {"audioCueButton"}, bgcolor = "white", opacity = 0.55 },
		{ selectors = {"audioCueButton", "hover"}, opacity = 1 },
		{ selectors = {"audioCueButton", "active"}, bgcolor = "@success", opacity = 1 },
		--Soundboard clear "x": default colour at rest, @danger tint on hover so the
		--destructive intent reveals when you point at it (no flicker -- only the colour
		--changes, the element stays present).
		{ selectors = {"audioStudioClearGlyph", "parent:hover"}, color = "@danger" },
	}

	local root
	root = gui.Panel{
		classes = {"launchablePanel"},
		styles = ThemeEngine.MergeStyles(studioExtraStyles),
		width = 1000,
		--Tall enough to show all right-column cards without scrolling, but never taller
		--than the screen (small displays cap at screenHeight - 80 so it never overflows).
		height = math.min(920, dmhub.screenDimensions.y - 80),
		flow = "vertical",
		pad = 16,
		data = {},
		create = function(element)
			element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.MergeStyles(studioExtraStyles)
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
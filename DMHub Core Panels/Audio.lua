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
		--halign="right" removed (chunk F, L2): the default left-align sits the
		--slider immediately after its 76px label in MakeFaderRow, instead of
		--pushed to the row's far right with a gap between them.
		style = {
			width = 170,
			height = 16,
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
		--halign="right" removed (chunk F, L2): matches MakeMasterFader -- default
		--left-align sits the slider immediately after its label.
		style = {
			width = 170,
			height = 16,
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

		--Live local feedback while dragging. Invalidate the sync cache so a drag that
		--ends WITHOUT confirm (cancelled) is not left stuck at the preview level: since
		--the doc value has not changed, SyncBroadcastLevelsToEngine's cache compare
		--would otherwise think the engine already matches the doc and skip re-pushing it.
		preview = function(element)
			audio.SetGroupShared(groupid, element.value)
			broadcastSyncApplied[groupid] = nil
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

--Session-only memory of which dock section (Levels/Anthems/Soundboard) is expanded.
--Replaces the old per-user "Controls" drawer + three persisted collapse settings: the
--umbrella header is gone and the three sections are now an exclusive segmented
--selector (one open at a time, or none). Deliberately NOT a setting -- a fresh app
--session always starts with nothing expanded; this local only survives the dock panel
--being rebuilt while the app stays open, so reopening the dock mid-session restores
--the last choice.
local g_dockControlsSelected = nil

--Max height of the dock's scrollable body (everything below the pinned now-playing
--strip + view toggle). The dock host is a fixed 470px (minHeight=maxHeight in the
--registration, vscroll=false); the pinned top eats ~100px, leaving ~360 for the
--body. With nothing selected in the segmented selector the content is shorter than
--this so it never scrolls; an expanded section (esp. Anthems with many heroes)
--scrolls past it instead of clipping.
local audioScrollMaxHeight = 360

--Unified soundboard button builder (chunk F1a), forward-declared here since the dock
--grid (CreatePlayerGrid, below) is defined before the helpers (DisplayNameForAsset,
--PlayBroadcastClip) the real implementation needs. Assigned further down, once those
--helpers exist; CreatePlayerGrid only calls it at build time (when the dock panel is
--actually opened), by which point the module has finished loading top to bottom, so
--the forward-declared upvalue is populated.
local CreateSoundboardButton

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

--Precomputed swatch palette (chunk F1a) for the unified soundboard button's fill
--tint. asset.color is an index 0-7; index 0 is the base red (hue 0), the rest are
--hue-rotated 1/8 turn apart. Deep/muted (F polish, 2026-07-02 review): the fill
--paints the button itself now (see FillColorHex in CreateSoundboardButton) with
--white name/duration text pinned on top while playing, so every hue must stay
--comfortably legible under white text at ~90% alpha over a dark surface -- the
--original bright hues were too light for that. Idle states (~30% alpha) let the
--theme surface dominate, so the theme's own contrast still holds there.
local AudioSwatchColors = {
	[0] = "#8F2626",
	[1] = "#8A6420",
	[2] = "#5E7A22",
	[3] = "#1F7040",
	[4] = "#1F6E6E",
	[5] = "#2A4A8F",
	[6] = "#5E2E8F",
	[7] = "#8F2670",
}

local function AudioSwatchColor(colorIndex)
	return AudioSwatchColors[colorIndex] or AudioSwatchColors[0]
end



--Board/slot counts for the soundboard documents (audiogrid-<board>-<slot>),
--shared by the dock grid (CreatePlayerGrid) and the Studio soundboard card
--(CreateStudioSoundboard) below -- hoisted here since the dock grid builds
--first but both surfaces must agree on the same 5 boards x 12 slots.
local STUDIO_BOARDS = 5
local STUDIO_SLOTS = 12

--Dock soundboard grid (chunk F1c): pure perform surface, no drag. Each button is the
--unified CreateSoundboardButton (surface="dock"); the grid rebuilds its 12 buttons
--whenever the board number cycles (SetGridNumber) since that is simpler and no more
--expensive than threading the new board through every button's refreshGrid.
--Fixed grid dimensions (chunk F, P4): 3 columns x (110 button + 2+2 hmargins) =
--342; 4 rows x (62 + 2+2 vmargins) = 264. A deterministic size (instead of the old
--wrap=true/width=100%/height=auto auto-flow) is cheap to lay out AND reports its
--true height correctly -- the old auto-height wrap was under-measuring, which is
--why the dock's vscroll body could not be scrolled all the way to the bottom.
--halign="center" also satisfies the centering ask for free once the box has a
--known width. Shared by both surfaces (see CreateStudioSoundboard's gridPanel).
local AUDIO_SB_GRID_WIDTH = 342
local AUDIO_SB_GRID_HEIGHT = 264

local CreatePlayerGrid = function()
	local resultPanel
	local gridNumber = 1

	local function GetBoard()
		return gridNumber
	end

	--Built ONCE (chunk F, P2): the 12 buttons are constructed a single time with a
	--getBoard getter, not rebuilt on every board switch. SetGridNumber below just
	--updates gridNumber and fires refreshGrid across the subtree so each button
	--recomputes its own docid.
	local function BuildSlots()
		local children = {}
		for i=1,STUDIO_SLOTS do
			children[#children+1] = CreateSoundboardButton(nil, i, { surface = "dock", getBoard = GetBoard })
		end
		resultPanel.children = children
	end

	resultPanel = gui.Panel{
		flow = "horizontal",
		wrap = true,
		width = AUDIO_SB_GRID_WIDTH,
		height = AUDIO_SB_GRID_HEIGHT,
		halign = "center",
		data = {
			gridNumber = 1,
			--No-rebuild board switch (chunk F, P2): DELETE the old BuildSlots-on-switch
			--rebuild. Only the initial BuildSlots() below still constructs buttons.
			SetGridNumber = function(num)
				gridNumber = num
				resultPanel.data.gridNumber = num
				resultPanel:FireEventTree("refreshGrid")
			end,
		},
	}

	BuildSlots()

	return resultPanel
end

--Dock board selector (F polish, task 3): a compact segmented row matching the
--Studio's "Board" + five buttons, wired directly to the dock grid's
--data.SetGridNumber. Replaces the old tiny board-preview strips (deleted --
--see CreateSoundboardPreviewPanel/CreateGridMenu/CreateAudioGrid removal),
--which were the only thing that had called SetGridNumber from the dock; the
--dock previously had no way to switch boards at all.
local function CreateDockBoardSelector(playerGrid)
	local boardButtons = {}
	local children = {
		gui.Label{
			classes = {"sizeXs", "fgMuted"},
			text = "Board",
			width = "auto",
			height = "auto",
			hmargin = 4,
			valign = "center",
		},
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
				playerGrid.data.SetGridNumber(idx)
				for j, b in ipairs(boardButtons) do
					b:SetClass("selected", j == idx)
				end
			end,
		}
		btn:SetClass("selected", idx == playerGrid.data.gridNumber)
		boardButtons[idx] = btn
		children[#children+1] = btn
	end

	return gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",
		valign = "center",
		vmargin = 4,
		children = children,
	}
end

--Shared category (Music / Ambience / Effects) dropdown, used by the Studio library
--row builder (CreateAudioStudioRow) so the dropdown options, "-"/unset
--normalisation and change behavior stay in one place. Styling differs per call
--site, so that is passed in via opts.

--Recognised raw audio file extensions. Used only to decide whether a stored
--description looks like an un-renamed upload filename, for DISPLAY purposes.
local audioFileExtensions = { "mp3", "ogg", "wav", "flac" }

--Display name for an asset: strips a recognised file extension (case-insensitive)
--from the stored description for DISPLAY ONLY -- the stored description itself is
--never modified by this transform. Shared by every Studio surface that shows a
--clip name (the library row, the soundboard assign popup, filled board buttons)
--so the "looks like a raw filename" heuristic cannot drift between them.
local function DisplayNameForAsset(asset)
	local name = (asset ~= nil and asset.description) or ""
	local lower = string.lower(name)
	for _,ext in ipairs(audioFileExtensions) do
		local suffix = "." .. ext
		if string.len(lower) > string.len(suffix) and string.sub(lower, -string.len(suffix)) == suffix then
			return string.sub(name, 1, string.len(name) - string.len(suffix))
		end
	end
	return name
end

--Play-start order registry. audio.currentlyPlaying keys have no stable
--ordering, and a looping track's elapsed .time resets to 0 on every loop --
--sorting by elapsed made the "most recent" track cycle whenever a loop
--restarted (visually distracting). Instead each playing id gets a
--monotonically increasing sequence number the first time it is seen;
--ids that stop are pruned so a later replay re-registers as new. Module-scoped
--(chunk D7) so PlayBroadcastClip and the Studio strip (D9) can share it with
--CreateSoundPanel's now-playing card instead of keeping separate registries.
local m_playOrder = {}
local m_playOrderNext = 1
local function PlayOrderOf(assetid)
	if m_playOrder[assetid] == nil then
		m_playOrder[assetid] = m_playOrderNext
		m_playOrderNext = m_playOrderNext + 1
	end
	return m_playOrder[assetid]
end
local function PrunePlayOrder()
	for assetid,_ in pairs(m_playOrder) do
		if audio.currentlyPlaying[assetid] == nil then
			m_playOrder[assetid] = nil
		end
	end
end

--All clips currently playing for a category (Music/Ambience/Effects), found by
--scanning audio.currentlyPlaying. Sorted by play-start order ascending
--(oldest first) -- stable across loop restarts.
local function PlayingTracksForCategory(cat)
	local list = {}
	for assetid,_ in pairs(audio.currentlyPlaying) do
		local a = assets.audioTable[assetid]
		if a ~= nil and a.category == cat then
			list[#list+1] = { id = assetid, asset = a, order = PlayOrderOf(assetid) }
		end
	end
	table.sort(list, function(x, y) return x.order < y.order end)
	return list
end

--Broadcast play helper (chunk D7): routes every table-facing Play button (dock tile,
--Studio library row, Studio soundboard) through one place so music can be kept to a
--single track. Music does not layer -- starting a new music clip stops every OTHER
--currently-playing music clip first. Ambience/effects are unaffected (those are
--allowed to layer). opts is an optional table of extra PlaySoundEvent fields (e.g.
--volume) forwarded as-is; asset is always set from the asset parameter.
--Chunk G upgrades the stop to a crossfade; deliberate music layering is chunk H's
--simultaneous playlist mode.
local function PlayBroadcastClip(asset, opts)
	if asset == nil then
		return
	end
	if asset.category == "music" then
		local stopIds = {}
		for assetid,_ in pairs(audio.currentlyPlaying) do
			if assetid ~= asset.id then
				local a = assets.audioTable[assetid]
				if a ~= nil and a.category == "music" then
					stopIds[#stopIds+1] = assetid
				end
			end
		end
		for _,id in ipairs(stopIds) do
			audio.StopSoundEvent(id)
		end
	end
	local playArgs = {}
	if opts ~= nil then
		for k,v in pairs(opts) do
			playArgs[k] = v
		end
	end
	playArgs.asset = asset
	audio.PlaySoundEvent(playArgs)
end

--Normalise the stored category to a dropdown option id. An unset category reads back
--as nil (never set) OR "" (set to nil through the current AudioAssetLua setter, which
--stringifies nil to ""); both mean "uncategorised". NB Lua treats "" as truthy, so a
--bare `category or "none"` would surface a blank option for the empty-string case.
local function GetAssetCategoryId(asset)
	local c = asset.category
	if c == nil or c == "" then
		return "none"
	end
	return c
end

--Builds the category dropdown for one asset. opts carries only presentation
--differences between the dock tile and the Studio row (width/height/fontSize/etc);
--behavior (options list, idChosen normalisation, refreshAssets, change) is identical.
--opts.unroutedHint (Studio row only) turns on the "unrouted" warning tint + tooltip
--while the asset has no category, nudging the DM to route it before it gets ignored
--by the Levels faders.
local function CreateCategoryDropdown(asset, opts)
	opts = opts or {}

	local function IsUnrouted()
		return opts.unroutedHint and GetAssetCategoryId(asset) == "none"
	end

	local dropdown
	dropdown = gui.Dropdown{
		floating = opts.floating,
		valign = opts.valign or "center",
		halign = opts.halign,
		y = opts.y,
		width = opts.width or 90,
		height = opts.height or 22,
		fontSize = opts.fontSize or 12,
		hmargin = opts.hmargin,
		options = {
			{ id = "none", text = "-" },
			{ id = "music", text = "Music" },
			{ id = "ambience", text = "Ambience" },
			{ id = "effects", text = "Effects" },
		},
		idChosen = GetAssetCategoryId(asset),

		monitorAssets = "audio",
		refreshAssets = function(element)
			element.idChosen = GetAssetCategoryId(asset)
			element:SetClass("unrouted", IsUnrouted())
		end,

		change = function(element)
			local newCategory = element.idChosen
			if newCategory == "none" then
				newCategory = nil
			end
			asset.category = newCategory
			asset:Upload()
			element:SetClass("unrouted", IsUnrouted())
		end,

		linger = function(element)
			if IsUnrouted() then
				gui.Tooltip("Set a Category. This clip will ignore Levels faders until you set a category.")(element)
			end
		end,
	}
	dropdown:SetClass("unrouted", IsUnrouted())
	return dropdown
end

--Unified soundboard button style rules (chunk F1a/F1d). Shared verbatim by BOTH
--surfaces: the dock attaches these via ThemeEngine.MergeTokens on soundboardBody
--(chunk F, P1 -- NOT the dock content root, to avoid duplicating the full base
--theme), the Studio appends them into studioExtraStyles on its own standalone
--root. Kept as one module-level table so the two surfaces cannot drift apart
--visually.
--
--Fill/playing states are class-driven (idle = dim tint, playing = full tint + accent
--border) on the button itself; the actual per-asset hue is data-driven (set via
--selfStyle.bgcolor in refreshGame, see CreateSoundboardButton) since there is no
--fixed set of classes for "which of 8 colors". Progress line is a thin bottom bar.
local AudioSoundboardButtonStyles = {
	{ selectors = {"audioSbButton"}, transitionTime = 0.15 },
	{ selectors = {"audioSbButton", "playing"}, borderColor = "@accent", border = 2 },
	{ selectors = {"audioSbProgress"}, bgcolor = "@accent" },
	{ selectors = {"audioSbName"}, fontSize = 11, color = "@fg" },
	{ selectors = {"audioSbName", "parent:playing"}, color = "#FFFFFF" },
	{ selectors = {"audioSbDuration"}, fontSize = 10, color = "@fgMuted" },
	{ selectors = {"audioSbDuration", "parent:playing"}, color = "#FFFFFF" },
	--Edit-mode declutter (F polish): only fill/name/clear-x/swatch/drag matter while
	--curating, so duration, the mute/volume row, and the loop glyph are hidden while
	--editMode is set on the button. The old {audioSbDuration, parent:editMode}
	--hmargin=20 nudge is gone with it -- the label is not shown at all now.
	{ selectors = {"audioSbDuration", "parent:editMode"}, hidden = 1 },
	{ selectors = {"audioSbVolumeRow", "parent:editMode"}, hidden = 1 },
	{ selectors = {"audioSbLoop", "parent:editMode"}, hidden = 1 },
	--Loop glyph: dim when off, accent-tinted when on. Always visible on filled buttons.
	{ selectors = {"audioSbLoop"}, bgcolor = "white", opacity = 0.4 },
	{ selectors = {"audioSbLoop", "active"}, bgcolor = "@accent", opacity = 1 },
	--Mute glyph: image-tint-neutral white, dims when idle, brightens on hover/muted.
	{ selectors = {"audioSbMute"}, bgcolor = "white", opacity = 0.6 },
	{ selectors = {"audioSbMute", "hover"}, opacity = 1 },
	{ selectors = {"audioSbMute", "muted"}, bgcolor = "@danger", opacity = 1 },
	--Edit row (Delete + swatch, bottom of the button): only shown on filled buttons
	--in edit mode. The gating lives on the ROW (its parent is the button, so
	--parent:editMode resolves); the Delete button and swatch inside need none of
	--their own. Never hover-gated, per the flicker rule.
	{ selectors = {"audioSbEditRow"}, hidden = 1 },
	{ selectors = {"audioSbEditRow", "filled", "parent:editMode"}, hidden = 0 },
	--Delete is the house bin button (gui.DeleteItemButton) - it carries its own
	--styles, so no rules needed here.
	--Color swatch: sits beside the bin in the edit row.
	{ selectors = {"audioSbSwatch"}, borderColor = "white", border = 1 },
	{ selectors = {"audioSbSwatch", "hover"}, brightness = 1.4 },
	--"+ Assign" only makes sense in edit mode; perform mode leaves empty buttons inert.
	{ selectors = {"audioSbAssignLabel"}, hidden = 1 },
	{ selectors = {"audioSbAssignLabel", "parent:editMode"}, hidden = 0 },
}

--Soundboard button dimensions (F1a). 110 wide + 2px margins = 114 per cell, so 3
--columns need 342px, inside the dock's ~355px usable interior (116+4 margins = 124
--per cell rendered only 2 columns - verified live); 62 tall fits name (2 lines) +
--loop corner + mute/volume row + duration without crowding. Same on both surfaces.
local AUDIO_SB_BUTTON_WIDTH = 110
local AUDIO_SB_BUTTON_HEIGHT = 62

--Unified soundboard button (chunk F1a): the ONE builder for both the dock grid and
--the Studio soundboard grid. slot + opts.getBoard() identify the
--audiogrid-<board>-<slot> doc this button monitors (refreshGame). opts.surface =
--"dock" | "studio"; opts.isEditMode() (Studio only) reports whether edit-mode
--affordances should show.
--
--(chunk F, P2): the board number is DYNAMIC, not fixed at construction. opts.getBoard
--is a function returning the current board number, so a board switch no longer needs
--to rebuild the 12 buttons on a surface -- it just calls refreshGrid (below), which
--recomputes docid and re-fires refreshGame. This is what lets SetGridNumber (dock)
--and the Studio board selector avoid a full grid rebuild.
CreateSoundboardButton = function(getBoardOrLegacyBoard, slot, opts)
	opts = opts or {}
	local surface = opts.surface or "dock"
	local isStudio = surface == "studio"

	local function IsEditMode()
		return isStudio and opts.isEditMode ~= nil and opts.isEditMode()
	end

	--Accept either opts.getBoard (preferred) or, for safety, a plain number passed
	--positionally -- both resolve through GetBoard() so CurrentDocId() has one path.
	local getBoard = opts.getBoard
	if getBoard == nil then
		local fixedBoard = getBoardOrLegacyBoard
		getBoard = function() return fixedBoard end
	end

	local function CurrentDocId()
		return string.format("audiogrid-%d-%d", getBoard(), slot)
	end

	local docid = CurrentDocId()
	local assetid = nil
	local muted = false

	local nameLabel = gui.Label{
		classes = {"audioSbName", "collapsed"},
		text = "",
		width = "100%-4",
		height = "auto",
		halign = "center",
		valign = "top",
		y = 14,
		textAlignment = "center",
		textWrap = true,
		maxVisibleLines = 2,
		textOverflow = "ellipsis",
	}

	local emptyLabel = gui.Label{
		classes = {"audioSbAssignLabel", "fgMuted", "sizeXs"},
		text = "+ Assign",
		width = "auto",
		height = "auto",
		halign = "center",
		valign = "center",
	}

	--Loop glyph: top-left corner, always visible on filled buttons (both surfaces).
	--bgimage set directly (not via a class rule) so it renders under any cascade.
	local loopGlyph = gui.Panel{
		classes = {"audioSbLoop", "collapsed"},
		bgimage = "game-icons/infinity.png",
		width = 13,
		height = 13,
		halign = "left",
		valign = "top",
		swallowPress = true,
		press = function(element)
			local asset = assets.audioTable[assetid]
			if asset == nil then return end
			asset.loop = not asset.loop
			asset:Upload()
			element:SetClass("active", asset.loop == true)
		end,
		linger = function(element)
			gui.Tooltip("Loop")(element)
		end,
	}

	--Delete: the house bin button (gui.DeleteItemButton - same delete affordance as
	--everywhere else in the app; James swapped it in over a text "Delete" button).
	--Edit-mode-only via the edit row's gating; clears the slot assignment.
	local deleteButton = gui.DeleteItemButton{
		width = 16,
		height = 16,
		valign = "center",
		hmargin = 4,
		click = function()
			local doc = mod:GetDocumentSnapshot(docid)
			doc:BeginChange()
			doc.data.assetid = nil
			doc:CompleteChange("Clear soundboard button")
		end,
	}

	--Color swatch: bottom-right corner, edit-mode-only. Opens the 8-hue popup (ported
	--from the old createAudioPanel colorPanel) on click. No title on the popup.
	--The swatch face shows the asset's CURRENT color: data-driven bgcolor set in
	--refreshGame (the audioItemColor class rules only exist inside the popup's own
	--MergeStyles snapshot, so the face cannot rely on that class here).
	--Popup squares (F polish): plain AudioSwatchColors[i] bgcolor at full alpha,
	--NOT the old hueshift transform -- the picker must show exactly what the
	--button will look like, and the button now paints the swatch color directly
	--(FillColorHex) rather than hueshifting a fixed base image.
	local swatchButton
	swatchButton = gui.Panel{
		classes = {"audioSbSwatch"},
		bgimage = "panels/square.png",
		width = 14,
		height = 14,
		hmargin = 4,
		valign = "center",
		popupPositioning = "panel",
		swallowPress = true,
		press = function(element)
			if not IsEditMode() then return end
			local asset = assets.audioTable[assetid]
			if asset == nil then return end
			if element.popup ~= nil then
				element.popup = nil
				return
			end
			local parentElement = element
			element.popup = gui.Panel{
				styles = ThemeEngine.MergeStyles{
					{
						selectors = {"audioItemColor"},
						halign = "left",
						valign = "center",
						width = 12,
						height = 12,
						border = 0.5,
						borderColor = "white",
						cornerRadius = 2,
						bgimage = "panels/square.png",
						hmargin = 4,
						vmargin = 4,
					},
					{
						selectors = {"audioItemColor", "hover"},
						brightness = 1.5,
					},
				},
				classes = {"framedPanel"},
				width = 80,
				height = "auto",
				halign = "right",
				flow = "horizontal",
				wrap = true,
				create = function(popupElement)
					local children = {}
					for i=0,7 do
						children[#children+1] = gui.Panel{
							classes = {"audioItemColor"},
							bgcolor = AudioSwatchColors[i],
							press = function()
								asset.color = i
								asset:Upload()
								parentElement.popup = nil
							end,
						}
					end
					popupElement.children = children
				end,
			}
		end,
	}

	--Edit row: Delete (left) + color swatch (right) along the bottom of the button,
	--only visible on filled buttons in edit mode (style-gated on the row itself, see
	--AudioSoundboardButtonStyles). Being an in-flow row keeps both affordances off
	--the rounded corners (the old absolute-corner swatch touched the curved border).
	--Auto width so the Delete + swatch pair shrinks to fit and centers as a unit
	--at the bottom of the button (James: centred, next to each other).
	local editRow = gui.Panel{
		classes = {"audioSbEditRow"},
		flow = "horizontal",
		width = "auto",
		height = 18,
		halign = "center",
		valign = "bottom",
		deleteButton,
		swatchButton,
	}

	--Mute + per-track volume row, bottom of the button. Wiring copied from the old
	--createAudioPanel volume slider: preview/confirm write audio.SetSoundEventVolume
	--live, confirm additionally persists to the soundevent-<assetid> doc.
	local volumeSlider
	volumeSlider = gui.Slider{
		minValue = 0,
		maxValue = 1,
		sliderWidth = 62,
		labelWidth = 0,
		labelFormat = "",
		style = { width = "100%-18", height = 12, valign = "center" },
		events = {
			preview = function(element)
				if assetid ~= nil and not muted then
					audio.SetSoundEventVolume(assetid, element.value)
				end
			end,
			confirm = function(element)
				if assetid == nil then return end
				if not muted then
					audio.SetSoundEventVolume(assetid, element.value)
				end
				local doc = mod:GetDocumentSnapshot(string.format("soundevent-%s", assetid))
				doc:BeginChange()
				doc.data.volume = element.value
				doc:CompleteChange("Set audio volume")
			end,
			refreshPlayingAudio = function(element)
				if assetid == nil then return end
				local doc = mod:GetDocumentSnapshot(string.format("soundevent-%s", assetid))
				local asset = assets.audioTable[assetid]
				local base = (asset ~= nil) and asset.volume or 1
				element.value = cond(doc.data.volume ~= nil, doc.data.volume, base)
			end,
		},
	}

	local muteButton
	muteButton = gui.Panel{
		classes = {"audioSbMute", "hoverable"},
		bgimage = "ui-icons/AudioVolumeButton.png",
		width = 12,
		height = 12,
		valign = "center",
		swallowPress = true,
		press = function(element)
			if assetid == nil then return end
			muted = not muted
			element:SetClass("muted", muted)
			if muted then
				element.bgimage = "ui-icons/AudioMuteButton.png"
				audio.SetSoundEventVolume(assetid, 0)
			else
				element.bgimage = "ui-icons/AudioVolumeButton.png"
				audio.SetSoundEventVolume(assetid, volumeSlider.value)
			end
		end,
		linger = function(element)
			gui.Tooltip("Mute")(element)
		end,
	}

	local volumeRow = gui.Panel{
		classes = {"audioSbVolumeRow"},
		flow = "horizontal",
		width = "100%",
		height = 14,
		halign = "center",
		valign = "bottom",
		y = -2,
		floating = true,
		muteButton,
		volumeSlider,
	}

	local durationLabel = gui.Label{
		classes = {"audioSbDuration"},
		text = "",
		width = "auto",
		height = "auto",
		halign = "right",
		valign = "top",
		hmargin = 3,
		vmargin = 2,
	}

	--Progress line: thin bottom bar that fills while playing, reusing the old tile's
	--sliderFill think pattern (poll every 0.1s while audio.currentlyPlaying holds
	--this asset). Cleared (0-width, no think) once stopped.
	local progressFill
	progressFill = gui.Panel{
		classes = {"audioSbProgress"},
		bgimage = "panels/square.png",
		selfStyle = { width = "0%", height = "100%", halign = "left" },

		refreshPlayingAudio = function(element)
			local asset = assets.audioTable[assetid]
			local soundEvent = (assetid ~= nil) and audio.currentlyPlaying[assetid] or nil
			if soundEvent ~= nil and asset ~= nil then
				element.thinkTime = 0.1
				durationLabel.text = string.format("%s/%s", FormatTime(soundEvent.time, asset.duration), FormatTime(asset.duration, asset.duration))
			else
				element.thinkTime = nil
				progressFill.selfStyle.width = "0%"
				if asset ~= nil then
					durationLabel.text = FormatTime(asset.duration, asset.duration)
				end
			end
		end,

		think = function(element)
			local asset = assets.audioTable[assetid]
			local soundEvent = (assetid ~= nil) and audio.currentlyPlaying[assetid] or nil
			if soundEvent ~= nil and asset ~= nil and asset.duration > 0 then
				durationLabel.text = string.format("%s/%s", FormatTime(soundEvent.time, asset.duration), FormatTime(asset.duration, asset.duration))
				progressFill.selfStyle.width = string.format("%f%%", (100*soundEvent.time)/asset.duration)
			else
				element.thinkTime = nil
				progressFill.selfStyle.width = "0%"
			end
		end,
	}

	local progressBar = gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "clear",
		floating = true,
		width = "100%",
		height = 2,
		halign = "center",
		valign = "bottom",
		progressFill,
	}

	--Color fill (F polish): painted directly on the BUTTON's own bgimage/bgcolor
	--instead of an inset child panel, so the fill is full-bleed with the button's
	--rounded corners and has zero gap at the 4px pad (the old fillPanel sat INSIDE
	--the padded content box and read as a small square floating in the button --
	--the exact artifact flagged in review). The hue is data-driven (asset.color),
	--so idle/playing use alpha-carrying hex strings computed once per refresh
	--(refreshGame AND refreshPlayingAudio, since only the latter knows the live
	--playing state) rather than class-driven opacity.
	local function FillColorHex(asset, playing)
		if asset == nil then
			return "clear"
		end
		local base = AudioSwatchColor(asset.color)
		if playing then
			return base .. "E6" --~90% alpha
		end
		return base .. "4D" --~30% alpha
	end

	local button
	button = gui.Panel{
		classes = {"bordered", "hoverable", "audioSbButton"},
		flow = "none",
		width = AUDIO_SB_BUTTON_WIDTH,
		height = AUDIO_SB_BUTTON_HEIGHT,
		margin = 2,
		pad = 4,
		borderBox = true,
		bgimage = "panels/square.png",
		popupPositioning = "panel",
		monitorGame = mod:GetDocumentSnapshot(docid).path,
		monitorAssets = "audio",

		--Studio only: draggable for slot-to-slot swap. Set at build time AND kept
		--current on every refreshGame/refreshGrid (chunk F, P3) -- edit-mode toggling
		--no longer rebuilds the grid, so a construction-time-only flag would go stale
		--the moment the mode flipped.
		draggable = isStudio and IsEditMode(),
		dragTarget = isStudio,
		canDragOnto = isStudio and function(element, target)
			return target ~= nil and target:HasClass("audioSbButton")
		end or nil,
		drag = isStudio and function(element, target)
			if target == nil or not target:HasClass("audioSbButton") then return end
			if target == element then return end
			local srcDoc = mod:GetDocumentSnapshot(docid)
			local dstDoc = mod:GetDocumentSnapshot(target.data.docid)
			local srcId = srcDoc.data.assetid
			local dstId = dstDoc.data.assetid
			srcDoc:BeginChange()
			srcDoc.data.assetid = dstId
			srcDoc:CompleteChange("Swap soundboard buttons")
			dstDoc:BeginChange()
			dstDoc.data.assetid = srcId
			dstDoc:CompleteChange("Swap soundboard buttons")
		end or nil,

		data = { docid = docid },

		create = function(element)
			element:FireEvent("refreshGame")
		end,

		--Board switch, no rebuild (chunk F, P2): recomputes docid from the CURRENT
		--getBoard() result, updates the monitored doc + the data.docid the drag
		--handler/drag targets read, then re-fires refreshGame so the button's
		--content matches the new board. Fired via FireEventTree("refreshGrid") from
		--SetGridNumber (dock) and the Studio board selector -- this restores the OLD
		--dock pattern (no full 12-button rebuild on every board switch).
		refreshGrid = function(element)
			docid = CurrentDocId()
			element.data.docid = docid
			element.monitorGame = mod:GetDocumentSnapshot(docid).path
			element:FireEvent("refreshGame")
		end,

		refreshGame = function(element)
			local doc = mod:GetDocumentSnapshot(docid)
			assetid = doc.data.assetid
			local asset = (assetid ~= nil) and assets.audioTable[assetid] or nil
			if asset ~= nil then
				local displayName = DisplayNameForAsset(asset)
				if displayName == "" then displayName = "(unnamed)" end
				nameLabel.text = displayName
				nameLabel:SetClass("collapsed", false)
				emptyLabel:SetClass("collapsed", true)
				element:SetClass("filled", true)
				editRow:SetClass("filled", true)
				swatchButton.selfStyle.bgcolor = AudioSwatchColor(asset.color)
				loopGlyph:SetClass("collapsed", false)
				loopGlyph:SetClass("active", asset.loop == true)
				volumeRow:SetClass("collapsed", false)
				durationLabel.text = FormatTime(asset.duration, asset.duration)
			else
				assetid = nil
				nameLabel:SetClass("collapsed", true)
				emptyLabel:SetClass("collapsed", false)
				element:SetClass("filled", false)
				editRow:SetClass("filled", false)
				loopGlyph:SetClass("collapsed", true)
				volumeRow:SetClass("collapsed", true)
				durationLabel.text = ""
			end
			element.selfStyle.bgcolor = FillColorHex(asset, assetid ~= nil and audio.currentlyPlaying[assetid] ~= nil)
			element:SetClass("editMode", IsEditMode())
			--Dynamic draggable (chunk F, P3): edit-mode toggling no longer rebuilds the
			--grid, so this flag must be re-applied on every refresh instead of only at
			--construction time.
			element.draggable = (isStudio and IsEditMode()) or false
			element:FireEvent("refreshPlayingAudio")
		end,

		refreshAssets = function(element)
			element:FireEvent("refreshGame")
		end,

		refreshPlayingAudio = function(element)
			local asset = (assetid ~= nil) and assets.audioTable[assetid] or nil
			local playing = assetid ~= nil and audio.currentlyPlaying[assetid] ~= nil
			element:SetClass("playing", playing)
			element.selfStyle.bgcolor = FillColorHex(asset, playing)
			progressFill:FireEvent("refreshPlayingAudio")
			volumeSlider:FireEvent("refreshPlayingAudio")
		end,

		--Perform mode (dock always; Studio with edit mode off): filled = play/stop,
		--empty = inert. Studio edit mode: filled is inert (affordances only), empty
		--opens the assign popup (opts.openAssignPopup, Studio-only).
		click = function(element)
			if IsEditMode() then
				if assetid == nil and opts.openAssignPopup ~= nil then
					opts.openAssignPopup(element, getBoard(), slot)
				end
				return
			end
			if assetid == nil then return end
			if audio.currentlyPlaying[assetid] ~= nil then
				audio.StopSoundEvent(assetid)
			else
				local asset = assets.audioTable[assetid]
				if asset ~= nil then
					PlayBroadcastClip(asset, { volume = volumeSlider.value })
				end
			end
		end,

		loopGlyph,
		nameLabel,
		emptyLabel,
		volumeRow,
		durationLabel,
		progressBar,
		editRow,
	}

	return button
end


CreateSoundPanel = function()
	if not dmhub.isDM then
		return nil
	end
	

	--The folder library used to live here as a maximize-to-reveal drawer in the
	--dock. It has moved to the Audio Studio (the "Audio Studio" button opens it;
	--see CreateAudioLibraryTree / CreateFolderNode), keeping the dock to live
	--controls only. No in-dock library panel is built anymore.

	--Master mute. Lives in the now-playing header so it is always reachable (it
	--used to float on the spectrum strip, which this section replaces). Stop-all
	--used to be a right-click menu here (D10 moved it to its own always-visible
	--button, stopAllButton, so it is discoverable instead of hidden behind a
	--right-click) -- this button is mute-only now.
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
		linger = function(element)
			gui.Tooltip("Mute")(element)
		end,
		styles = {
			{ bgimage = "ui-icons/AudioVolumeButton.png" },
			{ selectors = {"muted"}, bgimage = "ui-icons/AudioMuteButton.png" },
			{ selectors = {"hover"}, brightness = 2 },
		},
	}

	--Stop-all (D10): a visible button, not a right-click secret, directly left of
	--the mute button. Same visual family as the hero stopButton (white square
	--glyph). Hidden entirely when nothing is playing so the status row does not
	--show a dead control at rest.
	local stopAllButton = gui.Panel{
		classes = {"hidden"},
		bgimage = "panels/square.png",
		bgcolor = "white",
		width = 12,
		height = 12,
		valign = "center",
		hmargin = 4,
		halign = "right",
		press = function(element)
			audio.StopAllSoundEvents()
		end,
		linger = function(element)
			gui.Tooltip("Stop all audio")(element)
		end,
	}

	--Play-start order registry and PlayingTracksForCategory are module-scoped
	--(chunk D7 -- see near DisplayNameForAsset) so PlayBroadcastClip and the
	--Studio strip (D9) share the same ordering with this card.

	--Now-playing hero card. Music is the lead channel (big title + read-only progress +
	--Stop); Ambience is a slim always-visible footer line (name + stop). Seek (a
	--draggable scrubber) and pause/resume need engine work -- .time is read-only and
	--there is no pause API -- so the transport is display-only progress + Stop for now;
	--the sleek look ships, seek/pause land with the engine pass. m_musicId holds
	--the resolved music channel id so the hero Stop button acts on the live
	--track (ambience beds each carry their own id via ambienceRows -- D8).
	local m_musicId = nil

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
		--Complement of statusDot + globalMuteButton + the "Studio" icon+text button
		--(wider than the old icon-only glyph -- see D4). Bumped from 100%-72 to
		--100%-112 (+40), then to 100%-132 (+20, chunk D10) to make room for the
		--new stopAllButton alongside globalMuteButton.
		width = "100%-132",
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

	--Extra-row factory for tracks beyond the primary one in a channel (e.g. two
	--ambience beds layered at once). A gui element has one parent, so each row is
	--built fresh by this factory rather than shared between the music/ambience
	--containers. Indented ~10px so the rows read as children of the channel above.
	local function CreateExtraTrackRow(id, asset)
		return gui.Panel{
			flow = "horizontal",
			width = "100%-10",
			height = 16,
			valign = "center",
			vmargin = 1,
			lmargin = 10,
			gui.Label{
				--Same non-muted color as the primary track's name: every row here
				--is equally "playing", so a dimmer tint would misread as a
				--different (inactive) state.
				classes = {"sizeXs"},
				text = DisplayNameForAsset(asset),
				width = "100%-20",
				height = "auto",
				halign = "left",
				valign = "center",
				textWrap = false,
				textOverflow = "ellipsis",
			},
			gui.Panel{
				bgimage = "panels/square.png",
				bgcolor = "white",
				width = 11,
				height = 11,
				halign = "right",
				valign = "center",
				hmargin = 4,
				press = function(element)
					audio.StopSoundEvent(id)
				end,
				linger = function(element)
					gui.Tooltip("Stop")(element)
				end,
			},
		}
	end

	--Extra-track containers. UpdateNowPlaying runs on a 0.2s think, so children are
	--only rebuilt when the signature of extra ids changes (rebuilding every tick
	--would be wasted work -- the row count is usually 0). Signatures are stored as
	--upvalues local to this section.
	local musicExtrasSig = nil
	local musicExtras = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
	}
	local ambienceRowsSig = nil
	local ambienceRows = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
	}

	--Rebuilds a row container's children from a tracks array only when the ordered
	--id signature differs from last time. Shared by musicExtras (tracks NOT shown
	--by the hero card -- everything but the newest) and, since D8, ambienceRows
	--(every playing ambience bed -- there is no ambience hero card to exclude).
	local function RefreshExtrasContainer(container, extras, lastSig)
		local ids = {}
		for i=1,#extras do
			ids[#ids+1] = extras[i].id
		end
		local sig = table.concat(ids, "|")
		if sig == lastSig then
			return sig
		end
		local rows = {}
		for i=1,#extras do
			rows[#rows+1] = CreateExtraTrackRow(extras[i].id, extras[i].asset)
		end
		container.children = rows
		return sig
	end

	--Ambience is no longer a single "primary bed + extras" footer line (D8) --
	--every playing ambience bed is an equal layer, so it gets a header (styled
	--like subtitleLabel) followed by one row per bed via ambienceRows, exactly
	--like music's musicExtras rows read below the hero card.
	local ambienceHeader = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = "Ambience",
		width = "100%-8",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
	}
	local ambienceIdleLabel = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = "Silent",
		width = "100%-10",
		height = "auto",
		halign = "left",
		valign = "center",
		lmargin = 10,
	}

	--Idle-state CTA: shown only when nothing is playing at all (replaces
	--titleLabel/subtitleLabel/transportRow, which are collapsed in that state so
	--the CTA does not leave a gap above it). Points the DM at the Studio instead
	--of leaving the dock looking dead.
	local ctaBlock = gui.Panel{
		classes = {"collapsed"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		vmargin = 4,
		gui.Button{
			classes = {"sizeXs"},
			text = "Open Audio Studio",
			width = "100%-8",
			height = 26,
			halign = "center",
			hmargin = 4,
			hpad = 8,
			borderBox = true,
			press = function(element)
				LaunchablePanel.LaunchPanelByName("Audio Studio")
			end,
		},
		gui.Label{
			classes = {"sizeXs", "fgMuted"},
			text = "Play music and ambience for your table.",
			width = "100%-8",
			height = "auto",
			textAlignment = "center",
			halign = "center",
			hmargin = 4,
			vmargin = 2,
		},
	}

	local function UpdateNowPlaying()
		--Duck state rides the status dot/line (amber dot + "Music ducked for Anthem")
		--instead of a separate badge, now that the dot already signals play state.
		local anthemState = rawget(_G, "g_drawSteelAnthemState")
		local ducked = anthemState ~= nil and anthemState.duckActive == true

		PrunePlayOrder()

		--Music hero = the most recently STARTED track (starting a new track is
		--an intentional act, so it takes the big slot); earlier tracks remain
		--as extra rows in start order.
		local musicList = PlayingTracksForCategory("music")
		local mid, ma = nil, nil
		local musicExtrasList = {}
		if #musicList > 0 then
			mid, ma = musicList[#musicList].id, musicList[#musicList].asset
			for i=1,#musicList-1 do
				musicExtrasList[#musicExtrasList+1] = musicList[i]
			end
		end
		m_musicId = mid
		if ma ~= nil then
			local ev = audio.currentlyPlaying[mid]
			local t = (ev ~= nil and ev.time) or 0
			local dur = ma.duration or 0
			statusDot:SetClass("playing", not ducked)
			statusDot:SetClass("ducked", ducked)
			statusLabel.text = ducked and "Music ducked for Anthem" or "Playing to your table"
			titleLabel.text = DisplayNameForAsset(ma)
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
			stopButton:SetClass("hidden", true)
			timeCurrent.text = ""
			timeTotal.text = ""
			progressFill.selfStyle.width = "0%"
		end
		musicExtrasSig = RefreshExtrasContainer(musicExtras, musicExtrasList, musicExtrasSig)

		--Ambience rows -- every playing bed is an equal layer (D8), listed in
		--start order under the "Ambience" header. No single bed is promoted to
		--a hero line; ambienceIdleLabel covers the nothing-playing case.
		local ambienceList = PlayingTracksForCategory("ambience")
		local ambiencePlaying = #ambienceList > 0
		ambienceRowsSig = RefreshExtrasContainer(ambienceRows, ambienceList, ambienceRowsSig)
		ambienceIdleLabel:SetClass("hidden", ambiencePlaying)

		--Idle-state layout: CTA replaces title/subtitle/transport only when BOTH
		--channels are silent. Music-idle-but-ambience-playing shows "Silent" / "Music"
		--in the hero slot instead (no CTA -- the table is not actually quiet).
		local musicPlaying = ma ~= nil
		local nothingPlaying = (not musicPlaying) and (not ambiencePlaying)
		if nothingPlaying then
			titleLabel:SetClass("collapsed", true)
			subtitleLabel:SetClass("collapsed", true)
			transportRow:SetClass("collapsed", true)
			ctaBlock:SetClass("collapsed", false)
		else
			ctaBlock:SetClass("collapsed", true)
			transportRow:SetClass("collapsed", not musicPlaying)
			titleLabel:SetClass("collapsed", false)
			subtitleLabel:SetClass("collapsed", false)
			if not musicPlaying then
				titleLabel.text = "Silent"
				titleLabel:SetClass("fgMuted", true)
				subtitleLabel.text = "Music"
			end
		end

		globalMuteButton:SetClass("muted", audio.muted)

		--Stop-all (D10) is only shown when something is actually playing, across
		--ANY category -- not just music/ambience. currentlyPlaying is engine
		--userdata, not a plain Lua table, so this checks membership by iterating
		--and bailing on the first entry rather than calling next() on it.
		local anyPlaying = false
		for _,_ in pairs(audio.currentlyPlaying) do
			anyPlaying = true
			break
		end
		stopAllButton:SetClass("hidden", not anyPlaying)
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
			stopAllButton,
			globalMuteButton,
			--Icon + "Studio" label chip. NOT a gui.Button: the theme's
			--{button, hasIcon} rules assume icon-ONLY buttons (square chrome,
			--icon child stretched to 100%), so icon+text through gui.Button
			--renders the glyph smeared across the label. Composite instead:
			--a bordered hoverable panel with a fixed-size tinted icon + label.
			gui.Panel{
				classes = {"bgAlt", "border", "hoverable"},
				flow = "horizontal",
				border = 1,
				cornerRadius = 3,
				width = "auto",
				height = 20,
				halign = "right",
				valign = "center",
				hmargin = 4,
				hpad = 6,
				borderBox = true,
				press = function(element)
					LaunchablePanel.LaunchPanelByName("Audio Studio")
				end,
				linger = function(element)
					gui.Tooltip("Open Audio Studio")(element)
				end,
				gui.Panel{
					--buttonIcon supplies the @fg tint; inline size overrides the
					--class's 100% fill so the glyph stays square.
					classes = {"buttonIcon"},
					bgimage = "icons/standard/Icon_App_GameControls.png",
					width = 13,
					height = 13,
					valign = "center",
				},
				gui.Label{
					classes = {"sizeXs"},
					text = "Studio",
					width = "auto",
					height = "auto",
					valign = "center",
					lmargin = 4,
				},
			},
		},

		titleLabel,
		subtitleLabel,
		transportRow,
		musicExtras,
		--CTA sits in the hero (Music) slot it replaces, ABOVE the ambience header,
		--so the idle card reads status -> CTA -> Ambience like the playing card
		--reads status -> title/transport -> Ambience.
		ctaBlock,
		ambienceHeader,
		ambienceRows,
		ambienceIdleLabel,
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
	--shared "audio mix" doc (the GroupShared table-mix layer). The segmented
	--selector row (SelectDockSection) drives its collapsed state; see below.
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

	--"Levels" body is categoryFaders itself -- the segmented selector row below
	--toggles its "collapsed" class directly (SelectDockSection), same mechanism the
	--old MakeCollapsibleSection used, just driven by the selector instead of its own
	--header. Master stays out of it (always visible above the selector).

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
			--Last master level applied by the row think's mid-preview re-scale; the
			--think only rewrites the preview volume when the master fader actually
			--moved, so it cannot stomp the volume slider's live drag-preview value
			--(which uses the not-yet-committed drag value) every poll.
			local lastAppliedMaster = nil

			--Swap the glyph between the headphones cue glyph and a stop square
			--depending on whether THIS row's anthem is the one currently previewing.
			--No rotate on this button (unlike the old triangle) since the headphones
			--glyph and the stop square both read fine upright.
			local UpdatePreviewIcon = function()
				if previewButton == nil then
					return
				end
				local previewing = previewingCharid == charid and previewInstance ~= nil and previewInstance.playing
				previewButton.bgimage = previewing and "panels/square.png" or "icons/icon_app/icon_app_23.png"
			end

			previewButton = gui.Panel{
				bgimage = "icons/icon_app/icon_app_23.png",
				bgcolor = "white",
				width = 14,
				height = 14,
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
						previewInstance.volume = (t.anthemVolume or 1) * audio.masterVolume
					end
					UpdatePreviewIcon()
				end,
				linger = function(element)
					gui.Tooltip("Preview (only you)")(element)
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
						previewInstance.volume = element.value * audio.masterVolume
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
						previewInstance.volume = element.value * audio.masterVolume
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
					--Re-apply master scaling when the master fader moves mid-preview.
					--Gated on the master actually changing so this poll never fights
					--the volume slider's live drag-preview writes.
					if previewingCharid == charid and previewInstance ~= nil and previewInstance.playing then
						if lastAppliedMaster ~= audio.masterVolume then
							lastAppliedMaster = audio.masterVolume
							previewInstance.volume = (t.anthemVolume or 1) * audio.masterVolume
						end
					else
						lastAppliedMaster = nil
					end
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

		--Ordered list of every hero charid across all parties, used both to build the rows
		--and as a cheap "did the roster change" signature (joined string compare) for the
		--periodic re-scan below.
		local function GetAnthemRowCharids()
			local ids = {}
			for _,partyid in ipairs(GetAllParties() or {}) do
				for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
					ids[#ids+1] = charid
				end
			end
			return ids
		end

		local rowsPanel
		rowsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			data = { rosterSignature = nil },

			create = function(element)
				local ids = GetAnthemRowCharids()
				local children = {}
				for _,charid in ipairs(ids) do
					local row = CreateAnthemRow(charid)
					if row ~= nil then
						children[#children+1] = row
					end
				end
				element.children = children
				element.data.rosterSignature = table.concat(ids, ",")
			end,

			--Rows are built once above from the party list; heroes added/removed while
			--the dock is open would otherwise never appear/disappear. Cheap periodic
			--re-scan: only rebuild when the joined-id signature actually changes.
			thinkTime = 2,
			think = function(element)
				local ids = GetAnthemRowCharids()
				local sig = table.concat(ids, ",")
				if sig ~= element.data.rosterSignature then
					element.data.rosterSignature = sig
					local children = {}
					for _,charid in ipairs(ids) do
						local row = CreateAnthemRow(charid)
						if row ~= nil then
							children[#children+1] = row
						end
					end
					element.children = children
				end
			end,
		}

		--Return just the BODY; show/hide is driven by the segmented selector row
		--(SelectDockSection) at the call site, same as Levels and Soundboard.
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

	--The Anthems body is CreateAnthemNode()'s returned panel, toggled by the segmented
	--selector below (same as Levels/Soundboard). ("Anthem ducks music" has moved to
	--the Studio Anthem controls, so it no longer lives on the dock.)
	local anthemsBody = CreateAnthemNode()

	local dockPlayerGrid = CreatePlayerGrid()
	--The unified soundboard button rules (AudioSoundboardButtonStyles) are
	--attached HERE, not on the dock content root -- MergeTokens resolves the
	--small custom rule list's @token references against the active scheme
	--WITHOUT merging the full base theme (unlike MergeStyles), so this stays
	--cheap: only the soundboard subtree gets the extra cascade, and the rest of
	--the dock keeps inheriting the DockablePanel host cascade untouched.
	local soundboardBody
	soundboardBody = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		styles = ThemeEngine.MergeTokens(AudioSoundboardButtonStyles),

		data = {},

		create = function(element)
			element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.MergeTokens(AudioSoundboardButtonStyles)
					element.data.themeTick = not element.data.themeTick
					element:SetClassTree("themeRefreshTick", element.data.themeTick == true)
				end
			end)
		end,

		destroy = function(element)
			if element.data.themeSub ~= nil then
				element.data.themeSub:Deregister()
				element.data.themeSub = nil
			end
		end,

		CreateDockBoardSelector(dockPlayerGrid),
		dockPlayerGrid,

		--Perform-only surface (F1c): assignment/curation lives in the Studio now.
		gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "Open Audio Studio to manage your soundboard.",
			width = "100%",
			height = "auto",
			textWrap = true,
			halign = "left",
			vmargin = 2,
		},
	}
	--Segmented selector row replacing the old "Controls" umbrella drawer: three
	--equal-width toggle buttons, exclusive selection (picking one hides whichever
	--else was open; picking the active one again collapses back to none). Mirrors
	--the Studio soundboard's "Edit board" toggle (gui.Button + press + SetClass
	--"selected") since that affordance is already verified working and themed.
	local levelsButton, anthemsButton, soundboardButton
	local SelectDockSection

	SelectDockSection = function(id)
		g_dockControlsSelected = id
		categoryFaders:SetClass("collapsed", id ~= "levels")
		anthemsBody:SetClass("collapsed", id ~= "anthems")
		soundboardBody:SetClass("collapsed", id ~= "soundboard")
		levelsButton:SetClass("selected", id == "levels")
		anthemsButton:SetClass("selected", id == "anthems")
		soundboardButton:SetClass("selected", id == "soundboard")
	end

	levelsButton = gui.Button{
		classes = {"sizeXs"},
		text = "Levels",
		width = 106,
		height = 24,
		hmargin = 2,
		borderBox = true,
		valign = "center",
		press = function()
			SelectDockSection(cond(g_dockControlsSelected == "levels", nil, "levels"))
		end,
	}

	anthemsButton = gui.Button{
		classes = {"sizeXs"},
		text = "Anthems",
		width = 106,
		height = 24,
		hmargin = 2,
		borderBox = true,
		valign = "center",
		press = function()
			SelectDockSection(cond(g_dockControlsSelected == "anthems", nil, "anthems"))
		end,
	}

	soundboardButton = gui.Button{
		classes = {"sizeXs"},
		text = "Soundboard",
		width = 106,
		height = 24,
		hmargin = 2,
		borderBox = true,
		valign = "center",
		press = function()
			SelectDockSection(cond(g_dockControlsSelected == "soundboard", nil, "soundboard"))
		end,
	}

	--Deterministic widths + a centred auto-width row: 33% x3 plus margins overran the
	--dock's real content width and clipped the right button against the panel edge
	--(percent widths ignore the margins), so the buttons are fixed-size and the row
	--shrinks to fit and centres, leaving equal space either side by construction --
	--same lesson as the fixed 342px soundboard grids (chunk F).
	local dockSectionSelectorRow = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",
		halign = "center",
		vmargin = 4,

		levelsButton,
		anthemsButton,
		soundboardButton,
	}

	local dockSectionBodies = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		categoryFaders,
		anthemsBody,
		soundboardBody,
	}

	--Restore whatever was selected earlier this session (nil on a fresh app session,
	--since g_dockControlsSelected is a plain local, never a persisted setting).
	SelectDockSection(g_dockControlsSelected)

	--Content root of the Audio dock panel. It inherits the DockablePanel host's
	--ThemeEngine cascade (DockablePanel.lua runs GetStyles at the dock root), so
	--NO local style root is declared here -- a MergeStyles snapshot on this root
	--used to duplicate the entire base theme on top of the host cascade every
	--panel under the dock already inherits (perf regression, chunk F). The
	--unified soundboard button's extra rules are attached ONLY where they are
	--needed -- on soundboardBody, via ThemeEngine.MergeTokens (see above) -- not
	--here.
	local mainPanel
	mainPanel = gui.Panel{
		halign = 'left',
		valign = 'top',
		width = "100%",
		height = "auto",
		flow = "vertical",

		refreshAudio = function(element)
			element:FireEventTree("refreshPlayingAudio")
		end,

		children = {
			--Pinned top: the now-playing section stays put. Everything below scrolls so
			--an expanded section (esp. Anthems with many heroes) scrolls rather than
			--clipping the fixed 470px dock. With nothing selected in the segmented
			--selector the body is short (now-playing + master only) and does not scroll.
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

				--Master is always visible above the segmented selector.
				masterRow,
				dockSectionSelectorRow,
				dockSectionBodies,
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

--Category id -> the top-level library folder new uploads of that category land in.
--An incremental step toward the locked design (brief 7.1: the categories ARE the
--top-level folders); legacy folders (Sounds/Soundscapes/...) are left alone for the
--user to merge manually.
local g_categoryFolderNames = { music = "Music", ambience = "Ambience", effects = "Effects" }

--Set by an upload once its landing folder is known; the library tree's next rebuild
--consumes it and force-expands that folder so the newly uploaded clip is visible
--immediately (folders remember collapse state, so a fresh upload into a collapsed
--folder would otherwise land invisibly).
local g_pendingRevealFolder = nil

--Id of the top-level, non-hidden folder with the given name (case-insensitive).
local function FindTopLevelFolderByName(name)
	local lower = string.lower(name)
	for fid,f in pairs(assets.audioFoldersTable) do
		if not f.hidden and f.parentFolder == nil and string.lower(f.description or "") == lower then
			return fid
		end
	end
	return nil
end

--Find-or-create the category's landing folder, then callback(folderid).
--UploadNewAudioFolder returns nothing and the new folder only appears in
--audioFoldersTable after the cloud echo (verified live), so the create path polls
--for the folder by name. callback(nil) if the retries exhaust - the upload then
--proceeds unfoldered and displays under the default folder.
local function EnsureCategoryFolder(category, callback)
	local name = g_categoryFolderNames[category]
	if name == nil then
		callback(nil)
		return
	end
	local existing = FindTopLevelFolderByName(name)
	if existing ~= nil then
		callback(existing)
		return
	end
	assets:UploadNewAudioFolder{ description = name }
	local attempts = 20
	local function poll()
		if mod.unloaded then return end
		local fid = FindTopLevelFolderByName(name)
		if fid ~= nil then
			callback(fid)
			return
		end
		attempts = attempts - 1
		if attempts <= 0 then
			callback(nil)
			return
		end
		dmhub.Schedule(0.25, poll)
	end
	dmhub.Schedule(0.25, poll)
end

--Stamp the chosen category onto a newly uploaded asset. The upload callback fires
--when the file TRANSFER completes, but the asset only appears in assets.audioTable
--once the cloud echo lands -- typically AFTER that callback (verified live), so a
--direct table read there silently misses. Poll briefly until the asset shows up.
local function StampUploadedAudioAsset(assetid, category, attemptsLeft)
	if attemptsLeft == nil then attemptsLeft = 40 end
	local asset = assets.audioTable[assetid]
	if asset ~= nil then
		asset.category = category
		asset:Upload()
		return
	end
	if attemptsLeft <= 0 then return end
	dmhub.Schedule(0.5, function()
		if mod.unloaded then return end
		StampUploadedAudioAsset(assetid, category, attemptsLeft - 1)
	end)
end

--File-choose + upload flow (the second half of C7; the Add-audio menu below picks
--the category and calls this). The landing folder is resolved (find-or-create)
--BEFORE the file dialog opens so the upload can carry parentFolder directly; each
--uploaded asset is then stamped with the category once its cloud echo lands, and
--the tree is told to reveal the landing folder.
local function DoAudioStudioUpload(category)
	EnsureCategoryFolder(category, function(folderid)
	dmhub.OpenFileDialog{
		id = 'AudioAssets',
		extensions = {'ogg', 'mp3', 'wav', 'flac'},
		multiFiles = true,
		prompt = "Choose audio to load",
		open = function(path)
			local operation
			local assetid = assets:UploadAudioAsset{
				path = path,
				parentFolder = folderid,
				error = function(text)
					gui.ModalMessage{ title = 'Error creating audio', message = text }
				end,
				upload = function(id)
					StampUploadedAudioAsset(id, category)
					if folderid ~= nil then
						g_pendingRevealFolder = folderid
					end
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
	end)
end

--Upload action for the Studio toolbar "+ Add audio" (C7, reshaped per James's
--field feedback): a menu of the three categories going straight to the native file
--dialog. One explicit choice per upload -- no popup to parse, no stale "last used"
--default -- and a multi-file selection gets the chosen category as a batch.
local OpenAudioStudioUpload = function(buttonElement)
	buttonElement.popup = gui.ContextMenu{
		width = 180,
		entries = {
			{
				text = "Add Music",
				click = function()
					buttonElement.popup = nil
					DoAudioStudioUpload("music")
				end,
			},
			{
				text = "Add Ambience",
				click = function()
					buttonElement.popup = nil
					DoAudioStudioUpload("ambience")
				end,
			},
			{
				text = "Add Effects",
				click = function()
					buttonElement.popup = nil
					DoAudioStudioUpload("effects")
				end,
			},
		},
	}
end

--One library row: play/stop + name + per-row category dropdown + volume. Plays
--through the same GameSoundEvent path as the dock tiles. opts carries the library
--tree's drag wiring (draggable / canDragOnto / drag) so a clip can be dragged into
--a folder; it is nil when the row is used outside the tree.
--DM-only audition ("cue"): only one library clip previews at a time. asset:Play()
--is local-only (never broadcast) and bypasses the mix groups, so a cue is not a
--level-matched monitor of what the table hears -- but its volume is scaled by
--audio.masterVolume (applied at cue start and refreshed on the cueButton's think)
--so it at least tracks the DM's master fader instead of blasting at raw asset
--volume. Tracked at module scope so starting a cue in one row stops the cue in
--another.
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

--Shared delete confirm for one or more library clips (C2 context menu / future
--callers). ids is a list of assetids; names is used only for the single-clip
--message. Soft-deletes (hidden = true) rather than a hard delete, matching every
--other delete path in this file.
local function ConfirmDeleteAudioClips(ids)
	if #ids == 0 then return end
	local title = "Delete Audio?"
	local message
	if #ids == 1 then
		local a = assets.audioTable[ids[1]]
		message = string.format('Are you sure you want to delete "%s"? It will be removed from your library and any soundboard buttons that use it.', DisplayNameForAsset(a))
	else
		message = string.format("Are you sure you want to delete these %d clips? They will be removed from your library and any soundboard buttons that use them.", #ids)
	end
	gui.ModalMessage{
		title = title,
		message = message,
		options = {
			{
				text = "Delete",
				execute = function()
					for _,id in ipairs(ids) do
						local a = assets.audioTable[id]
						if a ~= nil then
							a.hidden = true
							a:Upload()
						end
					end
				end,
			},
			{
				text = "Cancel",
				execute = function()
				end,
			},
		},
	}
end

--Shared "set category for these clips" (C2 row menu / folder menu). ids is a list
--of assetids; category is "music"/"ambience"/"effects"/nil (nil clears).
local function SetCategoryForAudioClips(ids, category)
	for _,id in ipairs(ids) do
		local a = assets.audioTable[id]
		if a ~= nil then
			a.category = category
			a:Upload()
		end
	end
end

--Submenu entries for "Set Category" (row + folder context menus share this list).
local function CategorySubmenuEntries(applyFn)
	return {
		{ text = "Music", click = function() applyFn("music") end },
		{ text = "Ambience", click = function() applyFn("ambience") end },
		{ text = "Effects", click = function() applyFn("effects") end },
		{ text = "Clear category", click = function() applyFn(nil) end },
	}
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
				PlayBroadcastClip(audioAsset, { volume = audioAsset.volume })
			end
		end,
		linger = function(element)
			gui.Tooltip("Play to table")(element)
		end,
	}

	--DM-only audition: headphones glyph (icon_app_23) stands in for "only you hear
	--this" -- a placeholder until better art lands (glyph upgrade bucket, plan M0).
	--Local asset:Play(); turns "active" (green) while this row is cueing and polls
	--so it clears when the clip ends or another row takes over.
	local cueButton
	cueButton = gui.Panel{
		classes = {"audioCueButton"},
		bgimage = "icons/icon_app/icon_app_23.png",
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
					g_studioCueInstance.volume = audioAsset.volume * audio.masterVolume
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
			else
				--Re-apply master scaling each poll so dragging the master fader
				--mid-cue takes effect immediately, not just at cue start.
				g_studioCueInstance.volume = audioAsset.volume * audio.masterVolume
			end
		end,
		create = function(element)
			element:FireEvent("refreshCue")
		end,
		linger = function(element)
			gui.Tooltip("Preview (only you)")(element)
		end,
	}

	--Loop toggle: same "game-icons/infinity.png" glyph + disabled-when-off styling
	--approach as the unified soundboard button's loop glyph, sized to sit inline in
	--the row. bgimage is set directly (not via a class rule) so it renders under any
	--cascade -- this Studio row is a separate surface from the soundboard buttons.
	local loopButton = gui.Panel{
		classes = {"audioRowLoopButton", cond(audioAsset.loop, nil, "disabled")},
		bgimage = "game-icons/infinity.png",
		width = 16,
		height = 16,
		valign = "center",
		hmargin = 3,
		monitorAssets = "audio",
		refreshAssets = function(element)
			element:SetClass("disabled", not audioAsset.loop)
		end,
		press = function(element)
			audioAsset.loop = not audioAsset.loop
			audioAsset:Upload()
			element:SetClass("disabled", not audioAsset.loop)
		end,
		linger = function(element)
			gui.Tooltip("Loop")(element)
		end,
	}

	--Mute: local-only, mirrors the dock tile mute (SetSoundEventVolume(id, 0) vs
	--restore-to-slider-volume). volumeSlider is forward-declared since the press
	--handler reads its current value on unmute.
	local volumeSlider
	local muted = false
	local muteButton = gui.Panel{
		classes = {"hoverable", "audioRowMuteButton"},
		bgimage = "ui-icons/AudioVolumeButton.png",
		bgcolor = "white",
		width = 16,
		height = 16,
		valign = "center",
		hmargin = 3,
		press = function(element)
			muted = not muted
			element:SetClass("muted", muted)
			if muted then
				element.bgimage = "ui-icons/AudioMuteButton.png"
				audio.SetSoundEventVolume(audioAsset.id, 0)
			else
				element.bgimage = "ui-icons/AudioVolumeButton.png"
				audio.SetSoundEventVolume(audioAsset.id, volumeSlider.value)
			end
		end,
		linger = function(element)
			gui.Tooltip("Mute")(element)
		end,
	}

	--Duration: muted mm:ss readout, matching the dock tile's FormatTime(duration,
	--duration) source (no live playback progress here -- that lives on the dock).
	local durationLabel = gui.Label{
		classes = {"sizeXs", "fgMuted"},
		text = FormatTime(audioAsset.duration, audioAsset.duration),
		width = 40,
		height = "auto",
		halign = "right",
		valign = "center",
		hmargin = 3,
		fontSize = 11,
		textAlignment = "right",
		monitorAssets = "audio",
		refreshAssets = function(element)
			element.text = FormatTime(audioAsset.duration, audioAsset.duration)
		end,
	}

	--Title is the leftmost scan anchor and flexes to fill; the controls sit to its
	--right. Width is the column minus the fixed control cluster (duration+loop+play+
	--cue+mute+category+volume+margins) -- a deterministic complement, since "100%
	--available" collapses. Editable on double-click (C1); displays the extension-
	--stripped name via DisplayNameForAsset, but edits the full stored description.
	--There is no engine hook to intercept "editing is about to begin" on a Label, so
	--a double-click edits the displayed (extension-stripped) text -- the brief's
	--documented fallback. The "Rename" context-menu entry (BeginRenameEditing below)
	--takes a cleaner path: it controls the BeginEditing() call directly, so it loads
	--the full stored description into the field first.
	local nameLabel
	local function BeginRenameEditing()
		nameLabel.text = audioAsset.description
		nameLabel:BeginEditing()
	end
	nameLabel = gui.Label{
		editableOnDoubleClick = true,
		text = DisplayNameForAsset(audioAsset),
		width = "100%-348",
		height = "auto",
		halign = "left",
		valign = "center",
		hmargin = 4,
		textWrap = false,
		textOverflow = "ellipsis",

		change = function(element)
			audioAsset.description = element.text
			audioAsset:Upload()
			element.text = DisplayNameForAsset(audioAsset)
		end,

		monitorAssets = "audio",
		refreshAssets = function(element)
			if not element.editing then
				element.text = DisplayNameForAsset(audioAsset)
			end
		end,
		linger = function(element)
			gui.Tooltip(DisplayNameForAsset(audioAsset))(element)
		end,
	}

	--Behavior (options/normalisation/change) is shared with the dock tile version via
	--CreateCategoryDropdown; only the row-specific layout is passed in here.
	--unroutedHint (C8) is Studio-row-only: the dock tile dropdown never gets the
	--warning tint/tooltip.
	local categorySelector = CreateCategoryDropdown(audioAsset, {
		hmargin = 3,
		unroutedHint = true,
	})

	volumeSlider = gui.Slider{
		value = audioAsset.volume,
		minValue = 0,
		maxValue = 1,
		sliderWidth = 70,
		labelWidth = 0,
		labelFormat = "",
		style = { width = 80, height = 16, valign = "center", hmargin = 3 },
		events = {
			preview = function(element)
				if not muted then
					audio.SetSoundEventVolume(audioAsset.id, element.value)
				end
			end,
			confirm = function(element)
				if not muted then
					audio.SetSoundEventVolume(audioAsset.id, element.value)
				end
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

	--C2: right-click context menu. Multi-select aware -- when this row's assetid is
	--part of an active multi-selection (opts.getSelection, threaded from the tree),
	--Delete and Set Category apply to the whole selection instead of just this row.
	local function TargetIds()
		if opts.getSelection ~= nil then
			local sel = opts.getSelection()
			if sel ~= nil and sel[audioAsset.id] == true then
				local ids = {}
				local count = 0
				for id,_ in pairs(sel) do
					ids[#ids+1] = id
					count = count + 1
				end
				if count > 1 then
					return ids
				end
			end
		end
		return { audioAsset.id }
	end

	local function OpenRowContextMenu(element)
		local ids = TargetIds()
		local entries = {
			{
				text = "Rename",
				click = function()
					element.popup = nil
					BeginRenameEditing()
				end,
			},
			{
				text = "Set Category",
				submenu = CategorySubmenuEntries(function(category)
					element.popup = nil
					SetCategoryForAudioClips(ids, category)
				end),
			},
			{
				text = "Delete",
				click = function()
					element.popup = nil
					ConfirmDeleteAudioClips(ids)
				end,
			},
		}
		if devmode() then
			entries[#entries+1] = {
				text = "Copy ID",
				click = function()
					element.popup = nil
					dmhub.CopyToClipboard(audioAsset.id)
				end,
			}
		end
		element.popup = gui.ContextMenu{
			width = 180,
			entries = entries,
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
		rightClick = function(element)
			OpenRowContextMenu(element)
		end,
		refreshSelection = function(element, selectedSet)
			element:SetClass("selected", selectedSet ~= nil and selectedSet[audioAsset.id] == true)
		end,
		reorderSpacer,
		nameLabel,
		durationLabel,
		loopButton,
		playButton,
		cueButton,
		muteButton,
		categorySelector,
		volumeSlider,
		--Reserved gutter: the library vscroll bar overlays the right edge of each
		--row, hiding the slider diamond + editable value without this spacer.
		gui.Panel{ width = 12, height = 1 },
	}
end

--Studio Soundboard curation card (right column). Five boards of twelve buttons,
--sharing the same audiogrid-<board>-<slot> documents the dock soundboard plays
--from: this surface ASSIGNS and CLEARS clips, the dock surface fires them. A clip
--occupies at most one button per board (de-duped on assign). Buttons are the
--unified CreateSoundboardButton (surface="studio"); the card's own edit mode gates
--the assign/clear/swatch/drag affordances (chunk F1b) -- see the "Edit board"
--toggle below.

local CreateStudioSoundboard = function()
	local m_board = 1
	local m_editMode = false
	local gridPanel
	local boardButtons = {}
	local editToggle
	local captionLabel

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
			return string.find(string.lower(DisplayNameForAsset(asset)), searchText, 1, true) ~= nil
		end

		local function RebuildList()
			local children = {}
			for _,asset in ipairs(AssignableClips()) do
				if MatchClip(asset) then
					local a = asset
					local displayName = DisplayNameForAsset(a)
					if displayName == "" then displayName = "(unnamed)" end
					children[#children+1] = gui.Label{
						classes = {"sizeS", "hoverable"},
						text = displayName,
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
					borderBox = true,
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

	local function IsEditMode()
		return m_editMode
	end

	local function GetBoard()
		return m_board
	end

	--Built ONCE at card build (chunk F, P2/P3): the 12 buttons are constructed a
	--single time with a getBoard getter and never rebuilt again. Board switches and
	--edit-mode toggles both now just fire refreshGrid across the subtree instead of
	--calling this a second time.
	local function BuildGrid()
		local children = {}
		for slot = 1, STUDIO_SLOTS do
			children[#children+1] = CreateSoundboardButton(nil, slot, {
				surface = "studio",
				isEditMode = IsEditMode,
				getBoard = GetBoard,
				openAssignPopup = OpenAssignPopup,
			})
		end
		gridPanel.children = children
	end

	--Fixed size + centered (chunk F, P4): shared AUDIO_SB_GRID_WIDTH/HEIGHT constants
	--(342 x 264 -- 3 columns x 4 rows of 114/66 cells) with the dock grid, so both
	--surfaces present the same deterministic 3x4 shape. Replaces the old
	--width=350/height="auto" wrap, which cost more to lay out and, being
	--auto-height, is also why the width could drift from the dock's true 342.
	gridPanel = gui.Panel{
		flow = "horizontal",
		wrap = true,
		width = AUDIO_SB_GRID_WIDTH,
		height = AUDIO_SB_GRID_HEIGHT,
		halign = "center",
		vmargin = 4,
	}

	--Board selector: "Board" label + five segmented buttons. The active board carries
	--{selected} (themed fill). Switching no longer rebuilds the grid (chunk F, P2) --
	--it just updates m_board + the selected classes, then fires refreshGrid so every
	--button recomputes its own docid.
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
				gridPanel:FireEventTree("refreshGrid")
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

	--Edit board toggle: flips m_editMode, updates its own text/selected class and the
	--caption copy, then fires refreshGrid (chunk F, P3) -- no more grid rebuild on
	--every toggle. refreshGame (fired by refreshGrid) already applies
	--element:SetClass("editMode", IsEditMode()) and the dynamic draggable flag, so
	--this is the only thing the toggle needs to do.
	editToggle = gui.Button{
		classes = {"sizeXs"},
		text = "Edit board",
		--Fixed width: "auto" wrapped the two-word label onto two lines here.
		--"Stop editing" is the longest label this button shows; 84 still fits it
		--at sizeXs (verified live), so the width is unchanged.
		width = 84,
		height = 24,
		valign = "center",
		press = function(element)
			m_editMode = not m_editMode
			element:SetClass("selected", m_editMode)
			element.text = m_editMode and "Stop editing" or "Edit board"
			gridPanel:FireEventTree("refreshGrid")
			captionLabel.text = m_editMode
				and "Click an empty button to assign a clip. Use the bin to clear a button, drag to reorder, and the swatch to set its color."
				or "Click a button to play or stop its clip. Use Edit board to change assignments."
		end,
	}

	captionLabel = gui.Label{
		classes = {"fgMuted", "sizeXs"},
		text = "Click a button to play or stop its clip. Use Edit board to change assignments.",
		width = "100%",
		height = "auto",
		halign = "left",
		vmargin = 2,
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

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",
			vmargin = 2,
			gui.Panel{
				flow = "horizontal",
				width = "100%-90",
				height = "auto",
				halign = "left",
				valign = "center",
				gui.Label{ classes = {"bold", "sizeS"}, text = "Soundboard", width = "auto", height = "auto", halign = "left", valign = "center" },
			},
			editToggle,
		},

		boardSelector,
		gridPanel,

		captionLabel,
	}
end

--Studio Ducking controls (F polish, task 6d: moved off the right column into a
--popover off the Levels card's "Ducking settings" button -- the right column only
--has room for the soundboard + mixer now). P1 = the "Duck Music Under Anthems"
--toggle (the anthemduckmusic game setting, also surfaced in Settings->Audio and
--read by the anthem hook) plus a depth control setting how far music dips while an
--anthem plays (anthemduckdepth, read live by the anthem hook). The per-target duck
--matrix is Phase 3-4, shown as a dimmed placeholder. Both settings are
--game-scoped/DM-owned; the toggle is think-synced so it tracks changes made from
--Settings->Audio.
--Fallback-only mirror of MCDMInitiativeBar.lua's anthemDuckDefaults, used only if the
--Draw Steel rules layer has not loaded (should not happen in practice since this file
--loads after it, but keeps this card from erroring in isolation). Keep these three
--values in sync with g_drawSteelAnthemDuckDefaults if that source ever changes.
local kFallbackAnthemDuckDefaults = { depth = 0.15, fadeIn = 1.0, fadeOut = 2.5 }

--Body builder: just the ducking CONTROLS (no card frame), so it can be reused by
--both a standalone card shell and the popover without duplicating the wiring. The
--think-based settings sync (duckCheck) keeps working wherever this is parented,
--including inside a transient popup.
local function CreateStudioDuckingBody()
	local duckDefaults = rawget(_G, "g_drawSteelAnthemDuckDefaults") or kFallbackAnthemDuckDefaults

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
		--halign="right" removed (chunk F, L2): sits immediately after its label,
		--like the fader rows; label widths (96, both here and in MakeSecondsRow
		--below) are kept equal so the three sliders in this popover still line up
		--with EACH OTHER.
		style = {
			width = 170,
			height = 16,
			valign = "center",
		},
		sliderWidth = 130,
		labelWidth = 30,
		labelFormat = "percent",
		minValue = 0,
		maxValue = 1,
		value = dmhub.GetSettingValue("anthemduckdepth") or duckDefaults.depth,
		confirm = function(element)
			dmhub.SetSettingValue("anthemduckdepth", element.value)
		end,
	}

	--A "label + seconds slider" row (0..5s) for the two duck fade times. Reads the game
	--setting on build; commits on release. The readout is editable (type a number).
	local function MakeSecondsRow(labelText, settingId, defaultVal)
		--halign="right" removed (chunk F, L2): matches depthSlider above.
		local slider = gui.Slider{
			style = { width = 170, height = 16, valign = "center" },
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
		gui.Label{ classes = {"fgMuted", "sizeXs"}, text = "Per-track ducking controls are planned for a future update.", width = "100%", height = "auto", textWrap = true, vmargin = 2 },
	}

	--No card frame here -- the caller (the standalone popover) supplies its own
	--framedPanel shell; this panel is just the stacked controls, so it also picks
	--up whatever cascade its parent provides (the popover routes its own
	--MergeStyles snapshot, same as every other popup in this file).
	return gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

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
		MakeSecondsRow("Fade in (s)", "anthemduckfadein", duckDefaults.fadeIn),
		MakeSecondsRow("Fade out (s)", "anthemduckfadeout", duckDefaults.fadeOut),

		matrixPlaceholder,
	}
end

--Studio Mixer card (right column): a full duplicate of the dock's parent faders so a DM
--who works from the Studio finds the core table mix here too. Same faders + same shared
--"audio mix" doc / SetGroupShared wiring as the dock (module-scoped helpers), so the two
--surfaces stay in lockstep. Master is live (audio.masterVolume); the five category faders
--write the broadcast layer. The header row also carries the "Ducking settings" button
--(F polish, task 6d) that opens the ducking controls in a popover -- same placement
--pattern as the Studio soundboard's "Edit board" toggle (right side of the title row).
local CreateStudioMixerCard = function()
	--Mirror the persisted broadcast levels into this client's engine on build.
	ApplyBroadcastToEngine()

	--Popover trigger. Popups are reparented to the popup layer and do not inherit
	--the Studio cascade, so route their own ThemeEngine snapshot (transient --
	--rebuilt each open, no OnThemeChanged), same pattern as the swatch/assign
	--popups elsewhere in this file. The body content is CreateStudioDuckingBody(),
	--the same reusable builder the ducking controls always used -- there is no
	--separate card frame to duplicate the wiring against.
	local duckingButton
	duckingButton = gui.Button{
		classes = {"sizeXs"},
		text = "Ducking settings",
		--Fits "Ducking settings" at sizeXs; wider than the old "Ducking..." button
		--since the label is now the full descriptive string (signed, 2026-07-02).
		width = 106,
		height = 24,
		valign = "center",
		popupPositioning = "panel",
		press = function(element)
			if element.popup ~= nil then
				element.popup = nil
				return
			end
			element.popup = gui.Panel{
				styles = ThemeEngine.MergeStyles{},
				classes = {"framedPanel"},
				width = 380,
				height = "auto",
				halign = "right",
				flow = "vertical",
				pad = 8,
				borderBox = true,
				CreateStudioDuckingBody(),
			}
		end,
	}

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
			gui.Panel{
				flow = "horizontal",
				width = "100%-114",
				height = "auto",
				halign = "left",
				valign = "center",
				gui.Label{ classes = {"bold", "sizeS"}, text = "Levels", width = "auto", height = "auto", halign = "left", valign = "center" },
			},
			duckingButton,
		},

		gui.Label{
			classes = {"fgMuted", "sizeXs"},
			text = "These are the broadcast levels (what the table hears). Players can manage their own mixing levels but the above levels set the ceiling.",
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 2,
		},

		MakeFaderRow("Master", MakeMasterFader(), false),
		MakeFaderRow("Music", MakeBroadcastFader("music"), false),
		MakeFaderRow("Ambience", MakeBroadcastFader("ambience"), false),
		MakeFaderRow("Effects", MakeBroadcastFader("effects"), false),
		MakeFaderRow("UI Sounds", MakeBroadcastFader("uisounds"), false),
		MakeFaderRow("Anthem", MakeBroadcastFader("anthem"), false),
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

	--C6 library search. m_searchText is the active lowercase filter ("" = none).
	--m_preSearchExpanded snapshots the user's expansion state (m_expanded) the moment
	--a search session STARTS (first non-empty search text), so clearing the search
	--restores exactly what they had open before -- captured once, not on every
	--keystroke, so typing further into an active search does not re-snapshot the
	--already-filtered (all-expanded) state.
	local m_searchText = ""
	local m_preSearchExpanded = nil

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
		--Prune ids of clips that were since deleted or moved to a different folder, so
		--the doc does not accumulate stale ids forever (only runs on reorder writes, not
		--per frame). Uses the live asset table rather than an extra scan of the folder.
		local pruned = {}
		for _,id in ipairs(list) do
			local a = assets.audioTable[id]
			if a ~= nil and not a.hidden and (a.parentFolder or defaultFolder) == folderid then
				pruned[#pruned+1] = id
			end
		end

		local doc = mod:GetDocumentSnapshot(audioClipOrderDocId)
		doc:BeginChange()
		if doc.data.order == nil then doc.data.order = {} end
		doc.data.order[folderid] = pruned
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

	--C6: restrict the maps BuildMaps produced to what an active search should show.
	--A folder is kept if its OWN name matches, or it contains a matching clip, or ANY
	--descendant folder does (recursively) -- so a match three folders deep still pulls
	--its whole ancestor chain into view. Clips are filtered to matches only, within
	--whichever folders survive. Matched folders are recorded into matchedFolderSet so
	--CreateFolderNode can force them open + built regardless of remembered expansion.
	local function FilterMaps(foldersByParent, clipsByFolder, searchText, matchedFolderSet)
		if searchText == "" then
			return foldersByParent, clipsByFolder
		end

		--Recursively decide (and memoise) whether folderid should survive the filter:
		--its own name matches, one of its direct clips matches, or a child folder does.
		local decided = {}
		local function FolderSurvives(folderid, folder)
			if decided[folderid] ~= nil then
				return decided[folderid]
			end
			--Guard against re-entrancy on a malformed cycle (should not happen).
			decided[folderid] = false

			local survives = false
			if folder ~= nil and string.find(string.lower(folder.description or ""), searchText, 1, true) ~= nil then
				survives = true
			end
			if not survives then
				for _,asset in ipairs(clipsByFolder[folderid] or {}) do
					if string.find(string.lower(DisplayNameForAsset(asset)), searchText, 1, true) ~= nil then
						survives = true
						break
					end
				end
			end
			if not survives then
				for _,sub in ipairs(foldersByParent[folderid] or {}) do
					if FolderSurvives(sub.id, sub.folder) then
						survives = true
						break
					end
				end
			end

			decided[folderid] = survives
			if survives then
				matchedFolderSet[folderid] = true
			end
			return survives
		end

		local outFoldersByParent = {}
		local outClipsByFolder = {}
		local function FilterLevel(parentKey)
			for _,entry in ipairs(foldersByParent[parentKey] or {}) do
				if FolderSurvives(entry.id, entry.folder) then
					local t = outFoldersByParent[parentKey]
					if t == nil then t = {} outFoldersByParent[parentKey] = t end
					t[#t+1] = entry

					local clips = {}
					for _,asset in ipairs(clipsByFolder[entry.id] or {}) do
						if string.find(string.lower(DisplayNameForAsset(asset)), searchText, 1, true) ~= nil then
							clips[#clips+1] = asset
						end
					end
					outClipsByFolder[entry.id] = clips

					FilterLevel(entry.id)
				end
			end
		end
		FilterLevel("__root__")

		return outFoldersByParent, outClipsByFolder
	end

	--Remembered expansion per folderid, so a tree rebuild (any asset/folder change,
	--including a drag-move) does not collapse everything. Captured from the live
	--nodes just before each rebuild.
	local m_expanded = {}
	--Folders an active search matched (directly or via a descendant/clip match);
	--CreateFolderNode force-opens + force-builds these regardless of m_expanded.
	local m_searchMatched = {}

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

		--Only touch the asset (and pay for a cloud Upload + monitorAssets rebuild on every
		--client) when the drag actually moved it to a different folder. A pure
		--intra-folder reorder only needs the audioClipOrder doc write below.
		for _,id in ipairs(ids) do
			local a = assets.audioTable[id]
			if a ~= nil and (a.parentFolder or defaultFolder) ~= destFolderId then
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
					--Threaded (not a global read) so the row's C2 context menu can tell
					--whether it is right-clicked as part of a live multi-selection.
					getSelection = function() return m_selected end,
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
		--An active search force-opens every folder it matched (C6 "auto-expand every
		--folder shown"), regardless of the user's remembered expansion.
		local forceOpen = m_searchMatched[folderid] == true
		local startOpen = forceOpen or m_expanded[folderid] == true

		local node
		node = gui.TreeNode{
			classes = {"audioFolderNode"},
			text = folder.description or "Folder",
			width = "100%",
			editable = true,
			expanded = startOpen,
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
				local entries = {
					{
						text = "Set category for all clips in this folder",
						submenu = CategorySubmenuEntries(function(category)
							element.popup = nil
							--RECURSIVE (James's field call): applies to the folder's own
							--clips AND every clip in descendant subfolders, so bulk-setting
							--"Effects" from the top folder routes its whole subtree. Reads
							--the live asset/folder tables (not the closure's clipsByFolder)
							--so an active library search filter cannot narrow the target
							--set. The visited guard stops a malformed parentFolder cycle.
							local targetFolders = { [folderid] = true }
							local added = true
							while added do
								added = false
								for fid,f in pairs(assets.audioFoldersTable) do
									if not targetFolders[fid] and f.parentFolder ~= nil and targetFolders[f.parentFolder] then
										targetFolders[fid] = true
										added = true
									end
								end
							end
							local ids = {}
							for id,asset in pairs(assets.audioTable) do
								if not asset.hidden and targetFolders[asset.parentFolder or defaultFolder] then
									ids[#ids+1] = id
								end
							end
							SetCategoryForAudioClips(ids, category)
						end),
					},
				}
				if not isDefault then
					--The default "Sounds" folder is not deletable.
					entries[#entries+1] = {
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
					}
				end
				element.popup = gui.ContextMenu{
					width = 220,
					entries = entries,
				}
			end,
		}
		--A folder that starts expanded (remembered state, or force-opened by an active
		--search match) builds its contents now; collapsed folders defer until first
		--opened. The expand event covers the toggle-open case.
		if startOpen then
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

	--Chunk F5: true when the library has no non-hidden clips at all (independent of
	--folders existing or an active search). Checked directly against the live asset
	--table rather than derived from BuildMaps/FilterMaps so an active search filter
	--never triggers this -- an empty SEARCH RESULT is a different, already-handled
	--case (the folder tree just renders empty under the search bar).
	local function LibraryIsEmpty()
		for _,asset in pairs(assets.audioTable) do
			if not asset.hidden then
				return false
			end
		end
		return true
	end

	local function DoRebuild(element)
		--While a search is active, the live tree's expansion is search-driven (every
		--matched folder force-opened), not the user's real preference -- capturing it
		--into m_expanded would clobber what they had open before the search started.
		--m_preSearchExpanded already holds that pre-search snapshot (taken once, see
		--below), so skip the live capture entirely for the duration of the search.
		if m_searchText == "" then
			CaptureExpansion(element)
		end

		--A fresh upload asks the tree to reveal its landing folder (consumed once,
		--AFTER CaptureExpansion so the live collapsed state cannot overwrite it).
		--m_expanded persists across rebuilds, so the folder stays open afterwards
		--like any user-expanded folder.
		if g_pendingRevealFolder ~= nil then
			m_expanded[g_pendingRevealFolder] = true
			g_pendingRevealFolder = nil
		end

		--F5: empty-library hint replaces the (otherwise empty) folder tree entirely.
		--Constructed only in this branch (never speculatively) and disappears on the
		--next rebuild once a clip exists, since monitorAssets already drives rebuilds.
		if LibraryIsEmpty() then
			element.children = {
				gui.Label{
					classes = {"fgMuted", "sizeS"},
					text = "Your library is empty. Click + Add audio to get started.",
					width = "100%",
					height = "100%",
					textAlignment = "center",
					halign = "center",
					valign = "center",
				},
			}
			return
		end

		local rawFoldersByParent, rawClipsByFolder = BuildMaps()
		m_searchMatched = {}
		local foldersByParent, clipsByFolder = FilterMaps(rawFoldersByParent, rawClipsByFolder, m_searchText, m_searchMatched)

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

	--C6: apply a new search string and rebuild. Captures the pre-search expansion
	--once, on the transition from no-filter to filtered, and restores it once, on the
	--transition back to no-filter (clearing the search) -- typing further within an
	--active search does not touch the snapshot.
	local function SetSearchFilter(rawText)
		local text = string.lower(trim(rawText or ""))
		if text == m_searchText then
			return
		end
		if m_searchText == "" and text ~= "" then
			--Search session starting: snapshot current expansion once.
			m_preSearchExpanded = {}
			for k,v in pairs(m_expanded) do m_preSearchExpanded[k] = v end
		elseif m_searchText ~= "" and text == "" then
			--Search session ending: restore what the user had open before it started.
			if m_preSearchExpanded ~= nil then
				m_expanded = m_preSearchExpanded
			end
			m_preSearchExpanded = nil
		end
		m_searchText = text
		RequestRebuild()
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
		height = "100%-28",
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

	--C6: search bar above the tree. gui.SearchInput fires "search" with the already
	--lowercased/trimmed text; SetSearchFilter re-lowercases/trims defensively (cheap)
	--so this does not depend on that internal behavior.
	local searchInput = gui.SearchInput{
		placeholderText = "Search library...",
		--Shorter than the card so it cannot clip the bordered edge (a 100% row ran
		--under the border); it does not need the full width to do its job.
		width = 300,
		height = 24,
		halign = "left",
		vmargin = 2,
		search = function(element, text)
			SetSearchFilter(text)
		end,
	}

	return gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "100%-24",
		searchInput,
		m_root,
	}
end

--Fixed category row order for the Studio now-playing BLOCK (D9, restructured
--under Option A -- see CreateStudioNowPlayingStrip below). Mirrors the dock's
--Music/Ambience layout, then Effects, then anything with no category at all
--under "Uncategorised". id is the value stored on asset.category
--(GetAssetCategoryId normalises nil/"" to "none"); label is the row's display
--name. ALL FOUR rows are now permanently reserved (Option A, 2026-07-02 review):
--every row renders "Silent" when idle instead of disappearing, so the block is a
--fixed height and the Library below it never shifts when a one-shot fires.
local STUDIO_STRIP_CATEGORY_ORDER = {
	{ id = "music", label = "Music", reserved = true },
	{ id = "ambience", label = "Ambience", reserved = true },
	{ id = "effects", label = "Effects", reserved = true },
	{ id = "none", label = "Uncategorised", reserved = true },
}

--Row height (each of the 4 reserved category rows) and the header row height,
--shared between the block's own layout and AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT
--below so the two cannot drift apart.
local AUDIO_STUDIO_NOWPLAYING_ROW_HEIGHT = 24
local AUDIO_STUDIO_NOWPLAYING_HEADER_HEIGHT = 20

--Fixed total height of the now-playing block (Option A): header row (20 + 2*2
--vmargin = 24) + 4 category rows (24 + 2*2 vmargin = 28 each -> 112) + the
--block's own 8px top/bottom pad (16) = 152. Computed once here so the left
--column's constants (below, near CreateAudioStudio) can reference it instead of
--re-deriving the same arithmetic.
local AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT = AUDIO_STUDIO_NOWPLAYING_HEADER_HEIGHT + 4
	+ 4 * (AUDIO_STUDIO_NOWPLAYING_ROW_HEIGHT + 4) + 16

--Studio now-playing BLOCK (Option A, 2026-07-02 review -- replaces the old
--full-width top strip): a fixed-height card at the top of the LEFT column,
--above the Library, showing every playing track across all categories at once
--(the dock only surfaces the primary music/ambience pair), one row per category
--(chunk D9). ALL FOUR rows (Music/Ambience/Effects/Uncategorised) are always
--present ("Silent" when idle) so the block never grows or shrinks and the
--Library tree below it never shifts when a one-shot starts or ends -- there is
--no more onLayout/numRows callback; height is the fixed
--AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT constant, computed once above.
--Updated by the root's refreshAudio -> refreshPlayingAudio tree fire (instant on
--play/stop) plus its own 0.5s poll (a track ending naturally fires no event).
local function CreateStudioNowPlayingStrip()
	--Full width now -- "Stop all" moved from a floating overlay on this column
	--into a normal child of headerRow (below), so rowsColumn no longer needs to
	--leave a gutter for it.
	local rowsColumn = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
	}
	local lastSig = nil

	--Hidden while nothing plays (a dead control at rest); the block itself stays
	--visible with its reserved rows, so toggling this never changes the height.
	local stopAllButton = gui.Button{
		classes = {"sizeXs", "hidden"},
		text = "Stop all",
		width = "auto",
		height = 20,
		halign = "right",
		valign = "top",
		hmargin = 4,
		press = function(element)
			audio.StopAllSoundEvents()
		end,
	}

	local function CreateChip(id, asset)
		return gui.Panel{
			classes = {"bgAlt", "border"},
			flow = "horizontal",
			border = 1,
			cornerRadius = 3,
			width = "auto",
			height = 20,
			hmargin = 4,
			hpad = 6,
			borderBox = true,
			valign = "center",
			gui.Label{
				classes = {"sizeXs"},
				text = DisplayNameForAsset(asset),
				width = 180,
				height = "auto",
				halign = "left",
				valign = "center",
				textWrap = false,
				textOverflow = "ellipsis",
			},
			gui.Panel{
				bgimage = "panels/square.png",
				bgcolor = "white",
				width = 11,
				height = 11,
				valign = "center",
				hmargin = 4,
				press = function(element)
					audio.StopSoundEvent(id)
				end,
				linger = function(element)
					gui.Tooltip("Stop")(element)
				end,
			},
		}
	end

	--One row per category: a fixed-width label + that category's chips in
	--play-start order (or a muted "Silent" for an idle reserved row -- matching
	--the dock's idle vocabulary). Fixed height so an idle row occupies exactly
	--the space its chips will: the block never grows or shrinks as tracks start
	--and stop. table.sort is not needed here -- PlayOrderOf/PlayingTracksForCategory
	--(module-scoped, chunk D7) already return tracks oldest-first.
	local function CreateCategoryRow(categoryLabel, entries)
		local children = {
			gui.Label{
				classes = {"sizeXs", "bold"},
				text = categoryLabel,
				--Wide enough for "Uncategorised" (the longest label) on one line --
				--64 wrapped it onto two lines inside the 24px row.
				width = 92,
				height = "auto",
				textWrap = false,
				halign = "left",
				valign = "center",
			},
		}
		if #entries == 0 then
			children[#children+1] = gui.Label{
				classes = {"sizeXs", "fgMuted"},
				text = "Silent",
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 4,
			}
		end
		for i=1,#entries do
			children[#children+1] = CreateChip(entries[i].id, entries[i].asset)
		end
		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = AUDIO_STUDIO_NOWPLAYING_ROW_HEIGHT,
			valign = "center",
			vmargin = 2,
			children = children,
		}
	end

	local function Refresh(element)
		--Signature encodes both category grouping AND order within each category
		--("cat:id" per entry, in display order) so a track moving between
		--categories or reordering within one triggers a rebuild.
		local sigParts = {}
		local rowsByCategory = {}
		for _,cat in ipairs(STUDIO_STRIP_CATEGORY_ORDER) do
			rowsByCategory[cat.id] = {}
		end
		for assetid,_ in pairs(audio.currentlyPlaying) do
			local a = assets.audioTable[assetid]
			if a ~= nil then
				local catId = GetAssetCategoryId(a)
				if rowsByCategory[catId] == nil then
					rowsByCategory[catId] = {}
				end
				table.insert(rowsByCategory[catId], { id = assetid, asset = a, order = PlayOrderOf(assetid) })
			end
		end

		--Two passes: compute the signature first, and only CONSTRUCT row panels
		--when it changed. Building rows unconditionally would orphan a fresh set
		--of panels on every 0.5s think ("created but not attached" warnings). All
		--four rows are reserved now (Option A) -- always emitted, idle or not,
		--with a "-" marker in the signature so idle <-> playing transitions
		--rebuild. Row count is therefore always 4; the block height is fixed
		--(AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT), so there is no onLayout callback.
		local anyPlaying = false
		local activeRows = {}
		for _,cat in ipairs(STUDIO_STRIP_CATEGORY_ORDER) do
			local entries = rowsByCategory[cat.id]
			if entries ~= nil and #entries > 0 then
				table.sort(entries, function(x, y) return x.order < y.order end)
				for _,entry in ipairs(entries) do
					sigParts[#sigParts+1] = cat.id .. ":" .. entry.id
				end
				anyPlaying = true
				activeRows[#activeRows+1] = { label = cat.label, entries = entries }
			else
				sigParts[#sigParts+1] = cat.id .. ":-"
				activeRows[#activeRows+1] = { label = cat.label, entries = {} }
			end
		end

		local sig = table.concat(sigParts, "|")
		if sig ~= lastSig then
			local rows = {}
			for _,row in ipairs(activeRows) do
				rows[#rows+1] = CreateCategoryRow(row.label, row.entries)
			end
			rowsColumn.children = rows
			lastSig = sig
		end

		stopAllButton:SetClass("hidden", not anyPlaying)
	end

	local headerRow = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = AUDIO_STUDIO_NOWPLAYING_HEADER_HEIGHT,
		valign = "center",
		vmargin = 2,
		gui.Label{
			classes = {"bold", "sizeS"},
			text = "Now Playing",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
		},
		stopAllButton,
	}

	--Always visible -- the reserved rows give the block a constant footprint, so
	--there is no collapsed state to toggle. {bordered} card (chunk F, L4) matching
	--the Soundboard/Levels/Library cards -- REMOVED the old {bgAlt} full-block fill
	--+ cornerRadius=4, which painted the whole block one flat color and made the
	--"Now Playing" header read as just another row instead of the card's title (the
	--other cards' bold sizeS title already reads correctly against a plain
	--surface, so this title needed the same treatment, not a special fill). Fixed
	--height (AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT) -- see the constant's comment
	--for the derivation (pad=8 unchanged, so the constant's arithmetic still
	--holds) -- so the Library card below it never shifts as tracks start/stop.
	local block
	block = gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT,
		valign = "top",
		vmargin = 4,
		pad = 8,
		borderBox = true,

		create = function(element)
			Refresh(element)
		end,
		refreshPlayingAudio = function(element)
			Refresh(element)
		end,
		thinkTime = 0.5,
		think = function(element)
			Refresh(element)
		end,

		headerRow,
		rowsColumn,
	}

	return block
end

--Left-column height allowances (Option A, task 6b; card chrome accounted for in
--chunk F, L3): the Soundboard card no longer lives in the left column (it moved
--to the RIGHT column, above the Mixer -- see CreateAudioStudio), so the library
--card's complement only has to account for the now-playing block above it. The
--tree keeps its own internal vscroll for overflow within its share.
--Now-playing block: AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT (fixed, see above) plus
--its own 4px top/bottom vmargin (8).
local AUDIO_STUDIO_NOWPLAYING_ALLOWANCE = AUDIO_STUDIO_NOWPLAYING_BLOCK_HEIGHT + 8
--Library header row (label + New Folder/Add audio buttons) above the tree,
--INSIDE the library card now (chunk F, L3): still 32 for the row itself, since
--the card's own pad is accounted for separately (borderBox on the card already
--shrinks its content box by 2*pad, so the header allowance only needs to cover
--the header row's own height/vmargin, unchanged from before the card wrap).
local AUDIO_STUDIO_LIBRARY_HEADER_ALLOWANCE = 32
--Library card's own vmargin (chunk F, L3): the Library header + tree wrapper are
--now wrapped in a {bordered} card matching Soundboard/Levels (pad 8, borderBox,
--vmargin 4). borderBox already keeps the card's pad OUT of its declared
--height (the height IS the outer box), but vmargin is external spacing added on
--TOP of that box -- with the card as leftColumn's last (only remaining) child,
--its own top+bottom vmargin (2*4=8) must be subtracted from the card's declared
--height too, or the card would overflow leftColumn's 100% by that much.
local AUDIO_STUDIO_LIBRARY_CARD_VMARGIN = 8

CreateAudioStudio = function()
	if not dmhub.isDM then
		return nil
	end

	--Left column (Option A, task 6b): the now-playing BLOCK (fixed height, always
	--visible), THEN a Library CARD (header + tree, chunk F L3) matching the
	--Soundboard/Levels card look. The Studio Soundboard card has moved OUT of this
	--column entirely -- it now sits at the top of the right column, next to the
	--Mixer, so curation and playback assignment share the same column as the
	--levels they route into. The tree gets a deterministic height complement (the
	--library card's own content box, minus the header row) so its auto-height
	--content fits below both without overflow; the tree keeps its own internal
	--vscroll for its share.
	local nowPlayingBlock = CreateStudioNowPlayingStrip()

	local libraryTreeWrapper = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "100%-" .. tostring(AUDIO_STUDIO_LIBRARY_HEADER_ALLOWANCE),
		CreateAudioLibraryTree(),
	}

	--Library card (chunk F, L3): {bordered} card matching the Soundboard/Levels
	--cards on the right column. borderBox=true means its OWN pad is already
	--excluded from libraryTreeWrapper's "100%" above -- libraryTreeWrapper only
	--has to subtract the header row's own allowance, not the card's pad. The
	--card's declared height DOES have to subtract its own vmargin
	--(AUDIO_STUDIO_LIBRARY_CARD_VMARGIN) on top of the now-playing allowance,
	--since vmargin is external spacing that is NOT covered by borderBox.
	local libraryCard = gui.Panel{
		classes = {"bordered"},
		flow = "vertical",
		width = "100%",
		height = "100%-" .. tostring(AUDIO_STUDIO_NOWPLAYING_ALLOWANCE + AUDIO_STUDIO_LIBRARY_CARD_VMARGIN),
		pad = 8,
		borderBox = true,
		vmargin = 4,

		--Library header row: label left, the add buttons right-aligned to this column
		--(these become glyph buttons later). The label sits in a fixed-width flex
		--panel since "100% available" collapses to 0 here. The bold sizeS "Library"
		--label is this card's title, matching the other cards' title styling.
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
				--Breathing room: auto-width buttons rendered the border tight
				--against the letters.
				hpad = 8,
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
				hpad = 8,
				valign = "center",
				hmargin = 3,
				press = function(element)
					OpenAudioStudioUpload(element)
				end,
			},
		},

		libraryTreeWrapper,
	}

	--Left column width (chunk F, L1): "100% available" is no longer a percentage
	--share -- rightColumn is now a FIXED 372 (see below), so leftColumn is sized as
	--a precise, deterministic complement instead of a "60%"/"38%" split that could
	--drift out of sync with the right column's real content width. Consumed by the
	--right side: rightColumn's own hmargin (4 left + 4 right = 8) + rightColumn's
	--fixed box width (372) + leftColumn's own hmargin (4 left + 4 right = 8) =
	--388. The Library absorbs all width freed by pinning the soundboard column.
	local leftColumn = gui.Panel{
		flow = "vertical",
		width = "100%-388",
		height = "100%",
		hmargin = 4,

		nowPlayingBlock,

		libraryCard,
	}

	--Right column (task 6c; chunk F, L1 fixes the width): Soundboard FIRST
	--(curation lives with the levels it feeds), then the Mixer/Levels card (which
	--now also hosts the "Ducking settings" popover trigger -- see
	--CreateStudioMixerCard). vscroll stays on as a safety net for small displays.
	--Width FIXED at 372 (was "38%", which could drift the card interior away from
	--the soundboard grid's own fixed 342 width): the soundboard card below is
	--width="100%" of this column with pad=8/borderBox=true, so its content box is
	--372-16=356 -- 14px wider than the 342 grid, split evenly by the grid's own
	--halign="center" (AUDIO_SB_GRID_WIDTH/HEIGHT, see CreateStudioSoundboard) into
	--equal 7px left/right gaps inside the card, matching the user's "right gap ==
	--left gap" ask.
	local rightColumn = gui.Panel{
		flow = "vertical",
		width = 372,
		height = "100%",
		hmargin = 4,
		vscroll = true,
		CreateStudioSoundboard(),
		CreateStudioMixerCard(),
	}

	--Body height is a simple fixed complement now (header + divider only) -- the
	--now-playing block lives IN the left column at a fixed height (Option A), so
	--it no longer spans the window above both columns and there is no more
	--onLayout/numRows churn to react to. ~30px title (sizeXl, auto) + divider
	--(1px + 4 tmargin + 8 bmargin = 13) = ~43; rounded up for breathing room.
	local body = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "100%-44",
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
		--DM cue (headphones): dim until hovered; green while this row is auditioning locally.
		{ selectors = {"audioCueButton"}, bgcolor = "white", opacity = 0.55 },
		{ selectors = {"audioCueButton", "hover"}, opacity = 1 },
		{ selectors = {"audioCueButton", "active"}, bgcolor = "@success", opacity = 1 },
		--Row loop/mute glyphs. Loop dims when off, tints @accent when on; mute dims
		--normally and tints @danger while active. (Separate from the soundboard
		--button's own audioSbLoop/audioSbMute rules above -- this is the library row.)
		{ selectors = {"audioRowLoopButton"}, bgcolor = "white" },
		{ selectors = {"audioRowLoopButton", "disabled"}, opacity = 0.4 },
		{ selectors = {"audioRowLoopButton", "~disabled"}, bgcolor = "@accent" },
		{ selectors = {"audioRowMuteButton"}, opacity = 0.55 },
		{ selectors = {"audioRowMuteButton", "hover"}, opacity = 1 },
		{ selectors = {"audioRowMuteButton", "muted"}, bgcolor = "@danger", opacity = 1 },
		--Unrouted category dropdown (C8): a subtle warning border, not a loud fill --
		--nudges without shouting. Cleared automatically once a category is chosen.
		{ selectors = {"unrouted"}, borderColor = "@warning", border = 1 },
	}
	--Unified soundboard button rules (F1a/F1d), shared with the dock (see
	--soundboardBody's own MergeTokens, chunk F P1). Appended here (not just
	--referenced) so a single MergeStyles call produces the full Studio cascade --
	--the Studio root is a standalone LaunchablePanel outside any host cascade, so
	--MergeStyles (the full base theme + extras) is correct here, unlike the dock.
	for _,rule in ipairs(AudioSoundboardButtonStyles) do
		studioExtraStyles[#studioExtraStyles+1] = rule
	end

	local root
	root = gui.Panel{
		--surfaceLinear: the launchable-panel host draws only engine-default (black)
		--chrome outside the ThemeEngine cascade, and DefaultStyles deliberately keeps
		--{launchablePanel} transparent -- so the Studio paints its own content area
		--with the scheme's standard dialog surface via the {panel, surfaceLinear}
		--utility class (the DSVictoryScreen hero-card pattern). The bgimage property
		--is required for the class's gradient to have something to paint on.
		classes = {"launchablePanel", "surfaceLinear"},
		bgimage = "panels/square.png",
		styles = ThemeEngine.MergeStyles(studioExtraStyles),
		--borderBox makes pad below shrink the content area inward rather than adding on
		--top, so width/height here are bumped by 2*pad (32) over the CONTENT-box
		--values (chunk F3: content widened 1000 -> 1100 to give the reflowed left
		--column room for the library tree + soundboard card; content height target
		--min(760, screenHeight-80) so it never overflows a small display) to keep
		--the CONTENT area at exactly those numbers.
		width = 1132,
		--Tall enough for the reflowed columns without scrolling, but never taller
		--than the screen (small displays cap at screenHeight - 48 so it never overflows).
		height = math.min(792, dmhub.screenDimensions.y - 48),
		flow = "vertical",
		pad = 16,
		borderBox = true,
		data = {},
		create = function(element)
			element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
				if element.valid then
					element.styles = ThemeEngine.MergeStyles(studioExtraStyles)
					--Reassigning .styles updates the rule array but does not mark
					--descendants dirty, so the previous scheme keeps painting until a
					--pseudo-class churns. Toggle a no-op class across the subtree to
					--force the re-cascade (the CodexTitleBar themeRefreshTick pattern).
					element.data.themeTick = not element.data.themeTick
					element:SetClassTree("themeRefreshTick", element.data.themeTick == true)
				end
			end)

			--The launchable-panel host adds its floating close X BEFORE the content
			--panel, and paint order follows child order, so this root's opaque
			--themed surface covers the X. Move the host's close button to the end
			--of its children so it paints above us. At create time we are not yet
			--parented (the host constructs content first), so retry briefly on a
			--schedule. No-ops once the button is already last (e.g. on engine
			--builds where game-hud-menu.txt orders it after the content).
			local attempts = 0
			local function RaiseHostCloseButton()
				if mod.unloaded or (not element.valid) then
					return
				end
				local host = element.parent
				if host ~= nil then
					local kids = host.children
					if kids[#kids] ~= nil and kids[#kids]:HasClass("closeButton") then
						return
					end
					for _,child in ipairs(kids) do
						if child ~= element and child:HasClass("closeButton") then
							host:AddChild(child)
							return
						end
					end
					return
				end
				attempts = attempts + 1
				if attempts < 20 then
					dmhub.Schedule(0.1, RaiseHostCloseButton)
				end
			end
			RaiseHostCloseButton()
		end,
		destroy = function(element)
			if element.data.themeSub ~= nil then
				element.data.themeSub:Deregister()
				element.data.themeSub = nil
			end

			--The DM-local audition cue (Studio row "eye" preview) must not keep playing
			--after the Studio window closes. Mirrors the dock anthem preview's
			--`destroy = StopPreview` pattern above.
			StopStudioCue()
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
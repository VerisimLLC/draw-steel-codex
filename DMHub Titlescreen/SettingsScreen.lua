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

-- Gates the codex MCDM Shop UI behind the dev:storepreview testing flag.
-- Settings are keyed by id, so re-declaring "dev:storepreview" here gives read access
-- to the same persisted preference the title bar uses (CodexTitleBar.lua). When off,
-- the Shopify account section is hidden.
local g_devStorePreviewSetting = setting{
	id = "dev:storepreview",
	default = true,
	storage = "preference",
}

g_devStorePreviewSetting:Set(true)

-- Pure order normalizers for the codex Shopify purchases list. Mirror the companion's
-- src/shop/orders.js so codex and web render identically. ASCII only; never error.

-- SCREAMING_SNAKE -> "Screaming snake".
local function TitleCaseStatus(s)
	if type(s) ~= "string" or s == "" then return "" end
	local out = {}
	for word in string.gmatch(s, "[^_]+") do
		word = string.lower(word)
		out[#out+1] = string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end
	return table.concat(out, " ")
end

-- Collapse Shopify financial+fulfillment status into one short label.
local function DeriveStatusLabel(financialStatus, fulfillmentStatus)
	if fulfillmentStatus == "FULFILLED" then return "Fulfilled" end
	if fulfillmentStatus == "PARTIALLY_FULFILLED" then return "Partly fulfilled" end
	if financialStatus == "REFUNDED" then return "Refunded" end
	if financialStatus == "PARTIALLY_REFUNDED" then return "Partly refunded" end
	if financialStatus == "PAID" then return "Paid" end
	local label = TitleCaseStatus(financialStatus)
	if label == "" then label = TitleCaseStatus(fulfillmentStatus) end
	if label == "" then label = "Order" end
	return label
end

-- { amount, currencyCode } -> "$19.99" (USD) or "19.99 EUR" or "".
local function FormatMoney(total)
	if type(total) ~= "table" or total.amount == nil then return "" end
	local n = tonumber(total.amount)
	if n == nil then return "" end
	local cur = total.currencyCode or "USD"
	if cur == "USD" then
		return string.format("$%.2f", n)
	end
	return string.format("%.2f %s", n, cur)
end

local g_shortMonths = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}

-- ISO timestamp "2026-06-21T..." -> "Jun 21, 2026" (or "" if unparseable).
local function FormatOrderDate(iso)
	if type(iso) ~= "string" then return "" end
	local y, m, d = string.match(iso, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if y == nil then return "" end
	local mi = tonumber(m)
	if mi == nil or mi < 1 or mi > 12 then return "" end
	return string.format("%s %d, %s", g_shortMonths[mi], tonumber(d), y)
end

-- Sanitized backend order list -> render-ready rows. Never errors; guards nils.
local function NormalizeOrders(rawList)
	local out = {}
	if type(rawList) ~= "table" then return out end
	for _, o in ipairs(rawList) do
		if type(o) == "table" then
			local lineItems = {}
			if type(o.lineItems) == "table" then
				for _, li in ipairs(o.lineItems) do
					if type(li) == "table" then
						lineItems[#lineItems+1] = {
							title = (type(li.title) == "string" and li.title ~= "") and li.title or "Item",
							quantity = tonumber(li.quantity) or 1,
						}
					end
				end
			end
			out[#out+1] = {
				name = (type(o.name) == "string" and o.name) or "",
				date = FormatOrderDate(o.createdAt),
				statusLabel = DeriveStatusLabel(o.financialStatus, o.fulfillmentStatus),
				total = FormatMoney(o.total),
				statusPageUrl = (type(o.statusPageUrl) == "string" and o.statusPageUrl ~= "") and o.statusPageUrl or nil,
				lineItems = lineItems,
			}
		end
	end
	return out
end

local CreateBetaBranchEditor = function()
	local branch = dmhub.betaBranch
	if branch == nil then
		return nil
	end

	local changesLabel = 
	gui.Label{
		classes = {"collapseAnim"},
		fontSize = 14,
		width = "auto",
		height = "auto",
		halign = "center",
		vmargin = 6,
		text = "Changes to the DMHub Version will occur when DMHub is restarted.",
	}

	return gui.Panel{
		width = "90%",
		height = "auto",
		halign = "center",
		flow = "vertical",
		gui.Panel{
			classes = {"formRow"},
			width = "100%",
			gui.Label{
				classes = {"form"},
				width = "66%",
				text = "DMHub Version:",
			},
			gui.Dropdown{
				classes = {"form"},
				width = "33%",
				idChosen = branch,
				options = {
					{
						id = "Default",
						text = "Default",
					},
					{
						id = "Head",
						text = "Development Beta",
					},
					{
						id = "Previous",
						text = "Previous Version",
					},
				},
				change = function(element)
					dmhub.betaBranch = element.idChosen
					changesLabel:SetClass("collapseAnim", false)
				end,
			},
		},

		changesLabel,
	}
end

local CreateLanguageEditor
CreateLanguageEditor = function()

	local options = {
		{
			id = "",
			text = "English",
		}
	}

	for _,id in ipairs(i18n.translations) do
		local t = i18n.GetTranslation(id)
		options[#options+1] = {
			id = t.identifier,
			text = t.name,
		}
	end

	table.sort(options, function(a,b) return a.text < b.text end)
	dmhub.Debug(string.format("LANG:: %s", json(options)))

	return gui.Panel{
		width = "90%",
		height = "auto",
		halign = "center",
		flow = "vertical",

		search = function(element, text, results)
			results[#results+1] = {
				id = "lang",
				create = CreateLanguageEditor,
				shown = string.find("language", string.lower(text)),
			}
		end,

		gui.Panel{
			classes = {"formRow"},
			width = "100%",
			gui.Label{
				classes = {"form"},
				width = "66%",
				text = "Language:",
			},
			gui.Dropdown{
				classes = {"form"},
				width = "33%",
				idChosen = dmhub.GetSettingValue("lang"),
				options = options,
				change = function(element)
					dmhub.SetSettingValue("lang", element.idChosen)
				end,
			},
		},
	}
end

--True when this client may operate game-wide audio controls: the Director, or a
--player granted DJ (audio-DJ-delegation, full-parity decision 3). Routed through
--the audio module's narrow export since this screen cannot see its module locals;
--falls back to plain isDM if the export is not loaded.
local function CanControlAudioForSettings()
	local bar = rawget(_G, "g_drawSteelAudioBar")
	if bar ~= nil and bar.CanControlAudio ~= nil then
		return bar.CanControlAudio()
	end
	return dmhub.isDM
end

--A slider that controls the game-wide master volume -- the same value as the
--master slider in the Audio panel (audio.masterVolume / gameDetails.audio).
--Only shown to the Director or a DJ, and only while in a game, since the value
--lives on the game's shared audio state rather than a per-machine preference.
local CreateGameWideMasterVolumeEditor = function()
	if (not dmhub.inGame) or (not CanControlAudioForSettings()) then
		return nil
	end

	local slider = gui.Slider{
		width = "33%",
		height = 30,
		halign = "right",
		sliderWidth = 110,
		labelWidth = 40,
		labelFormat = "%d%%",
		minValue = 0,
		maxValue = 100,
		round = true,
		value = math.floor(audio.masterVolume*100 + 0.5),
		confirm = function(element)
			audio.masterVolume = element.value*0.01
			if audio.masterVolume > 0 and audio.muted then
				audio.muted = false
				audio.UploadMuted()
			end
			audio.UploadMasterVolume()
		end,
		preview = function(element)
			audio.masterVolume = element.value*0.01
		end,
	}

	return gui.Panel{
		classes = {"formRow"},
		width = "90%",
		height = 48,
		halign = "center",
		flow = "horizontal",
		gui.Label{
			classes = {"form"},
			width = "66%",
			text = "Game-Wide Master Volume",
		},
		slider,
	}
end

--A checkbox that controls whether library/anthem track loudness is automatically
--normalized for this game (audio.normalizeLoudness / gameDetails.audio). Only shown
--to the Director or a DJ, and only while in a game, since the value lives on the
--game's shared audio state rather than a per-machine preference. Mirrors
--CreateGameWideMasterVolumeEditor's guard.
local CreateNormalizeLoudnessToggle = function()
	if (not dmhub.inGame) or (not CanControlAudioForSettings()) then
		return nil
	end

	return gui.Panel{
		classes = {"formRow"},
		width = "90%",
		halign = "center",
		gui.Check{
			value = audio.normalizeLoudness,
			text = "Normalize track loudness",
			tooltip = "Automatically balances volume across tracks so quiet and loud clips play at a similar level. Does not affect sound effects.",
			change = function(element)
				audio.normalizeLoudness = element.value
				audio.UploadNormalizeLoudness()
			end,
		},
	}
end

--called from DMHub (from DialogLua, reference to script is a Unity property.)
-- Builds the image-editor chooser UI (heading + blurb + dropdown). Shared by the Settings "Editing"
-- tab and the first-run / re-prompt setup dialog. The dropdown writes the imageeditor /
-- imageeditor:usedefault preferences and marks imageeditor:configured so the live-edit setup prompt
-- stops appearing once the user has made a choice.
local function CreateImageEditorChooser()
	local detectedEditors = dmhub.DetectImageEditors()
	local dropdown

	local function BaseName(path)
		local result = path
		for i = #path, 1, -1 do
			local c = string.sub(path, i, i)
			if c == "/" or c == "\\" then
				result = string.sub(path, i + 1)
				break
			end
		end
		return result
	end

	local function BuildOptions()
		local options = {}
		options[#options + 1] = { id = "", text = "System Default" }

		local useDefault = dmhub.GetSettingValue("imageeditor:usedefault")
		local currentPath = dmhub.GetSettingValue("imageeditor")
		local foundCurrent = false

		for _,editor in ipairs(detectedEditors) do
			options[#options + 1] = { id = editor.path, text = editor.name }
			if (not useDefault) and editor.path == currentPath then
				foundCurrent = true
			end
		end

		if (not useDefault) and currentPath ~= nil and currentPath ~= "" and (not foundCurrent) then
			options[#options + 1] = { id = currentPath, text = BaseName(currentPath) }
		end

		options[#options + 1] = { id = "__browse__", text = "Choose File..." }
		return options
	end

	local function CurrentChoice()
		if dmhub.GetSettingValue("imageeditor:usedefault") then
			return ""
		end
		local path = dmhub.GetSettingValue("imageeditor")
		if path == nil or path == "" then
			return ""
		end
		return path
	end

	local function BrowseForEditor()
		local extensions = {}
		if dmhub.platform == "windows" then
			extensions = {"exe"}
		elseif dmhub.platform == "macOS" then
			extensions = {"app"}
		end
		dmhub.OpenFileDialog{
			id = "imageeditor",
			extensions = extensions,
			directory = dmhub.applicationsFolder,
			prompt = "Select Image Editor",
			open = function(path)
				dmhub.SetSettingValue("imageeditor", path)
				dmhub.SetSettingValue("imageeditor:usedefault", false)
				dmhub.SetSettingValue("imageeditor:configured", true)
				if dropdown ~= nil then
					dropdown.options = BuildOptions()
					dropdown.idChosen = path
				end
			end,
		}
	end

	dropdown = gui.Dropdown{
		options = BuildOptions(),
		idChosen = CurrentChoice(),
		width = 300,
		height = 40,
		halign = "right",
		valign = "center",
		fontSize = 16,

		multimonitor = {"imageeditor", "imageeditor:usedefault"},
		events = {
			monitor = function(element)
				element.options = BuildOptions()
				element.idChosen = CurrentChoice()
			end,

			change = function(element)
				local id = element.idChosen
				if id == "__browse__" then
					element.idChosen = CurrentChoice()
					BrowseForEditor()
				elseif id == "" then
					dmhub.SetSettingValue("imageeditor:usedefault", true)
					dmhub.SetSettingValue("imageeditor:configured", true)
				else
					dmhub.SetSettingValue("imageeditor", id)
					dmhub.SetSettingValue("imageeditor:usedefault", false)
					dmhub.SetSettingValue("imageeditor:configured", true)
				end
			end,
		}
	}

	return {
		gui.Label{
			width = "100%",
			height = 40,
			fontSize = 26,
			bold = true,
			text = "Image Editing",
		},

		gui.Label{
			width = "90%",
			height = "auto",
			halign = "center",
			fontSize = 14,
			vmargin = 4,
			text = string.format("Choose the program that opens when you use Live Edit Image on a map object. When you save the file in that program, the object's image updates live in %s.", dmhub.whiteLabelAppName),
		},

		gui.Panel{
			classes = {"formRow"},
			width = "90%",
			halign = "center",
			gui.Label{
				classes = {"form"},
				width = "40%",
				text = "Image Editor:",
			},
			dropdown,
		},
	}
end

--Local assets: a per-game developer feature where the game's cloud assets are
--replaced by one or more local directory trees of YAML files (see
--LocalAssetDirectory in the engine and the /localassets macro). Multiple
--directories form an ordered overlay: the FIRST is the "top" directory --
--highest precedence, and the home for newly created entries. Returns a list
--of panels for the Editing settings tab, or an empty list when the feature
--does not apply (not in dev mode, or not in a real game).
local function CreateLocalAssetsSection()
	if dmhub.isLobbyGame or (not dmhub.GetSettingValue("dev")) then
		return {}
	end

	--The directory list is stored newline-delimited in localassets:dirs, top
	--directory first; the legacy single-path localassets:dir is honored as a
	--fallback so games configured before the multi-directory feature keep
	--working until the list is first edited here.
	local function GetDirs()
		local result = {}
		local str = dmhub.GetSettingValue("localassets:dirs")
		if str ~= nil and str ~= "" then
			for line in string.gmatch(str, "[^\n]+") do
				line = line:match("^%s*(.-)%s*$")
				if line ~= "" then
					result[#result+1] = line
				end
			end
		end
		if #result == 0 then
			local legacy = dmhub.GetSettingValue("localassets:dir")
			if legacy ~= nil and legacy ~= "" then
				result[1] = legacy
			end
		end
		return result
	end

	local function SetDirs(dirs)
		dmhub.SetSettingValue("localassets:dirs", table.concat(dirs, "\n"))
		if #dirs == 0 then
			--clear the legacy single-dir setting too, or GetDirs would fall
			--back to it and the feature would not actually turn off.
			dmhub.SetSettingValue("localassets:dir", "")
		end
		--a pure reordering may apply live; other changes require a game
		--reload. The status label reflects which via LocalAssetsStatus.
		if dmhub.LocalAssetsApplyDirs ~= nil then
			dmhub.LocalAssetsApplyDirs()
		end
	end

	local function TopDir()
		local dirs = GetDirs()
		if dirs[1] == nil then
			return ""
		end
		return dirs[1]
	end

	local function StatusText()
		local status = dmhub.LocalAssetsStatus()
		local dirs = GetDirs()
		if status ~= nil and status.active then
			local ndirs = 1
			if status.directories ~= nil and #status.directories > 0 then
				ndirs = #status.directories
			end
			local text
			if ndirs > 1 then
				text = string.format("Active: assets load from %d directories; new entries are created in %s.", ndirs, status.directories[1])
			else
				text = string.format("Active: this game's assets are loading from %s.", status.directory or "?")
			end
			if status.shadowedCount ~= nil and status.shadowedCount > 0 then
				text = text .. string.format(" %d item(s) exist in multiple directories; the higher directory's copy wins.", status.shadowedCount)
			end
			if status.reloadRequired then
				text = text .. " Directory changes are PENDING: reload the game to apply them."
			end
			return text
		elseif #dirs > 0 then
			return "Set, but not active yet: reload the game to activate."
		else
			return "Not set: this game uses cloud assets."
		end
	end

	local statusLabel = gui.Label{
		width = "90%",
		height = "auto",
		halign = "center",
		fontSize = 14,
		vmargin = 2,
		italics = true,
		text = StatusText(),
		multimonitor = {"localassets:dirs", "localassets:dir"},
		events = {
			monitor = function(element)
				element.text = StatusText()
			end,
		},
	}

	local function SmallButton(text, w, disabled, fn)
		return gui.Button{
			width = w,
			height = 24,
			fontSize = 12,
			halign = "left",
			valign = "center",
			hmargin = 2,
			text = text,
			classes = {cond(disabled, "disabled")},
			interactable = not disabled,
			click = fn,
		}
	end

	--One row per configured directory: position, editable path, Browse, and
	--reordering controls. Rows are rebuilt whenever the setting changes, so
	--the captured indexes are always fresh.
	local function MakeDirRow(index, dir, count)
		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = 30,
			vmargin = 2,

			gui.Label{
				classes = {"form"},
				width = 26,
				minWidth = 26,
				halign = "left",
				valign = "center",
				fontSize = 14,
				text = string.format("%d.", index),
			},

			gui.Input{
				classes = {"form"},
				width = 250,
				valign = "center",
				fontSize = 14,
				text = dir,
				change = function(element)
					local dirs = GetDirs()
					local text = element.text:match("^%s*(.-)%s*$")
					if text == "" then
						table.remove(dirs, index)
					else
						dirs[index] = text
					end
					SetDirs(dirs)
				end,
			},

			SmallButton("Browse...", 64, false, function(element)
				dmhub.OpenFolderDialog{
					id = "localassets",
					extensions = {"yaml"},
					prompt = "Select Local Assets Directory",
					open = function(folderPath, filePaths)
						local dirs = GetDirs()
						dirs[index] = folderPath
						SetDirs(dirs)
					end,
				}
			end),

			SmallButton("Top", 40, index == 1, function(element)
				local dirs = GetDirs()
				local d = table.remove(dirs, index)
				table.insert(dirs, 1, d)
				SetDirs(dirs)
			end),

			SmallButton("Up", 36, index == 1, function(element)
				local dirs = GetDirs()
				dirs[index], dirs[index-1] = dirs[index-1], dirs[index]
				SetDirs(dirs)
			end),

			SmallButton("Down", 52, index == count, function(element)
				local dirs = GetDirs()
				dirs[index], dirs[index+1] = dirs[index+1], dirs[index]
				SetDirs(dirs)
			end),

			SmallButton("X", 26, false, function(element)
				local dirs = GetDirs()
				table.remove(dirs, index)
				SetDirs(dirs)
			end),
		}
	end

	local function BuildDirRows()
		local dirs = GetDirs()
		local rows = {}
		for i,dir in ipairs(dirs) do
			rows[#rows+1] = MakeDirRow(i, dir, #dirs)
		end
		if #rows == 0 then
			rows[1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				italics = true,
				text = "No directories configured.",
			}
		end
		return rows
	end

	local dirsListArgs = {
		width = "90%",
		height = "auto",
		flow = "vertical",
		halign = "center",
		multimonitor = {"localassets:dirs", "localassets:dir"},
		events = {
			monitor = function(element)
				element.children = BuildDirRows()
			end,
		},
	}
	for _,row in ipairs(BuildDirRows()) do
		dirsListArgs[#dirsListArgs+1] = row
	end
	local dirsListPanel = gui.Panel(dirsListArgs)

	local addButton = gui.Button{
		width = 150,
		height = 32,
		fontSize = 16,
		halign = "left",
		valign = "center",
		text = "Add Directory...",
		click = function(element)
			dmhub.OpenFolderDialog{
				id = "localassets",
				extensions = {"yaml"},
				prompt = "Select Local Assets Directory",
				open = function(folderPath, filePaths)
					local dirs = GetDirs()
					--the new directory goes on TOP: highest precedence and
					--the home for new entries. Use Down to lower it.
					table.insert(dirs, 1, folderPath)
					SetDirs(dirs)
				end,
			}
		end,
	}

	local function DoExport()
		local dir = TopDir()
		local result = dmhub.ExportAllAssets{directory = dir}
		if result == nil then
			gui.ModalMessage{
				title = "Local Assets",
				message = string.format("Could not export to %s.", dir),
			}
		else
			gui.ModalMessage{
				title = "Local Assets",
				message = string.format("Exported %d items in %d categories to %s.", result.itemsExported, result.categoriesExported, result.directory),
			}
		end
	end

	--When local-assets mode is already active for this game AND the current
	--directory has files, populating again just re-exports the in-memory
	--assets (which were themselves loaded from that same directory) back over
	--the files -- redundant, and it reformats/overwrites them. Grey the button
	--out in that case: the "disabled" class drives the dimmed look (the theme
	--gates hover feedback with ~disabled), while `interactable = false` blocks
	--the click -- `interactable` alone has no visual effect. It stays enabled
	--while the directory is only "set but not active" (pre-reload) so you can
	--still fill it immediately, and while a newly-chosen directory is empty.
	local function PopulateDisabled()
		local status = dmhub.LocalAssetsStatus()
		if status == nil or not status.active then
			return false
		end
		local dir = TopDir()
		if dir == "" or dmhub.GetDirectoryInfo == nil then
			return false
		end
		local info = dmhub.GetDirectoryInfo(dir)
		return info ~= nil and info.exists and info.fileCount > 0
	end

	local populateDisabled = PopulateDisabled()
	local populateButton = gui.Button{
		width = 210,
		height = 32,
		fontSize = 16,
		halign = "left",
		valign = "center",
		text = "Populate Top Directory",
		classes = {cond(populateDisabled, "disabled")},
		interactable = not populateDisabled,
		multimonitor = {"localassets:dirs", "localassets:dir"},
		events = {
			monitor = function(element)
				local disabled = PopulateDisabled()
				element:SetClass("disabled", disabled)
				element.interactable = not disabled
			end,
		},
		click = function(element)
			local dir = TopDir()
			if dir == "" then
				gui.ModalMessage{
					title = "Local Assets",
					message = "Add a directory first.",
				}
				return
			end

			--GetDirectoryInfo may not exist on older engine builds; without it
			--we populate without the non-empty warning.
			local info = nil
			if dmhub.GetDirectoryInfo ~= nil then
				info = dmhub.GetDirectoryInfo(dir)
			end
			if info ~= nil and info.exists and info.fileCount > 0 then
				gui.ModalMessage{
					title = "Directory Is Not Empty",
					message = string.format("%s already contains %d file(s). Populating will overwrite files for assets with matching names; other files are left alone. Continue?", dir, info.fileCount),
					options = {
						{ text = "Cancel" },
						{ text = "Populate Anyway", execute = DoExport },
					},
				}
			else
				DoExport()
			end
		end,
	}

	--------------------------------------------------------------------
	--File browser (multi-dir Phase 2): a collapsible, lazily-built tree per
	--configured directory driven by the engine's live index via
	--dmhub.LocalAssetsFileTree, plus a search box over ids, display names
	--and filenames via dmhub.LocalAssetsSearch. Children are built only when
	--a node expands, and a directory node re-fetches its tree on every
	--expand, so the view stays fresh without polling. Clicking a row reveals
	--the file in the OS file browser. Only shown when local assets mode is
	--actually active (the index lives in the running LocalAssetDirectory)
	--and the engine has the browser bridges.
	--------------------------------------------------------------------

	local function CreateFileBrowser()
		if dmhub.LocalAssetsFileTree == nil then
			return nil --engine build predates the browser bridges.
		end

		local status = dmhub.LocalAssetsStatus()
		if status == nil or (not status.active) or status.directories == nil then
			return nil
		end

		local browserStyles = {
			gui.Style{
				selectors = {"latree-row"},
				bgcolor = "clear",
			},
			gui.Style{
				selectors = {"latree-row", "hover"},
				bgcolor = "#ffffff22",
			},
			--directory headers light up as drop targets while a file row is
			--being dragged (engine-applied drag state classes).
			gui.Style{
				selectors = {"latree-row", "drag-target"},
				bgcolor = "#33663377",
			},
			gui.Style{
				selectors = {"latree-row", "drag-target-hover"},
				bgcolor = "#55aa5599",
			},
		}

		--attached DIRECTLY to each triangle panel, with a selector-less base
		--rule, matching every working triangle in the codebase (gui.TreeNode,
		--ModShare, ClassEditor). Cascading these rules down from an ancestor
		--styles list left the rotate unapplied -- the triangles rendered but
		--always pointed down.
		local triangleStyles = {
			gui.Style{
				width = 10,
				height = 10,
				hmargin = 4,
				valign = "center",
				rotate = 90,
			},
			gui.Style{
				selectors = {"expanded"},
				rotate = 0,
				transitionTime = 0.2,
			},
		}

		------------------------------------------------------------------
		--Git awareness (Phase 3): read-only status badges from the engine's
		--GitStatusService via dmhub.LocalAssetsGitRefresh/GitStatus. The
		--last completed status per directory is cached in m_gitStatus and
		--broadcast down the browser with FireEventTree("gitstatus", dirIndex,
		--st); rows/labels also pull the cache from their create event so
		--nodes built after a refresh start out correct. All keyed by the
		--normPath the bridges attach to every item -- normalization happens
		--in ONE place, the engine's LocalAssetDirectory.NormalizePath.
		------------------------------------------------------------------

		local browserRoot = nil
		local m_gitStatus = {} --dirIndex -> last completed status snapshot
		local m_byNorm = {}    --dirIndex -> normPath -> tree item entry
		local m_polling = {}

		--"Show Only Git Changes": when on (the default), tree items filter
		--to files git reports as changed. Directories without git info (not
		--a repo, git missing, status not loaded yet) always show all files.
		local m_showOnlyChanges = true
		local m_builtSig = {} --dirIndex -> filter signature the tree was last built with

		local gitStateInfo = {
			untracked = { letter = "?", color = "#77cc77" },
			added = { letter = "A", color = "#77cc77" },
			modified = { letter = "M", color = "#ddbb55" },
			deleted = { letter = "D", color = "#cc6666" },
			renamed = { letter = "R", color = "#77aacc" },
		}

		local function RefreshGitFor(dirIndex)
			if dmhub.LocalAssetsGitRefresh == nil then
				return --engine build predates the git integration.
			end

			dmhub.LocalAssetsGitRefresh(dirIndex)
			if m_polling[dirIndex] then
				return
			end
			m_polling[dirIndex] = true

			local attempts = 0
			local function Poll()
				if browserRoot == nil or (not browserRoot.valid) then
					m_polling[dirIndex] = nil
					return
				end
				local st = dmhub.LocalAssetsGitStatus(dirIndex)
				attempts = attempts + 1
				if st ~= nil and st.refreshing and attempts < 120 then
					dmhub.Schedule(0.25, Poll)
					return
				end
				m_polling[dirIndex] = nil
				if st ~= nil then
					m_gitStatus[dirIndex] = st
					browserRoot:FireEventTree("gitstatus", dirIndex, st)
				end
			end
			dmhub.Schedule(0.25, Poll)
		end

		--true when the changes-only filter actually applies to a directory:
		--the checkbox is on AND git produced a usable status for it.
		local function GitFilterActive(dirIndex)
			if not m_showOnlyChanges then
				return false
			end
			if dmhub.LocalAssetsGitStatus == nil then
				return false
			end
			local st = m_gitStatus[dirIndex]
			if st == nil or (not st.hasResult) or st.error ~= nil or (not st.isRepo) then
				return false
			end
			return true
		end

		local function FilterItems(items, dirIndex)
			if not GitFilterActive(dirIndex) then
				return items
			end
			local states = m_gitStatus[dirIndex].states or {}
			local result = {}
			for _,entry in ipairs(items) do
				if entry.normPath ~= nil and states[entry.normPath] ~= nil then
					result[#result+1] = entry
				end
			end
			return result
		end

		--identity of the changed-file set a tree build was based on; used to
		--skip pointless (and sub-node-collapsing) rebuilds when a refresh
		--reports the same changes again.
		local function FilterSignature(st)
			if st == nil or (not st.hasResult) or st.error ~= nil or (not st.isRepo) then
				return "nogit"
			end
			local parts = {}
			for _,c in ipairs(st.changes) do
				parts[#parts+1] = c.normPath .. "=" .. c.state
			end
			return table.concat(parts, ";")
		end

		------------------------------------------------------------------
		--Git operations (Phase 4): move a file to another directory (drag
		--onto a directory header, or the right-click Move to... menu) and
		--per-file reverts. Both confirm destructive steps with a modal.
		------------------------------------------------------------------

		--after a mutating operation: refresh git promptly, then again once
		--the watcher/sweep and debounces have settled, with a tree rebuild
		--so rows appear/vanish even when the changes-only filter is off.
		local function AfterGitOp(dirIndexes)
			for _,i in ipairs(dirIndexes) do
				RefreshGitFor(i)
			end
			dmhub.Schedule(3, function()
				if browserRoot ~= nil and browserRoot.valid then
					for _,i in ipairs(dirIndexes) do
						RefreshGitFor(i)
					end
					browserRoot:FireEventTree("latreeRebuild")
				end
			end)
		end

		local DoMove
		DoMove = function(entry, fromDirIndex, toDirIndex, overwrite)
			local result = dmhub.LocalAssetsMoveFile(entry.path, toDirIndex, overwrite == true)
			if result == nil then
				return
			end

			if result.collision and (not (overwrite == true)) then
				gui.ModalMessage{
					title = "Overwrite File?",
					message = string.format("Directory %d already has a file for this item:\n%s\n\nMoving will overwrite that copy with the file being moved. Continue?", toDirIndex, result.collisionPath or "?"),
					options = {
						{ text = "Cancel" },
						{ text = "Overwrite", execute = function()
							DoMove(entry, fromDirIndex, toDirIndex, true)
						end },
					},
				}
				return
			end

			if not result.success then
				gui.ModalMessage{
					title = "Move Failed",
					message = result.error or "Unknown error.",
				}
				return
			end

			--the index updated synchronously, so rebuild right away; the
			--delayed AfterGitOp pass catches the staged git states.
			if browserRoot ~= nil and browserRoot.valid then
				browserRoot:FireEventTree("latreeRebuild")
			end
			AfterGitOp({fromDirIndex, toDirIndex})
		end

		local revertLabels = {
			modified = { menu = "Revert Changes", confirm = "Discard the local changes to %s and restore the last committed version?" },
			deleted = { menu = "Restore Deleted File", confirm = "Restore %s from the last committed version?" },
			renamed = { menu = "Revert Rename", confirm = "Attempt to revert the rename of %s? Renames may need manual git use if this fails." },
			added = { menu = "Revert Added File", confirm = "Un-stage %s and DELETE it from disk?" },
			untracked = { menu = "Delete Untracked File", confirm = "DELETE %s from disk? It is not tracked by git, so this cannot be undone." },
		}

		local function DoRevert(entry, dirIndex, state)
			local info = revertLabels[state]
			if info == nil then
				return
			end
			gui.ModalMessage{
				title = "Confirm Git Revert",
				message = string.format(info.confirm, entry.fileName),
				options = {
					{ text = "Cancel" },
					{ text = info.menu, execute = function()
						local err = dmhub.LocalAssetsRevertFile(dirIndex, entry.path, state)
						if err ~= nil then
							gui.ModalMessage{
								title = "Revert Failed",
								message = err,
							}
							return
						end
						AfterGitOp({dirIndex})
					end },
				},
			}
		end

		--one clickable row for an item file. entry comes from
		--LocalAssetsFileTree or LocalAssetsSearch (or is synthesized by the
		--Changes view; entry.revealPath overrides the click target there);
		--detail is optional extra dim text appended after the filename
		--(search attribution). dirIndex drives the git badge.
		local function FileRow(entry, detail, dirIndex)
			local nameText = entry.displayName or entry.id or entry.fileName
			local fileText = entry.fileName
			if entry.shadowed then
				fileText = fileText .. " (shadowed)"
			end
			if detail ~= nil then
				fileText = fileText .. "  " .. detail
			end

			local badge = gui.Label{
				width = 12,
				height = "auto",
				fontSize = 12,
				bold = true,
				valign = "center",
				text = "",
				create = function(element)
					element:FireEvent("gitstatus", dirIndex, m_gitStatus[dirIndex])
				end,
				gitstatus = function(element, evDirIndex, st)
					if evDirIndex ~= dirIndex then
						return
					end
					local state = nil
					if st ~= nil and st.states ~= nil and entry.normPath ~= nil then
						state = st.states[entry.normPath]
					end
					local info = gitStateInfo[state]
					if info == nil then
						element.text = ""
					else
						element.text = info.letter
						element.selfStyle.color = info.color
					end
				end,
			}

			local canMove = dmhub.LocalAssetsMoveFile ~= nil and dirIndex ~= nil

			return gui.Panel{
				classes = {"latree-row"},
				flow = "horizontal",
				width = "100%",
				height = "auto",
				bgimage = "panels/square.png",
				click = function(element)
					dmhub.RevealInFileBrowser(entry.revealPath or entry.path)
				end,

				--drag a row onto another directory's header to move it.
				draggable = canMove,
				canDragOnto = function(element, target)
					return target:HasClass("latree-dirtarget") and target.data ~= nil and target.data.dirIndex ~= dirIndex
				end,
				drag = function(element, target)
					if target ~= nil and target.data ~= nil and target.data.dirIndex ~= nil then
						DoMove(entry, dirIndex, target.data.dirIndex)
					end
				end,

				rightClick = function(element)
					local entries = {}
					entries[#entries+1] = {
						text = "Reveal in File Browser",
						click = function()
							element.popup = nil
							dmhub.RevealInFileBrowser(entry.revealPath or entry.path)
						end,
					}

					local state = nil
					local st = m_gitStatus[dirIndex]
					if st ~= nil and st.states ~= nil and entry.normPath ~= nil then
						state = st.states[entry.normPath]
					end

					--a deleted file has nothing on disk to move.
					if canMove and state ~= "deleted" then
						local liveStatus = dmhub.LocalAssetsStatus()
						local dirs = (liveStatus ~= nil and liveStatus.directories) or {}
						if #dirs > 1 then
							for k,dirPath in ipairs(dirs) do
								if k ~= dirIndex then
									entries[#entries+1] = {
										text = string.format("Move to %d. %s", k, dirPath),
										click = function()
											element.popup = nil
											DoMove(entry, dirIndex, k)
										end,
									}
								end
							end
						end
					end

					if dmhub.LocalAssetsRevertFile ~= nil and state ~= nil and revertLabels[state] ~= nil then
						entries[#entries+1] = {
							text = revertLabels[state].menu .. "...",
							click = function()
								element.popup = nil
								DoRevert(entry, dirIndex, state)
							end,
						}
					end

					element.popup = gui.ContextMenu{
						entries = entries,
					}
				end,

				badge,
				gui.Label{
					width = "42%",
					height = "auto",
					fontSize = 13,
					valign = "center",
					italics = entry.shadowed,
					opacity = cond(entry.shadowed, 0.6, 1),
					text = nameText,
				},
				gui.Label{
					width = "52%",
					height = "auto",
					fontSize = 12,
					valign = "center",
					opacity = 0.6,
					italics = entry.shadowed,
					text = fileText,
				},
			}
		end

		--a collapsible node: a header row with a triangle. buildChildren()
		--runs fresh on every expand; collapse clears the children so large
		--trees never linger in the hierarchy. extraHeader (optional) is an
		--extra panel appended to the header row (git summary / live counts).
		--rebuildEvents (optional) maps event name -> predicate(...); when
		--the event fires on the node and the predicate passes, an EXPANDED
		--node rebuilds its children in place (used by the changes-only
		--filter; collapsed nodes rebuild naturally on their next expand).
		--dropTargetDirIndex (optional) makes the header a drag target for
		--file rows (moving files into that directory).
		local function TreeNode(labelText, countText, buildChildren, extraHeader, rebuildEvents, dropTargetDirIndex)
			local expanded = false
			local triangle = gui.Panel{
				bgimage = "panels/triangle.png",
				--inline, not in triangleStyles: something in the settings
				--sheet's style cascade was overriding the style-rule bgcolor
				--to black; inline properties win.
				bgcolor = "white",
				styles = triangleStyles,
			}
			local childrenPanel = gui.Panel{
				flow = "vertical",
				width = "100%",
				height = "auto",
				lmargin = 16,
			}
			local headerClasses = {"latree-row"}
			if dropTargetDirIndex ~= nil then
				headerClasses[#headerClasses+1] = "latree-dirtarget"
			end

			local header = gui.Panel{
				classes = headerClasses,
				dragTarget = dropTargetDirIndex ~= nil,
				data = { dirIndex = dropTargetDirIndex },
				flow = "horizontal",
				width = "100%",
				height = 22,
				bgimage = "panels/square.png",
				click = function(element)
					expanded = not expanded
					triangle:SetClass("expanded", expanded)
					if expanded then
						childrenPanel.children = buildChildren()
					else
						childrenPanel.children = {}
					end
				end,
				triangle,
				gui.Label{
					width = "auto",
					height = "auto",
					fontSize = 14,
					valign = "center",
					text = labelText,
				},
				gui.Label{
					width = "auto",
					height = "auto",
					fontSize = 12,
					valign = "center",
					hmargin = 6,
					opacity = 0.6,
					text = countText or "",
				},
				extraHeader,
			}

			local nodeArgs = {
				flow = "vertical",
				width = "100%",
				height = "auto",
				header,
				childrenPanel,
			}
			if rebuildEvents ~= nil then
				--the rebuild is deferred a tick: these events arrive via
				--FireEventTree, and swapping the children out mid-traversal
				--would let the same event reach just-destroyed row panels.
				local rebuildPending = false
				for eventName,predicate in pairs(rebuildEvents) do
					nodeArgs[eventName] = function(element, ...)
						if expanded and (not rebuildPending) and predicate(...) then
							rebuildPending = true
							dmhub.Schedule(0.05, function()
								rebuildPending = false
								if element.valid and expanded then
									childrenPanel.children = buildChildren()
								end
							end)
						end
					end
				end
			end
			return gui.Panel(nodeArgs)
		end

		local function NoteLabel(text)
			return gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 12,
				italics = true,
				opacity = 0.6,
				text = text,
			}
		end

		--item rows are capped per node; anything bigger is what search is for.
		local MaxRowsPerNode = 500

		local function BuildItemRows(items, dirIndex)
			local rows = {}
			for i,entry in ipairs(items) do
				if i > MaxRowsPerNode then
					rows[#rows+1] = NoteLabel(string.format("... and %d more; use search to narrow down.", #items - MaxRowsPerNode))
					break
				end
				rows[#rows+1] = FileRow(entry, nil, dirIndex)
			end
			return rows
		end

		--category data is captured when the directory node fetches its tree;
		--expanding the directory again re-fetches everything beneath it.
		--With the changes-only filter active the item lists are filtered up
		--front (so header counts match), containers with no changed items
		--are dropped, and a fully-unchanged category returns nil.
		local function CategoryNode(cat, dirIndex)
			local filtering = GitFilterActive(dirIndex)
			local flatItems = FilterItems(cat.items, dirIndex)
			local containers = {}
			local total = #flatItems
			for _,c in ipairs(cat.containers) do
				local citems = FilterItems(c.items, dirIndex)
				if (#citems > 0) or (not filtering) then
					containers[#containers+1] = { data = c, items = citems }
					total = total + #citems
				end
			end

			if filtering and total == 0 then
				return nil
			end

			return TreeNode(cat.name, string.format("(%d)", total), function()
				local children = {}
				for _,c in ipairs(containers) do
					children[#children+1] = TreeNode(c.data.displayName or c.data.id, string.format("(%d)", #c.items), function()
						return BuildItemRows(c.items, dirIndex)
					end)
				end
				for _,row in ipairs(BuildItemRows(flatItems, dirIndex)) do
					children[#children+1] = row
				end
				return children
			end)
		end

		--compact per-directory git summary shown on the directory header,
		--e.g. "git: 3M 1D 4?"; empty until a refresh has completed.
		local function GitSummaryText(st)
			if st == nil or (not st.hasResult) then
				return ""
			end
			if st.error ~= nil then
				return "git: error"
			end
			if not st.isRepo then
				return "no git"
			end
			local c = st.counts
			if c == nil or c.total == 0 then
				return "git: clean"
			end
			local parts = {}
			if c.modified > 0 then parts[#parts+1] = c.modified .. "M" end
			if c.added > 0 then parts[#parts+1] = c.added .. "A" end
			if c.renamed > 0 then parts[#parts+1] = c.renamed .. "R" end
			if c.deleted > 0 then parts[#parts+1] = c.deleted .. "D" end
			if c.untracked > 0 then parts[#parts+1] = c.untracked .. "?" end
			return "git: " .. table.concat(parts, " ")
		end

		local function GitSummaryLabel(dirIndex)
			return gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 12,
				valign = "center",
				hmargin = 6,
				opacity = 0.75,
				text = "",
				create = function(element)
					element:FireEvent("gitstatus", dirIndex, m_gitStatus[dirIndex])
				end,
				gitstatus = function(element, evDirIndex, st)
					if evDirIndex == dirIndex then
						element.text = GitSummaryText(st)
					end
				end,
			}
		end

		--the per-directory Changes view: every file git reports as changed,
		--INCLUDING deleted files, which have no live tree row (a deleted
		--row's click reveals the containing folder instead). Built from the
		--cached status at expand time; the header count stays live.
		local function ChangesNode(dirIndex)
			local countLabel = gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 12,
				valign = "center",
				hmargin = 6,
				opacity = 0.6,
				text = "",
				create = function(element)
					element:FireEvent("gitstatus", dirIndex, m_gitStatus[dirIndex])
				end,
				gitstatus = function(element, evDirIndex, st)
					if evDirIndex ~= dirIndex then
						return
					end
					if st == nil or st.counts == nil then
						element.text = ""
					else
						element.text = string.format("(%d)", st.counts.total)
					end
				end,
			}

			return TreeNode("Changes", nil, function()
				local st = m_gitStatus[dirIndex]
				if st == nil or (not st.hasResult) then
					return { NoteLabel("Git status not loaded yet; try again in a moment.") }
				end
				if st.error ~= nil then
					return { NoteLabel("Git error: " .. st.error) }
				end
				if not st.isRepo then
					return { NoteLabel("Not inside a git repository.") }
				end

				local rows = {}
				local byNorm = m_byNorm[dirIndex] or {}
				for i,c in ipairs(st.changes) do
					if i > MaxRowsPerNode then
						rows[#rows+1] = NoteLabel(string.format("... and %d more.", #st.changes - MaxRowsPerNode))
						break
					end
					local treeEntry = byNorm[c.normPath]
					local entry = {
						path = c.path,
						normPath = c.normPath,
						fileName = c.fileName,
					}
					if treeEntry ~= nil then
						entry.displayName = treeEntry.displayName
					end
					if c.state == "deleted" then
						entry.revealPath = c.path:match("^(.*)/[^/]*$")
					end
					rows[#rows+1] = FileRow(entry, nil, dirIndex)
				end
				if #rows == 0 then
					rows[1] = NoteLabel("No changes -- working tree clean.")
				end
				return rows
			end, countLabel)
		end

		local function DirectoryNode(dirIndex, dirPath)
			return TreeNode(string.format("%d. %s", dirIndex, dirPath), nil, function()
				RefreshGitFor(dirIndex)
				m_builtSig[dirIndex] = FilterSignature(m_gitStatus[dirIndex])

				local tree = dmhub.LocalAssetsFileTree(dirIndex)
				if tree == nil then
					return { NoteLabel("Could not read the directory index.") }
				end

				--index the tree by normPath so the Changes view can show
				--display names for files that still exist. (normPath is
				--absent on engine builds that predate the git integration.)
				local byNorm = {}
				for _,cat in ipairs(tree.categories) do
					for _,item in ipairs(cat.items) do
						if item.normPath ~= nil then
							byNorm[item.normPath] = item
						end
					end
					for _,c in ipairs(cat.containers) do
						for _,item in ipairs(c.items) do
							if item.normPath ~= nil then
								byNorm[item.normPath] = item
							end
						end
					end
				end
				m_byNorm[dirIndex] = byNorm

				local children = {}
				if dmhub.LocalAssetsGitStatus ~= nil then
					children[#children+1] = ChangesNode(dirIndex)
				end
				local nCategories = 0
				for _,cat in ipairs(tree.categories) do
					local node = CategoryNode(cat, dirIndex)
					if node ~= nil then
						children[#children+1] = node
						nCategories = nCategories + 1
					end
				end
				if #children == 0 then
					children[1] = NoteLabel("No indexed files in this directory.")
				elseif nCategories == 0 and GitFilterActive(dirIndex) then
					children[#children+1] = NoteLabel("No git changes; uncheck Show Only Git Changes to see all files.")
				end
				return children
			end, GitSummaryLabel(dirIndex), {
				--re-filter in place when a git refresh changes the set of
				--changed files (only relevant while the filter is on; badge
				--labels update themselves otherwise), and on checkbox toggle.
				gitstatus = function(evDirIndex, st)
					if evDirIndex ~= dirIndex or (not m_showOnlyChanges) then
						return false
					end
					return FilterSignature(st) ~= m_builtSig[dirIndex]
				end,
				latreeRebuild = function()
					return true
				end,
			}, dirIndex)
		end

		local function BuildDirectoryNodes()
			local nodes = {}
			local liveStatus = dmhub.LocalAssetsStatus()
			if liveStatus ~= nil and liveStatus.active and liveStatus.directories ~= nil then
				for i,dir in ipairs(liveStatus.directories) do
					nodes[#nodes+1] = DirectoryNode(i, dir)
				end
			end
			return nodes
		end

		--the trees rebuild when the directory settings change (e.g. a live
		--reorder renumbers the directories).
		local treesArgs = {
			flow = "vertical",
			width = "100%",
			height = "auto",
			multimonitor = {"localassets:dirs", "localassets:dir"},
			events = {
				monitor = function(element)
					element.children = BuildDirectoryNodes()
				end,
			},
		}
		for _,node in ipairs(BuildDirectoryNodes()) do
			treesArgs[#treesArgs+1] = node
		end
		local treesPanel = gui.Panel(treesArgs)

		local searchResultsPanel = gui.Panel{
			classes = {"collapsed"},
			flow = "vertical",
			width = "100%",
			height = "auto",
		}

		local MaxSearchRows = 100

		local searchInput = gui.Input{
			width = 180,
			height = 24,
			fontSize = 14,
			halign = "left",
			vmargin = 4,
			placeholderText = "Search ids, names, filenames...",
			editlag = 0.25,
			edit = function(element)
				local text = element.text
				if text == nil or #text < 2 then
					searchResultsPanel.children = {}
					searchResultsPanel:SetClass("collapsed", true)
					treesPanel:SetClass("collapsed", false)
					return
				end

				local results = dmhub.LocalAssetsSearch(text) or {}
				local rows = {}
				for i,entry in ipairs(results) do
					if i > MaxSearchRows then
						break
					end
					local loc = entry.category
					if entry.tableid ~= nil then
						loc = loc .. "/" .. entry.tableid
					end
					rows[#rows+1] = FileRow(entry, string.format("[%s]  (dir %d)", loc, entry.dirIndex), entry.dirIndex)
				end
				if #rows == 0 then
					rows[1] = NoteLabel("No matches.")
				elseif #results > MaxSearchRows then
					rows[#rows+1] = NoteLabel(string.format("Showing the first %d of %d matches.", MaxSearchRows, #results))
				end
				searchResultsPanel.children = rows
				searchResultsPanel:SetClass("collapsed", false)
				treesPanel:SetClass("collapsed", true)
			end,
		}

		--refreshes git status for every configured directory. Sits next to
		--the search box rather than on the tree headers so a click can never
		--double as an expand toggle.
		local refreshGitButton = nil
		if dmhub.LocalAssetsGitStatus ~= nil then
			refreshGitButton = gui.Button{
				width = 110,
				height = 24,
				fontSize = 13,
				valign = "center",
				hmargin = 8,
				text = "Refresh Git",
				click = function(element)
					local liveStatus = dmhub.LocalAssetsStatus()
					if liveStatus ~= nil and liveStatus.directories ~= nil then
						for i,_ in ipairs(liveStatus.directories) do
							RefreshGitFor(i)
						end
					end
				end,
			}
		end

		--"Show Only Git Changes" (default ON): filters the trees to files
		--git reports as changed; directories without git info always show
		--everything. Toggling rebuilds any expanded directory in place via
		--the latreeRebuild event.
		local changesOnlyCheck = nil
		if dmhub.LocalAssetsGitStatus ~= nil then
			changesOnlyCheck = gui.Check{
				text = "Show Only Git Changes",
				value = m_showOnlyChanges,
				halign = "left",
				valign = "center",
				hmargin = 8,
				change = function(element)
					m_showOnlyChanges = element.value
					if browserRoot ~= nil and browserRoot.valid then
						browserRoot:FireEventTree("latreeRebuild")
					end
				end,
			}
		end

		local toolbarArgs = {
			flow = "horizontal",
			width = "100%",
			height = "auto",
			searchInput,
		}
		if changesOnlyCheck ~= nil then
			toolbarArgs[#toolbarArgs+1] = changesOnlyCheck
		end
		if refreshGitButton ~= nil then
			toolbarArgs[#toolbarArgs+1] = refreshGitButton
		end
		local toolbar = gui.Panel(toolbarArgs)

		--which git executable the integration uses: the resolved path and
		--version, a Locate browse fallback (stores localassets:gitpath, a
		--GLOBAL setting), and Auto to return to auto-detection.
		local function GitPathRow()
			if dmhub.LocalAssetsGitInfo == nil then
				return nil
			end

			local function InfoText()
				local info = dmhub.LocalAssetsGitInfo()
				if info == nil then
					return ""
				end
				if info.path ~= nil then
					local src = ""
					if info.source == "setting" then
						src = " (configured)"
					end
					return string.format("Git: %s -- %s%s", info.path, info.version or "?", src)
				end
				return "Git: not found -- status badges disabled. Use Locate to point at a git executable."
			end

			local infoLabel = gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 13,
				valign = "center",
				opacity = 0.8,
				text = InfoText(),
			}

			local locateButton = gui.Button{
				width = 100,
				height = 24,
				fontSize = 13,
				valign = "center",
				hmargin = 8,
				text = "Locate Git...",
				click = function(element)
					dmhub.OpenFileDialog{
						id = "localassetsgit",
						--Windows filter; on Mac auto-detection covers the
						--standard install locations so Locate is rarely needed.
						extensions = {"exe"},
						prompt = "Locate the git executable",
						open = function(path)
							local version = dmhub.LocalAssetsValidateGit(path)
							if version == nil then
								gui.ModalMessage{
									title = "Not a Git Executable",
									message = string.format("%s did not answer --version like git does.", path),
								}
								return
							end
							dmhub.SetSettingValue("localassets:gitpath", path)
							infoLabel.text = InfoText()
						end,
					}
				end,
			}

			local autoButton = gui.Button{
				width = 60,
				height = 24,
				fontSize = 13,
				valign = "center",
				hmargin = 4,
				text = "Auto",
				click = function(element)
					dmhub.SetSettingValue("localassets:gitpath", "")
					infoLabel.text = InfoText()
				end,
			}

			return gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vmargin = 2,
				infoLabel,
				locateButton,
				autoButton,
			}
		end

		--assembled programmatically: GitPathRow() is nil on engine builds
		--without the git bridges, and a nil hole in the positional children
		--would truncate everything after it.
		local rootArgs = {
			flow = "vertical",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 6,
			styles = browserStyles,

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 16,
				bold = true,
				vmargin = 4,
				text = "Browse Files",
			},
		}
		local gitRow = GitPathRow()
		if gitRow ~= nil then
			rootArgs[#rootArgs+1] = gitRow
		end
		rootArgs[#rootArgs+1] = toolbar
		rootArgs[#rootArgs+1] = searchResultsPanel
		rootArgs[#rootArgs+1] = treesPanel

		browserRoot = gui.Panel(rootArgs)
		return browserRoot
	end

	local resultPanels = {
		gui.Label{
			width = "100%",
			height = 40,
			fontSize = 26,
			bold = true,
			vmargin = 8,
			text = "Local Assets (Developer)",
		},

		gui.Label{
			width = "90%",
			height = "auto",
			halign = "center",
			fontSize = 14,
			vmargin = 4,
			text = "Point this game at one or more local directories of YAML asset files. When set, the game's cloud assets are ignored: assets load from the directories, edits you make in-game are written back to the file each item lives in, and external changes to the files hot-reload into the game. Directory 1 is the TOP directory: when an item exists in several directories the top-most copy wins, and newly created entries are written to it. Use Top/Up/Down to reorder; sending a directory to the top makes it the home for new entries. Takes effect when the game loads (pure reordering usually applies immediately). If the directories are all empty or missing, the top one is populated from the game's assets automatically on next load; use Populate Top Directory to fill it immediately.",
		},

		dirsListPanel,

		gui.Panel{
			flow = "horizontal",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 4,
			addButton,
			gui.Panel{ width = 16, height = 1 },
			populateButton,
		},

		statusLabel,
	}

	local browserPanel = CreateFileBrowser()
	if browserPanel ~= nil then
		resultPanels[#resultPanels+1] = browserPanel
	end

	return resultPanels
end

--Creator Organizations: create an organization (or convert your personal
--creator id into one), manage members and one-use invite codes, join an
--organization with an invite code, transfer ownership, or delete the
--organization. Organizations publish modules under a shared author id; the
--Publish As dropdown in the module share dialog lists the ones you belong to.
local function CreateCreatorOrganizationsSection()

	--engine support gate: on engine builds without the organizations API the
	--section is hidden entirely. (Calling a missing member on the C# module
	--interface raises, so probe with pcall.)
	local hasOrgSupport = pcall(function()
		module.GetOurOrganizations()
	end)
	if not hasOrgSupport then
		return {}
	end

	local contentPanel = nil
	local BuildContent = nil

	local function Refresh()
		module.RefreshOurOrganizations{
			success = function(orgs)
				if contentPanel == nil or (not contentPanel.valid) then
					return
				end
				BuildContent()
			end,
		}
	end

	local function OwnedOrg(orgs)
		for _,org in ipairs(orgs) do
			if org.role == "owner" then
				return org
			end
		end
		return nil
	end

	--gui.ModalMessage needs the game hud, which does not exist on the
	--titlescreen where this settings screen can also be shown. Use it when
	--available and otherwise show a simple overlay dialog on our own sheet.
	local function ShowMessage(args)
		if rawget(_G, "gamehud") ~= nil then
			gui.ModalMessage(args)
			return
		end

		local root = nil
		if contentPanel ~= nil and contentPanel.valid then
			root = contentPanel.root
		end
		if root == nil then
			return
		end

		local overlay = nil

		local buttons = {}
		local options = args.options or {{ text = "Okay" }}
		for _,option in ipairs(options) do
			buttons[#buttons+1] = gui.Button{
				width = 180,
				height = 36,
				fontSize = 16,
				halign = "center",
				valign = "center",
				hmargin = 6,
				text = option.text,
				click = function(element)
					overlay:DestroySelf()
					if option.execute ~= nil then
						option.execute()
					end
				end,
			}
		end

		overlay = gui.Panel{
			floating = true,
			width = "100%",
			height = "100%",
			halign = "center",
			valign = "center",
			bgimage = "panels/square.png",
			bgcolor = "#000000cc",

			gui.Panel{
				width = 600,
				height = "auto",
				halign = "center",
				valign = "center",
				flow = "vertical",
				bgimage = "panels/square.png",
				bgcolor = "#111111f8",
				border = 2,
				borderColor = "#999999ff",
				pad = 20,
				borderBox = true,

				gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 22,
					bold = true,
					halign = "center",
					textAlignment = "center",
					text = args.title or "",
				},

				gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 16,
					halign = "center",
					vmargin = 8,
					text = args.message or "",
				},

				gui.Panel{
					flow = "horizontal",
					width = "auto",
					height = "auto",
					halign = "center",
					vmargin = 4,
					children = buttons,
				},
			},
		}

		root:AddChild(overlay)
	end

	local function ErrorModal(title, msg)
		ShowMessage{
			title = title,
			message = msg or "Something went wrong. Please try again.",
		}
	end

	local function SubHeading(text)
		return gui.Label{
			width = "90%",
			height = "auto",
			halign = "center",
			fontSize = 20,
			bold = true,
			vmargin = 6,
			text = text,
		}
	end

	local function BodyText(text)
		return gui.Label{
			width = "90%",
			height = "auto",
			halign = "center",
			fontSize = 14,
			vmargin = 2,
			text = text,
		}
	end

	local function MemberRow(org, member)
		local removeButton = nil
		if org.role == "owner" and (not member.owner) then
			removeButton = gui.Button{
				width = 100,
				height = 26,
				fontSize = 14,
				valign = "center",
				halign = "right",
				text = "Remove",
				click = function(element)
					ShowMessage{
						title = "Remove Member",
						message = string.format("Remove %s from %s? They will no longer be able to publish or update the organization's modules.", member.displayName, org.displayName),
						options = {
							{ text = "Cancel" },
							{
								text = "Remove",
								execute = function()
									module.RemoveOrgMember{
										orgid = org.id,
										userid = member.userid,
										success = Refresh,
										failure = function(msg)
											ErrorModal("Remove Member", msg)
										end,
									}
								end,
							},
						},
					}
				end,
			}
		end

		local memberText = member.displayName
		if member.owner then
			memberText = string.format("%s (owner)", member.displayName)
		end

		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			vmargin = 1,
			gui.Label{
				width = "60%",
				height = "auto",
				fontSize = 14,
				valign = "center",
				text = memberText,
			},
			removeButton,
		}
	end

	local function InviteRow(org, invite)
		return gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			vmargin = 1,
			gui.Label{
				width = "60%",
				height = "auto",
				fontSize = 14,
				valign = "center",
				text = invite.inviteCode,
			},
			gui.Button{
				width = 70,
				height = 26,
				fontSize = 14,
				valign = "center",
				text = "Copy",
				click = function(element)
					dmhub.CopyToClipboard(invite.inviteCode)
				end,
			},
			gui.Panel{ width = 8, height = 1 },
			gui.Button{
				width = 90,
				height = 26,
				fontSize = 14,
				valign = "center",
				text = "Revoke",
				click = function(element)
					module.RevokeOrgInvite{
						orgid = org.id,
						code = invite.code,
						success = Refresh,
					}
				end,
			},
		}
	end

	--Patreon creator-account linking for an organization. The owner links one
	--Patreon campaign to the org; other members see a read-only connected line.
	--All link state lives in server-side default-deny paths and is read through
	--the patreonOrgStatus cloud function. The connect flow mirrors the MCDM
	--Shop link: open the browser into the OAuth consent screen, then poll
	--status until the callback records the link.
	local function PatreonOrgSection(org)
		local isOwner = org.role == "owner"

		local panel

		--bumped to retire any in-flight link-poll timers; every scheduled tick
		--compares its captured generation against this before acting.
		local m_pollGeneration = 0

		local ShowUnlinked
		local ShowLinked
		local RefreshStatus
		local StartLinkPoll

		local linkErrorMessages = {
			nocampaign = "That Patreon account does not have a campaign. Log in as the account that owns your campaign and try again.",
			multiple = "Linking accounts with multiple campaigns is not supported yet.",
			campaigntaken = "That Patreon campaign is already linked to a different organization. Disconnect it from that organization first.",
			error = "Something went wrong linking Patreon. Please try again.",
		}

		local function Heading()
			return gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				bold = true,
				vmargin = 2,
				text = "Patreon",
			}
		end

		local function StatusChildren(text)
			return {
				Heading(),
				gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 14,
					italics = true,
					text = text,
				},
			}
		end

		--linked state: campaign name + connected date; the owner also gets the
		--persistence checkbox and the Disconnect button.
		ShowLinked = function(data)
			local campaignName = data.campaignName
			if campaignName == nil or campaignName == "" then
				campaignName = "your campaign"
			end

			if not isOwner then
				panel.children = {
					gui.Label{
						width = "100%",
						height = "auto",
						fontSize = 14,
						vmargin = 2,
						text = string.format('Patreon: connected to "%s"', campaignName),
					},
				}
				return
			end

			local connectedText = string.format('Connected to "%s"', campaignName)
			if (data.connectedAt or 0) > 0 then
				connectedText = string.format("%s   (connected %s)", connectedText, os.date("%d %b %Y", math.floor(data.connectedAt / 1000)))
			end

			local children = { Heading() }

			children[#children+1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				vmargin = 2,
				text = connectedText,
			}

			--setting element.value programmatically fires change, so guard the
			--revert-on-failure write with a flag.
			local suppressChange = false
			children[#children+1] = gui.Check{
				text = "Patrons keep unlocked modules after their patronage ends",
				value = data.entitlementsPersistOnLapse ~= false,
				halign = "left",
				vmargin = 4,
				change = function(element)
					if suppressChange then
						return
					end
					local newValue = element.value
					net.Post{
						url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgSetPolicy",
						data = {
							orgid = org.id,
							entitlementsPersistOnLapse = newValue,
						},
						success = function(response)
							if not element.valid then
								return
							end
							if type(response) ~= "table" or not response.ok then
								suppressChange = true
								element.value = not newValue
								suppressChange = false
								ErrorModal("Patreon", "Could not save the setting. Please try again.")
							end
						end,
						error = function(msg)
							if not element.valid then
								return
							end
							suppressChange = true
							element.value = not newValue
							suppressChange = false
							ErrorModal("Patreon", "Could not save the setting. Please try again.")
						end,
					}
				end,
			}

			children[#children+1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 12,
				italics = true,
				vmargin = 2,
				text = "When unchecked, access is removed if a patron cancels.",
			}

			--Which of this organization's published modules come with a Patreon
			--membership. Saved to ModuleAuthor/{orgid}/patreonModules, which is
			--publicly readable - patrons are not members of the organization, so
			--anything gated on membership would be invisible to exactly the people
			--who need to see it.
			children[#children+1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				bold = true,
				vmargin = 8,
				text = "Modules included with membership",
			}

			local orgModules = data.orgModules or {}
			if #orgModules == 0 then
				children[#children+1] = gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 13,
					italics = true,
					color = "#999999",
					vmargin = 2,
					text = "This organization has not published any modules yet. Publish one and it will appear here.",
				}
			else
				--current selection, mutated by the checkboxes and posted whole:
				--the endpoint takes the complete list, so there is no partial
				--state to reconcile if one save fails.
				local included = {}
				for _,id in ipairs(data.patreonModules or {}) do
					included[id] = true
				end

				local moduleError = gui.Label{
					classes = {"collapsed"},
					width = "100%",
					height = "auto",
					fontSize = 13,
					color = "#ff6666",
					vmargin = 2,
					text = "",
				}

				local function SelectedList()
					local out = {}
					for _,id in ipairs(orgModules) do
						if included[id] then
							out[#out+1] = id
						end
					end
					return out
				end

				for _,moduleId in ipairs(orgModules) do
					local id = moduleId
					local suppress = false
					children[#children+1] = gui.Check{
						text = id,
						value = included[id] == true,
						halign = "left",
						vmargin = 1,
						change = function(element)
							if suppress then
								return
							end
							local newValue = element.value
							included[id] = newValue or nil
							moduleError:SetClass("collapsed", true)
							net.Post{
								url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgSetModules",
								data = {
									orgid = org.id,
									modules = SelectedList(),
								},
								success = function(response)
									if not element.valid then
										return
									end
									if type(response) ~= "table" or not response.ok then
										--roll the local model back so the next save is not
										--built on a selection the server rejected.
										included[id] = (not newValue) or nil
										suppress = true
										element.value = not newValue
										suppress = false
										moduleError.text = "Could not save. Please try again."
										moduleError:SetClass("collapsed", false)
									end
								end,
								error = function(msg)
									if not element.valid then
										return
									end
									included[id] = (not newValue) or nil
									suppress = true
									element.value = not newValue
									suppress = false
									moduleError.text = "Could not contact the server. Please try again."
									moduleError:SetClass("collapsed", false)
								end,
							}
						end,
					}
				end

				children[#children+1] = moduleError

				children[#children+1] = gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 12,
					italics = true,
					color = "#999999",
					vmargin = 2,
					text = "Patrons of your campaign can see and install these from their account settings.",
				}
			end

			children[#children+1] = gui.Button{
				width = 190,
				height = 30,
				fontSize = 14,
				halign = "left",
				vmargin = 4,
				text = "Disconnect Patreon",
				click = function(element)
					ShowMessage{
						title = "Disconnect Patreon",
						message = string.format("Disconnect Patreon from %s? Your patrons will no longer be granted access to your modules.", org.displayName),
						options = {
							{ text = "Cancel" },
							{
								text = "Disconnect",
								execute = function()
									net.Post{
										url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgUnlink",
										data = { orgid = org.id },
										success = function(response)
											if type(response) == "table" and response.ok then
												Refresh()
											else
												local err = nil
												if type(response) == "table" and type(response.error) == "string" then
													err = response.error
												end
												ErrorModal("Disconnect Patreon", err)
											end
										end,
										error = function(msg)
											ErrorModal("Disconnect Patreon", "Could not contact the server. Please try again.")
										end,
									}
								end,
							},
						},
					}
				end,
			}

			panel.children = children
		end

		--unlinked state: the owner gets the pitch + Link button (message is an
		--optional failure note from the previous attempt); members see nothing.
		ShowUnlinked = function(message)
			if not isOwner then
				panel.children = {}
				return
			end

			local children = { Heading() }

			children[#children+1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 13,
				vmargin = 2,
				text = "Link your Patreon creator account so your patrons can be granted access to your premium modules. We only read your campaign's membership list - never payment details.",
			}

			if message ~= nil then
				children[#children+1] = gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 13,
					color = "#ff6666",
					vmargin = 2,
					text = message,
				}
			end

			children[#children+1] = gui.Button{
				width = 240,
				height = 30,
				fontSize = 14,
				halign = "left",
				vmargin = 4,
				text = "Link Patreon Creator Account",
				click = function(element)
					panel.children = StatusChildren("Opening Patreon in your browser...")
					net.Post{
						url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgAuthStart",
						data = { orgid = org.id },
						success = function(data)
							if not panel.valid then
								return
							end
							if type(data) == "table" and data.ok and type(data.authorizeUrl) == "string" then
								dmhub.OpenURL(data.authorizeUrl)
								StartLinkPoll()
							else
								local err = "Could not start the link. Please try again."
								if type(data) == "table" and data.error == "already-linked" then
									err = "This organization already has a linked Patreon campaign."
								elseif type(data) == "table" and type(data.error) == "string" then
									err = data.error
								end
								ShowUnlinked(err)
							end
						end,
						error = function(msg)
							if not panel.valid then
								return
							end
							ShowUnlinked("Could not contact the server. Please try again.")
						end,
					}
				end,
			}

			panel.children = children
		end

		--ported from the MCDM Shop link poll: 4s tick, 180s deadline, Cancel,
		--transient errors do not end the wait. Additionally stops early when
		--the callback records a link error for this attempt.
		StartLinkPoll = function()
			m_pollGeneration = m_pollGeneration + 1
			local generation = m_pollGeneration
			local deadline = dmhub.Time() + 180

			local children = StatusChildren("Waiting for you to finish linking Patreon in your browser...")
			children[#children+1] = gui.Button{
				width = 120,
				height = 30,
				fontSize = 14,
				halign = "left",
				vmargin = 4,
				text = "Cancel",
				click = function(element)
					RefreshStatus()
				end,
			}
			panel.children = children

			local function PollExpired()
				--the settings sheet may have been destroyed while a tick was
				--scheduled; a dead panel is not safe to touch at all.
				return mod.unloaded or generation ~= m_pollGeneration or (not panel.valid)
			end

			local function FinishTimedOut()
				m_pollGeneration = m_pollGeneration + 1
				ShowUnlinked("Linking timed out. Try again after finishing in your browser.")
			end

			local Tick
			Tick = function()
				if PollExpired() then
					return
				end
				net.Post{
					url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgStatus",
					data = { orgid = org.id },
					success = function(data)
						if PollExpired() then
							return
						end
						if type(data) == "table" and data.ok then
							if data.linked then
								m_pollGeneration = m_pollGeneration + 1
								ShowLinked(data)
								return
							end
							if data.lastError ~= nil then
								m_pollGeneration = m_pollGeneration + 1
								ShowUnlinked(linkErrorMessages[data.lastError] or linkErrorMessages.error)
								return
							end
						end
						if dmhub.Time() > deadline then
							FinishTimedOut()
							return
						end
						dmhub.Schedule(4, Tick)
					end,
					error = function(msg)
						if PollExpired() then
							return
						end
						if dmhub.Time() > deadline then
							FinishTimedOut()
							return
						end
						dmhub.Schedule(4, Tick)
					end,
				}
			end

			Tick()
		end

		--fetch link status and rebuild the panel. Also retires any active poll.
		RefreshStatus = function()
			m_pollGeneration = m_pollGeneration + 1
			if isOwner then
				panel.children = StatusChildren("Checking Patreon...")
			end
			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/patreonOrgStatus",
				data = { orgid = org.id },
				success = function(data)
					if not panel.valid then
						return
					end
					if type(data) == "table" and data.ok and data.linked then
						ShowLinked(data)
					else
						ShowUnlinked(nil)
					end
				end,
				error = function(msg)
					if not panel.valid then
						return
					end
					if isOwner then
						ShowUnlinked("Could not check Patreon status.")
					else
						panel.children = {}
					end
				end,
			}
		end

		panel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			vmargin = 4,
			create = function(element)
				RefreshStatus()
			end,
		}

		return panel
	end

	local function OrgCard(org)
		local children = {}

		local roleText = "member"
		if org.role == "owner" then
			roleText = "you own this organization"
		end

		children[#children+1] = gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 20,
			bold = true,
			vmargin = 2,
			text = string.format("%s (%s)", org.displayName, roleText),
		}

		children[#children+1] = gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 14,
			bold = true,
			vmargin = 2,
			text = "Members:",
		}

		for _,member in ipairs(org.members) do
			children[#children+1] = MemberRow(org, member)
		end

		if org.role == "owner" then
			children[#children+1] = gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				bold = true,
				vmargin = 2,
				text = "Outstanding Invites:",
			}

			--the invite list loads asynchronously into this panel.
			children[#children+1] = gui.Panel{
				flow = "vertical",
				width = "100%",
				height = "auto",
				create = function(element)
					module.GetOrgInvites{
						orgid = org.id,
						success = function(invites)
							if not element.valid then
								return
							end
							local rows = {}
							for _,invite in ipairs(invites) do
								rows[#rows+1] = InviteRow(org, invite)
							end
							if #rows == 0 then
								rows[1] = gui.Label{
									width = "100%",
									height = "auto",
									fontSize = 14,
									italics = true,
									text = "No outstanding invites.",
								}
							end
							element.children = rows
						end,
						failure = function(msg)
						end,
					}
				end,
			}

			--transfer-ownership row, revealed by the Transfer Ownership button.
			local transferPanel = nil
			local otherMembers = {}
			for _,member in ipairs(org.members) do
				if not member.owner then
					otherMembers[#otherMembers+1] = { id = member.userid, text = member.displayName }
				end
			end

			if #otherMembers > 0 then
				local transferDropdown = gui.Dropdown{
					options = otherMembers,
					idChosen = otherMembers[1].id,
					width = 220,
					valign = "center",
				}

				transferPanel = gui.Panel{
					classes = {"collapsed"},
					flow = "horizontal",
					width = "100%",
					height = "auto",
					vmargin = 4,
					transferDropdown,
					gui.Panel{ width = 8, height = 1 },
					gui.Button{
						width = 110,
						height = 30,
						fontSize = 14,
						valign = "center",
						text = "Transfer",
						click = function(element)
							local targetid = transferDropdown.idChosen
							local targetName = targetid
							for _,m in ipairs(otherMembers) do
								if m.id == targetid then
									targetName = m.text
								end
							end
							ShowMessage{
								title = "Transfer Ownership",
								message = string.format("Transfer ownership of %s to %s? You will remain a member, but they will control the organization's members, invites, ownership, and deletion. You will not be able to undo this.", org.displayName, targetName),
								options = {
									{ text = "Cancel" },
									{
										text = "Transfer Ownership",
										execute = function()
											module.TransferOrgOwnership{
												orgid = org.id,
												userid = targetid,
												success = Refresh,
												failure = function(msg)
													ErrorModal("Transfer Ownership", msg)
												end,
											}
										end,
									},
								},
							}
						end,
					},
				}
			end

			local buttonsRow = gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vmargin = 4,
			}

			local buttons = {}
			buttons[#buttons+1] = gui.Button{
				width = 170,
				height = 30,
				fontSize = 14,
				valign = "center",
				text = "New Invite Code",
				click = function(element)
					module.CreateOrgInvite{
						orgid = org.id,
						success = function(code)
							dmhub.CopyToClipboard(code)
							ShowMessage{
								title = "Invite Created",
								message = string.format("One-use invite code (copied to your clipboard):\n\n%s\n\nGive it to the person you want to join %s. You can revoke it here until it is used.", code, org.displayName),
							}
							Refresh()
						end,
						failure = function(msg)
							ErrorModal("New Invite Code", msg)
						end,
					}
				end,
			}

			if transferPanel ~= nil then
				buttons[#buttons+1] = gui.Panel{ width = 8, height = 1 }
				buttons[#buttons+1] = gui.Button{
					width = 190,
					height = 30,
					fontSize = 14,
					valign = "center",
					text = "Transfer Ownership...",
					click = function(element)
						transferPanel:SetClass("collapsed", not transferPanel:HasClass("collapsed"))
					end,
				}
			end

			buttons[#buttons+1] = gui.Panel{ width = 8, height = 1 }
			buttons[#buttons+1] = gui.Button{
				width = 190,
				height = 30,
				fontSize = 14,
				valign = "center",
				text = "Delete Organization",
				click = function(element)
					ShowMessage{
						title = "Delete Organization",
						message = string.format("Delete %s? All members will be removed and nobody will be able to publish or update its modules any more. Modules that were published remain available to the users who installed them. The organization id stays reserved to your account so nobody else can claim it. This cannot be undone.", org.displayName),
						options = {
							{ text = "Cancel" },
							{
								text = "Delete Organization",
								execute = function()
									module.DeleteOrganization{
										orgid = org.id,
										success = Refresh,
										failure = function(msg)
											ErrorModal("Delete Organization", msg)
										end,
									}
								end,
							},
						},
					}
				end,
			}

			buttonsRow.children = buttons

			children[#children+1] = PatreonOrgSection(org)
			children[#children+1] = buttonsRow
			children[#children+1] = transferPanel
		else
			children[#children+1] = PatreonOrgSection(org)
			children[#children+1] = gui.Button{
				width = 170,
				height = 30,
				fontSize = 14,
				halign = "left",
				valign = "center",
				vmargin = 4,
				text = "Leave Organization",
				click = function(element)
					ShowMessage{
						title = "Leave Organization",
						message = string.format("Leave %s? You will no longer be able to publish or update its modules.", org.displayName),
						options = {
							{ text = "Cancel" },
							{
								text = "Leave",
								execute = function()
									module.LeaveOrganization{
										orgid = org.id,
										success = Refresh,
										failure = function(msg)
											ErrorModal("Leave Organization", msg)
										end,
									}
								end,
							},
						},
					}
				end,
			}
		end

		return gui.Panel{
			flow = "vertical",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 6,
			pad = 12,
			borderBox = true,
			bgimage = "panels/square.png",
			bgcolor = "#00000066",
			children = children,
		}
	end

	local function CreateOrgPanels(children)
		children[#children+1] = SubHeading("Create an Organization")
		children[#children+1] = BodyText("An organization lets a group of creators publish modules under a shared id. You can create one organization and invite others to it with one-use invite codes.")

		local orgIdInput = gui.Input{
			width = 220,
			height = 26,
			fontSize = 16,
			valign = "center",
			characterLimit = 12,
			placeholderText = "Organization id...",
		}

		children[#children+1] = gui.Panel{
			flow = "horizontal",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 4,
			orgIdInput,
			gui.Panel{ width = 8, height = 1 },
			gui.Button{
				width = 110,
				height = 30,
				fontSize = 14,
				valign = "center",
				text = "Create",
				click = function(element)
					local orgid = string.gsub(orgIdInput.text or "", "%s+", "")
					if orgid == "" then
						ErrorModal("Create Organization", "Enter an id for your organization. It may contain the characters a-z, 0-9, and _.")
						return
					end

					module.CreateOrganization{
						orgid = orgid,
						success = Refresh,
						failure = function(msg)
							ErrorModal("Create Organization", msg)
						end,
					}
				end,
			},
		}

		if module.savedAuthorid ~= nil then
			children[#children+1] = BodyText(string.format("Alternatively, convert your creator id '%s' into an organization. Modules you have already published under it become organization modules, and your account will no longer have a personal creator id (you will choose a new one if you publish personally again).", module.savedAuthorid))
			children[#children+1] = gui.Button{
				width = 280,
				height = 30,
				fontSize = 14,
				halign = "center",
				valign = "center",
				vmargin = 4,
				text = string.format("Convert '%s' to an Organization", module.savedAuthorid),
				click = function(element)
					ShowMessage{
						title = "Convert to Organization",
						message = string.format("Convert your creator id '%s' into an organization? Your published modules become organization modules that any member you invite can update. This cannot be undone.", module.savedAuthorid),
						options = {
							{ text = "Cancel" },
							{
								text = "Convert",
								execute = function()
									module.ConvertAuthorIdToOrganization{
										success = Refresh,
										failure = function(msg)
											ErrorModal("Convert to Organization", msg)
										end,
									}
								end,
							},
						},
					}
				end,
			}
		end
	end

	local function JoinOrgPanels(children)
		children[#children+1] = SubHeading("Join an Organization")
		children[#children+1] = BodyText("Enter a one-use invite code given to you by an organization's owner.")

		local joinStatusLabel = gui.Label{
			width = "90%",
			height = "auto",
			halign = "center",
			fontSize = 14,
			vmargin = 2,
			italics = true,
			text = "",
		}

		local codeInput = gui.Input{
			width = 300,
			height = 26,
			fontSize = 16,
			valign = "center",
			placeholderText = "Invite code...",
		}

		children[#children+1] = gui.Panel{
			flow = "horizontal",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 4,
			codeInput,
			gui.Panel{ width = 8, height = 1 },
			gui.Button{
				width = 110,
				height = 30,
				fontSize = 14,
				valign = "center",
				text = "Join",
				click = function(element)
					local text = string.gsub(codeInput.text or "", "%s+", "")
					local orgid, code = string.match(text, "^([%w_]+):(%w+)$")
					if orgid == nil then
						joinStatusLabel.text = "That does not look like an invite code. Codes look like myorg:ABCDEFGHJKMNPQRS."
						return
					end

					joinStatusLabel.text = "Joining..."

					net.Post{
						url = dmhub.cloudFunctionsBaseUrl .. "/orgRedeemInvite",
						data = {
							orgid = string.lower(orgid),
							code = code,
						},
						success = function(data)
							if not joinStatusLabel.valid then
								return
							end
							if type(data) == "table" and data.ok then
								joinStatusLabel.text = ""
								local message = string.format("You have joined %s. You can now publish modules as the organization from the module publishing dialog.", data.displayName or orgid)
								if data.alreadyMember then
									message = string.format("You are already a member of %s.", data.displayName or orgid)
								end
								ShowMessage{
									title = "Organization Joined",
									message = message,
								}
								Refresh()
							else
								local err = "Could not join the organization."
								if type(data) == "table" and data.error ~= nil then
									err = data.error
								end
								joinStatusLabel.text = err
							end
						end,
						error = function(msg)
							if not joinStatusLabel.valid then
								return
							end
							joinStatusLabel.text = "Could not contact the server. Please try again."
						end,
					}
				end,
			},
		}

		children[#children+1] = joinStatusLabel
	end

	--Premium Modules: creators generate one-use keys for premium modules they
	--have published. Keys are backed by the store gift-code system: the first
	--generation creates a hidden ("Not on store") store entry for the module,
	--and each key redeems once to grant the module. The heavy lifting happens
	--in the moduleKeysGenerate/moduleKeysList cloud functions, which verify we
	--control the module before writing the admin-only coupon paths.
	local PREMIUM_MODULE_MAX_KEYS = 500
	local PREMIUM_MODULE_KEY_BATCH = 50

	local function SaveKeysFile(fullid, ordinal, codes)
		local text = table.concat(codes, "\r\n") .. "\r\n"
		dmhub.SaveFileDialog{
			data = text,
			filename = string.format("%s-keys-%d.txt", fullid, ordinal),
			extensions = {"txt"},
		}
	end

	local function ModuleKeysCard(entry)
		local fullid = entry.fullid

		--the latest moduleKeysList-shaped state for this module.
		local m_keys = nil

		local card = nil
		local generateButton = nil

		local statusLabel = gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 14,
			vmargin = 2,
			text = "Loading key information...",
		}

		local allocationsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
		}

		local limitLabel = gui.Label{
			classes = {"collapsed"},
			width = "100%",
			height = "auto",
			fontSize = 14,
			vmargin = 2,
			text = string.format("This module has the maximum of %d keys. Contact admin@dmhub.info if you need more keys.", PREMIUM_MODULE_MAX_KEYS),
		}

		--Store Listing editor: the image and description shown for this module
		--in the store. Only revealed once keys have been generated (the first
		--batch is what creates the store entry). The image uploads through the
		--same global content-addressed image system module cover art uses;
		--the moduleKeysUpdateItem cloud function stamps the resulting id (and
		--the description) onto the admin-only store entry for us.
		local listingStatusLabel = gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 13,
			vmargin = 2,
			text = "",
		}

		local listingThumb = nil
		local ChooseListingImage = nil

		local function SetListingImage(imageid)
			if imageid ~= nil and imageid ~= "" then
				listingThumb.bgimage = imageid
				listingThumb.selfStyle.bgcolor = "white"
				listingThumb:FireEventTree("hasimage", true)
			else
				listingThumb.bgimage = "panels/square.png"
				listingThumb.selfStyle.bgcolor = "#111111ff"
				listingThumb:FireEventTree("hasimage", false)
			end
		end

		local function SaveListing(fields)
			listingStatusLabel.text = "Saving..."
			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/moduleKeysUpdateItem",
				data = {
					moduleid = fullid,
					details = fields.details,
					image = fields.image,
				},
				success = function(data)
					if card == nil or (not card.valid) then
						return
					end
					if type(data) == "table" and data.ok then
						listingStatusLabel.text = "Saved."
					else
						local err = "Could not save. Please try again."
						if type(data) == "table" and data.error ~= nil then
							err = data.error
						end
						listingStatusLabel.text = err
					end
				end,
				error = function(msg)
					if card == nil or (not card.valid) then
						return
					end
					listingStatusLabel.text = "Could not contact the server. Please try again."
				end,
			}
		end

		ChooseListingImage = function()
			dmhub.OpenFileDialog{
				id = "PremiumModuleShopImage",
				extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
				prompt = "Choose the image shown for this module in the store",
				multiFiles = false,
				open = function(path)
					local art = assets:LoadImageOrVideoFileLocally(path)
					if art == nil then
						listingStatusLabel.text = "The file you chose could not be loaded."
						return
					end
					if art.error ~= nil then
						--over the user's bandwidth allowance; art.error says so.
						listingStatusLabel.text = art.error
						return
					end

					--preview instantly from the local cache, upload the bytes
					--to the global image store, and stamp the id on the entry.
					SetListingImage(art.image)
					art:Upload()
					SaveListing{ image = art.image }
				end,
			}
		end

		listingThumb = gui.Panel{
			width = 200,
			height = 120,
			halign = "left",
			valign = "top",
			borderWidth = 1,
			borderColor = "#666666ff",
			bgimage = "panels/square.png",
			bgcolor = "#111111ff",
			click = function(element)
				ChooseListingImage()
			end,

			gui.Label{
				interactable = false,
				width = "100%",
				height = "auto",
				halign = "center",
				valign = "center",
				fontSize = 12,
				textAlignment = "center",
				color = "#999999ff",
				text = "No image.\nClick to upload.",
				hasimage = function(element, val)
					element:SetClass("hidden", val)
				end,
			},
		}

		local descriptionInput = gui.Input{
			width = "100%",
			height = "auto",
			minHeight = 60,
			multiline = true,
			fontSize = 14,
			vmargin = 4,
			characterLimit = 1024,
			placeholderText = "Describe this module in the store...",
			change = function(element)
				SaveListing{ details = element.text }
			end,
		}

		local listingPanel = gui.Panel{
			classes = {"collapsed"},
			flow = "vertical",
			width = "100%",
			height = "auto",

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				bold = true,
				vmargin = 2,
				text = "Store Listing:",
			},

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 13,
				color = "#aaaaaaff",
				text = "The image and description shown for this module in the store.",
			},

			gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vmargin = 4,

				listingThumb,

				gui.Panel{
					flow = "vertical",
					width = "100%-212",
					height = "auto",
					lmargin = 12,
					valign = "top",

					gui.Button{
						width = 150,
						height = 26,
						fontSize = 14,
						halign = "left",
						text = "Upload Image...",
						click = function(element)
							ChooseListingImage()
						end,
					},

					descriptionInput,
				},
			},

			listingStatusLabel,
		}

		local function RebuildAllocations()
			local rows = {}
			local allocs = (m_keys ~= nil and m_keys.allocations) or {}
			for i,alloc in ipairs(allocs) do
				local codes = alloc.codes or {}
				local ordinal = i
				rows[#rows+1] = gui.Panel{
					flow = "horizontal",
					width = "100%",
					height = "auto",
					vmargin = 1,
					gui.Label{
						width = "60%",
						height = "auto",
						fontSize = 14,
						valign = "center",
						text = string.format("Batch %d: %d keys, created %s", ordinal, #codes, dmhub.FormatTimestamp(alloc.ctime or 0, "yyyy-MM-dd HH:mm")),
					},
					gui.Button{
						width = 110,
						height = 26,
						fontSize = 14,
						valign = "center",
						text = "Download",
						click = function(element)
							SaveKeysFile(fullid, ordinal, codes)
						end,
					},
				}
			end

			if #rows == 0 then
				rows[1] = gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 14,
					italics = true,
					text = "No keys generated yet.",
				}
			end

			allocationsPanel.children = rows
		end

		local function ApplyKeys(data)
			m_keys = data
			local total = data.totalKeys or 0
			statusLabel.text = string.format("Keys generated: %d / %d", total, PREMIUM_MODULE_MAX_KEYS)

			local capped = total + PREMIUM_MODULE_KEY_BATCH > PREMIUM_MODULE_MAX_KEYS
			generateButton:SetClass("collapsed", capped)
			limitLabel:SetClass("collapsed", not capped)

			--the store listing becomes editable once keys exist (generating
			--the first batch is what creates the store entry).
			local hasKeys = total > 0 and data.itemid ~= nil and data.itemid ~= ""
			listingPanel:SetClass("collapsed", not hasKeys)
			if hasKeys and data.item ~= nil then
				SetListingImage(data.item.image)
				local details = data.item.details or ""
				if descriptionInput.text ~= details then
					descriptionInput.text = details
				end
			end

			RebuildAllocations()
		end

		local function RefreshKeys()
			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/moduleKeysList",
				data = {
					moduleid = fullid,
				},
				success = function(data)
					if card == nil or (not card.valid) then
						return
					end
					if type(data) == "table" and data.ok then
						ApplyKeys(data)
					else
						local err = "Could not load key information."
						if type(data) == "table" and data.error ~= nil then
							err = data.error
						end
						statusLabel.text = err
					end
				end,
				error = function(msg)
					if card == nil or (not card.valid) then
						return
					end
					statusLabel.text = "Could not contact the server to load key information."
				end,
			}
		end

		generateButton = gui.Button{
			width = 190,
			height = 30,
			fontSize = 14,
			halign = "left",
			valign = "center",
			vmargin = 4,
			text = string.format("Generate %d Keys", PREMIUM_MODULE_KEY_BATCH),
			data = {
				pending = false,
			},
			click = function(element)
				if element.data.pending then
					return
				end
				element.data.pending = true
				element.text = "Generating..."

				net.Post{
					url = dmhub.cloudFunctionsBaseUrl .. "/moduleKeysGenerate",
					data = {
						moduleid = fullid,
					},
					success = function(data)
						if not element.valid then
							return
						end
						element.data.pending = false
						element.text = string.format("Generate %d Keys", PREMIUM_MODULE_KEY_BATCH)

						if type(data) == "table" and data.ok then
							--offer the fresh batch as a text file right away,
							--then re-sync the counts and batch list.
							local ordinal = 1
							if m_keys ~= nil and m_keys.allocations ~= nil then
								ordinal = #m_keys.allocations + 1
							end
							SaveKeysFile(fullid, ordinal, data.codes or {})
							RefreshKeys()
						else
							local err = "Could not generate keys. Please try again."
							if type(data) == "table" and data.error ~= nil then
								err = data.error
							end
							ShowMessage{
								title = "Generate Keys",
								message = err,
							}
							RefreshKeys()
						end
					end,
					error = function(msg)
						if not element.valid then
							return
						end
						element.data.pending = false
						element.text = string.format("Generate %d Keys", PREMIUM_MODULE_KEY_BATCH)
						ErrorModal("Generate Keys", "Could not contact the server. Please try again.")
					end,
				}
			end,
		}

		card = gui.Panel{
			flow = "vertical",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 6,
			pad = 12,
			borderBox = true,
			bgimage = "panels/square.png",
			bgcolor = "#00000066",

			create = function(element)
				RebuildAllocations()
				RefreshKeys()
			end,

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 20,
				bold = true,
				vmargin = 2,
				text = entry.name or fullid,
			},

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 12,
				color = "#aaaaaaff",
				text = fullid,
			},

			statusLabel,

			listingPanel,

			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				bold = true,
				vmargin = 2,
				text = "Key Batches:",
			},

			allocationsPanel,

			generateButton,
			limitLabel,
		}

		return card
	end

	local function CreatePremiumModulesSection()
		local cardsPanel = gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
		}

		local sectionPanel = nil
		sectionPanel = gui.Panel{
			classes = {"collapsed"},
			flow = "vertical",
			width = "100%",
			height = "auto",

			create = function(element)
				--older engine builds may lack the published-modules API.
				local ok, published = pcall(function()
					return module.GetOurPublishedModules()
				end)
				if (not ok) or published == nil or #published == 0 then
					return
				end

				--download each published module's info and keep the premium
				--ones; reveal the section only once all downloads settle so
				--the card list is built (and sorted) exactly once.
				local outstanding = #published
				local premium = {}
				local function complete()
					outstanding = outstanding - 1
					if outstanding ~= 0 or sectionPanel == nil or (not sectionPanel.valid) then
						return
					end
					if #premium == 0 then
						return
					end

					table.sort(premium, function(a,b) return (a.name or "") < (b.name or "") end)
					local cards = {}
					for _,entry in ipairs(premium) do
						cards[#cards+1] = ModuleKeysCard(entry)
					end
					cardsPanel.children = cards
					sectionPanel:SetClass("collapsed", false)
				end

				for _,fullid in ipairs(published) do
					module.DownloadModuleInfo{
						moduleid = fullid,
						success = function(info)
							if info ~= nil and info.premium and (not info.deleted) then
								premium[#premium+1] = {
									fullid = info.fullid,
									name = info.name,
								}
							end
							complete()
						end,
						failure = function(msg)
							complete()
						end,
					}
				end
			end,

			SubHeading("Premium Modules"),
			BodyText(string.format("Generate keys for premium modules you have published. Each key can be redeemed once to unlock the module. Keys are generated %d at a time and saved to a text file; you can re-download past batches here.", PREMIUM_MODULE_KEY_BATCH)),
			cardsPanel,
		}

		return sectionPanel
	end

	BuildContent = function()
		local orgs = module.GetOurOrganizations()

		local children = {}

		for _,org in ipairs(orgs) do
			children[#children+1] = OrgCard(org)
		end

		if OwnedOrg(orgs) == nil then
			CreateOrgPanels(children)
		end

		JoinOrgPanels(children)

		contentPanel.children = children
	end

	contentPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		create = function(element)
			--the cached list renders immediately; refresh from the server in
			--case membership changed since login.
			Refresh()
		end,
	}

	BuildContent()

	return {
		gui.Label{
			width = "100%",
			height = 40,
			fontSize = 26,
			bold = true,
			vmargin = 8,
			text = "Creator Organizations",
		},

		BodyText("Organizations let a group of creators publish modules under a shared id. Modules published as an organization can be updated by any of its members, and show the organization as their author."),

		contentPanel,

		CreatePremiumModulesSection(),
	}
end

local g_imageEditorSetupDialog = nil
local function ShowImageEditorSetupDialog(onProceed)
	--The dialog is shown with gui.ShowModal, so it must be dismissed by popping
	--the modal stack. Destroying the panel directly leaves the invisible
	--full-screen modal blocker up, freezing all mouse input except the top bar.
	--CloseModal orphans the dialog, which destroys it.
	local function closeDialog()
		if g_imageEditorSetupDialog ~= nil and g_imageEditorSetupDialog.valid then
			gui.CloseModal()
		end
		g_imageEditorSetupDialog = nil
	end

	closeDialog()

	local dialog
	dialog = gui.Panel{
		classes = {"framedPanel"},
		styles = ThemeEngine.GetStyles(),
		width = 620,
		height = "auto",
		halign = "center",
		valign = "center",
		flow = "vertical",
		pad = 24,
		borderBox = true,

		destroy = function(element)
			if g_imageEditorSetupDialog == element then
				g_imageEditorSetupDialog = nil
			end
		end,

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			children = CreateImageEditorChooser(),
		},

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			halign = "center",
			vmargin = 16,

			gui.PrettyButton{
				text = "Cancel",
				width = 150,
				height = 36,
				fontSize = 16,
				hmargin = 8,
				click = function(element)
					closeDialog()
				end,
			},

			gui.PrettyButton{
				text = "Start Editing",
				width = 150,
				height = 36,
				fontSize = 16,
				hmargin = 8,
				click = function(element)
					dmhub.SetSettingValue("imageeditor:configured", true)
					closeDialog()
					if onProceed ~= nil then
						onProceed()
					end
				end,
			},
		},
	}

	g_imageEditorSetupDialog = dialog
	gui.ShowModal(dialog)
end

dmhub.PromptImageEditorSetup = function(a, b)
	--Called from C# with (floorid, objid) for an object live-edit, or directly from Lua with a single
	--continuation function for a generic live-edit (e.g. a map appearance image). Branch on the arg type.
	if type(a) == "function" then
		ShowImageEditorSetupDialog(a)
	else
		ShowImageEditorSetupDialog(function()
			dmhub.StartLiveEditForObject(a, b)
		end)
	end
end

--Email confirmation (double opt-in). Lets the user register + confirm a contact
--email and opt in to notifications. Talks to the email-service Worker via the
--"emailConfirmation" C# interface (registered in ScriptEngine) and listens to
--/users/{uid} for the confirmed state. No polling: it uses the cloud realtime listener.
local CreateEmailConfirmationPanel = function()
	local m_state = nil        --latest {email, emailConfirmed, allowEmails} from the cloud.
	local m_waiting = false     --true once we've sent a mail and are waiting on the user to click the link.
	local m_pendingEmail = nil  --the address we last submitted.
	local m_monitor = nil       --realtime listener handle.
	local m_sending = false     --guards against overlapping/duplicate requests.
	local m_changingEmail = false --true while the user is re-registering a different address over an already-confirmed one.

	local emailInput
	local submitButton
	local RefreshSubmitButton
	local cancelChangeButton
	local statusLabel
	local inputRow
	local waitingRow
	local waitingLabel
	local confirmedRow
	local confirmedLabel
	local allowEmailsCheck

	local IsConfirmed = function()
		return m_state ~= nil and m_state.emailConfirmed == true
	end

	local RefreshState = function()
		local confirmed = IsConfirmed()

		--"registering" means the enter-email/confirm flow is active: either the
		--user has no confirmed address yet, or they've chosen to change the one
		--they have (m_changingEmail).
		local registering = (confirmed == false) or m_changingEmail

		inputRow:SetClass("collapsed", (registering == false) or m_waiting)
		waitingRow:SetClass("collapsed", (registering == false) or (m_waiting == false))
		confirmedRow:SetClass("collapsed", (confirmed == false) or m_changingEmail)

		--the Cancel button only appears when backing out of a change to an
		--already-confirmed address.
		if cancelChangeButton ~= nil then
			cancelChangeButton:SetClass("collapsed", m_changingEmail == false)
		end

		--reflect any prefilled/known address in the submit button's visibility.
		if RefreshSubmitButton ~= nil then
			RefreshSubmitButton()
		end

		--the opt-in checkbox only appears once the user has a confirmed email
		--on file (and isn't mid-change); until then there's no registered
		--address to send updates to.
		allowEmailsCheck:SetClass("collapsed", (confirmed == false) or m_changingEmail)
		allowEmailsCheck.interactable = confirmed
		if m_state ~= nil then
			allowEmailsCheck.value = (m_state.allowEmails == true)
		end

		local addr = m_pendingEmail
		if addr == nil and m_state ~= nil then
			addr = m_state.email
		end
		addr = addr or ""

		waitingLabel.text = string.format("We've emailed a confirmation link to %s. Click the link in that email to finish confirming.", addr)

		if m_state ~= nil and m_state.email ~= nil and m_state.email ~= "" then
			confirmedLabel.text = string.format("%s is confirmed.", m_state.email)
		else
			confirmedLabel.text = "Your email address is confirmed."
		end
	end

	local SetStatus = function(text, isError)
		statusLabel.text = text or ""
		statusLabel:SetClass("collapsed", text == nil or text == "")
		statusLabel.selfStyle.color = cond(isError, "#ff6666", "#88ff88")
	end

	local SendRequest
	SendRequest = function(email)
		if m_sending then
			return
		end

		m_sending = true
		m_pendingEmail = email
		submitButton.interactable = false
		SetStatus("Sending...", false)

		emailConfirmation.RequestEmail{
			email = email,
			complete = function(result)
				m_sending = false
				submitButton.interactable = true

				if result ~= nil and result.ok and result.status == "sent" then
					--the change has committed to the server; hand off to the
					--normal waiting/confirm flow (the cloud record now holds the
					--new, unconfirmed address).
					m_changingEmail = false
					m_waiting = true
					SetStatus(nil, false)
					RefreshState()
				elseif result ~= nil and (result.httpStatus == 429 or result.error == "rate_limited") then
					local secs = result.retryAfterSeconds or 60
					SetStatus(string.format("Too many attempts. Please try again in %d seconds.", math.floor(secs)), true)
				elseif result ~= nil and (result.httpStatus == 400 or result.error == "invalid_email") then
					SetStatus("That doesn't look like a valid email address.", true)
				elseif result ~= nil and (result.httpStatus == 401 or result.error == "invalid_token") then
					SetStatus("Your session has expired. Please try again.", true)
				else
					local msg = "Something went wrong. Please try again."
					if result ~= nil and result.error ~= nil then
						msg = string.format("Error: %s", tostring(result.error))
					end
					SetStatus(msg, true)
				end
			end,
		}
	end

	--basic sanity check for a plausible email address (has length, an '@', and a '.').
	local LooksLikeEmail = function(email)
		email = email or ""
		return string.len(email) >= 4 and string.find(email, "@") ~= nil and string.find(email, "%.") ~= nil
	end

	--show the submit button only once the entered text looks like a valid address.
	RefreshSubmitButton = function()
		if submitButton ~= nil then
			submitButton:SetClass("collapsed", LooksLikeEmail(emailInput.text) == false)
		end
	end

	local TrySubmit = function()
		if m_sending then
			return
		end

		if LooksLikeEmail(emailInput.text) == false then
			SetStatus("Please enter a valid email address.", true)
			return
		end
		SendRequest(emailInput.text)
	end

	emailInput = gui.Input{
		id = "emailInput",
		placeholderText = "Enter your email address...",
		characterLimit = 64,
		width = 280,
		height = 26,
		fontSize = 16,
		bgimage = "panels/square.png",
		borderWidth = 2,
		borderColor = "#c8a45a",
		halign = "left",
		valign = "center",
		edit = function(element)
			RefreshSubmitButton()
		end,
	}

	submitButton = gui.Button{
		classes = {"collapsed"},
		text = "Send Confirmation Email",
		width = 260,
		height = 40,
		fontSize = 18,
		halign = "left",
		vmargin = 4,
		click = function(element)
			TrySubmit()
		end,
	}

	cancelChangeButton = gui.Button{
		classes = {"collapsed"},
		text = "Cancel",
		width = 180,
		height = 36,
		fontSize = 16,
		halign = "left",
		vmargin = 4,
		click = function(element)
			--back out of a change to an already-confirmed address, leaving the
			--existing confirmed email untouched.
			m_changingEmail = false
			m_pendingEmail = nil
			SetStatus(nil, false)
			RefreshState()
		end,
	}

	inputRow = gui.Panel{
		id = "emailInputRow",
		flow = "vertical",
		width = "100%",
		height = "auto",
		emailInput,
		submitButton,
		cancelChangeButton,
	}

	waitingLabel = gui.Label{
		width = "100%",
		maxWidth = 600,
		height = "auto",
		fontSize = 14,
		text = "",
	}

	waitingRow = gui.Panel{
		id = "emailWaitingRow",
		classes = {"collapsed"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		waitingLabel,
		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			gui.Button{
				text = "Resend Email",
				width = 180,
				height = 36,
				fontSize = 16,
				halign = "left",
				vmargin = 4,
				click = function(element)
					local addr = m_pendingEmail
					if addr == nil and m_state ~= nil then
						addr = m_state.email
					end
					if addr ~= nil and addr ~= "" then
						SendRequest(addr)
					end
				end,
			},
			gui.Label{
				text = "Use a different address",
				color = "#00FFFF",
				fontSize = 14,
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				hmargin = 16,
				press = function(element)
					m_waiting = false
					SetStatus(nil, false)
					RefreshState()
				end,
			},
		},
	}

	confirmedLabel = gui.Label{
		width = "100%",
		height = "auto",
		fontSize = 14,
		text = "",
	}

	confirmedRow = gui.Panel{
		id = "emailConfirmedRow",
		classes = {"collapsed"},
		flow = "vertical",
		width = "100%",
		height = "auto",
		confirmedLabel,
		gui.Button{
			text = "Change Email",
			width = 180,
			height = 36,
			fontSize = 16,
			halign = "left",
			vmargin = 4,
			click = function(element)
				--reopen the registration form so the user can register a
				--different address. The cloud record isn't touched until they
				--submit a new address (the Worker overwrites it and the
				--confirmed flag only becomes true again once the new link is
				--clicked); Cancel backs out with no change.
				m_changingEmail = true
				m_waiting = false
				m_pendingEmail = nil
				SetStatus(nil, false)
				if m_state ~= nil and m_state.email ~= nil then
					emailInput.text = m_state.email
				else
					emailInput.text = ""
				end
				RefreshState()
			end,
		},
	}

	statusLabel = gui.Label{
		id = "emailStatus",
		classes = {"collapsed"},
		width = "100%",
		maxWidth = 600,
		height = "auto",
		fontSize = 13,
		vmargin = 2,
		color = "#ff6666",
		text = "",
	}

	allowEmailsCheck = gui.Check{
		id = "allowEmailsCheck",
		classes = {"collapsed"},
		text = "Send me occasional email updates",
		value = false,
		interactable = false,
		halign = "left",
		width = "100%",
		height = 36,
		fontSize = 14,
		vmargin = 4,
		change = function(element)
			emailConfirmation.SetAllowEmails(element.value)
		end,
	}

	local resultPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		vmargin = 12,

		create = function(element)
			m_monitor = emailConfirmation.MonitorStatus(function(state)
				m_state = state
				if state ~= nil and state.emailConfirmed then
					m_waiting = false
					--clear any lingering status/error (e.g. a "too many
					--attempts" rate-limit message) now that the address is
					--confirmed.
					SetStatus(nil, false)
				end

				--prefill the input with the known address while we're still collecting it.
				if IsConfirmed() == false and m_waiting == false and state ~= nil and state.email ~= nil and (emailInput.text == nil or emailInput.text == "") then
					emailInput.text = state.email
				end

				RefreshState()
			end)

			RefreshState()
		end,

		destroy = function(element)
			if m_monitor ~= nil then
				m_monitor:Stop()
				m_monitor = nil
			end
		end,

		gui.Label{
			classes = {"sizeL", "bold"},
			width = "auto",
			height = "auto",
			vmargin = 8,
			text = "Email Notifications",
		},

		gui.Label{
			width = "100%",
			maxWidth = 600,
			height = "auto",
			fontSize = 14,
			text = string.format("Confirm an email address to receive notifications from %s. We'll send you a link to confirm it's yours.", dmhub.whiteLabelAppName),
		},

		inputRow,
		waitingRow,
		confirmedRow,
		statusLabel,
		allowEmailsCheck,
	}

	return resultPanel
end

--The Patreon OAuth link flow, hoisted out of the account panel below so more
--than one place can offer it. A global table rather than mod.shared, which is
--per-mod: the module browser lives in another mod and offers the same one-click
--connect on the page of a module a membership unlocks. Same pattern as the
--ModuleBrowser global that browser exports.
--rawget: reading a never-assigned global raises in this runtime.
PatreonAccount = rawget(_G, "PatreonAccount") or {}

--Begins linking a Patreon account: ask patreonAuthStart for an authorize URL,
--open it in the system browser, then poll patreonStatus until the OAuth
--callback records the link.
--
--options:
--  alive     function -> boolean. Return false once the caller's UI is gone.
--            Every callback and every scheduled tick from then on is dropped -
--            a dead panel is not safe to touch at all.
--  progress  function(text)  status text as the flow advances.
--  linked    function(data)  the link completed; data is the patreonStatus reply.
--  failed    function(msg)   could not start, or the user never finished.
--
--Returns a handle with :Cancel(), which retires the flow without calling back.
function PatreonAccount.BeginLink(options)
	local m_finished = false

	local handle = {}
	function handle:Cancel()
		m_finished = true
	end

	local function Expired()
		return m_finished or mod.unloaded or (options.alive ~= nil and options.alive() ~= true)
	end

	local function Progress(text)
		if options.progress ~= nil then
			options.progress(text)
		end
	end

	local function Failed(msg)
		m_finished = true
		if options.failed ~= nil then
			options.failed(msg)
		end
	end

	--4s tick, 180s deadline; transient errors do not end the wait, since the
	--user is off in a browser and the network may blip.
	local function StartPoll()
		local deadline = dmhub.Time() + 180

		local Tick
		Tick = function()
			if Expired() then
				return
			end

			net.Post{
				url = dmhub.cloudFunctionsBaseUrl .. "/patreonStatus",
				data = {},
				success = function(data)
					if Expired() then
						return
					end
					if type(data) == "table" and data.ok and data.linked then
						m_finished = true
						if options.linked ~= nil then
							options.linked(data)
						end
						return
					end
					if dmhub.Time() > deadline then
						Failed("Linking timed out. Try again after finishing in your browser.")
						return
					end
					dmhub.Schedule(4, Tick)
				end,
				error = function(msg)
					if Expired() then
						return
					end
					if dmhub.Time() > deadline then
						Failed("Linking timed out. Try again after finishing in your browser.")
						return
					end
					dmhub.Schedule(4, Tick)
				end,
			}
		end

		Progress("Waiting for you to finish linking Patreon in your browser...")
		Tick()
	end

	Progress("Opening Patreon in your browser...")

	net.Post{
		url = dmhub.cloudFunctionsBaseUrl .. "/patreonAuthStart",
		data = {},
		success = function(data)
			if Expired() then
				return
			end

			if type(data) == "table" and data.ok and type(data.authorizeUrl) == "string" then
				dmhub.OpenURL(data.authorizeUrl)
				StartPoll()
			else
				local err = "Could not start the link. Please try again."
				if type(data) == "table" and type(data.error) == "string" then
					err = data.error
				end
				Failed(err)
			end
		end,
		error = function(msg)
			if Expired() then
				return
			end
			Failed("Could not contact the server. Please try again.")
		end,
	}

	return handle
end

--The Patreon campaign a Codex user is being asked to support. Only MCDM's own
--modules are surfaced this way (see Module.cs MCDMOrgId), so this is one fixed
--campaign, not a per-organization link: the publicly readable ModuleAuthor
--record carries the included-module list but not a campaign URL.
PatreonAccount.mcdmCampaignUrl = "https://www.patreon.com/cw/mcdm"

--Patreon PATRON account linking, for the logged-in user's own Patreon account.
--Distinct from PatreonOrgSection, which links a CREATOR's campaign to an
--organization. This one grants the user their own patron tier.
--
--Flow mirrors the MCDM Shop link and the org link: ask patreonAuthStart for an
--authorize URL, open it in the system browser, then poll patreonStatus until the
--callback records the link. Both functions accept the desktop {userid, secretid}
--that net.Post injects, so no Firebase idToken is needed here.
--
--Status comes from patreonStatus rather than dmhub.patronTier because the tier
--alone cannot tell "not linked" from "linked but on a free/lapsed tier" - both
--are 0, and offering "Connect" to someone already connected would rewrite their
--binding. dmhub.patronTier still updates live off /Patrons and is what the rest
--of the app gates on.
local CreatePatreonAccountPanel = function()
	local panel

	--the in-flight PatreonAccount.BeginLink handle, if any. Cancelled whenever we
	--re-render the section, which is what retires a poll the user walked away from.
	local m_link = nil

	local ShowUnlinked
	local ShowLinked
	local ShowConfirmDisconnect
	local RefreshStatus

	local function Heading()
		return gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 14,
			bold = true,
			vmargin = 2,
			text = "Patreon",
		}
	end

	local function StatusChildren(text)
		return {
			Heading(),
			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				italics = true,
				text = text,
			},
		}
	end

	local function ErrorLabel(message)
		return gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 13,
			color = "#ff6666",
			vmargin = 2,
			text = message,
		}
	end

	--tier 0 with a link is a real state: a free-tier or lapsed patron. Say so
	--rather than implying nothing is connected.
	local function ConnectedText(data)
		local tier = data.tier or 0
		local text
		if tier > 0 then
			text = string.format("Connected to Patreon   (patron tier %d)", tier)
		else
			text = "Connected to Patreon   (no active pledge)"
		end
		if (data.linkedAt or 0) > 0 then
			text = string.format("%s   linked %s", text, os.date("%d %b %Y", math.floor(data.linkedAt / 1000)))
		end
		return text
	end

	--The creator organizations this Patreon pledge unlocks. Read straight from
	--dmhub.patreonOrgEntitlements, which the engine mirrors live off /Patrons -
	--so when the user subscribes, the campaign webhook writes the entitlement
	--and this list gains a row within seconds, no refresh needed.
	--
	--Gate on `entitled`, not `active`: a creator can choose to let entitlements
	--persist after a pledge lapses, and those users must keep their access.
	local function EntitledOrgRows()
		local rows = {}
		local list = dmhub.patreonOrgEntitlements or {}

		for _,entry in ipairs(list) do
			if entry.entitled then
				local label = entry.orgid
				local suffix
				if entry.active then
					if (entry.cents or 0) > 0 then
						suffix = string.format("$%.2f/month", entry.cents / 100)
					else
						suffix = "active"
					end
				else
					--entitled but not active: kept by the creator's persist-on-lapse choice.
					suffix = "access retained after your pledge ended"
				end

				local orgid = entry.orgid

				--Which modules the membership includes lives on the org's public
				--ModuleAuthor record, not in our entitlement, so it is one source
				--of truth the creator can edit without a fan-out to every patron.
				--Cost is this lookup; it is a settings panel, so that is fine.
				--
				--The cards are the module browser's own widget
				--(mod.shared.CreateModuleSlot), so they look and behave exactly
				--like the ones in Browse Modules, and clicking one opens the real
				--module page with its Install button rather than a second copy of
				--it built here.
				local modulesContainer = gui.Panel{
					classes = {"collapsed"},
					flow = "horizontal",
					wrap = true,
					width = "100%",
					height = "auto",
					vmargin = 2,
					--the cards carry the browser's classes, so they need the
					--browser's rules too. Without these a slot has no size and its
					--details text spills across the whole settings column.
					styles = ThemeEngine.MergeTokens(ModuleBrowser.moduleStyles),
					create = function(element)
						module.GetOrganizationInfo{
							orgid = orgid,
							success = function(info)
								if not element.valid then
									return
								end
								local ids = info.patreonModules or {}
								if #ids == 0 then
									return
								end

								--one lookup per module: Search matches a bare module
								--id directly, which is also the path that now honours
								--a Patreon entitlement past the premium/store gate.
								module.QueryModuleIndex{
									index = "Hot",
									success = function(moduleIndex)
										if not element.valid then
											return
										end
										local slots = {}
										for _,fullid in ipairs(ids) do
											moduleIndex:Search{
												text = fullid,
												success = function(result)
													if not element.valid then
														return
													end
													for _,moduleInfo in ipairs(result.items or {}) do
														--ModuleBrowser, not mod.shared: that table is per-mod
														--and ModShare lives in a different one.
														local slot = ModuleBrowser.CreateModuleSlot{
															press = function(info)
																ModuleBrowser.ShowDialog{focusModule = info}
															end,
														}
														slots[#slots+1] = slot
														element.children = slots
														slot:FireEvent("setmodule", moduleInfo)
														element:SetClass("collapsed", false)
													end
												end,
											}
										end
									end,
								}
							end,
							failure = function(msg)
								--silent: the entitlement itself is what matters, and a
								--failed lookup should not make it look revoked.
							end,
						}
					end,
				}

				rows[#rows+1] = gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 13,
					vmargin = 1,
					text = string.format("%s   <color=#999999>(%s)</color>", label, suffix),
					markdown = true,
				}
				rows[#rows+1] = modulesContainer
			end
		end

		if #rows == 0 then
			return {
				gui.Label{
					width = "100%",
					height = "auto",
					fontSize = 13,
					italics = true,
					color = "#999999",
					vmargin = 2,
					text = "No creator content unlocked yet. Supporting a creator on Patreon unlocks their content here automatically.",
				},
			}
		end

		table.insert(rows, 1, gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 13,
			bold = true,
			vmargin = 2,
			text = "Creator content you have access to",
		})
		return rows
	end

	ShowLinked = function(data)
		local children = {
			Heading(),
			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				vmargin = 2,
				text = ConnectedText(data),
			},
		}

		for _,row in ipairs(EntitledOrgRows()) do
			children[#children+1] = row
		end

		children[#children+1] = gui.Button{
			width = 190,
			height = 30,
			fontSize = 14,
			halign = "left",
			vmargin = 4,
			text = "Disconnect Patreon",
			click = function(element)
				ShowConfirmDisconnect(data)
			end,
		}

		panel.children = children
	end

	--inline confirm. ShowMessage/ErrorModal are locals of
	--CreateCreatorOrganizationsSection and are not in scope here, so this
	--follows the MCDM Shop section's two-step button instead of a modal.
	ShowConfirmDisconnect = function(data)
		local children = {
			Heading(),
			gui.Label{
				width = "100%",
				height = "auto",
				fontSize = 14,
				maxWidth = 600,
				vmargin = 2,
				text = "Disconnect your Patreon account? You will lose any benefits your patron tier unlocks until you link it again.",
			},
		}

		local errorLabel = gui.Label{
			classes = {"collapsed"},
			width = "100%",
			height = "auto",
			fontSize = 13,
			color = "#ff6666",
			vmargin = 2,
			text = "",
		}

		children[#children+1] = gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			gui.Button{
				width = 180,
				height = 30,
				fontSize = 14,
				halign = "left",
				vmargin = 4,
				text = "Confirm Disconnect",
				click = function(element)
					element.text = "Disconnecting..."
					element.interactable = false
					errorLabel:SetClass("collapsed", true)
					net.Post{
						url = dmhub.cloudFunctionsBaseUrl .. "/patreonUnlink",
						data = {},
						success = function(response)
							if not panel.valid then
								return
							end
							if type(response) == "table" and response.ok then
								RefreshStatus()
							else
								element.text = "Confirm Disconnect"
								element.interactable = true
								errorLabel.text = "Could not disconnect. Please try again."
								errorLabel:SetClass("collapsed", false)
							end
						end,
						error = function(msg)
							if not panel.valid then
								return
							end
							element.text = "Confirm Disconnect"
							element.interactable = true
							errorLabel.text = "Could not contact the server. Please try again."
							errorLabel:SetClass("collapsed", false)
						end,
					}
				end,
			},
			gui.Button{
				width = 120,
				height = 30,
				fontSize = 14,
				halign = "left",
				vmargin = 4,
				hmargin = 8,
				text = "Cancel",
				click = function(element)
					ShowLinked(data)
				end,
			},
		}

		children[#children+1] = errorLabel
		panel.children = children
	end

	ShowUnlinked = function(message)
		local children = { Heading() }

		children[#children+1] = gui.Label{
			width = "100%",
			height = "auto",
			fontSize = 13,
			maxWidth = 600,
			vmargin = 2,
			text = "Link your Patreon account to unlock what your patron tier includes. We only read which tier you are on - never payment details.",
		}

		if message ~= nil then
			children[#children+1] = ErrorLabel(message)
		end

		children[#children+1] = gui.Button{
			width = 200,
			height = 30,
			fontSize = 14,
			halign = "left",
			vmargin = 4,
			text = "Link Patreon Account",
			click = function(element)
				m_link = PatreonAccount.BeginLink{
					alive = function() return panel.valid end,
					progress = function(text)
						local children = StatusChildren(text)
						children[#children+1] = gui.Button{
							width = 120,
							height = 30,
							fontSize = 14,
							halign = "left",
							vmargin = 4,
							text = "Cancel",
							click = function(element)
								RefreshStatus()
							end,
						}
						panel.children = children
					end,
					linked = function(data)
						ShowLinked(data)
					end,
					failed = function(msg)
						ShowUnlinked(msg)
					end,
				}
			end,
		}

		panel.children = children
	end

	--/Patrons/{uid} carries a token-free mirror of the link, and the engine
	--already monitors it, so the linked state is in memory with no round trip.
	--Render from that first and let the patreonStatus call confirm behind it -
	--otherwise every visit to this tab eats a Cloud Function cold start (warm is
	--~100ms, cold is seconds) before showing anything.
	--
	--dmhub.patreonUserId, NOT dmhub.patronTier: patronTier is a hardcoded 3 on
	--MCDM white-label builds and says nothing about whether a Patreon is linked.
	local function LocalStatus()
		local id = dmhub.patreonUserId
		if id == nil or id == "" then
			return nil
		end
		return {
			linked = true,
			tier = dmhub.patreonPledgeTier,
			patreonUserId = id,
			linkedAt = dmhub.patreonLinkedAt,
		}
	end

	RefreshStatus = function()
		if m_link ~= nil then
			m_link:Cancel()
			m_link = nil
		end

		local local_ = LocalStatus()
		if local_ ~= nil then
			ShowLinked(local_)
		else
			--absent could mean "not linked" or "mirror not populated yet" (a link
			--made before the mirror existed), so still ask the server before
			--claiming unlinked.
			panel.children = StatusChildren("Checking Patreon...")
		end

		net.Post{
			url = dmhub.cloudFunctionsBaseUrl .. "/patreonStatus",
			data = {},
			success = function(data)
				if not panel.valid then
					return
				end
				if type(data) == "table" and data.ok and data.linked then
					ShowLinked(data)
				else
					ShowUnlinked(nil)
				end
			end,
			error = function(msg)
				if not panel.valid then
					return
				end
				ShowUnlinked("Could not check Patreon status.")
			end,
		}
	end

	panel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		vmargin = 4,
		create = function(element)
			RefreshStatus()
		end,
	}

	return panel
end

function CreateSettingsScreen(dialog, args)
    args = args or {}

	dmhub.Debug('EXEC SETTING SCREEN')

	local m_selectedTab = "General"

	--The root panel the settings UI lives in. Normally this is the sheet we
	--assign to the C# dialog container, but in-game it is hosted inside the
	--game hud instead (see the end of this function), so tree-wide events
	--must be fired on this rather than on dialog.sheet.
	local m_screenRoot = nil

	local SettingGroup = function(options)

		local group = options.group
		options.group = nil
		local buildFn = options.build
		options.build = nil

		local built = false
		local panel

		local function buildIfNeeded()
			if built then return end
			built = true
			if buildFn ~= nil then
                print("BUILD::", group)
				panel.children = buildFn()
			end
		end

		local args = {
			classes = {cond(m_selectedTab ~= group, "collapsed")},
			flow = "vertical",
			width = "auto",
			height = "auto",
			refreshTab = function(element)
				element:SetClass("collapsed", m_selectedTab ~= group)
				if m_selectedTab == group then
					buildIfNeeded()
				end
			end,
			forceBuild = function(element)
				buildIfNeeded()
			end,
		}

		for k,v in pairs(options) do
			args[k] = v
		end

		panel = gui.Panel(args)

		if m_selectedTab == group then
			buildIfNeeded()
		end

		return panel
	end

	local m_searchPanels = {}

	local Setting = function(settingid)
		local createfn = function()
			local result = CreateSettingsEditor(settingid)
			result.data.settingid = settingid
			return result
		end

		local editor = createfn()

		editor.events.search = function(element, text, results)
			results[#results+1] = {
				id = settingid,
				create = createfn,
				shown = SettingMatchesSearch(settingid, text),
			}
		end

		return editor
	end

	local SettingsHeading = function(title)
		return gui.Label{
			width = "100%",
			height = 40,
			fontSize = 26,
			bold = true,
			text = title,
		}
	end

	local SettingsSection = function(section)
		local items = {}
		for _,s in ipairs(SettingsOrdered) do
			if s.section ~= nil and string.lower(s.section) == string.lower(section) then
				items[#items+1] = s
			end
		end

		table.sort(items, function(aobj,bobj)
			local a = aobj.ord or aobj.id
			local b = bobj.ord or bobj.id
			return tostring(b) < tostring(a)
		end)

		local panels = {}
		for _,item in ipairs(items) do
			panels[#panels+1] = Setting(item.id)
		end

		return gui.Panel{
			flow = "vertical",
			width = "100%",
			height = "auto",
			children = panels,
		}

	end

	local CreateTab = function(args)
		if args.dmonly and ((not dmhub.inGame) or (not dmhub.isDM)) then
			return nil
		end
		
		return gui.Label{
			classes = {"tab", cond(args.text == m_selectedTab, "selected")},
			text = args.text,
			press = function(element)
				for _,child in ipairs(element.parent.children) do
					child:SetClass("selected", element == child)
				end

				m_selectedTab = args.text
				m_screenRoot:FireEventTree("refreshTab")
			end,
		}
	end

	local keybinds = nil
	local keybindsTab = nil
	if CreateKeybindsSettingsPanel ~= false then
		keybinds = SettingGroup{
			group = "Shortcuts",
			build = function()
				printf("CREATE KEYBINDS SETTINGS")
				return { CreateKeybindsSettingsPanel() }
			end,
			--fired when a bind is changed from outside this tab (right-clicking a
			--settings checkbox); the tab builds lazily once, so it must be rebuilt
			--for the new binding's row to appear.
			rebuildKeybinds = function(element)
				element.children = { CreateKeybindsSettingsPanel() }
			end,
		}
		keybindsTab = CreateTab{
			text = "Shortcuts",
		}
	end

	local settingsDialog = gui.Panel{
		id = "settingsDialog",
		classes = {"dialog"},

		width = 1140,
		height = 900,
		halign = "center",
		valign = "center",
		flow = "vertical",
		pad = 8,

		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
		end,

		styles = ThemeEngine.MergeStyles({
			{
				selectors = {"~dm", "dmonly"},
				collapsed = 1,
			},
		}),

		children = {
			gui.Button{
				-- classes = {"sizeS"},
				bgimage = true,
				text = "Close",
				floating = true,
				escapeActivates = true,
				halign = "right",
				valign = "bottom",
				hmargin = 20,
				vmargin = 20,
				click = function()
					dialog.sheet = nil

					if dmhub.settingsChangesRequireRestart then
						dmhub.QuitApplication()
					end
				end,
			},

			gui.Label{
				thinkTime = 0.2,
				think = function(element)
					element.selfStyle.opacity = cond(dmhub.settingsChangesRequireRestart, 1, 0)
				end,
				opacity = 0,
				floating = true,
				halign = "center",
				valign = "bottom",
				width = "auto",
				height = "auto",
				vmargin = 12,
				color = "white",
				fontSize = 18,
				text = string.format(tr("%s will need to be restarted to apply changes."), dmhub.whiteLabelAppName),
			},

			gui.Label{
				classes = {"dialogTitle"},
				text = "Settings",
				vmargin = 16,
			},


			gui.Panel{
				width = "auto",
				height = "auto",
				halign = "center",
				flow = "vertical",
				gui.SearchInput{
					placeholderText = "Search Settings...",
					width = 240,
					height = 20,
					bmargin = 6,
					halign = "left",
					characterLimit = 30,
					create = function(element)
						if args.search then
							element.text = args.search
							element:FireEvent("edit")
						end
					end,
					edit = function(element)
						if element.text ~= "" then
							m_screenRoot:FireEventTree("forceBuild")
						end
						local matches = {}
						m_screenRoot:FireEventTree("search", element.text, matches)
						if element.text ~= "" then
							local shownCount = 0
							for _,m in ipairs(matches) do
								if m.shown then shownCount = shownCount + 1 end
							end
							track("search_settings", {
								query = element.text,
								hasResults = shownCount > 0,
								resultCount = shownCount,
								deduplicate = 0.5,
								dailyLimit = 50,
							})
						end
					end,
				},
				gui.Panel{
					classes = {"tabBar"},

					search = function(element, text)
						element:SetClass("hidden", text ~= nil and text ~= "")
					end,

					CreateTab{
						text = "General",
					},
					CreateTab{
						text = "Graphics",
					},
					CreateTab{
						text = "Audio",
					},
					CreateTab{
						text = "Game",
						dmonly = true,
					},
					CreateTab{
						text = "Map",
						dmonly = true,
					},
					CreateTab{
						text = "Editing",
					},
					keybindsTab,
					CreateTab{
						text = "Account",
					},
				},
			},

			gui.Panel{
				vscroll = true,
				-- scrollHandleColor = "teal",
				width = "60%",
				height = "75%",
				flow = "vertical",
				halign = "center",
				valign = "center",

				search = function(element, text)
					element:SetClass("collapsed", text ~= nil and text ~= "")
				end,

				children = {
					SettingGroup{
						group = "General",
						build = function() return {

						--Setting('dev:webm'),
						--Setting('dev:mp4'),

						Setting('displayname'),
						Setting('playercolor'),
						--Setting('theme.charsheet'),
						Setting('diceequipped'),
						--Setting('dicecolor'),
						gui.Panel{
							classes = {"dicePreview"},
							bgimage = "#DicePreview",
							bgcolor = "white",
							width = 200,
							height = 200,
							halign = "right",
							hmargin = 20,
						},

						--Setting('dice:gravity'),
						--Setting('dice:velocity'),
						Setting('dev'),
						Setting('camerafollow'),
						Setting('edgepan'),
						Setting('dockscale'),

						SettingsSection("General"),

						CreateLanguageEditor(),

						CreateBetaBranchEditor(),

						Setting("codemod:safemode"),
						} end,
					},

					SettingGroup{
						group = "Graphics",
						build = function() return {

						Setting('vsync'),
						Setting('fps'),
						Setting('backgroundfps'),
						Setting('fullscreen'),
						Setting('hidef'),
						Setting('perf:postprocess'),
						Setting('perf:hdr'),
						Setting('perf:msaa'),
						Setting('perf:nocompress'),

						--Setting('perf:hideftextures'),
						Setting('perf:castshadows'),
                        Setting("graphics:uiblur"),

						SettingsSection("Graphics"),


						Setting("graphics:usegamma"),

						gui.Panel{
							classes = {cond(not dmhub.GetSettingValue("graphics:usegamma"), "collapsed")},
							width = "100%",
							height = "auto",
							flow = "vertical",
							monitor = "graphics:usegamma",
							events = {
								monitor = function(element)
									element:SetClass("collapsed", not dmhub.GetSettingValue("graphics:usegamma"))
								end,
							},

							gui.Panel{
								width = "100%",
								height = 200,
								bgimage = "panels/square.png",
								bgcolor = "black",
								flow = "horizontal",

								create = function(element)
									local children = {}
									for i=1,4 do
										children[#children+1] = gui.Panel{
											bgimage = "panels/square.png",
											bgcolor = "white",
											width = "15%",
											height = "80%",
											halign = "center",
											valign = "center",
											brightness = 0.001 * (10^(i-1)),
										}
									end

									element.children = children
								end,
							},

							gui.Label{
								halign = "center",
								width = "auto",
								height = "auto",
								fontSize = 16,
								vmargin = 4,
								text = "Adjust gamma until all four rectangles are visible.\nThe left-most rectangle should be barely visible.",
							},

							Setting("graphics:gamma"),
						},

                        gui.Button{
                            text = "Reset to Recommended Settings",
                            width = 320,
                            height = 30,
                            press = function(element)
                                dmhub.SetSettingValue("backgroundfps", false)
                                dmhub.SetSettingValue("perf:castshadows", true)
                                dmhub.SetSettingValue("perf:hdr", true)
                                local systemPower = dmhub.systemHardwareRating
                                if systemPower < 1 then
                                    dmhub.SetSettingValue("perf:postprocess", false)
                                    dmhub.SetSettingValue("perf:msaa", false)
                                    dmhub.SetSettingValue("blackbarsoff", false)
                                    dmhub.SetSettingValue("vsync", 0)
                                    dmhub.SetSettingValue("fps", 30)
                                else
                                    dmhub.SetSettingValue("perf:postprocess", true)
                                    dmhub.SetSettingValue("perf:msaa", true)
                                    dmhub.SetSettingValue("blackbarsoff", true)
                                    dmhub.SetSettingValue("vsync", 1)
                                    dmhub.SetSettingValue("fps", 60)
                                end

                                -- On Mac retina displays, default hidef off unless the
                                -- system is clearly powerful. Apple Silicon always
                                -- registers as integrated in systemPower, so use a more
                                -- permissive threshold than the main systemPower < 1 gate.
                                local pixelCount = dmhub.screenDimensions.x * dmhub.screenDimensions.y
                                if dmhub.platform == "macOS" and pixelCount > 3000000 and systemPower < 1.2 then
                                    dmhub.SetSettingValue("hidef", false)
                                else
                                    dmhub.SetSettingValue("hidef", true)
                                end
                            end,
                        },
						} end,
					},

					SettingGroup{
						group = "Audio",
						build = function() return {
						SettingsSection("Audio"),
						CreateGameWideMasterVolumeEditor(),
						CreateNormalizeLoudnessToggle(),
						} end,
					},


					SettingGroup{
						group = "Game",
						build = function() return {
						Setting("autorollall"),
						Setting("dicespeed"),

						Setting("selectedtokenvision"),
						Setting("monsterSaves:hideFromPlayers"),
						Setting("monsterSaves:quickRoll"),
						Setting("maxmoveduration"),
						Setting("movespeed"),
						Setting("constraintogrid"),
						Setting("fogcolor"),

						--Setting('perf:autoarchive'),

						SettingsSection("Game"),

						SettingsHeading("Lighting"),

						SettingsSection("GameLighting"),

						SettingsHeading("Rules Enforcement"),

						SettingsSection("GameStrictRules"),
						} end,
					},

					SettingGroup{
						group = "Map",
						build = function() return {
						Setting("map:playerviewable"),
						Setting("map:parallaxscale"),
						Setting("gridcolor"),

						SettingsSection("vision"),

						Setting("maplayout:tiletype"),
						Setting("maplayout:stagger"),
						Setting("maplayout:tilewidth"),
						Setting("maplayout:tileheight"),
						Setting("maplayout:hexslant"),

						Setting("editor:showpathfinding"),
						Setting("canlookup"),
						Setting("maxlookup"),

						SettingsSection("Map"),
						} end,
					},

					SettingGroup{
						group = "Editing",
						build = function()
							local children = CreateImageEditorChooser()
							for _,panel in ipairs(CreateLocalAssetsSection()) do
								children[#children+1] = panel
							end
							return children
						end,
					},

					keybinds,

					SettingGroup{
						group = "Account",
						build = function()

							local shopifyStatusLabel
							local shopifyConnectButton
							local shopifyDisconnectButton
							local shopifyConfirmPanel
							local shopifyConfirmButton
							local shopifyErrorLabel
							local shopifyRefreshButton
							local shopifyCancelWaitButton
							local RefreshShopifyStatus
							local ApplyShopifyStatusData
							local StartShopifyLinkPoll
							-- Bumped to retire any in-flight link-poll timers; every scheduled
							-- tick compares its captured generation against this before acting.
							local m_shopifyPollGeneration = 0
							local shopifyOrdersToggle
							local shopifyOrdersListPanel
							local shopifyOrdersLoaded = false
							local ordersShown = false
							local ordersCount = nil
							local FetchShopifyOrders
							local UpdateOrdersToggleText

							shopifyStatusLabel = gui.Label{
								fontSize = 14, width = "100%", maxWidth = 600, height = "auto",
								text = "Checking MCDM Shop...",
							}

							shopifyErrorLabel = gui.Label{
								classes = {"collapsed"},
								fontSize = 14, color = "#ff6666", width = "auto", height = "auto", text = "",
							}

							shopifyConnectButton = gui.Button{
								classes = {"collapsed"},
								width = 240, height = 40, fontSize = 20, halign = "left", vmargin = 4,
								text = "Connect MCDM Shop",
								click = function(element)
									-- Ask the backend for the Shopify authorize URL using the
									-- codex's own credentials (net.Post attaches them), then open
									-- the browser straight into Shopify's approve screen. The
									-- OAuth callback lands the browser on /link-store afterwards;
									-- the link poll flips this section to Connected on its own.
									shopifyStatusLabel.text = "Starting the connection..."
									shopifyConnectButton:SetClass("collapsed", true)
									shopifyRefreshButton:SetClass("collapsed", true)
									shopifyErrorLabel:SetClass("collapsed", true)
									net.Post{
										url = dmhub.cloudFunctionsBaseUrl .. "/shopifyAuthStart",
										data = { returnTo = "/link-store" },
										success = function(data)
											if not shopifyStatusLabel.valid then return end
											if type(data) == "table" and data.ok and type(data.authorizeUrl) == "string" then
												dmhub.OpenURL(data.authorizeUrl)
												StartShopifyLinkPoll()
											else
												shopifyStatusLabel.text = "Could not start the connection. Try again."
												shopifyConnectButton:SetClass("collapsed", false)
												shopifyRefreshButton:SetClass("collapsed", false)
											end
										end,
										error = function(msg)
											if not shopifyStatusLabel.valid then return end
											shopifyStatusLabel.text = "Could not start the connection. Try again."
											shopifyErrorLabel.text = "Error: " .. tostring(msg)
											shopifyErrorLabel:SetClass("collapsed", false)
											shopifyConnectButton:SetClass("collapsed", false)
											shopifyRefreshButton:SetClass("collapsed", false)
										end,
									}
								end,
							}

							shopifyCancelWaitButton = gui.Button{
								classes = {"collapsed"},
								width = 120, height = 30, fontSize = 14, halign = "left", vmargin = 4,
								text = "Cancel",
								click = function(element)
									RefreshShopifyStatus()
								end,
							}

							shopifyDisconnectButton = gui.Button{
								classes = {"collapsed"},
								width = 120, height = 30, fontSize = 14, halign = "left", vmargin = 4,
								text = "Disconnect",
								click = function(element)
									shopifyDisconnectButton:SetClass("collapsed", true)
									shopifyRefreshButton:SetClass("collapsed", true)
									shopifyConfirmPanel:SetClass("collapsed", false)
									shopifyErrorLabel:SetClass("collapsed", true)
								end,
							}

							shopifyConfirmButton = gui.Button{
								width = 180, height = 36, fontSize = 16, halign = "left", vmargin = 4,
								text = "Confirm Disconnect",
								click = function(element)
									element.text = "Disconnecting..."
									element.interactable = false
									shopifyErrorLabel:SetClass("collapsed", true)
									net.Post{
										url = dmhub.cloudFunctionsBaseUrl .. "/shopifyUnlink",
										data = {},
										success = function(data)
											element.text = "Confirm Disconnect"
											element.interactable = true
											shopifyConfirmPanel:SetClass("collapsed", true)
											RefreshShopifyStatus()
										end,
										error = function(msg)
											element.text = "Confirm Disconnect"
											element.interactable = true
											shopifyErrorLabel.text = "Disconnect failed: " .. tostring(msg)
											shopifyErrorLabel:SetClass("collapsed", false)
										end,
									}
								end,
							}

							shopifyConfirmPanel = gui.Panel{
								classes = {"collapsed"},
								flow = "vertical", width = "auto", height = "auto", vmargin = 4,
								gui.Label{
									fontSize = 14, maxWidth = 600, width = "100%", height = "auto",
									text = "Disconnect your MCDM Shop account?",
								},
								gui.Panel{
									flow = "horizontal", width = "auto", height = "auto",
									shopifyConfirmButton,
									gui.Button{
										width = 120, height = 36, fontSize = 16, halign = "left", vmargin = 4, hmargin = 8,
										text = "Cancel",
										click = function(element)
											shopifyConfirmPanel:SetClass("collapsed", true)
											shopifyDisconnectButton:SetClass("collapsed", false)
											shopifyRefreshButton:SetClass("collapsed", false)
											shopifyErrorLabel:SetClass("collapsed", true)
										end,
									},
								},
							}

							shopifyRefreshButton = gui.Button{
								classes = {"collapsed"},
								width = 120, height = 30, fontSize = 14, halign = "left", vmargin = 4,
								text = "Refresh",
								click = function(element)
									RefreshShopifyStatus()
								end,
							}

							-- Render a /shopifyStatus response into the section UI. Shared by
							-- the one-shot refresh and the post-Connect polling loop.
							ApplyShopifyStatusData = function(data)
								shopifyRefreshButton:SetClass("collapsed", false)
								if type(data) ~= "table" or not data.ok then
									shopifyStatusLabel.text = "Could not load MCDM Shop status."
									return
								end
								if data.linked then
									shopifyStatusLabel.text = (data.email ~= nil and data.email ~= "")
										and string.format("MCDM Shop: Connected as %s", data.email)
										or "MCDM Shop: Connected"
									shopifyDisconnectButton:SetClass("collapsed", false)
									shopifyOrdersToggle:SetClass("collapsed", false)
								else
									shopifyStatusLabel.text = "Connect your MCDM Shop account to link your purchases."
									shopifyConnectButton:SetClass("collapsed", false)
									shopifyOrdersToggle:SetClass("collapsed", true)
									shopifyOrdersListPanel:SetClass("collapsed", true)
									ordersShown = false
									shopifyOrdersLoaded = false
									ordersCount = nil
									UpdateOrdersToggleText()
								end
							end

							-- Fetch link status from the backend (Lua cannot read /shopLinks directly).
							-- Called on panel create, on Refresh, on Cancel while waiting, and
							-- after a successful disconnect. Also retires any active link poll.
							RefreshShopifyStatus = function()
								m_shopifyPollGeneration = m_shopifyPollGeneration + 1
								shopifyStatusLabel.text = "Checking MCDM Shop..."
								shopifyConnectButton:SetClass("collapsed", true)
								shopifyDisconnectButton:SetClass("collapsed", true)
								shopifyConfirmPanel:SetClass("collapsed", true)
								shopifyRefreshButton:SetClass("collapsed", true)
								shopifyErrorLabel:SetClass("collapsed", true)
								shopifyCancelWaitButton:SetClass("collapsed", true)
								net.Post{
									url = dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus",
									data = {},
									success = function(data)
										ApplyShopifyStatusData(data)
									end,
									error = function(msg)
										shopifyRefreshButton:SetClass("collapsed", false)
										shopifyStatusLabel.text = "Could not load MCDM Shop status."
										shopifyErrorLabel.text = "Error: " .. tostring(msg)
										shopifyErrorLabel:SetClass("collapsed", false)
									end,
								}
							end

							-- After Connect opens the browser, poll link status so the section
							-- flips to Connected on its own when the user finishes the web flow.
							-- Transient request errors do not end the wait; only success, Cancel,
							-- another refresh, or the deadline do.
							StartShopifyLinkPoll = function()
								m_shopifyPollGeneration = m_shopifyPollGeneration + 1
								local generation = m_shopifyPollGeneration
								local deadline = dmhub.Time() + 180

								shopifyStatusLabel.text = "Waiting for you to finish connecting in your browser..."
								shopifyConnectButton:SetClass("collapsed", true)
								shopifyRefreshButton:SetClass("collapsed", true)
								shopifyErrorLabel:SetClass("collapsed", true)
								shopifyCancelWaitButton:SetClass("collapsed", false)

								local function PollExpired()
									-- The settings sheet may have been destroyed while a tick was
									-- scheduled; a dead panel is not safe to touch at all.
									return mod.unloaded or generation ~= m_shopifyPollGeneration or (not shopifyStatusLabel.valid)
								end

								local function FinishTimedOut()
									m_shopifyPollGeneration = m_shopifyPollGeneration + 1
									shopifyCancelWaitButton:SetClass("collapsed", true)
									shopifyStatusLabel.text = "Connection timed out. Try again, or click Refresh after finishing in your browser."
									shopifyConnectButton:SetClass("collapsed", false)
									shopifyRefreshButton:SetClass("collapsed", false)
								end

								local Tick
								Tick = function()
									if PollExpired() then return end
									net.Post{
										url = dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus",
										data = {},
										success = function(data)
											if PollExpired() then return end
											if type(data) == "table" and data.ok and data.linked then
												m_shopifyPollGeneration = m_shopifyPollGeneration + 1
												shopifyCancelWaitButton:SetClass("collapsed", true)
												ApplyShopifyStatusData(data)
												return
											end
											if dmhub.Time() > deadline then
												FinishTimedOut()
												return
											end
											dmhub.Schedule(4, Tick)
										end,
										error = function(msg)
											if PollExpired() then return end
											if dmhub.Time() > deadline then
												FinishTimedOut()
												return
											end
											dmhub.Schedule(4, Tick)
										end,
									}
								end

								Tick()
							end

							UpdateOrdersToggleText = function()
								if ordersShown then
									shopifyOrdersToggle.text = "Hide purchases"
								elseif ordersCount ~= nil then
									shopifyOrdersToggle.text = string.format("Show purchases (%d)", ordersCount)
								else
									shopifyOrdersToggle.text = "Show purchases"
								end
							end

							local function BuildOrderRow(o)
								local detailChildren = {}
								if #o.lineItems == 0 then
									detailChildren[#detailChildren+1] = gui.Label{
										fontSize = 12, color = "#cfcabb", width = "100%", height = "auto", text = "No item detail",
									}
								else
									for _, li in ipairs(o.lineItems) do
										detailChildren[#detailChildren+1] = gui.Label{
											fontSize = 12, color = "#cfcabb", width = "100%", height = "auto",
											text = string.format("%s  x%d", li.title, li.quantity),
										}
									end
								end
								if o.statusPageUrl ~= nil then
									detailChildren[#detailChildren+1] = gui.Label{
										fontSize = 12, color = "#c8a45a", width = "auto", height = "auto", vmargin = 4,
										text = "View receipt ->",
										press = function(element)
											dmhub.OpenURL(o.statusPageUrl)
										end,
									}
								end

								local detail = gui.Panel{
									classes = {"collapsed"},
									flow = "vertical", width = "100%", height = "auto", vmargin = 2, hpad = 8, borderBox = true,
									children = detailChildren,
								}

								local header = string.format("%s%s%s   [%s]",
									o.name,
									(o.date ~= "" and (" - " .. o.date)) or "",
									(o.total ~= "" and ("   " .. o.total)) or "",
									o.statusLabel)

								local row = gui.Button{
									width = "100%", height = "auto", halign = "left", fontSize = 13, vmargin = 2,
									text = header,
									click = function(element)
										detail:SetClass("collapsed", not detail:HasClass("collapsed"))
									end,
								}

								return gui.Panel{
									flow = "vertical", width = "100%", height = "auto",
									row, detail,
								}
							end

							FetchShopifyOrders = function()
								shopifyOrdersListPanel.children = {
									gui.Label{ fontSize = 13, color = "#8a8a8a", width = "auto", height = "auto", text = "Loading your purchases..." },
								}
								net.Post{
									url = dmhub.cloudFunctionsBaseUrl .. "/shopifyOrders",
									data = {},
									success = function(data)
										shopifyOrdersLoaded = true
										if type(data) ~= "table" or not data.ok or type(data.orders) ~= "table" then
											shopifyOrdersLoaded = false
											shopifyOrdersListPanel.children = {
												gui.Label{ fontSize = 13, color = "#d96363", width = "100%", height = "auto", text = "Couldn't load your purchases." },
											}
											return
										end
										local orders = NormalizeOrders(data.orders)
										ordersCount = #orders
										UpdateOrdersToggleText()
										if #orders == 0 then
											shopifyOrdersListPanel.children = {
												gui.Label{ fontSize = 13, color = "#8a8a8a", width = "auto", height = "auto", text = "No purchases yet." },
											}
											return
										end
										local rows = {}
										for _, o in ipairs(orders) do
											rows[#rows+1] = BuildOrderRow(o)
										end
										shopifyOrdersListPanel.children = rows
									end,
									error = function(msg)
										shopifyOrdersLoaded = false
										shopifyOrdersListPanel.children = {
											gui.Label{ fontSize = 13, color = "#d96363", width = "100%", height = "auto",
												text = "Couldn't load your purchases: " .. tostring(msg) },
											gui.Button{ width = 120, height = 30, fontSize = 14, halign = "left", vmargin = 4, text = "Retry",
												click = function(element) FetchShopifyOrders() end },
										}
									end,
								}
							end

							shopifyOrdersListPanel = gui.Panel{
								classes = {"collapsed"},
								flow = "vertical", width = "100%", height = "auto", vmargin = 2,
							}

							-- minWidth rather than a fixed width: matches the Disconnect and
							-- Refresh buttons at rest, but the label can grow so the counted
							-- "Show purchases (N)" state never clips.
							shopifyOrdersToggle = gui.Button{
								classes = {"collapsed"},
								width = "auto", minWidth = 120, hpad = 8, borderBox = true, height = 30, fontSize = 14, halign = "left", vmargin = 4,
								text = "Show purchases",
								click = function(element)
									ordersShown = not ordersShown
									shopifyOrdersListPanel:SetClass("collapsed", not ordersShown)
									UpdateOrdersToggleText()
									if ordersShown and not shopifyOrdersLoaded then
										FetchShopifyOrders()
									end
								end,
							}

							--The Patreon account link and the email confirmation are part
							--of the in-development Patreon feature, gated behind the
							--hidden "patreonsub" preference. Built only when it is on, so
							--the panels' cloud-function status polling never runs for
							--users who cannot see them.
							local patreonSectionChildren = {}
							if dmhub.GetSettingValue("patreonsub") then
								patreonSectionChildren = {
									CreatePatreonAccountPanel(),

									gui.Panel{
										width = 16,
										height = 16,
									},

									CreateEmailConfirmationPanel(),

									gui.Panel{
										width = 16,
										height = 16,
									},
								}
							end

							local children = {

						gui.Panel{
							flow = "vertical",
							width = "100%",
							height = "auto",
							gui.Label{
								text = string.format("Logged in as %s", dmhub.userDisplayName),
								width = "auto",
								height = "auto",
							},

							gui.Panel{
								width = 16,
								height = 16,
							},

							gui.Panel{
								flow = "vertical",
								width = "100%",
								height = "auto",
								children = patreonSectionChildren,
							},

							gui.Label{
								classes = {"sizeL", "bold"},
								width = "auto",
								height = "auto",
								text = "Bandwidth Usage",
							},

							gui.Label{
								text = string.format("You have %dMB of your %dMB bandwidth upload quota for the month remaining.", math.floor(dmhub.uploadQuotaRemaining/(1024*1024)), math.floor(dmhub.uploadQuotaTotal/(1024*1024))),
								maxWidth = 600,
								width = "auto",
								height = "auto",
							},

                            gui.Label{
                                -- styles = Styles.Default,
                                text = "See our <color=#00FFFF><link=https://www.mcdmproductions.com/draw-steel-codex-terms-of-service>Terms of Service</link></color> and <color=#00FFFF><link=https://www.mcdmproductions.com/draw-steel-codex-privacy-policy>Privacy Policy</link></color>",
                                markdown = true,
                                maxWidth = 600,
                                fontSize = 14,
                                links = true,
                                width = "auto",
                                height = "auto",
                                press = function(element)
                                    if element.linkHovered ~= nil then
                                        dmhub.OpenURL(element.linkHovered)
                                    end
                                end,
                            },

							gui.Panel{
								vmargin = 16,
								classes = {"collapsed"}, --{cond(not dmhub.hasStoreAccess, "collapsed")},
								flow = "vertical",
								width = "100%",
								gui.Label{
									bold = true,
									fontSize = 16,
									width = "auto",
									height = "auto",
									text = "Subscription",
								},
								gui.Label{
									width = "100%",
									height = "auto",
									fontSize = 14,
									create = function(element)
										element:FireEvent("think")
									end,
									thinkTime = 0.1,
									think = function(element)
										if dmhub.subscriptionTier == 0 then
											element.text = "By subscribing to DMHub, you can gain more bandwidth, AI tokens, and other benefits."
										elseif dmhub.subscriptionTier == 2 then
											element.text = "Subscriber Status: DMHub Premium"
										elseif dmhub.subscriptionTier == 3 then
											element.text = "Subscriber Status: DMHub Premium Plus"
										else
											element.text = ""
										end
									end,
								},

								gui.Button{
									width = 240,
									height = 40,
									fontSize = 20,
									halign = "left",
									text = cond(dmhub.subscriptionTier == 0, "Subscribe", "Manage Subscription"),
									click = function(element)
										dialog.sheet = CreateSubscriptionScreen{
											dialog = dialog,
										}
									end,

								},
							},

							gui.Panel{
								vmargin = 16,
								classes = { cond(not g_devStorePreviewSetting:Get(), "collapsed") },
								flow = "vertical",
								width = "100%",
								height = "auto",

								create = function(element)
									RefreshShopifyStatus()
								end,

								gui.Label{
									bold = true, fontSize = 16, width = "auto", height = "auto",
									text = "MCDM Shop",
								},
								shopifyStatusLabel,
								shopifyConnectButton,
								shopifyDisconnectButton,
								shopifyCancelWaitButton,
								shopifyConfirmPanel,
								shopifyRefreshButton,
								shopifyErrorLabel,
								shopifyOrdersToggle,
								shopifyOrdersListPanel,
							},
						},
						}

						--Creator Organizations lives at the bottom of the Account tab.
						for _,panel in ipairs(CreateCreatorOrganizationsSection()) do
							children[#children+1] = panel
						end

						return children
					end,
					},
				}
			},

			gui.Panel{
				classes = {"collapsed"},
				vscroll = true,
				width = "60%",
				height = "75%",
				flow = "vertical",
				halign = "center",
				valign = "center",

				search = function(element, text, entries)
					element:SetClass("collapsed", text == nil or text == "")
					if element:HasClass("collapsed") then
						return
					end

					local children = {}
					for _,entry in ipairs(entries) do
						local existing = m_searchPanels[entry.id]
						if entry.shown then

							local p = existing or entry.create()
							p:SetClass("collapsed", false)
							children[#children+1] = p

							m_searchPanels[entry.id] = p
						else
							if existing ~= nil then
								existing:SetClass("collapsed", true)
								children[#children+1] = existing
							end
						end
					end

					element.children = children
				end,
			}
		}
	}

	m_screenRoot = gui.Panel{
		width = "100%",
		height = "100%",
		settingsDialog,
	}

	--In-game, the C# host for this sheet (PlayerSettingsScreenLua) lives in
	--the topmost UI canvas, which renders above the game hud's canvas --
	--including the modal layer used by gui.ShowModal, so modals could never
	--appear above the settings dialog. Instead, host the settings UI inside
	--the game hud's main dialog panel: the modal panel is a later sibling of
	--it (and re-promotes itself via SetAsLastSibling on every show), so
	--modals render on top. The C# container gets a placeholder sheet that
	--forwards its lifecycle: whenever the container destroys the placeholder
	--(settings toggled or closed, or the sheet replaced by the subscription
	--screen), the hosted panel is destroyed with it. The placeholder must
	--stay a sheet root; if we parented the real sheet into the hud, the
	--container's DestroySheet would tear it down without unlinking it from
	--its hud parent, leaving a stale dead child that corrupts the next open.
	--
	--This hud-hosting is only correct in a real game, where the game hud is the
	--topmost thing on screen. On the titlescreen/lobby the game hud's canvas is
	--BEHIND the titlescreen, so hosting there buries the settings dialog out of
	--sight. There we keep the original behavior of assigning the sheet directly
	--to the C# container, whose topmost canvas renders above the titlescreen and
	--uses ordinary screen coordinates (the titlescreen root itself is wider than
	--the screen, so parenting into it would mis-centre the dialog).
	local hudDialogPanel = nil
	if dmhub.inGame and not dmhub.isLobbyGame then
		local ghud = rawget(_G, "gamehud")
		if ghud ~= nil then
			local candidate = ghud:try_get("mainDialogPanel")
			if candidate ~= nil and candidate.valid then
				hudDialogPanel = candidate
			end
		end
	end

	if hudDialogPanel ~= nil then
		local screenRoot = m_screenRoot
		hudDialogPanel:AddChild(screenRoot)
		dialog.sheet = gui.Panel{
			width = 1,
			height = 1,
			destroy = function(element)
				if screenRoot ~= nil and screenRoot.valid then
					screenRoot:DestroySelf()
				end
			end,
		}
	else
		dialog.sheet = m_screenRoot
	end

	settingsDialog:PulseClass("fadein")
end

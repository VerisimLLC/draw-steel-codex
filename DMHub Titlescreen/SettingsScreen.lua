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

-- Gates the codex MCDM Shopify Store UI behind the dev:storepreview testing flag.
-- Settings are keyed by id, so re-declaring "dev:storepreview" here gives read access
-- to the same persisted preference the title bar uses (CodexTitleBar.lua). When off,
-- the Shopify account section is hidden.
local g_devStorePreviewSetting = setting{
	id = "dev:storepreview",
	default = false,
	storage = "preference",
}

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
--replaced by a local directory tree of YAML files (see LocalAssetDirectory in
--the engine and the /localassets macro). Returns a list of panels for the
--Editing settings tab, or an empty list when the feature does not apply
--(not in dev mode, or not in a real game).
local function CreateLocalAssetsSection()
	if dmhub.isLobbyGame or (not dmhub.GetSettingValue("dev")) then
		return {}
	end

	local function CurrentDir()
		local dir = dmhub.GetSettingValue("localassets:dir")
		if dir == nil then
			return ""
		end
		return dir
	end

	local function StatusText()
		local status = dmhub.LocalAssetsStatus()
		if status ~= nil and status.active and status.directory ~= nil then
			return string.format("Active: this game's assets are loading from %s.", status.directory)
		elseif CurrentDir() ~= "" then
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
		multimonitor = {"localassets:dir"},
		events = {
			monitor = function(element)
				element.text = StatusText()
			end,
		},
	}

	local dirInput = gui.Input{
		classes = {"form"},
		width = 300,
		halign = "right",
		valign = "center",
		text = CurrentDir(),
		multimonitor = {"localassets:dir"},
		events = {
			change = function(element)
				dmhub.SetSettingValue("localassets:dir", element.text)
			end,
			monitor = function(element)
				element.text = CurrentDir()
			end,
		},
	}

	local browseButton = gui.Button{
		width = 110,
		height = 32,
		fontSize = 16,
		halign = "left",
		valign = "center",
		text = "Browse...",
		click = function(element)
			dmhub.OpenFolderDialog{
				id = "localassets",
				extensions = {"yaml"},
				prompt = "Select Local Assets Directory",
				open = function(folderPath, filePaths)
					dmhub.SetSettingValue("localassets:dir", folderPath)
				end,
			}
		end,
	}

	local function DoExport()
		local dir = CurrentDir()
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

	local populateButton = gui.Button{
		width = 200,
		height = 32,
		fontSize = 16,
		halign = "left",
		valign = "center",
		text = "Populate Directory",
		click = function(element)
			local dir = CurrentDir()
			if dir == "" then
				gui.ModalMessage{
					title = "Local Assets",
					message = "Choose a directory first.",
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

	return {
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
			text = "Point this game at a local directory of YAML asset files. When set, the game's cloud assets are ignored: assets load from the directory, edits you make in-game are written back to it as YAML, and external changes to the files hot-reload into the game. Takes effect when the game loads. If the directory does not exist, it is created and populated from the game's assets automatically on next load. Use Populate Directory to fill it immediately.",
		},

		gui.Panel{
			classes = {"formRow"},
			width = "90%",
			halign = "center",
			gui.Label{
				classes = {"form"},
				width = "40%",
				text = "Directory:",
			},
			dirInput,
		},

		gui.Panel{
			flow = "horizontal",
			width = "90%",
			height = "auto",
			halign = "center",
			vmargin = 4,
			browseButton,
			gui.Panel{ width = 16, height = 1 },
			populateButton,
		},

		statusLabel,
	}
end

local g_imageEditorSetupDialog = nil
local function ShowImageEditorSetupDialog(onProceed)
	local function closeDialog()
		if g_imageEditorSetupDialog ~= nil and g_imageEditorSetupDialog.valid then
			g_imageEditorSetupDialog:DestroySelf()
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
		-- Gate the email-update interface behind the same dev:storepreview
		-- preference that controls whether the shop is available (the
		-- Shop/Inventory title-bar menu and the MCDM Shopify Store section
		-- below). When the store isn't live, the email section stays hidden.
		classes = { cond(not g_devStorePreviewSetting:Get(), "collapsed") },
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
							local RefreshShopifyStatus
							local shopifyOrdersToggle
							local shopifyOrdersListPanel
							local shopifyOrdersLoaded = false
							local ordersShown = false
							local ordersCount = nil
							local FetchShopifyOrders
							local UpdateOrdersToggleText

							shopifyStatusLabel = gui.Label{
								fontSize = 14, width = "100%", maxWidth = 600, height = "auto",
								text = "Checking MCDM Shopify Store...",
							}

							shopifyErrorLabel = gui.Label{
								classes = {"collapsed"},
								fontSize = 14, color = "#ff6666", width = "auto", height = "auto", text = "",
							}

							shopifyConnectButton = gui.Button{
								classes = {"collapsed"},
								width = 240, height = 40, fontSize = 20, halign = "left", vmargin = 4,
								text = "Connect MCDM Shopify Store",
								click = function(element)
									dmhub.OpenURL("https://draw-steel-codex.com/more/account")
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
									text = "Disconnect your MCDM Shopify Store account?",
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

							-- Fetch link status from the backend (Lua cannot read /shopLinks directly).
							-- Called on panel create, on Refresh, and after a successful disconnect.
							RefreshShopifyStatus = function()
								shopifyStatusLabel.text = "Checking MCDM Shopify Store..."
								shopifyConnectButton:SetClass("collapsed", true)
								shopifyDisconnectButton:SetClass("collapsed", true)
								shopifyConfirmPanel:SetClass("collapsed", true)
								shopifyRefreshButton:SetClass("collapsed", true)
								shopifyErrorLabel:SetClass("collapsed", true)
								net.Post{
									url = dmhub.cloudFunctionsBaseUrl .. "/shopifyStatus",
									data = {},
									success = function(data)
										shopifyRefreshButton:SetClass("collapsed", false)
										if type(data) ~= "table" or not data.ok then
											shopifyStatusLabel.text = "Could not load MCDM Shopify Store status."
											return
										end
										if data.linked then
											shopifyStatusLabel.text = (data.email ~= nil and data.email ~= "")
												and string.format("MCDM Shopify Store: Connected as %s", data.email)
												or "MCDM Shopify Store: Connected"
											shopifyDisconnectButton:SetClass("collapsed", false)
											shopifyOrdersToggle:SetClass("collapsed", false)
										else
											shopifyStatusLabel.text = "Connect your MCDM Shopify Store account to link your purchases."
											shopifyConnectButton:SetClass("collapsed", false)
											shopifyOrdersToggle:SetClass("collapsed", true)
											shopifyOrdersListPanel:SetClass("collapsed", true)
											ordersShown = false
											shopifyOrdersLoaded = false
											ordersCount = nil
											UpdateOrdersToggleText()
										end
									end,
									error = function(msg)
										shopifyRefreshButton:SetClass("collapsed", false)
										shopifyStatusLabel.text = "Could not load MCDM Shopify Store status."
										shopifyErrorLabel.text = "Error: " .. tostring(msg)
										shopifyErrorLabel:SetClass("collapsed", false)
									end,
								}
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
										text = "View receipt on Shopify ->",
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

							shopifyOrdersToggle = gui.Button{
								classes = {"collapsed"},
								width = "auto", height = 26, fontSize = 14, halign = "left", vmargin = 4,
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

							return {

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

							CreateEmailConfirmationPanel(),

							gui.Panel{
								width = 16,
								height = 16,
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
									text = "MCDM Shopify Store",
								},
								shopifyStatusLabel,
								shopifyConnectButton,
								shopifyDisconnectButton,
								shopifyConfirmPanel,
								shopifyRefreshButton,
								shopifyErrorLabel,
								shopifyOrdersToggle,
								shopifyOrdersListPanel,
							},
						},
						} end,
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

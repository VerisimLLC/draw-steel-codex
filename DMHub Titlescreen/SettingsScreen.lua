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

--A slider that controls the game-wide master volume -- the same value as the
--master slider in the Audio panel (audio.masterVolume / gameDetails.audio).
--Only shown to the Director, and only while in a game, since the value lives
--on the game's shared audio state rather than a per-machine preference.
local CreateGameWideMasterVolumeEditor = function()
	if (not dmhub.inGame) or (not dmhub.isDM) then
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
		width = 540,
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

dmhub.PromptImageEditorSetup = function(floorid, objid)
	ShowImageEditorSetupDialog(function()
		dmhub.StartLiveEditForObject(floorid, objid)
	end)
end

function CreateSettingsScreen(dialog, args)
    args = args or {}

	dmhub.Debug('EXEC SETTING SCREEN')

	local m_selectedTab = "General"

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
				dialog.sheet:FireEventTree("refreshTab")
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

		width = 1024,
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
							dialog.sheet:FireEventTree("forceBuild")
						end
						local matches = {}
						dialog.sheet:FireEventTree("search", element.text, matches)
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
						group = "Editing",
						build = function()
							return CreateImageEditorChooser()
						end,
					},

					keybinds,

					SettingGroup{
						group = "Account",
						build = function() return {

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
							}
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

	dialog.sheet = gui.Panel{
		width = "100%",
		height = "100%",
		settingsDialog,
	}

	settingsDialog:PulseClass("fadein")
end

local mod = dmhub.GetModLoading()

local CreateBetaBranchEditor = function()
	local branch = dmhub.betaBranch
	if branch == nil then
		return nil
	end

	local changesLabel = 
	gui.Label{
		classes = {"collapsed-anim"},
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
			width = "100%",
			height = "48",
			flow = "horizontal",
			gui.Label{
				text = "DMHub Version:",
				halign = "left",
				valign = "center",
				fontSize = 18,
				width = "auto",
				height = "auto",
			},
			gui.Dropdown{
				halign = "right",
				valign = "center",
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
					changesLabel:SetClass("collapsed-anim", false)
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
			width = "100%",
			height = "48",
			flow = "horizontal",
			gui.Label{
				text = "Language:",
				halign = "left",
				valign = "center",
				fontSize = 18,
				width = "auto",
				height = "auto",
			},
			gui.Dropdown{
				halign = "right",
				valign = "center",
				idChosen = dmhub.GetSettingValue("lang"),
				options = options,
				change = function(element)
					dmhub.SetSettingValue("lang", element.idChosen)
				end,
			},
		},
	}
end

--called from DMHub (from DialogLua, reference to script is a Unity property.)
function CreateSettingsScreen(dialog, args)
    args = args or {}

	dmhub.Debug('EXEC SETTING SCREEN')

	local m_selectedTab = "General"

	local SettingGroup = function(options)
		
		local group = options.group
		options.group = nil

		local args = {
			classes = {cond(m_selectedTab ~= group, "collapsed")},			
			flow = "vertical",
			width = "auto",
			height = "auto",
			refreshTab = function(element)
				element:SetClass("collapsed", m_selectedTab ~= group)
			end,
		}

		for k,v in pairs(options) do
			args[k] = v
		end


		return gui.Panel(args)
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
			bgimage = "panels/square.png",
			classes = {"advantage-element", cond(args.text == m_selectedTab, "selected")},
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
		printf("CREATE KEYBINDS SETTINGS")
		keybinds = SettingGroup{
			group = "Shortcuts",
			CreateKeybindsSettingsPanel(),
		}
		keybindsTab = CreateTab{
			text = "Shortcuts",
		}
	end

	local settingsDialog = gui.Panel{
		id = "settingsDialog",
		classes = {"framedPanel"},

		width = 1024,
		height = 900,
		halign = "center",
		valign = "center",
		flow = "vertical",
        blurBackground = true,

		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
		end,
		
		styles = {
			Styles.Panel,
			Styles.Default,

			{
				selectors = {"label"},
				fontFace = "dubai",
			},
			{
				selectors = {"~dm", "dmonly"},
				collapsed = 1,
			},
		},

		children = {
			gui.PrettyButton{
				text = 'Close',
				floating = true,
				escapeActivates = true,
				style = {
					bgcolor = 'white',
					vmargin = 20,
					hmargin = 20,
					width = 200,
					height = 60,
					halign = 'right',
					valign = 'bottom',
				},

				events = {
					click = function()
						dialog.sheet = nil

						if dmhub.settingsChangesRequireRestart then
							dmhub.QuitApplication()
						end
					end
				}
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
				text = 'Settings',
				vmargin = 16,
				style = {
					color = 'white',
					valign = 'top',
					halign = 'center',
					width = 'auto',
					height = 'auto',
				}
			},


			gui.Panel{
				width = "auto",
				height = "auto",
				halign = "center",
				flow = "vertical",
				gui.Input{
					placeholderText = "Search Settings...",
					editlag = 0.25,
					width = 240,
					height = 20,
					fontSize = 16,
					bmargin = 6,
					borderWidth = 2,
					borderColor = Styles.textColor,
					bgimage = "panels/square.png",
					halign = "left",
					characterLimit = 30,
                    create = function(element)
                        if args.search then
                            element.text = args.search
                            element:FireEvent("edit")
                        end
                    end,
					edit = function(element)
						local matches = {}
						dialog.sheet:FireEventTree("search", element.text, matches)
					end,
					gui.Panel{
						bgimage = "icons/icon_tool/icon_tool_42.png",
						bgcolor = Styles.textColor,
						width = "100% height",
						height = "100%",
						halign = "right",
						vmargin = 0,
						floating = true,
					},
				},
				gui.Panel{
					classes = {'advantage-bar'},
					width = "auto",
					styles = {
						Styles.AdvantageBar,
					},

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
					keybindsTab,
					CreateTab{
						text = "Account",
					},
				},
			},

			gui.Panel{
				vscroll = true,
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
					
						--Setting('dev:webm'),
						--Setting('dev:mp4'),

						Setting('displayname'),
						Setting('playercolor'),
						--Setting('theme.charsheet'),
						Setting('diceequipped'),
						--Setting('dicecolor'),
						gui.Panel{
							bgimage = '#DicePreview',
							style = {
								bgcolor = 'white',
								width = 200,
								height = 200,
								halign = 'right',
								hmargin = 20,
							}
						},

						--Setting('dice:gravity'),
						--Setting('dice:velocity'),
						Setting('dev'),
						Setting('camerafollow'),
						Setting('edgepan'),

						SettingsSection("General"),

						CreateLanguageEditor(),

						CreateBetaBranchEditor(),

						Setting("codemod:safemode"),
					},

					SettingGroup{
						group = "Graphics",

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
						Setting('perf:hidefdice'),
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
                                dmhub.SetSettingValue("perf:hdr", true)
                                dmhub.SetSettingValue("perf:hidefdice", true)
                                dmhub.SetSettingValue("perf:castshadows", true)
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
                            end,
                        },
					},

					SettingGroup{
						group = "Audio",
						SettingsSection("Audio"),
					},


					SettingGroup{
						group = "Game",
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
					},

					keybinds,

					SettingGroup{
						group = "Account",
						
						gui.Panel{
							flow = "vertical",
							width = "100%",
							height = "auto",
							gui.Label{
								fontSize = 16,
								text = string.format("Logged in as %s", dmhub.userEmail),
								width = "auto",
								height = "auto",
							},

							gui.Panel{
								width = 16,
								height = 16,
							},

							gui.Label{
								bold = true,
								fontSize = 16,
								width = "auto",
								height = "auto",
								text = "Bandwidth Usage",
							},

							gui.Label{
								text = string.format("You have %dMB of your %dMB bandwidth upload quota for the month remaining.", math.floor(dmhub.uploadQuotaRemaining/(1024*1024)), math.floor(dmhub.uploadQuotaTotal/(1024*1024))),
								maxWidth = 600,
								fontSize = 14,
								width = "auto",
								height = "auto",
							},

							gui.Label{
								text = "Support us on Patreon for more bandwidth and other benefits",
								classes = {"link", cond(dmhub.hasStoreAccess, "collapsed")},
								fontSize = 14,
								width = "auto",
								height = "auto",
								click = function(element)
									dmhub.OpenRegisteredURL("Patreon")
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
					},
				}
			},

			gui.Panel{
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

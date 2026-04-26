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

local CreateSessionsPanel

DockablePanel.Register{
	name = "User Status",
	icon = "icons/standard/Icon_App_UserStatus.png",
	vscroll = true,
    dmonly = false,
	minHeight = 80,
	content = function()
		track("panel_open", {
			panel = "User Status",
			dailyLimit = 30,
		})
		return CreateSessionsPanel()
	end,
}

local CreateUserSessionPanel

CreateSessionsPanel = function()

	local sessionPanels = {}

	local addButton = gui.AddButton{
		halign = "right",
		valign = "bottom",
		margin = 0,
		click = function(element)


			local inviteDialog
			inviteDialog = gui.Panel{
				classes = {'framedPanel'},
				width = 600,
				height = 400,
				styles = {
					Styles.Panel,
				},

				gui.Label{
					fontSize = 24,
					width = "auto",
					height = "auto",
					floating = true,
					bold = true,
					text = "Invite Players",
					halign = "center",
					valign = "top",
					vmargin = 8,
				},

				gui.CloseButton{
					halign = "right",
					valign = "top",
					escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
					click = function(element)
						gui.CloseModal()
					end,
				},

				gui.Panel{
					halign = "center",
					valign = "center",
					flow = "horizontal",
					width = "auto",
					height = "auto",

					gui.Label{
						fontSize = 14,
						text = "Invite Code:",
						width = 100,
						textAlignment = "left",
					},

					gui.Panel{
						halign = "center",
						width = "auto",
						height = "auto",
						flow = "horizontal",

						click = function(element)
							local tooltip = gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
							dmhub.CopyToClipboard(dmhub.gameid)
						end,

						gui.Label{
							fontFace = "cambria",
							fontSize = 18,
							width = "auto",
							height = "auto",
							halign = "center",
							valign = "center",
							vmargin = 20,
							text = dmhub.gameid,
						},

						gui.Panel{
							bgimage = "icons/icon_app/icon_app_108.png",
							bgcolor = Styles.textColor,
							styles = {
								{
									classes = "parent:hover",
									brightness = 1.8,
								}
							},

							width = "100% height",
							height = 24,
							valign = "center",
							hmargin = 4,
						},
					}
				},
			}

			gui.ShowModal(inviteDialog)
		end,
		tooltip = "Invite players",
	}

	return gui.Panel{
		style = {
			width = '100%',
			height = 'auto',
			halign = 'left',
			valign = 'top',
			flow = 'vertical',
		},

        styles = {
            {
                selectors = {"statusIconDisplay"},
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                cornerRadius = 0,
                gradient = {
                    point_a = {x = 0, y = 0},
                    point_b = {x = 1, y = 0.5},
                    stops = {
                        {
                            position = 0,
                            color = "#444444",
                        },
                        {
                            position = 1,
                            color = "#ffffff",
                        },
                    },
                }
            },
            {
                selectors = {"statusIcon"},
                width = 32,
                height = 32,
                valign = 'center',
                cornerRadius = 0,
                bgimage = 'panels/square.png',
                bgcolor = "black",
                borderColor = Styles.textColor,
                borderWidth = 1,
            },
            {
                selectors = {"statusIconDisplay", "afk"},
                bgcolor = "yellow",
            },
            {
                selectors = {"statusIconDisplay", "online"},
                bgcolor = "green",
            },
            {
                selectors = {"statusIconDisplay", "offline"},
                bgcolor = "#555555",
            },
        },

		addButton,

		monitorGame = '/usersToSessions',

		events = {
			refreshGame = function(element)

				local newPanels = {}

				local users = dmhub.users
				for i,userid in ipairs(users) do
					newPanels[userid] = sessionPanels[userid] or CreateUserSessionPanel(userid)
				end

				sessionPanels = newPanels

				--make sure any DM accounts go on top.
				local newChildren = {}
				local newPlayers = {}
				for k,panel in pairs(sessionPanels) do
					local sessionInfo = dmhub.GetSessionInfo(k)
					if sessionInfo ~= nil and dmhub.IsUserDM(k) then
						newChildren[#newChildren+1] = panel
					else
						newPlayers[#newPlayers+1] = panel
					end
				end

				for i,child in ipairs(newPlayers) do
					newChildren[#newChildren+1] = child
				end

				newChildren[#newChildren+1] = addButton

				element.children = newChildren
			end,
		}
	}

end

CreateUserSessionPanel = function(userid)
	local statusIcon = gui.Panel{
        classes = {"statusIcon"},
		interactable = false,
        rotate = 45,
        x = -4,

        gui.Panel{
            classes = {"statusIconDisplay"},
        },
	}

	local tokenAvatar = gui.Panel{
		interactable = false,
		selfStyle = {
			color = "white",
			bgcolor = 'white',
			width = 16,
			height = 16,
			valign = 'center',
            hmargin = 4,
			textWrap = false,
		}
	}

	local nameLabel = gui.Label{
		text = 'USER',
		interactable = false,
        fontSize = 16,
        bold = true,
		height = 'auto',
		width = 'auto',
		color = 'white',
		valign = 'top',
		halign = 'left',
        tmargin = 0,
        bmargin = -2,
	}

    local nameAndAvatarPanel = gui.Panel{
        flow = "horizontal",
        valign = "top",
        halign = "left",
        width = "auto",
        height = "auto",
        nameLabel,
        tokenAvatar,
    }

    local statusLabel = gui.Label{
        text = "Offline",
		interactable = false,
        fontSize = 12,
        height = "auto",
        width = 200,
        color = Styles.textColor,
        opacity = 0.9,
        valign = "bottom",
        halign = "left",
        tmargin = -2,
        bmargin = 0,
    }

    local textPanel = gui.Panel{
        flow = "vertical",
        width = "70%",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        vmargin = 2,
        nameAndAvatarPanel,
        statusLabel,
    }

	local pingPanels = {}
	for i=1,3 do
		pingPanels[#pingPanels+1] = gui.Panel{
			classes = {"pingPanel"},
			bgimage = "game-icons/signal-strength-" .. i .. ".png",
		}
	end

	local pingPanelsParent = gui.Panel{
		interactable = true,
		bgimage = "panels/square.png",
		bgcolor = "clear",
		width = "100% height",
		height = 30,
		valign = "center",
		halign = "right",
		rmargin = 4,
		flow = "none",

		data = {
			pingTime = nil,
		},

		monitorGame = '/usersToSessions',
		refreshGame = function(element)
			local info = dmhub.GetSessionInfo(userid)
			if info ~= nil and info.ping ~= nil then
				local strength = 0
				if info.ping < 0.5 then
					strength = 3
				elseif info.ping < 1.5 then
					strength = 2
				elseif info.ping < 6 then
					strength = 1
				end

				for i=1,3 do
					pingPanels[i]:SetClass("hidden", false)
					pingPanels[i]:SetClass("off", i > strength)
				end
			else
				for i=1,3 do
					pingPanels[i]:SetClass("hidden", true)
				end
			end
		end,

		hover = function(element)
			local info = dmhub.GetSessionInfo(userid)
			if info == nil or info.ping == nil then
				return
			end
			gui.Tooltip(string.format("Ping: %.2f seconds", info.ping))(element)
		end,

		think = function(element)
			local t = dmhub.Time()
			if element.data.pingTime ~= nil and (t - element.data.pingTime) >= 10 then
				element.data.pingTime = nil
				element:PulseClassTree("pingfail")
			end

			if element.data.pingTime == nil then
				for i=1,3 do
					pingPanels[i]:SetClass("pinging", false)
				end
				element.thinkTime = nil
				return
			end

			for i=1,3 do
				pingPanels[i]:SetClass("pinging", true)
				pingPanels[i]:SetClass("pingseq", i == element.data.pingSeq)
			end

			element.data.pingSeq = element.data.pingSeq + 1
			if element.data.pingSeq > 3 then
				element.data.pingSeq = 1
			end
		end,

		click = function(element)
			local t = dmhub.Time()
			if element.data.pingTime ~= nil and (t - dmhub.element.data.pingTime) < 10 then
				return
			end

			local p2pping = nil

			element.data.pingTime = t
			element.data.pingSeq = 1
			element.thinkTime = 0.1
			print("PING:: PINGING AT", t)
			dmhub.PingUser(userid, function()
				if (not element.valid) or t ~= element.data.pingTime then
					return
				end

				element.data.pingTime = nil
				local delta = dmhub.Time() - t
				print("PING:: Got ping:", delta)

				local p2ptext = ""
				if p2pping ~= nil then
					p2ptext = string.format("\nPeer-to-peer: %.2f seconds", p2pping)
				end

				element:PulseClassTree("pingsuccess")
				gui.Tooltip(string.format("Pinged in %.2f seconds%s", delta, p2ptext))(element)
			end,
		
			function(p2ptime)
				p2pping = p2ptime
				print("PING:: Got peertopeer ping time:", p2ptime)
			end)
		end,

		children = pingPanels,

		styles = {
			{
				selectors = {"pingPanel"},
				width = "60%",
				height = "60%",
				bgcolor = Styles.textColor,
				valign = "center",
				halign = "center",
				hmargin = 0,
				vmargin = 0,
				hpad = 0,
				vpad = 0,
			},
			{
				selectors = {"pingPanel", "off"},
				bgcolor = "#666666ff",
			},
			{
				selectors = {"pinging"},
				bgcolor = "#666666ff",
			},
			{
				selectors = {"pinging", "pingseq"},
				bgcolor = "#ffffffff",
			},
			{
				selectors = {"pingsuccess"},
				transitionTime = 0.5,
				brightness = 4,
			},
			{
				selectors = {"pingfail"},
				transitionTime = 0.5,
				brightness = 2,
				bgcolor = "red",
			},
		}
	}

	local userSessionPanel
	userSessionPanel = gui.Panel{
		bgimage = 'panels/square.png',

        borderWidth = 1,
        borderColor = Styles.textColor,
		bgcolor = 'black',
		cornerRadius = 8,
		width = "100%-20",
        height = "auto",
		minHeight = 30,
		flow = 'horizontal',
        halign = "right",
		vmargin = 6,
        beveledcorners = true,


		monitorGame = string.format('/usersToSessions/%s', userid),
		thinkTime = 5,

		events = {
			click = function(element)
				local sessionInfo = dmhub.GetSessionInfo(userid)
				if sessionInfo.primaryCharacter then
					dmhub.CenterOnToken(sessionInfo.primaryCharacter)
				end
			end,

			rightClick = function(element)
				local contextMenu = {}

				local parties = dmhub.GetTable(Party.tableName) or {}
				local playerInfo = dmhub.GetPlayerInfo(userid)
				local partyid = playerInfo.partyid

				local partySubmenu = {}
				for k,party in unhidden_pairs(parties) do
					partySubmenu[#partySubmenu+1] = {
						text = party.name,
						check = k == partyid,
						click = function()
							local playerInfo = dmhub.GetPlayerInfo(userid, true)
							playerInfo.partyid = k
							dmhub.UploadPlayerInfo(userid)
							element.popup = nil
						end,
					}
				end

				if dmhub.isGameOwner or dmhub.isDM then

					if #partySubmenu > 0 then
						contextMenu[#contextMenu+1] = {
							submenu = partySubmenu,
							text = "Party",
						}
					end

					if dmhub.IsUserDM(userid) == false then
						contextMenu[#contextMenu+1] = {
							text = string.format('Make %s', GameSystem.GameMasterShortName),
							click = function()
								dmhub.SetDMStatus(userid, true)
								element.popup = nil
								userSessionPanel:FireEventTree("dmstatus", userid, true)
							end
						}
					else
						contextMenu[#contextMenu+1] = {
							text = string.format('Revoke %s Status', GameSystem.GameMasterShortName),
							click = function()
								dmhub.SetDMStatus(userid, false)
								element.popup = nil
								userSessionPanel:FireEventTree("dmstatus", userid, false)
							end
						}
					end

					if dmhub.userid ~= userid and dmhub.isGameOwner then
						contextMenu[#contextMenu+1] = {
							text = 'Kick Player',
							click = function()
								dmhub.KickPlayer(userid)
								element.popup = nil
							end,
						}
					end
				end

				if #contextMenu > 0 then
					element.popup = gui.ContextMenu{
						entries = contextMenu
					}
				end
			end,

			hover = function(element)
				local sessionInfo = dmhub.GetSessionInfo(userid)
				if sessionInfo.version ~= nil then

					--can delete this after version 0.0.368 ships and this is a core function.
					local DescribeSecondsAgo = function(secondsAgo)
						if secondsAgo < 6 then
							return "just now"
						elseif secondsAgo < 15 then
							return "a few seconds ago"
						elseif secondsAgo < 40 then
							return "seconds ago"
						elseif secondsAgo < 90 then
							return "a minute ago"
						elseif secondsAgo < 280 then
							return "a few minutes ago"
						elseif secondsAgo < 55*60 then
							local minutes = round(secondsAgo/60)
							return string.format("%d minutes ago", minutes)
						elseif secondsAgo < 90*60 then
							return "an hour ago"
						elseif secondsAgo < 60*60*24 then
							local hours = round(secondsAgo/(60*60))
							return string.format("%d hours ago", hours)
						elseif secondsAgo < 2*60*60*24 then
							return "a day ago"
						else
							local days = round(secondsAgo/(60*60*24))
							return string.format("%d days ago", days)
						end
					end
					

					local perf = sessionInfo.perf
					local loggedInText = "Logged In"
					if sessionInfo.loggedOut or sessionInfo.timeSinceLastContact > 60 then
						loggedInText = string.format("Last seen %s", DescribeSecondsAgo(sessionInfo.timeSinceLastContact))
					else
						if sessionInfo.ping == nil then
							loggedInText = loggedInText .. "\nPing: unknown"
						else
							loggedInText = string.format("%s\nPing: %.2f seconds", loggedInText, sessionInfo.ping)
						end
					end

					local peerToPeerInfo = "Peer-to-peer: no connection"
					if sessionInfo.p2pheartbeat ~= nil then
						peerToPeerInfo = string.format("Peer-to-peer: %.2f seconds ago", sessionInfo.p2pheartbeat)
					end
					gui.Tooltip(string.format('Version %s\n%s\n%s\nPerf: min=%dms; max=%dms; median=%dms; mean=%dms; cpu=%dms; gpu=%dms; res=%dx%d', sessionInfo.version, peerToPeerInfo, loggedInText, math.floor(perf.min*1000 or 0), math.floor(perf.max*1000 or 0), math.floor(perf.median*1000 or 0), math.floor(perf.mean*1000 or 0), math.floor(perf.meanCPU or 0), math.floor(perf.meanGPU or 0), math.floor(perf.screenWidth), math.floor(perf.screenHeight)))(element)
				end
			end,

			--a cache override of the dm status.
			dmstatus = function(element, id, status)
				if id == userid then
					if status then
                        tokenAvatar.selfStyle.bgimage = "panels/hud/crown.png"
                        tokenAvatar.selfStyle.bgcolor = Styles.textColor
                        tokenAvatar:SetClass("collapsed", false)
					else
						tokenAvatar:SetClass("collapsed", true)
					end
				end
			end,


			think = function(element)
				element:FireEvent('refreshGame')
			end,
			refreshGame = function(element)
				local sessionInfo = dmhub.GetSessionInfo(userid)
				if sessionInfo ~= nil then
					nameLabel.text = sessionInfo.displayName

                    local status = sessionInfo.richStatus;
                    if sessionInfo.loggedOut or sessionInfo.timeSinceLastContact >= 140 then
                        status = "Offline"
                    elseif sessionInfo.timeSinceLastContact >= 100 then
                        status = "Away"
                    elseif sessionInfo.dm and dmhub.GetSettingValue("redactdirectorlocation") then
                        status = "Online"
                    elseif status == nil then
                        if sessionInfo.dm then
                            status = "Online"
                        else
                            local charid = sessionInfo.primaryCharacter
                            if charid == nil or charid == "" or dmhub.GetCharacterById(sessionInfo.primaryCharacter) == nil then
                                status = "No Character Assigned"
                            else
                                local c = dmhub.GetCharacterById(sessionInfo.primaryCharacter)
                                if c.name == nil then
                                    status = "Character not yet named"
                                else
                                    status = string.format("Playing as %s", c.name)
                                end
                            end
                        end
                    end

                    statusLabel.text = status

                    local color = sessionInfo.displayColor

                    --make sure the name has a minimum brightness.
                    local colorhsv = core.Color(color)
                    if colorhsv.v < 0.6 then
                        colorhsv.v = 0.6
                        color = colorhsv.tostring
                    end

					nameLabel.selfStyle.color = color

					if sessionInfo.loggedOut or sessionInfo.timeSinceLastContact > 140 then
                        statusIcon:SetClassTree("offline", true)
                        statusIcon:SetClassTree("online", false)
                        statusIcon:SetClassTree("afk", false)
					elseif sessionInfo.timeSinceLastContact > 100 then
                        statusIcon:SetClassTree("offline", false)
                        statusIcon:SetClassTree("online", false)
                        statusIcon:SetClassTree("afk", true)
					else
                        statusIcon:SetClassTree("offline", false)
                        statusIcon:SetClassTree("online", true)
                        statusIcon:SetClassTree("afk", false)
					end

					if dmhub.IsUserDM(userid) then
						--tokenAvatar.bgimage = 'ui-icons/DMHubLogo.png'
                        tokenAvatar.bgimage = "panels/hud/crown.png"
                        tokenAvatar.selfStyle.bgcolor = Styles.textColor
                        tokenAvatar:SetClass("collapsed", false)
					else
						local token = nil
						if sessionInfo.primaryCharacter ~= nil then
							token = dmhub.GetCharacterById(sessionInfo.primaryCharacter)
						end
						if token ~= nil then
							tokenAvatar.bgimage = token.portrait
                            tokenAvatar.selfStyle.bgcolor = "white"
							tokenAvatar:SetClass("collapsed", false)
						else
							tokenAvatar:SetClass("collapsed", true)
						end
					end
				end
			end
		},

		children = {
			statusIcon,
			textPanel,
			pingPanelsParent,
		}
	}

	return userSessionPanel
end

--player colors shouldn't have opacity less than 1. This is a check if they do and it will reset if they do.
local playercolor = dmhub.GetSettingValue("playercolor")
if playercolor ~= nil and type(playercolor) == "userdata" and type(playercolor.a) == "number" and playercolor.a < 1 then
	playercolor.a = 1
	dmhub.SetSettingValue("playercolor", playercolor)
end

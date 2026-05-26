local mod = dmhub.GetModLoading()



local g_titleLabelStyle = gui.Style{
    selectors = {"title", "label"},
    fontSize = 38,
    minFontSize = 28,
    wrap = false,
    smallcaps = true,
    fontWeight = "regular",
    halign = "center",
    valign = "top",
    vmargin = 2,
    width = "80%",
    textAlignment = "center",
    height = 40,
}



local g_gamePageSetting = setting{
	id = "gamepage",
	storage = "preference",
	default = 1,
}

local codeMod5e = "b2f58995-4b34-40ab-9dba-5ae0ec387c33"

local AvailableGameSystems = {
	{
		id = "dmhub-legacy",
		text = "D&D 5e",
        codeMod = codeMod5e,
		description = "The fifth edition core rules and bestiary.",
		terms = "This work includes material taken from the System Reference Document 5.1 (\"SRD 5.1\") by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode.",
	},
	{
		id = "shwayguy-pathfinder2e",
		text = "Pathfinder 2e",
        codeMod = "a13c3073-f1d8-465f-bcfa-6ee076435676",
		description = "Pathfinder Gamesystem, Core Rulebook and Bestiary",
		terms = "This system uses trademarks and/or copyrights owned by Paizo Inc., used under Paizo's Community Use Policy (paizo.com/communityuse). We are expressly prohibited from charging you to use or access this content. This system is not published, endorsed, or specifically approved by Paizo. For more information about Paizo Inc. and Paizo products, visit paizo.com.",
	},
	{
		id = "dmhub-tabularasa",
		text = "No System",
        codeMod = codeMod5e,
        playerText = "Custom System",
		description = "A blank slate! Your game won't have any compendium data loaded. Useful if you want to create your own brand new system.",
	},
}

if dmhub.whiteLabel == "mcdm" then
	AvailableGameSystems = {
        {
            id = "mcdm-drawsteel",
            text = "Draw Steel",
            playerText = "Draw Steel",
            codeMod = "349dd88f-04ba-43bc-a2ba-ff6efb99b60c",
            description = "Draw Steel, a Tactical, Cinematic, Heroic, Fantasy Role Playing Game by MCDM."
        }
    }
end

print("SystemCodeMod: Register:", AvailableGameSystems)

dmhub.availableGameSystems = AvailableGameSystems

local function GetGameSystemInfo(id)
    for _,system in ipairs(AvailableGameSystems) do
        if system.id == id then
            return system
        end
    end

    return nil
end


local CreateGameScreen = function(titlescreen)
    local m_gamescreen = nil

    local m_gameBackgroundContainer = nil


    local m_exitButton = gui.Button{
		icon = "game-icons/exit-door.png",
		style = {
			halign = "left",
			valign = "top",
			width = 70,
			height = 70,
		},

		escapeActivates = true,
		escapePriority = EscapePriority.DMHUB_EXIT_TITLESCREEN,

		click = function(element)
            if titlescreen:has_key("gamesScreen") then
			    titlescreen.gamesScreen:FireEvent("elegantlyDie")
			    titlescreen.gamesScreen = nil
            end
			titlescreen.mainScreen:SetClassTree("offscreen", false)
		end,
	}

    local m_selectedGameId
	local m_games = {}
	local m_searchText = nil
	local m_orderedGames


    local GetCoverArt = function(gameid)
        gameid = gameid or m_selectedGameId
        if gameid == nil then
			return "panels/gamescreen/grass5.png"
        end

		local game = m_games[gameid]
		if game == nil or game.gameInfo == nil then
			return "panels/gamescreen/grass5.png"
		end

		return game.gameInfo.coverart
	end

	local RefreshGames = function()
		m_games = {}
		m_orderedGames = {}

		local hasSelectedGame = false
		for i,g in ipairs(lobby.games) do

			local matchesSearch = true

			if m_searchText ~= nil then
				matchesSearch = g:MatchesSearch(m_searchText)
			end

			if matchesSearch then
				if g.gameid == m_selectedGameId then
					hasSelectedGame = true
				end

				m_games[g.gameid] = m_games[g.gameid] or { gameid = g.gameid }
				local game = m_games[g.gameid]
			
				game.numplayers = #g.players
				game.gameInfo = g

				m_orderedGames[#m_orderedGames+1] = g.gameid
			end
		end

		if (not hasSelectedGame) and m_selectedGameId ~= "newgame" then
			m_selectedGameId = nil
		end

		if m_searchText == nil then
			m_orderedGames[#m_orderedGames+1] = "newgame"

			m_games["newgame"] = m_games["newgame"] or
			{
				name = "New Game",
				flagclasses = "newgame",
			}
		end
	end

    RefreshGames()

    local m_currentGame = nil

    local m_messagePanel = gui.Label{
        classes = {"collapsed"},
        width = "80%",
        height = "auto",
        textAlignment = "center",
        halign = "center",
        valign = "center",
        fontWeight = "bold",
        fontSize = 32,
    }

    local m_gameDetailPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        gui.Label{
            text = "Game Details",
            classes = {"title"},
            refreshLobby = function(element)
                if m_currentGame == nil then
                    return
                end

                element.text = m_currentGame.description
            end,
        },

        gui.Panel{
            vscroll = true,
            halign = "center",
            valign = "top",
            width = "80%",
            height = 300,
            gui.Label{
                width = "100%-8",
                height = "auto",
                halign = "left",
                valign = "top",
                textAlignment = "left",
                fontSize = 18,
                refreshLobby = function(element)
                    if m_currentGame == nil then
                        return
                    end

                    element.text = m_currentGame.descriptionDetails
                end,
            },
        },

        gui.Divider{
        },

        gui.Label{
            opacity = 0.6,
            width = "80%",
            height = 30,
            halign = "center",
            fontSize = 20,
            textAlignment = "center",

            refreshLobby = function(element)
                if m_currentGame == nil then
                    element.text = ""
                    return
                end

                local systemInfo = GetGameSystemInfo(m_currentGame.gameSystem)
                if systemInfo == nil then
                    element.text = ""
                    return
                end

                element.text = systemInfo.playerText or systemInfo.text
            end,
        },

        gui.Panel{
            width = "90%",
            halign = "center",
            valign = "bottom",
            tmargin = 24,
            bmargin = 16,
            flow = "vertical",
            height = "auto",

            gui.Panel{
                width = "100%",
                flow = "horizontal",
                height = "auto",
                vmargin = 8,

                gui.Panel{
                    classes = {"infoPanel"},
                    width = "45%",
                    halign = "left",

                    gui.Panel{
                        classes = {"infoIcon"},
                        bgimage = "panels/gamescreen/dmicon2.png",
                    },

                    gui.Label{
                        classes = {"infoLabel"},
                        textWrap = false,
                        text = "Velalyn",

                        refreshLobby = function(element)
                            if m_currentGame == nil then
                                element.text = ""
                                return
                            end

                            element.text = m_currentGame.ownerDisplayName
                        end,
                    }
                },

                gui.Panel{
                    classes = {"infoPanel"},
                    width = "45%",
                    halign = "right",
                    gui.Panel{
                        classes = {"infoIcon"},
                        bgimage = "panels/gamescreen/playersicon.png",
                    },
                    gui.Label{
                        classes = {"infoLabel"},
                        text = "Velalyn",

                        refreshLobby = function(element)
                            if m_currentGame == nil then
                                element.text = ""
                                return
                            end

                            element.text = string.format("%d", #m_currentGame.players)
                        end,
                    }
                },

            },

            gui.Panel{
                classes = {"infoPanel"},
                width = "100%",
                halign = "center",
                vmargin = 8,

                gui.Panel{
                    classes = {"infoIcon"},
                    bgimage = "panels/gamescreen/timeicon2.png",
                },

                gui.Label{
                    classes = {"infoLabel"},
                    textAlignment = "center",
                    halign = "center",

                    refreshLobby = function(element)
                        if m_currentGame == nil then
                            element.text = ""
                            return
                        end

                        local t = m_currentGame.timePlayed
                        if t < 60 then
                            element.text = "00:00"
                            return
                        end

                        local minutes = math.floor(t/60)
                        local hours = math.floor(minutes/60)
                        minutes = minutes - hours*60

                        element.text = string.format("%02d:%02d", hours, minutes)
                    end,
                }
            },

            gui.Panel{
                classes = {"infoPanel", "selectable"},
                height = 40,
                width = "100%",
                halign = "center",
                vmargin = 8,
                click = function(element)
                    local tooltip = gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
                    dmhub.CopyToClipboard(m_selectedGameId)
                end,

                gui.Label{
                    classes = {"infoLabel"},
                    fontSize = 20,
                    minFontSize = 14,
                    width = "80%",
                    textAlignment = "center",
                    textWrap = false,
                    halign = "center",

                    refreshLobby = function(element)
                        if m_currentGame == nil then
                            element.text = "NONE"
                            return
                        end

                        element.text = m_selectedGameId
                    end,
                },

                gui.Panel{
                    classes = {"infoIcon", "selectable", "parentSelectable"},
                    halign = "right",
                    bgimage = "icons/icon_app/icon_app_108.png",
                    hmargin = 8,
                    height = "70%",
                    width = "100% height",
                },
            },

            gui.Button{
                classes = {"gradient"},
                text = "Play",
                fontSize = 28,
                fontWeight = "light",

                width = "80%",
                height = 60,
                cornerRadius = 30,
                halign = "center",

                click = function(element)
                    lobby:EnterGame(m_selectedGameId)
                end,
            },
        },
    }

    local m_gameSettingsPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        flow = "vertical",

        styles = {
            {
                selectors = {"fieldLabel"},
                fontSize = 16,
                width = "80%",
                height = "auto",
                halign = "center",
                tmargin = 10,
                bmargin = 4,
                textAlignment = "left",
            },
            {
                selectors = {"input"},
                color = Styles.textColor,
                borderWidth = 2,
                borderColor = Styles.textColor,
                bgimage = "panels/square.png",
                width = "77%",
                halign = "center",
                fontSize = 16,
                height = 24,
                borderFade = false,
                cornerRadius = 6,
            },
        },

        gui.Label{
            classes = {"title"},
            text = "Campaign Settings",
        },

        gui.Divider{
            vmargin = 2,
            valign = "top",
        },
--[[ hidden unless we decide to allow multiple game systems.
        gui.Dropdown{
            width = "80%",
            halign = "center",
            vmargin = 8,
            options = AvailableGameSystems,

            refreshLobby = function(element)
                if m_currentGame == nil then
                    return
                end

                element.idChosen = m_currentGame.gameSystem
            end,

            change = function(element)
                if m_currentGame == nil then
                    return
                end

                m_currentGame.gameSystem = element.idChosen
                titlescreen:RefreshLobby()
            end,
        },
        ]]

        gui.Label{
            classes = {"fieldLabel"},
            text = "Campaign Name:",
        },

        gui.Input{
            refreshLobby = function(element)
                if m_currentGame == nil then
                    return
                end

                element.text = m_currentGame.description
            end,

            change = function(element)
                m_currentGame.description = element.text
                titlescreen:RefreshLobby()
            end,
        },

        gui.Label{
            classes = {"fieldLabel"},
            text = "Campaign Description:",
        },

        gui.Input{
            height = 160,
            multiline = true,
            characterLimit = lobby.maxGameDetailsLength,
            placeholderText = "Describe your game...",
            textAlignment = "topLeft",
            refreshLobby = function(element)
                if m_currentGame == nil then
                    return
                end

                element.text = m_currentGame.descriptionDetails
            end,

            change = function(element)
                m_currentGame.descriptionDetails = element.text
                titlescreen:RefreshLobby()
            end,
        },

        gui.Label{
            classes = {"fieldLabel"},
            text = "Image:",
        },

		--cover art
		gui.Panel{
			id = "coverart",
			bgimage = GetCoverArt(m_selectedGameId),
			bgcolor = "white",
			width = "80%",
			height = "56.25% width", --16:9 aspect ratio
			halign = "center",
			valign = "top",
			hmargin = 32,

			refreshLobby = function(element)
				element.bgimage = GetCoverArt(m_selectedGameId)
			end,

			press = function(element)
				dmhub.OpenFileDialog{
					id = "CoverArt",
					extensions = {"jpeg", "jpg", "png", "mp4", "webm", "webp"},
					prompt = string.format("Choose image or video to use for your game's cover art"),
					open = function(path)
                        local imageid
						imageid = m_currentGame:UploadCoverArt{
							path = path,
							upload = function()
							end,
							error = function(message)

								local modal
								modal = titlescreen:ShowModal{
									width = 600,
									height = 600,

									gui.Label{
										classes = {"title"},
										text = "Error Uploading Cover Art",
									},

									gui.Label {
										classes = {"dialogMessage"},
										text = message,
									},

									gui.Panel{
										classes = {"dialogButtonsPanel"},
										gui.Button{
                                            classes = {"dialogButton"},
											text = "Close",
											halign = "center",
											scale = 0.7,
											click = function(element)
												modal:DestroySelf()
											end,
										},
									},
								}
							end,
						}
					end,

					
				}
			end,

			styles = {
				{
					transitionTime = 0.1,
					selectors = {"hover"},
					brightness = 0.5,
				},
			},

			gui.Label{
                gui.Label{
                    fontSize = 10,
                    floating = true,
                    bold = true,
                    valign = "bottom",
                    halign = "center",
                    text = "Ideal Image Size: 1920x1080",
                    color = "white",
                    opacity = 0.5,
                    vmargin = 2,
                    width = "auto",
                    height = "auto",
                },
				id = "coverartBand",
				interactable = false,
				width = "100%",
				height = "25%",
                valign = "center",
				bgimage = "panels/square.png",
				bgcolor = "black",
				opacity = 0.9,
				color = "white",
				textAlignment = "center",
				fontSize = 24,
				text = "Choose Cover Art",
				styles = {
					{
                        selectors = {"#coverartBand"},
						hidden = 1,
					},
					{
						transitionTime = 0.1,
						selectors = {"#coverartBand", "parent:hover"},
						hidden = 0,
					},
				},
			},
        },

        gui.Label{
            classes = {"fieldLabel"},
            text = "Invite Code:",
        },

        gui.Panel{
            classes = {"infoPanel", "selectable"},
            height = 30,
            width = "80%",
            halign = "center",
            vmargin = 0,
            click = function(element)
                local tooltip = gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
                dmhub.CopyToClipboard(m_selectedGameId)
            end,

            gui.Label{
                classes = {"infoLabel"},
                fontSize = 16,
                minFontSize = 16,
                width = "70%",
                textAlignment = "center",
                halign = "center",

                refreshLobby = function(element)
                    if m_currentGame == nil then
                        element.text = "NONE"
                        return
                    end

                    element.text = m_selectedGameId
                end,
            },

            gui.Panel{
                classes = {"infoIcon", "selectable", "parentSelectable"},
                halign = "right",
                bgimage = "icons/icon_app/icon_app_108.png",
                hmargin = 8,
                height = "70%",
                width = "100% height",
            },
        },

        gui.Label{
            classes = {"fieldLabel"},
            text = "Password:",
        },

        gui.Input{
            characterLimit = lobby.maxGamePasswordLength,
            placeholderText = "(Optional) Enter a password here...",
            password = true,

            change = function(element)
                m_currentGame.password = element.text
                titlescreen:RefreshLobby()
            end,
        },
    }

    local m_deleteGameButton = gui.DeleteItemButton{
        classes = {"infoIcon", "hidden"},
        bgcolor = Styles.textColor,
        floating = true,
        halign = "right",
        valign = "top",
        hmargin = 46,
        vmargin = 16,
        width = 24,
        height = 24,

        styles = {
            {
                classes = {"hover"},
                brightness = 1.8,
            },
        },

        click = function(element)

            local modal
            modal = titlescreen:ShowModal{
                width = 600,
                height = 600,

                gui.Label{
                    classes = {"title"},
                    text = "Delete Game?",
                },

                gui.Label {
                    classes = {"dialogMessage"},
                    text = "Do you really want to delete this game?",
                },

                gui.Panel{
                    classes = {"dialogButtonsPanel"},
                    gui.Button{
                        classes = {"dialogButton"},
                        text = "Delete",
                        halign = "center",
                        scale = 0.7,
                        click = function(element)
                            if m_selectedGameId ~= nil and m_games[m_selectedGameId] ~= nil then
                                m_games[m_selectedGameId].gameInfo:Delete()

                                m_gamescreen:FireEventTree("showGameMessage", "Game Deleted")

                                titlescreen:RefreshLobby()
                            end
                            modal:DestroySelf()
                        end,
                    },
                    gui.Button{
                        classes = {"dialogButton"},
                        text = "Cancel",
                        halign = "center",
                        scale = 0.7,
                        click = function(element)
                            modal:DestroySelf()
                        end,
                    },
                },
            }
        end,

    }

    local m_settingsPanel = gui.Panel{
        classes = {"infoIcon"},
        bgcolor = Styles.textColor,
        floating = true,
        halign = "right",
        valign = "top",
        hmargin = 12,
        vmargin = 16,
        width = 24,
        height = 24,

        styles = {
			
            {
                bgimage = "panels/gamescreen/settings.png",
            },

            {
                classes = {"is_player"},
                bgimage = "game-icons/exit-door.png",
            },

            {
                classes = {"hover"},
                brightness = 1.8,
            },
        },

        
        refreshLobby = function(element)
            if m_currentGame == nil then
                return
            end

            element:SetClass("is_player", not m_currentGame:IsOwner())
        end,

        click = function(element)
            if m_currentGame == nil then
                return
            end

            if not m_currentGame:IsOwner() then
                local modal
                modal = titlescreen:ShowModal{
                    width = 600,
                    height = 600,

                    gui.Label{
                        classes = {"title"},
                        text = "Leave Game?",
                    },

                    gui.Label {
                        classes = {"dialogMessage"},
                        text = "Do you really want to leave this game?",
                    },

                    gui.Panel{
                        classes = {"dialogButtonsPanel"},
                        gui.Button{
                            classes = {"dialogButton"},
                            text = "Leave",
                            halign = "center",
                            scale = 0.7,
                            click = function(element)
                                if m_currentGame ~= nil then
                                    m_currentGame:Leave()
                                    titlescreen:RefreshLobby()
                                end
                                modal:DestroySelf()
                            end,
                        },
                        gui.Button{
                            classes = {"dialogButton"},
                            text = "Cancel",
                            halign = "center",
                            scale = 0.7,
                            click = function(element)
                                modal:DestroySelf()
                            end,
                        },
                    },
                }
                
                return
            end --end player section / asking to leave game.

            --we are the game owner, show settings.
            m_gameDetailPanel:SetClass("collapsed", not m_gameDetailPanel:HasClass("collapsed"))
            m_gameSettingsPanel:SetClass("collapsed", not m_gameSettingsPanel:HasClass("collapsed"))
            m_deleteGameButton:SetClass("hidden", m_gameSettingsPanel:HasClass("collapsed"))
            m_messagePanel:SetClass("collapsed", true)

        end,
    }

    local m_joinGamePanel
    m_joinGamePanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        flow = "vertical",

        gui.Panel{
            flow = "vertical",
            width = "80%",
            halign = "center",
            valign = "top",

            gui.Label{
                classes = {"title"},
                halign = "center",
                valign = "top",
                text = "Join Game",
                tmargin = 8,
            },

            gui.Divider{},

            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 16,
                text = "Enter an invite code to join a game:",
            },

            gui.Input{
                width = "100%",
                halign = "center",
                height = 26,
                fontSize = 18,
                placeholderText = "Enter invite code...",
                characterLimit = 52,

                editlag = 0.25,
                edit = function(element)
                    if element.text ~= "" then
                        local text = element.text
                        lobby:LookupGame(text, function(gameInfo)
                            if text == element.text then
                                m_joinGamePanel:FireEventTree("lookupGame", gameInfo, text)
                            end
                        end)
                    else
                        m_joinGamePanel:FireEventTree("clearLookup")
                    end
                end,
            }
        },

        gui.Label{
            classes = {"hidden"},
            fontSize = 16,
            width = "80%",
            height = "auto",
            halign = "center",
            vmargin = 16,

            lookupGame = function(element, gameInfo, gameCode)
                element:SetClass("hidden", false)
                if gameInfo == nil then
                    element.text = "No game found with that code."
                elseif gameInfo.deleted then
                    element.text = "Game has been deleted."
                elseif m_games[gameCode] ~= nil then
                    element.text = gameInfo.description .. "--Already in game"
                else
                    element.text = gameInfo.description
                end
            end,

            clearLookup = function(element)
                element:SetClass("hidden", true)
            end,
        },

        gui.Input{
            classes = {"hidden"},
            width = "80%",
            halign = "center",
            password = true,
            height = 26,
            fontSize = 18,
            placeholderText = "Enter Password...",

            data = {
            },

            edit = function(element)
                m_joinGamePanel:FireEventTree("password", element.data.gameInfo, element.text)
            end,

            lookupGame = function(element, gameInfo, gameCode)
                element.text = ""
                if gameInfo ~= nil and (not gameInfo.deleted) and gameInfo.password and m_games[gameCode] == nil then
                    element:SetClass("hidden", false)
                    element.data.gameInfo = gameInfo
                else
                    element:SetClass("hidden", true)
                end
            end,

            clearLookup = function(element)
                element:SetClass("hidden", true)
            end,
        },

        gui.Button{
            data = {
                gameCode = nil,
                gameInfo = nil,
            },
            classes = {"gradient", "hidden"},
            text = "Join Game",
            fontSize = 28,
            fontWeight = "light",

            width = "80%",
            height = 60,
            cornerRadius = 30,
            halign = "center",
            valign = "center",

            lookupGame = function(element, gameInfo, gameCode)
                element.data.gameCode = gameCode
                element.data.gameInfo = gameInfo
                element:SetClass("hidden", gameInfo == nil or (gameInfo.deleted and (not gameInfo:IsOwner())) or gameInfo.password or m_games[gameCode] ~= nil)
                if gameInfo == nil then
                    element.text = ""
                else
                    element.text = cond(gameInfo.deleted, "Undelete Game", "Join Game")
                end
            end,

            clearLookup = function(element)
                element:SetClass("hidden", true)
            end,

            password = function(element, gameInfo, password)
                element:SetClass("hidden", gameInfo.password ~= password)
            end,

            click = function(element)
                local gameInfo = element.data.gameInfo
                if gameInfo.deleted and gameInfo:IsOwner() then
                    gameInfo:Undelete()
                end
                lobby:JoinGame(element.data.gameCode)
            end,

        },

        gui.Label{
            classes = {"title"},
            halign = "center",
            valign = "bottom",
            text = "Host New Game",
        },
        gui.Divider{
            valign = "bottom",
        },
        gui.Button{
            data = {

            },
            classes = {"gradient"},
            text = "Host Game",
            fontSize = 28,
            fontWeight = "light",

            width = "80%",
            height = 60,
            cornerRadius = 30,
            halign = "center",
            valign = "bottom",
            bmargin = 16,

            click = function(element)
                m_gamescreen:FireEventTree("showGameMessage", "Creating Game...")
                lobby:CreateGame()
            end,
        },
    }


    local m_currentGamePanel = gui.Panel{
        classes = {"framedPanel", "collapsed"},
        width = 560,
		height = 800,
		valign = "center",
		halign = "left",
		lmargin = 180,

        styles = {
            {
                selectors = {"framedPanel", "newGame"},
                transitionTime = 0.4,
                x = -1200,
            },
            {
                selectors = {"leaving"},
                transitionTime = 0.4,
                uiscale = 0.001,
            }
        },

        showGame = function(element, gameid)
            if m_games[gameid] == nil or m_games[gameid].gameInfo == nil then
                m_currentGame = nil
                m_messagePanel:SetClass("collapsed", true)
                m_gameDetailPanel:SetClass("collapsed", true)
                m_gameSettingsPanel:SetClass("collapsed", true)
                m_joinGamePanel:SetClass("collapsed", false)
                m_settingsPanel:SetClass("collapsed", true)
                m_deleteGameButton:SetClass("collapsed", true)
                element:SetClass("collapsed", false)
                return
            end

            element:SetClass("collapsed", false)

            m_currentGame = m_games[gameid].gameInfo

            m_joinGamePanel:SetClass("collapsed", true)
            m_gameDetailPanel:SetClass("collapsed", false)
            m_gameSettingsPanel:SetClass("collapsed", true)
            m_settingsPanel:SetClass("collapsed", false)
            m_deleteGameButton:SetClass("collapsed", false)
            m_messagePanel:SetClass("collapsed", true)
            element:FireEventTree("refreshLobby")
        end,

        showGameMessage = function(element, text)
            m_gameDetailPanel:SetClass("collapsed", true)
            m_joinGamePanel:SetClass("collapsed", true)
            m_gameSettingsPanel:SetClass("collapsed", true)
            m_settingsPanel:SetClass("collapsed", true)
            m_deleteGameButton:SetClass("collapsed", true)
            m_messagePanel:SetClass("collapsed", false)

            m_messagePanel.text = text
        end,

        m_joinGamePanel,
        m_messagePanel,
        m_gameDetailPanel,
        m_gameSettingsPanel,
        m_settingsPanel,
        m_deleteGameButton,


    }


    local GamePageSize = 6
    local GetNumPages = function()
		if dmhub.patronTier == 0 then
			return 1
		end

        --m_orderedGames includes the 'new game' pseudo-game.
		return math.min(4, math.ceil(#m_orderedGames/GamePageSize))
	end

    local m_artGradient = gui.Gradient{
        point_a = {x = 0, y = 0.9},
        point_b = {x = 1, y = 1},
        stops = {
            {
                position = 0,
                color = "#ffffff00",
            },
            {
                position = 1,
                color = "#ffffffff",
            },
        }
    }

    local MakeGamePanel = function(gameid)
        local m_game = m_games[gameid]
        local m_singleGamePanel

        m_singleGamePanel = gui.Panel{
            classes = {"framedPanel", "gamePanel"},
            height = 90,
            vmargin = 20,
            refreshLobby = function(element)
                m_game = m_games[gameid]
            end,

            gui.Panel{
                bgimage = GetCoverArt(gameid),
                refreshLobby = function(element)
                    element.bgimage = GetCoverArt(gameid)
                end,

                imageLoaded = function(element)
                    local imageAspect = element.bgsprite.dimensions.y/element.bgsprite.dimensions.x

                    local panelAspect = 86/320

                    local height = panelAspect/imageAspect

                    element.selfStyle.imageRect = {
                        x1 = 0,
                        x2 = 1,
                        y1 = 0.5 - height/2,
                        y2 = 0.5 + height/2,
                    }
                end,

                gradient = m_artGradient,
                bgcolor = "white",
                halign = "right",
                valign = "top",
                width = 320,
                height = 86,
                y = 1,
            },

            gui.Label{
                classes = {"gameLabel"},
                refreshLobby = function(element)
                    if m_game.gameInfo == nil then
                        element.text = "New Game"
                    else
                        element.text = m_game.gameInfo.description
                    end
                end,
            },

            selectGame = function(element, id)
                if id == gameid then
                    element:FireEvent("press")
                end
            end,


            press = function(element)
                m_selectedGameId = gameid
                m_currentGamePanel:FireEvent("showGame", gameid)

                m_gamescreen:FireEventTree("setbackground", gameid)


                for _,panel in ipairs(element.parent.children) do
                    panel:SetClass("selected", panel == element)
                end
            end,
        }

        return m_singleGamePanel
    end

    local m_gamePanels = {}

    local m_gamelistPanel = gui.Panel{
        classes = {"gamelist"},
        halign = "right",
        valign = "center",
        height = "80%",
        width = 700,
        flow = "vertical",

        styles = {
            {
                selectors = {"gamelist", "create"},
                x = 800,
                transitionTime = 0.4,
            },
            {
                selectors = {"gamelist", "leaving"},
                x = 800,
                transitionTime = 0.4,
            },
        },

        refreshLobby = function(element)
            local children = {}
            local numPages = GetNumPages()
            local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)

            local newGamePanels = {}

            for i=1,GamePageSize do
                local gameIndex = (npage-1)*GamePageSize + i
                local gameid = m_orderedGames[gameIndex]

                if gameid == nil then
                    break
                end

                local gamePanel = m_gamePanels[gameid] or MakeGamePanel(gameid)

                children[#children+1] = gamePanel
                newGamePanels[gameid] = gamePanel
            end

            m_gamePanels = newGamePanels
            element.children = children
        end,
    }

    local m_lowerRightPanel = gui.Panel{
        classes = {"lowerRightPanel"},
        halign = "right",
        valign = "bottom",
        width = 400,
        height = 100,
        bgimage = "panels/square.png",

        styles = {
            {
                selectors = {"lowerRightPanel", "leaving"},
                y = 100,
                transitionTime = 0.4,
            },
        },

        gui.Input{
            placeholderText = "Search Games...",
            width = 160,
            height = 26,
            fontSize = 18,
            valign = "center",
            edit = function(element)
                if element.text == "" then
                    m_searchText = nil
                else
                    m_searchText = element.text
                end

                RefreshGames()
                element.root:FireEventTree("refreshLobby")
            end,
        },

        gui.Panel{
            minWidth = 100,
            width = "auto",
            height = 60,
            flow = "horizontal",
            halign = "right",
            valign = "center",
            rmargin = 16,
            bgimage = true,
            bgcolor = "black",
            opacity = 0.9,

            gui.PagingArrow{
                facing = -1,
                height = 24,
                valign = "center",
                halign = "center",
                refreshLobby = function(element)
					local numPages = GetNumPages()
					local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
					element:SetClass("hidden", npage <= 1)
                end,
                press = function(element)
					g_gamePageSetting:Set(g_gamePageSetting:Get()-1)
					element.root:FireEventTree("refreshLobby")
                end,
            },

            gui.Label{
                textAlignment = "center",
                width = "auto",
                minWidth = 60,
                height = 50,
                fontSize = 20,
                halign = "center",
                valign = "center",
                refreshLobby = function(element)
					local numPages = GetNumPages()
					local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                    element.text = string.format("Page\n%d/%d", npage, numPages)
                end,
            },

            gui.PagingArrow{
                facing = 1,
                height = 24,
                halign = "center",
                valign = "center",
                refreshLobby = function(element)
					local numPages = GetNumPages()
					local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
					element:SetClass("hidden", npage >= numPages)
                end,
                press = function(element)
					g_gamePageSetting:Set(g_gamePageSetting:Get()+1)
					element.root:FireEventTree("refreshLobby")
                end,
            },
        },
    }

    m_gameBackgroundContainer = gui.Panel{
        idprefix = "gameBackgroundContainer",
        width = "100%",
        height = "100%",

        styles = {
            {
                selectors = {"background"},
                width = "100%",
                height = "100%",
                bgcolor = "#ffffffff",
                alphaThresholdFade = 0.1,
                alphaThreshold = 1,
            },
            
            {
                classes = {"background", "create"},
                bgcolor = "#ffffff00",
                alphaThreshold = -0.1,
                transitionTime = 0.6,
            },
            {
                classes = {"background", "dying"},
                bgcolor = "#ffffff00",
                alphaThreshold = -0.1,
                transitionTime = 0.4,
            },
        },

        removebg = function(element)
            local children = element.children
            if #children > 1 then
                table.remove(children, 1)
            end
            element.children = children
        end,

        setbackground = function(element, gameid)
            local imageid = GetCoverArt(gameid)

            local children = element.children
            if #children == 0 or children[#children].bgimage ~= imageid then
                children[#children+1] = gui.Panel{
                    bgimage = imageid,
                    bgimageAlpha = "panels/gamescreen/loadingscreen4.png",
                    classes = {"background"},

                    overrideLoadingScreenArt = function(element, coverart)
                        if coverart == nil or coverart == "" then
                            coverart = GetCoverArt(gameid)
                        end
        
                        element.bgimage = coverart
                    end,        
                }

                element.children = children

                if #children > 1 then
                    element:ScheduleEvent("removebg", 1)
                end
            end
        end,
    }

    local m_updateid = lobby.gamesRevision

    m_gamescreen = gui.Panel{
        idprefix = "gamescreen",
        width = "100%",
        height = "100%",

        styles = {
            Styles.Default,
            Styles.Panel,

            {
                selectors = {"label"},
                fontFace = "inter",
                fontWeight = "light",
            },

            {
                selectors = {"gamePanel"},
                width = 700,
                halign = "right",
            },
            {
                selectors = {"gamePanel", "hover"},
                width = 740,
                transitionTime = 0.2,
            },
            {
                selectors = {"gamePanel", "selected"},
                width = 740,
                transitionTime = 0.2,
            },
            {
                selectors = {"gameLabel"},
                smallcaps = true,
                fontWeight = "light",
                minWidth = 400,
                width = "auto",
                height = "auto",
                valign = "center",
                hmargin = 24,
                fontSize = 32,
            },
            {
                selectors = {"gameLabel", "parent:hover"},
                color = "white",
                transitionTime = 0.2,
            },
            {
                selectors = {"gameLabel", "parent:selected"},
                color = "white",
                transitionTime = 0.2,
            },
            {
                selectors = {"infoPanel"},
                bgimage = "panels/square.png",
                bgcolor = "clear",
                height = 60,
                borderColor = Styles.textColor,
                borderWidth = 2,
                cornerRadius = 8,
            },
            {
                selectors = {"infoPanel", "selectable", "hover"},
                transitionTime = 0.2,
                brightness = 1.5,
            },
            {
                selectors = {"infoLabel"},
                fontSize = 32,
                minFontSize = 12,
                textAlignment = "right",
                hmargin = 24,
                halign = "right",
                valign = "center",
                width = "60%",
                height = "auto",
            },
            {
                selectors = {"infoIcon"},
                height = "70%",
                width = "100% height",
                bgcolor = Styles.textColor,
                halign = "left",
                valign = "center",
                hmargin = 16,
            },
            {
                selectors = {"infoIcon", "parentSelectable", "parent:hover"},
                brightness = 1.5,
                transitionTime = 0.1,
            },

            g_titleLabelStyle,

        },

        elegantlyDie = function(element)
            print("TITLESCREEN:: elegantly die")
			element:SetClassTree("dying", true)
			element:SetClassTree("leaving", true)
			element:ScheduleEvent("die", 0.5)
		end,

        die = function(element)
            print("TITLESCREEN:: just die")
            element:DestroySelf()
        end,

        destroy = function(element)
            print("TITLESCREEN:: destroy")
        end,

        error = function(element, message)
            local dialog
            dialog = gui.Panel{
                classes = {"framedPanel"},
                styles = {
                    Styles.Panel,
                },

                width = 800,
                height = 400,
                floating = true,
                halign = "center",
                valign = "center",
                flow = "none",

                gui.Label{
                    classes = {"title"},
                    text = "Error",
                    halign = "center",
                    valign = "top",
                },

                gui.Label{
                    width = "80%",
                    height = "auto",
                    fontSize = 16,
                    textAlignment = "center",
                    text = message,
                    halign = "center",
                    valign = "center",
                },

                gui.Panel{
                    classes = {"dialogButtonsPanel"},
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    vmargin = 16,

                    gui.Button{
                        classes = {"dialogButton"},
                        text = "Close",
                        halign = "center",
                        click = function(element)
                            dialog:DestroySelf()
                        end,
                    },
                }
            }

            element:AddChild(dialog)
        end,

        thinkTime = 0.1,
        think = function(element)
            if m_updateid ~= lobby.gamesRevision then
                m_updateid = lobby.gamesRevision
                print("Update:: updateid = ", m_updateid)

                local oldGames = shallow_copy_table(m_games)

                RefreshGames()

                m_gamescreen:FireEventTree("refreshLobby")

                if m_selectedGameId ~= nil then
                    element:FireEventTree("setbackground", m_selectedGameId)
                end

                if oldGames ~= nil then
                    for gameid,game in pairs(m_games) do
                        if oldGames[gameid] == nil then
                            m_gamescreen:FireEventTree("selectGame", gameid)

                            break
                        end
                    end
                end
            end
        end,

        modload = function(element)
            local visible = m_gamescreen:HasClass("hidden") == false
            m_gamescreen:DestroySelf()
            titlescreen.gamesScreen = nil

            if visible then
                Titlescreen.ShowGamesScreen(titlescreen)
            end
        end,

        loading = function(element)
            print("TITLESCREEN:: loading")
			element:SetClassTreeImmediate("selected", true) --make sure background is shown.
			element:SetClassTree("newGame", true) --make flags disappear.
			element:SetClassTree("leaving", true)
			m_exitButton:SetClass("hidden", true)

			titlescreen.mainScreen:SetClassTree("loadgame", true)

			titlescreen:CreateLoadingScreen()
		end,

        beginLoading = function(element)
            print("TITLESCREEN:: begin loading")
            element:SetClassTree("create", false) --make the background appear.
        end,
        
        endLoading = function(element)
            print("TITLESCREEN:: end loading")
            element:SetClassTree("create", true) --make the background disappear.
        end,


		doneLoading = function(element)
            print("TITLESCREEN:: done loading")
			element:SetClassTree("create", true) --make the background disappear.
		end,

        returnFromGame = function(element)
            print("TITLESCREEN:: return from game")
			element:SetClassTree("create", false) --make the background reappear.
			element:SetClassTree("newGame", false) --make flags appear.
			element:SetClassTree("leaving", false)
			m_exitButton:SetClass("hidden", false)

			titlescreen.mainScreen:SetClassTree("loadgame", false)
        end,

        m_gameBackgroundContainer,
        m_exitButton,
        m_gamelistPanel,
        m_lowerRightPanel,
        m_currentGamePanel,
    }

    mod.unloadHandlers[#mod.unloadHandlers+1] = function()
        if m_gamescreen ~= nil and m_gamescreen.valid then
            m_gamescreen:ScheduleEvent("modload", 0.1)
        end
    end

    m_gamescreen:FireEventTree("refreshLobby")

    return m_gamescreen

end

function Titlescreen:ShowModal(options)
	options = DeepCopy(options)

	local args = {
		classes = {"framedPanel"},
		halign = "center",
		valign = "center",

		styles = {
            Styles.Default,
            Styles.Panel,
            g_titleLabelStyle,
            {
                selectors = {"dialogMessage"},
                halign = "center",
                valign = "center",
                width = "80%",
                textAlignment = "center",
                height = "auto",
                fontSize = 18,
            },
            {
                selectors = {"dialogButtonsPanel"},
                halign = "center",
                valign = "bottom",
                vmargin = 16,
                width = "80%",
                height = "auto",
                flow = "horizontal",
            },
            {
                selectors = {"dialogButton"},
                priority = 20,
                height = 40,
                width = 160,
                fontSize = 28,
                halign = "center",
            },
        },
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	local modal = gui.Panel(args)
	self.dialog.sheet:AddChild(modal)
	return modal
end


function Titlescreen:ShowGamesScreen()
	local tosPanel = self.dialog.sheet:Get("termsOfService")
	
	if tosPanel ~= nil then
		tosPanel:SetClass("hidden", true)
	end
	if self:try_get("gamesScreen") == nil then
		self.gamesScreen = CreateGameScreen(self)

		self.dialog.sheet:AddChild(self.gamesScreen)
	end
	
	self.gamesScreen:SetClass("hidden", false)
end

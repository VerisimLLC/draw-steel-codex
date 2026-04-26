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

local CreateHeroesPanel

DockablePanel.Register {
    name = "Heroes",
    icon = "icons/standard/Icon_App_Heroes.png",
    notitle = true,
    vscroll = false,
    dmonly = false,
    minHeight = 68,
    content = function()
        track("panel_open", {
            panel = "Heroes",
            dailyLimit = 30,
        })
        return CreateHeroesPanel()
    end,
}

local CreateDividerPanel = function()
    local resultPanel = gui.Panel {

        width = "100%",
        height = 1.5,

        bgimage = true,
        bgcolor = "#42362C",


        halign = "center",
        valign = "bottom",


    }

    return resultPanel
end

local CreateAddButtonPanel = function()
    local resultPanel = gui.Panel {

        data = {

            order = "x"

        },

        update = function(element, info)
            element.data.order = "x" .. string.lower(info.displayName)
        end,

        width = "100%",
        height = 32,

        bgimage = true,
        bgcolor = "#0A0D0C",

        halign = "center",
        valign = "top",

        flow = "horizontal",

        gui.AddButton {
            halign = "center",
            valign = "center",
            bgcolor = "#A29078",
            click = function(element)
                -- Detect whether the current game is a local (offline) game.
                -- Local games have storage == 3 (StorageBackend.Local in C#).
                local isLocalGame = false
                for _, g in ipairs(lobby.games or {}) do
                    if g.gameid == dmhub.gameid then
                        isLocalGame = (g.storage == 3)
                        break
                    end
                end

                local inviteDialog
                local contentPanel
                local progressLabel
                local StartPromote
                local SetContent

                local BuildInviteCodeView = function(displayGameid)
                    return gui.Panel {
                        halign = "center",
                        valign = "center",
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",

                        gui.Label {
                            fontSize = 14,
                            text = "Invite Code:",
                            width = 100,
                            textAlignment = "left",
                        },

                        gui.Panel {
                            halign = "center",
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",

                            click = function(el)
                                gui.Tooltip { text = "Copied to Clipboard", valign = "top", borderWidth = 0 } (el)
                                dmhub.CopyToClipboard(displayGameid)
                            end,

                            gui.Label {
                                fontFace = "cambria",
                                fontSize = 18,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",
                                vmargin = 20,
                                text = displayGameid,
                            },

                            gui.Panel {
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
                    }
                end

                local BuildOfflinePromptView = function()
                    return gui.Panel {
                        halign = "center",
                        valign = "center",
                        width = "90%",
                        height = "auto",
                        flow = "vertical",

                        gui.Label {
                            text = "This game is currently offline. Put it online to get an invite code that players can use to join.",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            fontSize = 16,
                            vmargin = 8,
                        },

                        gui.Label {
                            text = "A new game ID will be generated and all game data will be copied to the cloud. This may take a moment.",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            fontSize = 13,
                            color = "#A29078",
                            vmargin = 4,
                        },

                        gui.Button {
                            text = "Put Game Online",
                            width = "auto",
                            height = "auto",
                            fontSize = 18,
                            vpad = 6,
                            hpad = 16,
                            halign = "center",
                            vmargin = 16,
                            click = function()
                                StartPromote()
                            end,
                        },
                    }
                end

                local BuildProgressView = function()
                    return gui.Panel {
                        halign = "center",
                        valign = "center",
                        width = "90%",
                        height = "auto",
                        flow = "vertical",

                        gui.Label {
                            text = "Putting Game Online...",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            fontSize = 18,
                            bold = true,
                            vmargin = 8,
                        },

                        gui.Label {
                            text = "Preparing...",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            fontSize = 14,
                            color = "#A29078",
                            create = function(el)
                                progressLabel = el
                            end,
                        },
                    }
                end

                local BuildSuccessView = function(newGameid)
                    return gui.Panel {
                        halign = "center",
                        valign = "center",
                        width = "90%",
                        height = "auto",
                        flow = "vertical",

                        gui.Label {
                            text = "Game is Online!",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            fontSize = 20,
                            bold = true,
                            vmargin = 4,
                        },

                        BuildInviteCodeView(newGameid),

                        gui.Button {
                            text = "Play Online",
                            width = "auto",
                            height = "auto",
                            fontSize = 16,
                            vpad = 6,
                            hpad = 16,
                            halign = "center",
                            vmargin = 4,
                            click = function()
                                gui.CloseModal()
                                lobby:EnterGame(newGameid)
                            end,
                        },
                    }
                end

                local BuildErrorView = function(msg)
                    return gui.Panel {
                        halign = "center",
                        valign = "center",
                        width = "90%",
                        height = "auto",
                        flow = "vertical",

                        gui.Label {
                            text = "Failed to Put Game Online",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            fontSize = 18,
                            bold = true,
                            color = "red",
                            vmargin = 4,
                        },

                        gui.Label {
                            text = msg,
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            fontSize = 14,
                            color = "#A29078",
                            vmargin = 8,
                        },
                    }
                end

                SetContent = function(newContent)
                    if contentPanel ~= nil and contentPanel.valid then
                        contentPanel.children = { newContent }
                    end
                end

                StartPromote = function()
                    SetContent(BuildProgressView())
                    lobby:PromoteLocalGame {
                        gameid = dmhub.gameid,
                        -- TEMP: target staging until the release DO server
                        -- is redeployed with the /admin/bulk-upload route.
                        staging = true,
                        progress = function(status, pct)
                            if progressLabel ~= nil and progressLabel.valid then
                                progressLabel.text = status or ""
                            end
                        end,
                        complete = function(success, newGameid, err)
                            if inviteDialog == nil or not inviteDialog.valid then return end
                            if success then
                                SetContent(BuildSuccessView(newGameid))
                            else
                                SetContent(BuildErrorView(err or "Unknown error"))
                            end
                        end,
                    }
                end

                local titleText = isLocalGame and "Put Game Online" or "Invite Players"

                inviteDialog = gui.Panel {
                    classes = { 'framedPanel' },
                    width = 600,
                    height = 400,
                    styles = {
                        Styles.Panel,
                    },

                    gui.Label {
                        fontSize = 24,
                        width = "auto",
                        height = "auto",
                        floating = true,
                        bold = true,
                        text = titleText,
                        halign = "center",
                        valign = "top",
                        vmargin = 8,
                    },

                    gui.CloseButton {
                        halign = "right",
                        valign = "top",
                        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                        click = function(element)
                            gui.CloseModal()
                        end,
                    },

                    gui.Panel {
                        halign = "center",
                        valign = "center",
                        width = "90%",
                        height = "auto",
                        flow = "vertical",
                        create = function(el)
                            contentPanel = el
                            if isLocalGame then
                                el.children = { BuildOfflinePromptView() }
                            else
                                el.children = { BuildInviteCodeView(dmhub.gameid) }
                            end
                        end,
                    },
                }

                gui.ShowModal(inviteDialog)
            end,

            tooltip = "Invite players",

        },




    }

    return resultPanel
end

local CreateDirectorPanel = function(userid)
    --Director queen panel
    local resultPanel = gui.Panel {

        data = {

            order = "x"

        },

        update = function(element, info)
            if info.loggedOut or info.timeSinceLastContact > 140 then
                element.data.order = "dx" .. string.lower(info.displayName)
            else
                element.data.order = "da" .. string.lower(info.displayName)
            end
        end,

        width = "100%",
        height = 40,

        bgimage = true,
        bgcolor = "#0A0D0C99",

        halign = "center",
        valign = "top",

        flow = "horizontal",

        rightClick = function(element)
            local contextMenu = {}

            local parties = dmhub.GetTable(Party.tableName) or {}
            local playerInfo = dmhub.GetPlayerInfo(userid)
            local partyid = playerInfo.partyid

            local playerParty = Party.PlayerParty()

            local partySubmenu = {}
            for k, party in unhidden_pairs(parties) do
                if playerParty ~= nil and k == playerParty.id then
                    playerParty = nil
                end
                partySubmenu[#partySubmenu + 1] = {
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

            if playerParty ~= nil then
                partySubmenu[#partySubmenu + 1] = {
                    text = playerParty.name,
                    check = playerParty.id == partyid,
                    click = function()
                        local playerInfo = dmhub.GetPlayerInfo(userid, true)
                        playerInfo.partyid = playerParty.id
                        dmhub.UploadPlayerInfo(userid)
                        element.popup = nil
                    end,
                }
            end

            if dmhub.isGameOwner or dmhub.isDM then
                if #partySubmenu > 0 then
                    contextMenu[#contextMenu + 1] = {
                        submenu = partySubmenu,
                        text = "Party",
                    }
                end

                if dmhub.IsUserDM(userid) == false then
                    contextMenu[#contextMenu + 1] = {
                        text = string.format('Make %s', GameSystem.GameMasterShortName),
                        click = function()
                            dmhub.SetDMStatus(userid, true)
                            element.popup = nil
                            --userSessionPanel:FireEventTree("dmstatus", userid, true)
                        end
                    }
                else
                    contextMenu[#contextMenu + 1] = {
                        text = string.format('Revoke %s Status', GameSystem.GameMasterShortName),
                        click = function()
                            dmhub.SetDMStatus(userid, false)
                            element.popup = nil
                            --userSessionPanel:FireEventTree("dmstatus", userid, false)
                        end
                    }
                end

                if dmhub.userid ~= userid and dmhub.isGameOwner then
                    contextMenu[#contextMenu + 1] = {
                        text = 'Kick Player',
                        click = function()
                            dmhub.KickPlayer(userid)
                            element.popup = nil
                        end,
                    }
                end
            end

            if #contextMenu > 0 then
                element.popup = gui.ContextMenu {
                    entries = contextMenu
                }
            end
        end,



        gui.Panel {

            classes = { "director", "beforeDivider" },

            --online icon
            gui.Panel {


                width = 23 * 2,
                height = 23 * 2,

                bgimage = mod.images.status,
                bgcolor = "white",

                halign = "left",
                valign = "center",

                flow = "horizontal",

                update = function(element, info)
                    if info.loggedOut or info.timeSinceLastContact > 140 then
                        element.selfStyle.saturation = 0
                    else
                        element.selfStyle.saturation = 1
                    end
                end,

                --invisible hover panel
                gui.Panel {

                    width = 13,
                    height = 13,

                    opacity = 0.4,
                    bgimage = true,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",
                    x = -2,

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
                                elseif secondsAgo < 55 * 60 then
                                    local minutes = round(secondsAgo / 60)
                                    return string.format("%d minutes ago", minutes)
                                elseif secondsAgo < 90 * 60 then
                                    return "an hour ago"
                                elseif secondsAgo < 60 * 60 * 24 then
                                    local hours = round(secondsAgo / (60 * 60))
                                    return string.format("%d hours ago", hours)
                                elseif secondsAgo < 2 * 60 * 60 * 24 then
                                    return "a day ago"
                                else
                                    local days = round(secondsAgo / (60 * 60 * 24))
                                    return string.format("%d days ago", days)
                                end
                            end


                            local perf = sessionInfo.perf
                            local loggedInText = "Logged In"
                            if sessionInfo.loggedOut or sessionInfo.timeSinceLastContact > 60 then
                                loggedInText = string.format("Last seen %s",
                                    DescribeSecondsAgo(sessionInfo.timeSinceLastContact))
                            else
                                if sessionInfo.ping == nil then
                                    loggedInText = loggedInText .. "\nPing: unknown"
                                else
                                    loggedInText = string.format("%s\nPing: %.2f seconds", loggedInText, sessionInfo
                                        .ping)
                                end
                            end

                            local peerToPeerInfo = "Peer-to-peer: no connection"
                            if sessionInfo.p2pheartbeat ~= nil then
                                local connType = sessionInfo.p2pconnection or "unknown"
                                peerToPeerInfo = string.format("Peer-to-peer: %.2f seconds ago (%s)", sessionInfo
                                    .p2pheartbeat, connType)
                            end
                            gui.Tooltip(string.format(
                                'Version %s\n%s\n%s\nPerf: min=%dms; max=%dms; median=%dms; mean=%dms; cpu=%dms; gpu=%dms; res=%dx%d',
                                sessionInfo.version, peerToPeerInfo, loggedInText, math.floor(perf.min * 1000 or 0),
                                math.floor(perf.max * 1000 or 0), math.floor(perf.median * 1000 or 0),
                                math.floor(perf.mean * 1000 or 0), math.floor(perf.meanCPU or 0),
                                math.floor(perf.meanGPU or 0), math.floor(perf.screenWidth),
                                math.floor(perf.screenHeight)))(
                                    element)
                        end
                    end,

                    click = function(element)
                        local t = dmhub.Time()
                        if element.data.pingTime ~= nil and (t - element.data.pingTime) < 10 then
                            return
                        end

                        local p2pping = nil
                        local p2pconntype = nil

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
                                    local connLabel = p2pconntype or "unknown"
                                    p2ptext = string.format("\nPeer-to-peer: %.2f seconds (%s)", p2pping, connLabel)
                                end

                                element:PulseClassTree("pingsuccess")
                                if element:HasClass("hover") then
                                    gui.Tooltip(string.format("Pinged in %.2f seconds%s", delta, p2ptext))(element)
                                end
                            end,

                            function(p2ptime, conntype)
                                p2pping = p2ptime
                                p2pconntype = conntype
                                print("PING:: Got peertopeer ping time:", p2ptime, "connection:", conntype)
                            end)
                    end,

                },




            },



            --"Director" label
            gui.Label {

                text = "Director",
                fontFace = "Berling",
                fontSize = 16,
                minFontSize = 10,
                color = "#A29078",
                textOverflow = "ellipsis",
                textWrap = false,
                lmargin = -8,

                width = "auto",
                height = "100%",
                maxWidth = "90",

                bgimage = true,
                bgcolor = "clear",

                halign = "left",
                valign = "top",

                flow = "horizontal",

                update = function(element, info)
                    element.text = info.displayName
                    element.data.info = info
                end,

                hover = function (element)
                    gui.Tooltip(string.format("%s -- Director", element.data.info.displayName))(element)
                end
            
            },

            --divider middle
            gui.Panel {


                width = 1.5,
                height = 23,

                bgimage = true,
                bgcolor = "#42362C",

                halign = "right",
                valign = "center",


            },

        },


        --Acitivity text
        gui.Label {

            text = "Playing as MONSTERS",
            fontFace = "Berling",
            fontSize = 16,
            minFontSize = 10,
            color = "#A29078",
            textOverflow = "ellipsis",
            textWrap = false,


            width = "auto",
            height = "100%",
            maxWidth = "170",

            bgimage = true,
            bgcolor = "clear",

            halign = "left",
            valign = "top",

            flow = "horizontal",

            update = function(element, info)
                if info.loggedOut or info.timeSinceLastContact > 140 then
                    element.text = "Offline"
                elseif info.dm and dmhub.GetSettingValue("redactdirectorlocation") then
                    element.text = "Online"
                elseif info.richStatus == nil then
                    element.text = "Online"
--[[
                    if dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then
                        element.text = string.format("Fighting in %s", game.currentMap.description)
                    else
                        element.text = string.format("Exploring %s", game.currentMap.description)
                    end
                    ]]
                else
                    element.text = info.richStatus
                end
            end

        },

        --[[activity icon
        gui.Panel {


            width = "10%",
            height = "100%",

            bgimage = true,
            bgcolor = "purple",

            halign = "left",
            valign = "top",


        },]]

        gui.Panel {

            floating = true,


            width = "100%",
            height = 1.5,

            bgimage = true,
            bgcolor = "#42362C",


            halign = "center",
            valign = "bottom",


        },






    }

    return resultPanel
end

local CreatePlayerPanel = function(userid)
    local resultPanel = gui.Panel {

        data = {

            order = "x"

        },

        update = function(element, info)
            if info.loggedOut or info.timeSinceLastContact > 140 then
                element.data.order = "px" .. string.lower(info.displayName)
            else
                element.data.order = "pa" .. string.lower(info.displayName)
            end
        end,

        width = "100%",
        height = 40,

        bgimage = true,
        bgcolor = "#1B1A1899",

        halign = "center",
        valign = "top",

        flow = "horizontal",

        rowColor = function(element, bgFlag)
            if bgFlag then
                element.selfStyle.bgcolor = "#1B1A1899"
            else
                element.selfStyle.bgcolor = "#0A0D0C99"
            end
        end,

        rightClick = function(element)
            local contextMenu = {}

            local parties = dmhub.GetTable(Party.tableName) or {}
            local playerInfo = dmhub.GetPlayerInfo(userid)
            local partyid = playerInfo.partyid

            local playerParty = Party.PlayerParty()

            local partySubmenu = {}
            for k, party in unhidden_pairs(parties) do
                if playerParty ~= nil and k == playerParty.id then
                    playerParty = nil
                end

                partySubmenu[#partySubmenu + 1] = {
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

            if playerParty ~= nil then
                partySubmenu[#partySubmenu + 1] = {
                    text = playerParty.name,
                    check = playerParty.id == partyid,
                    click = function()
                        local playerInfo = dmhub.GetPlayerInfo(userid, true)
                        playerInfo.partyid = playerParty.id
                        dmhub.UploadPlayerInfo(userid)
                        element.popup = nil
                    end,
                }
            end

            if dmhub.isGameOwner or dmhub.isDM then
                if #partySubmenu > 0 then
                    contextMenu[#contextMenu + 1] = {
                        submenu = partySubmenu,
                        text = "Party",
                    }
                end

                if dmhub.IsUserDM(userid) == false then
                    contextMenu[#contextMenu + 1] = {
                        text = string.format('Make %s', GameSystem.GameMasterShortName),
                        click = function()
                            dmhub.SetDMStatus(userid, true)
                            element.popup = nil
                            --userSessionPanel:FireEventTree("dmstatus", userid, true)
                        end
                    }
                else
                    contextMenu[#contextMenu + 1] = {
                        text = string.format('Revoke %s Status', GameSystem.GameMasterShortName),
                        click = function()
                            dmhub.SetDMStatus(userid, false)
                            element.popup = nil
                            --userSessionPanel:FireEventTree("dmstatus", userid, false)
                        end
                    }
                end

                if dmhub.userid ~= userid and dmhub.isGameOwner then
                    contextMenu[#contextMenu + 1] = {
                        text = 'Kick Player',
                        click = function()
                            dmhub.KickPlayer(userid)
                            element.popup = nil
                        end,
                    }
                end
            end

            if #contextMenu > 0 then
                element.popup = gui.ContextMenu {
                    entries = contextMenu
                }
            end
        end,


        gui.Panel {

            classes = { "player", "beforeDivider" },

            --online icon
            gui.Panel {

                data = {previousLoggedOut = nil},

                width = 23 * 2,
                height = 23 * 2,

                bgimage = mod.images.status,
                bgcolor = "white",

                halign = "left",
                valign = "center",

                update = function(element, info)
                    if element.data.previousLoggedOut ~= nil and element.data.previousLoggedOut ~= info.loggedOut then 

                        if info.loggedOut then
                        
                            audio.FireSoundEvent("Notify.UserLeave")

                        else

                            audio.FireSoundEvent("Notify.UserJoin")
                        
                        end

                    end

                    if info.loggedOut or info.timeSinceLastContact >= 140 then
                        element.selfStyle.saturation = 0
                    else
                        element.selfStyle.saturation = 1
                    end

                    element.data.previousLoggedOut = info.loggedOut
                end,

                --invisible hover panel
                gui.Panel {

                    width = 13,
                    height = 13,

                    opacity = 0.4,
                    bgimage = true,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",
                    x = -2,

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
                                elseif secondsAgo < 55 * 60 then
                                    local minutes = round(secondsAgo / 60)
                                    return string.format("%d minutes ago", minutes)
                                elseif secondsAgo < 90 * 60 then
                                    return "an hour ago"
                                elseif secondsAgo < 60 * 60 * 24 then
                                    local hours = round(secondsAgo / (60 * 60))
                                    return string.format("%d hours ago", hours)
                                elseif secondsAgo < 2 * 60 * 60 * 24 then
                                    return "a day ago"
                                else
                                    local days = round(secondsAgo / (60 * 60 * 24))
                                    return string.format("%d days ago", days)
                                end
                            end


                            local perf = sessionInfo.perf
                            local loggedInText = "Logged In"
                            if sessionInfo.loggedOut or sessionInfo.timeSinceLastContact > 60 then
                                loggedInText = string.format("Last seen %s",
                                    DescribeSecondsAgo(sessionInfo.timeSinceLastContact))
                            else
                                if sessionInfo.ping == nil then
                                    loggedInText = loggedInText .. "\nPing: unknown"
                                else
                                    loggedInText = string.format("%s\nPing: %.2f seconds", loggedInText, sessionInfo
                                        .ping)
                                end
                            end

                            local peerToPeerInfo = "Peer-to-peer: no connection"
                            if sessionInfo.p2pheartbeat ~= nil then
                                local connType = sessionInfo.p2pconnection or "unknown"
                                peerToPeerInfo = string.format("Peer-to-peer: %.2f seconds ago (%s)", sessionInfo
                                    .p2pheartbeat, connType)
                            end
                            gui.Tooltip(string.format(
                                'Version %s\n%s\n%s\nPerf: min=%dms; max=%dms; median=%dms; mean=%dms; cpu=%dms; gpu=%dms; res=%dx%d',
                                sessionInfo.version, peerToPeerInfo, loggedInText, math.floor(perf.min * 1000 or 0),
                                math.floor(perf.max * 1000 or 0), math.floor(perf.median * 1000 or 0),
                                math.floor(perf.mean * 1000 or 0), math.floor(perf.meanCPU or 0),
                                math.floor(perf.meanGPU or 0), math.floor(perf.screenWidth),
                                math.floor(perf.screenHeight)))(
                                    element)
                        end
                    end,

                    click = function(element)
                        local t = dmhub.Time()
                        if element.data.pingTime ~= nil and (t - element.data.pingTime) < 10 then
                            return
                        end

                        local delta = nil
                        local p2pping = nil
                        local p2pconntype = nil

                        element.data.pingTime = t
                        element.data.pingSeq = 1
                        element.thinkTime = 0.1
                        print("PING:: PINGING AT", t)

                        local onping = function()
                            local tcptext = ""
                            if delta ~= nil then
                                tcptext = string.format("Pinged in %.2f seconds", delta)
                            end
                            local p2ptext = ""
                            if p2pping ~= nil then
                                local connLabel = p2pconntype or "unknown"
                                p2ptext = string.format("Peer-to-peer: %.2f seconds (%s)", p2pping, connLabel)
                            end

                            element:PulseClassTree("pingsuccess")
                            gui.Tooltip(table.concat({tcptext, p2ptext}, "\n"))(element)
                        end


                        dmhub.PingUser(userid, function()
                                if (not element.valid) or t ~= element.data.pingTime then
                                    return
                                end

                                element.data.pingTime = nil
                                delta = dmhub.Time() - t
                                print("PING:: Got ping:", delta)
                                onping()
                            end,

                            function(p2ptime, conntype)
                                p2pping = p2ptime
                                p2pconntype = conntype
                                print("PING:: Got peertopeer ping time:", p2ptime, "connection:", conntype)
                                onping()
                            end)
                    end,

                },




            },

            --"NAME" label
            gui.Panel{
                height = "100%",
                width = "auto",
                maxWidth = 90,
                flow = "vertical",

                gui.Label{
                    text = "Username",
                    fontFace = "Berling",
                    fontSize = 16,
                    minFontSize = 10,
                    color = "#A29078",
                    textOverflow = "ellipsis",
                    textWrap = false,

                    lmargin = -8,

                    width = "auto",
                    maxWidth = "90",
                    height = "60%",

                    bgimage = true,
                    bgcolor = "clear",

                    halign = "left",
                    valign = "top",

                    flow = "horizontal",

                    update = function(element, info)
                        element.text = info.displayName
                        local token = nil
                        if info.primaryCharacter ~= nil then
                            token = dmhub.GetCharacterById(info.primaryCharacter)
                        end

                        if token ~= nil then
                            element.text = token.name
                        end
                        print("info:", info.primaryCharacter)
                        element.data.info = info
                    end,
                },

                gui.Label{
                    text = "Username",
                    fontFace = "Berling",
                    fontSize = 12,
                    minFontSize = 10,
                    color = "#A29078",
                    textOverflow = "ellipsis",
                    textWrap = false,
                    bold = true,

                    lmargin = -8,

                    width = "auto",
                    maxWidth = "90",
                    height = "40%",

                    bgimage = true,
                    bgcolor = "clear",

                    halign = "left",
                    valign = "top",

                    flow = "horizontal",

                    update = function(element, info)
                        element.text = info.displayName
                    end,
                },

            },

            --divider middle
            gui.Panel {


                width = 1.5,
                height = 23,

                bgimage = true,
                bgcolor = "#42362C",

                halign = "right",
                valign = "center",


            },


        },

        --Acitivity text
        gui.Label {

            text = "Playing as MONSTERS",
            fontFace = "Berling",
            fontSize = 16,
            minFontSize = 10,
            color = "#A29078",
            textOverflow = "ellipsis",
            textWrap = false,


            width = "auto",
            height = "100%",
            maxWidth = "170",

            bgimage = true,
            bgcolor = "clear",

            halign = "left",
            valign = "top",

            flow = "horizontal",

            update = function(element, info)
                if info.loggedOut or info.timeSinceLastContact > 140 then
                    element.text = "Offline"
                elseif info.richStatus == nil then
                    if dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then
                        element.text = string.format("Fighting in %s", game.currentMap.description)
                    else
                        element.text = string.format("Exploring %s", game.currentMap.description)
                    end
                else
                    element.text = info.richStatus
                end
            end

        },

        --[[activity icon
        gui.Panel {


            width = "10%",
            height = "100%",

            bgimage = true,
            bgcolor = "purple",

            halign = "left",
            valign = "top",

            flow = "horizontal",

        },]]






    }

    return resultPanel
end

CreateHeroesPanel = function()
    local directorPanels = {}

    local m_currentRichStatus = nil
    local m_richStatusId = nil

    local dividerPanel = CreateDividerPanel()
    local addButtonPanel = CreateAddButtonPanel()

    --king panel
    local heroesPanel = gui.Panel {

        classes = { "kingPanel" },

        height = "100%",
        width = "100%",

        bgimage = true,
        bgcolor = "#0A0D0C00", 
        vscroll = true,

        flow = "vertical",

        thinkTime = 1,
        think = function(element)
            local richStatus = nil
            if dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden then
                richStatus = string.format("Fighting in %s", game.currentMap.description)
            else
                richStatus = string.format("Exploring %s", game.currentMap.description)
            end
            
            if richStatus ~= m_currentRichStatus then
                local existing = dmhub.currentUserStatusMessage
                if existing == nil or existing == m_currentRichStatus then
                    m_richStatusId = dmhub.PushUserRichStatus(richStatus, m_richStatusId)
                    m_currentRichStatus = richStatus
                end
            end
        end,

        destroy = function(element)
            if m_richStatusId ~= nil then
                dmhub.PopUserRichStatus(m_richStatusId)
            end
        end,

        styles = {

            {
                classes = "beforeDivider",
                width = "40%",
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                rmargin = 15,

            },

        },



        --[[queen panel for title and collapse button
        gui.Panel{

            width = "100%",
            height = 45,

            bgimage = true,
            bgcolor = "black",

            border = 2,
            borderColor = "white",

            halign = "center",
            valign = "top",

            flow = "horizontal",

            --player icon
            gui.Panel{


                width = 11*1.7,
                height = 11*1.7,

                bgimage = mod.images.user,
                bgcolor = "white",

                halign = "left",
                valign = "center",
                lmargin = 10,
                rmargin = 15,

            },

            --"Player Status" label
            gui.Label{

                text = "Player Status",
                fontFace = "Berling",
                fontSize = 19,
                color = "#A29078",

                width = "auto",
                height = "100%",

                bgimage = true,
                bgcolor = "clear",

                halign = "left",
                valign = "center",

            },

            --player icon
            gui.Panel{


                width = 10*1.4,
                height = 6*1.4,

                bgimage = mod.images.collapse,
                bgcolor = "white",

                halign = "right",
                valign = "center",
                lmargin = 10,
                rmargin = 15,

            },





        },]]

        gui.Panel {

            width = "100%",
            height = "auto",
            flow = "vertical",


            monitorGame = '/usersToSessions',


            refreshGame = function(element)
                local newPanels = {}
                local children = {}
                local nrOfDirectors = 0

                local users = dmhub.users
                for i, userid in ipairs(users) do
                    local info = dmhub.GetSessionInfo(userid)
                    print("info", info)
                    if info.dm then
                        local key = userid .. "director"
                        newPanels[key] = directorPanels[key] or CreateDirectorPanel(userid)
                        children[#children + 1] = newPanels[key]

                        newPanels[key]:FireEventTree("update", info)

                        nrOfDirectors = nrOfDirectors + 1
                    else
                        newPanels[userid] = directorPanels[userid] or CreatePlayerPanel(userid)
                        children[#children + 1] = newPanels[userid]

                        newPanels[userid]:FireEventTree("update", info)
                    end
                end

                table.sort(children, function(a, b)
                    return a.data.order < b.data.order
                end)

                local nrOfPlayers = #children - nrOfDirectors
                local bgFlag = true


                for i = nrOfDirectors + 1, #children do
                    children[i]:FireEventTree("rowColor", bgFlag)

                    bgFlag = not bgFlag
                end

                children[#children + 1] = dividerPanel
                children[#children + 1] = addButtonPanel

                

                element.children = children

                directorPanels = newPanels
            end,

            dividerPanel,
            addButtonPanel,
        },













    }

    return heroesPanel
end

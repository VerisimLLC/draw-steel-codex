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

local g_heroesExtras = {
    {
        selectors = {"beforeDivider"},
        width = "40%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        rmargin = 15,
    },
    {
        selectors = {"row", "bordered"},
        cornerRadius = 0,
    },
    {
        selectors = {"label", "bordered"},
        cornerRadius = 0,
    },
}

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

local CreateAddButtonPanel = function()
    local resultPanel = gui.Panel {

        data = {

            order = "x"

        },

        update = function(element, info)
            element.data.order = "x" .. string.lower(info.displayName)
        end,

        classes = {"row", "bordered"},
        width = "100%",
        height = 32,

        border = { x1 = 0, x2 = 0, y1 = 0, y2 = 1 },

        halign = "center",
        valign = "top",

        flow = "horizontal",

        gui.Button {
            classes = {"sizeM", "addButton"},
            halign = "center",
            valign = "center",
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
                            classes = {"sizeS"},
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
                                classes = {"sizeM"},
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",
                                vmargin = 20,
                                text = displayGameid,
                            },

                            gui.Panel {
                                classes = {"image"},
                                bgimage = "icons/icon_app/icon_app_108.png",
                                styles = {
                                    {
                                        selectors = {"parent:hover"},
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
                            classes = {"sizeS"},
                            text = "This game is currently offline. Put it online to get an invite code that players can use to join.",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            vmargin = 8,
                        },

                        gui.Label {
                            classes = {"sizeS"},
                            text = "A new game ID will be generated and all game data will be copied to the cloud. This may take a moment.",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
                            vmargin = 4,
                        },

                        gui.Button {
                            classes = {"sizeM"},
                            text = "Put Game Online",
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
                            classes = {"sizeM", "bold"},
                            text = "Putting Game Online...",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            vmargin = 8,
                        },

                        gui.Label {
                            classes = {"sizeS"},
                            text = "Preparing...",
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
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
                            classes = {"sizeL", "bold"},
                            text = "Game is Online!",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            vmargin = 4,
                        },

                        BuildInviteCodeView(newGameid),

                        gui.Button {
                            classes = {"sizeL"},
                            text = "Play Online",
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
                            classes = {"sizeM", "bold", "danger"},
                            text = "Failed to Put Game Online",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            vmargin = 4,
                        },

                        gui.Label {
                            classes = {"sizeS"},
                            text = msg,
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            textAlignment = "center",
                            textWrap = true,
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
                    classes = { "framedPanel" },
                    width = 600,
                    height = 400,
                    styles = ThemeEngine.GetStyles(),

                    gui.Label {
                        classes = {"modalTitle"},
                        text = titleText,
                        tmargin = 16,
                    },

                    gui.Button {
                        classes = {"closeButton"},
                        halign = "right",
                        valign = "top",
                        floating = true,
                        margin = 8,
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

        classes = {"row", "bordered"},
        width = "100%",
        height = 40,

        border = { x1 = 0, x2 = 0, y1 = 0, y2 = 1 },

        halign = "center",
        valign = "top",

        flow = "horizontal",

        rowColor = function(element, bgFlag)
            element:SetClass("evenRow", bgFlag)
            element:SetClass("oddRow", not bgFlag)
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

                --DJ delegation (audio): grant/revoke full audio control. Hidden for
                --DM users - a Director already has it. rawget so the menu degrades
                --to no entry if the audio module is absent.
                local audioBar = rawget(_G, "g_drawSteelAudioBar")
                if audioBar ~= nil and dmhub.IsUserDM(userid) == false then
                    if audioBar.IsAudioDelegate(userid) then
                        contextMenu[#contextMenu + 1] = {
                            text = 'Revoke DJ Status',
                            click = function()
                                audioBar.SetAudioDelegate(userid, false)
                                element.popup = nil
                            end,
                        }
                    else
                        contextMenu[#contextMenu + 1] = {
                            text = 'Make DJ',
                            click = function()
                                audioBar.SetAudioDelegate(userid, true)
                                element.popup = nil
                            end,
                        }
                    end
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

                classes = {"image"},

                width = 23 * 2,
                height = 23 * 2,

                bgimage = mod.images.status,

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

                classes = {"sizeS"},
                text = "Director",
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

        },


        --Acitivity text
        gui.Label {

            classes = {"sizeS", "bordered"},
            text = "Playing as MONSTERS",
            textOverflow = "ellipsis",
            textWrap = false,

            border = { x1 = 1, x2 = 0, y1 = 0, y2 = 0 },
            lmargin = 8,
            hpad = 8,
            borderBox = true,

            width = "auto",
            height = "100%",
            maxWidth = "170",

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

        classes = {"row", "bordered"},
        width = "100%",
        height = 40,

        border = { x1 = 0, x2 = 0, y1 = 0, y2 = 1 },

        halign = "center",
        valign = "top",

        flow = "horizontal",

        rowColor = function(element, bgFlag)
            element:SetClass("evenRow", bgFlag)
            element:SetClass("oddRow", not bgFlag)
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

                --DJ delegation (audio): grant/revoke full audio control. Hidden for
                --DM users - a Director already has it. rawget so the menu degrades
                --to no entry if the audio module is absent.
                local audioBar = rawget(_G, "g_drawSteelAudioBar")
                if audioBar ~= nil and dmhub.IsUserDM(userid) == false then
                    if audioBar.IsAudioDelegate(userid) then
                        contextMenu[#contextMenu + 1] = {
                            text = 'Revoke DJ Status',
                            click = function()
                                audioBar.SetAudioDelegate(userid, false)
                                element.popup = nil
                            end,
                        }
                    else
                        contextMenu[#contextMenu + 1] = {
                            text = 'Make DJ',
                            click = function()
                                audioBar.SetAudioDelegate(userid, true)
                                element.popup = nil
                            end,
                        }
                    end
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

                classes = {"image"},

                data = {previousLoggedOut = nil},

                width = 23 * 2,
                height = 23 * 2,

                bgimage = mod.images.status,

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
                    classes = {"sizeS"},
                    text = "Username",
                    textOverflow = "ellipsis",
                    textWrap = false,

                    lmargin = -8,

                    width = "auto",
                    maxWidth = "90",
                    height = "60%",

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
                    classes = {"sizeXs", "bold"},
                    text = "Username",
                    textOverflow = "ellipsis",
                    textWrap = false,

                    lmargin = -8,

                    width = "auto",
                    maxWidth = "90",
                    height = "40%",

                    halign = "left",
                    valign = "top",

                    flow = "horizontal",

                    update = function(element, info)
                        element.text = info.displayName
                    end,
                },

            },


        },

        --Acitivity text
        gui.Label {

            classes = {"sizeS", "bordered"},
            text = "Playing as MONSTERS",
            textOverflow = "ellipsis",
            textWrap = false,

            border = { x1 = 1, x2 = 0, y1 = 0, y2 = 0 },
            lmargin = 8,
            hpad = 8,
            borderBox = true,

            width = "auto",
            height = "100%",
            maxWidth = "170",

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

    local addButtonPanel = CreateAddButtonPanel()

    --king panel
    local heroesPanel = gui.Panel {

        classes = { "kingPanel" },

        height = "100%",
        width = "100%",

        bgcolor = "clear",
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

        styles = ThemeEngine.MergeStyles(g_heroesExtras),



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

                children[#children + 1] = addButtonPanel



                element.children = children

                directorPanels = newPanels
            end,

            addButtonPanel,
        },













    }

    ThemeEngine.OnThemeChanged(mod, function()
        if heroesPanel ~= nil and heroesPanel.valid then
            heroesPanel.styles = ThemeEngine.MergeStyles(g_heroesExtras)
        end
    end)

    return heroesPanel
end

--------------------------------------------------------------------------------
-- SAFETY TOOLS PANEL
--
-- Table safety tools for the whole group: the X-Card, Lines & Veils, the MCDM
-- Tabletop Safety Checklist, and Stars & Wishes session feedback.
--
-- Behavior decisions:
--  * The X-Card never stops or pauses play. Tapping it is purely a quiet
--    notification to the Director. Other players see nothing; the Director
--    sees who tapped it so they can steer the scene and follow up.
--  * Checklist answers are private per user. Everyone sees only the merged,
--    anonymous Lines / Veils / Not My PC topics.
--  * Stars & Wishes submissions are collected into a Director-private journal
--    document ("Director's Journal") under the private journal folder.
--------------------------------------------------------------------------------

SafetyTools = {}

SafetyTools.docId = "safetyTools"
mod:RegisterDocumentForCheckpointBackups(SafetyTools.docId)

SafetyTools.journalTitle = "Director's Journal"

--- The MCDM Tabletop Safety Checklist (from the MCDM Tabletop Safety Toolkit).
--- Each user can privately mark any item as a Line, a Veil, or Not My PC.
SafetyTools.Checklist = {
    {
        id = "horror",
        name = "Horror",
        items = {
            { id = "apocalypses", text = "Apocalypses" },
            { id = "blood", text = "Blood" },
            { id = "body-horror", text = "Body Horror" },
            { id = "demons", text = "Demons" },
            { id = "gore", text = "Gore" },
            { id = "body-parts", text = "Injury to certain body parts (please specify)" },
            { id = "mind-control", text = "Mind Control" },
            { id = "serial-killers", text = "Serial Killers" },
            { id = "vampires", text = "Vampires" },
            { id = "zombies", text = "Zombies" },
        },
    },
    {
        id = "fears",
        name = "Fears and Traumas",
        items = {
            { id = "abduction", text = "Abduction" },
            { id = "bugs", text = "Bugs" },
            { id = "rats", text = "Rats" },
            { id = "snakes", text = "Snakes" },
            { id = "spiders", text = "Spiders" },
            { id = "claustrophobia", text = "Claustrophobia" },
            { id = "dehydration", text = "Dehydration" },
            { id = "drowning", text = "Drowning" },
            { id = "hypothermia", text = "Hypothermia" },
            { id = "involuntary-commitment", text = "Involuntary commitment" },
            { id = "fire", text = "Fire" },
            { id = "starvation", text = "Starvation" },
            { id = "suffocation", text = "Suffocation" },
            { id = "domestic-violence", text = "Domestic violence" },
            { id = "sexual-violence", text = "Sexual violence" },
            { id = "gaslighting", text = "Gaslighting" },
            { id = "imperialism", text = "Imperialism and/or colonialism" },
            { id = "military-violence", text = "Military violence or aggression" },
            { id = "police-violence", text = "Police violence or aggression" },
            { id = "prison", text = "Prison" },
            { id = "terrorism", text = "Terrorism" },
            { id = "torture", text = "Torture" },
            { id = "trypophobia", text = "Trypophobia (fear of holes)" },
        },
    },
    {
        id = "hate",
        name = "Hate speech/discrimination/violence based on",
        items = {
            { id = "hate-disability", text = "Disability" },
            { id = "hate-gender", text = "Gender" },
            { id = "hate-heritage", text = "Heritage" },
            { id = "hate-origin", text = "Land of origin" },
            { id = "hate-race", text = "Race or ancestry" },
            { id = "hate-religion", text = "Religion" },
            { id = "hate-sexuality", text = "Sexuality" },
            { id = "hate-weight", text = "Weight or size" },
        },
    },
    {
        id = "health",
        name = "Health and body",
        items = {
            { id = "addiction", text = "Addiction" },
            { id = "alcohol", text = "Alcohol" },
            { id = "amputation", text = "Amputation" },
            { id = "cancer", text = "Cancer" },
            { id = "dementia", text = "Dementia" },
            { id = "drugs", text = "Drugs" },
            { id = "insanity", text = "\"Insanity\"" },
            { id = "mental-illness", text = "Mental illness" },
            { id = "paralysis", text = "Paralysis" },
            { id = "ptsd", text = "PTSD" },
            { id = "self-harm", text = "Self-harm" },
            { id = "smoking", text = "Smoking" },
            { id = "suicide", text = "Suicide" },
            { id = "vehicle-crash", text = "Vehicle crash" },
            { id = "vomit", text = "Vomit" },
        },
    },
    {
        id = "pregnancy",
        name = "Pregnancy",
        items = {
            { id = "abortion", text = "Abortion" },
            { id = "childbirth", text = "Childbirth" },
            { id = "miscarriage", text = "Miscarriage" },
            { id = "pregnancy-complications", text = "Pregnancy complications" },
            { id = "still-birth", text = "Still birth" },
        },
    },
    {
        id = "threats",
        name = "Threats to",
        items = {
            { id = "threats-animals", text = "Animals" },
            { id = "threats-children", text = "Children" },
            { id = "threats-elders", text = "Elders" },
        },
    },
    {
        id = "harm",
        name = "Harm or violence to",
        items = {
            { id = "harm-animals", text = "Animals" },
            { id = "harm-children", text = "Children" },
            { id = "harm-elders", text = "Elders" },
        },
    },
    {
        id = "disasters",
        name = "Natural Disasters",
        items = {
            { id = "earthquake", text = "Earthquake" },
            { id = "flood", text = "Flood" },
            { id = "storm", text = "Storm" },
            { id = "tsunami", text = "Tsunami" },
            { id = "wildfire", text = "Wildfire" },
        },
    },
    {
        id = "romance",
        name = "Romance",
        items = {
            { id = "light-flirting", text = "Light flirting" },
            { id = "horny-flirting", text = "Horny flirting" },
            { id = "romance-pcs", text = "Romance between PCs" },
            { id = "romance-npcs", text = "Romance between NPCs" },
            { id = "romance-pcs-npcs", text = "Romance between PCs and NPCs" },
        },
    },
    {
        id = "sexual",
        name = "Sexual Content",
        items = {
            { id = "sex-jokes", text = "Jokes about sex or genitalia" },
            { id = "kissing", text = "Kissing" },
            { id = "having-sex", text = "Having sex" },
            { id = "sex-pcs", text = "Sex between PCs" },
            { id = "sex-pcs-npcs", text = "Sex between PCs and NPCs" },
        },
    },
}

SafetyTools.toolDefaults = {
    xcard = true,
    linesveils = true,
    checklist = true,
    starswishes = true,
}

local g_safetyMarkRank = { line = 3, veil = 2, notmypc = 1 }

local g_safetyMarkDefs = {
    { id = "line", text = "L", tooltip = "Line: this should not exist in the world of the game at all." },
    { id = "veil", text = "V", tooltip = "Veil: this can exist in the world, but stays off screen and is not described or roleplayed." },
    { id = "notmypc", text = "PC", tooltip = "Not My PC: fine in the story, as long as it does not impact my character." },
}

function SafetyTools.Path()
    return mod:GetDocumentPath(SafetyTools.docId)
end

function SafetyTools.GetDoc()
    return mod:GetDocumentSnapshot(SafetyTools.docId)
end

function SafetyTools.ToolEnabled(toolid)
    local doc = SafetyTools.GetDoc()
    local tools = doc.data.tools
    if tools == nil or tools[toolid] == nil then
        return SafetyTools.toolDefaults[toolid] == true
    end
    return tools[toolid] == true
end

function SafetyTools.SetToolEnabled(toolid, enabled)
    local doc = SafetyTools.GetDoc()
    doc:BeginChange()
    doc.data.tools = doc.data.tools or {}
    doc.data.tools[toolid] = enabled
    doc:CompleteChange("Safety tools: toggle " .. toolid, { undoable = false })
end

function SafetyTools.DirectorUserIds()
    local result = {}
    for _,userid in ipairs(dmhub.users) do
        local si = dmhub.GetSessionInfo(userid)
        if si ~= nil and si.dm == true then
            result[#result + 1] = userid
        end
    end
    return result
end

--- Tapping the X-Card never stops or interrupts play. It records who tapped
--- and quietly notifies the Director; other players see nothing.
function SafetyTools.InvokeXCard()
    local doc = SafetyTools.GetDoc()
    doc:BeginChange()
    doc.data.xcards = doc.data.xcards or {}
    doc.data.xcards[dmhub.GenerateGuid()] = {
        who = dmhub.userid,
        name = dmhub.userDisplayName,
        t = dmhub.serverTime,
    }
    doc:CompleteChange("X-Card tapped", { undoable = false })

    if SendTitledChatMessage ~= nil then
        local directors = SafetyTools.DirectorUserIds()
        if #directors > 0 then
            SendTitledChatMessage(string.format("%s tapped the X-Card. Steer the scene away; check in when you can.", dmhub.userDisplayName), "X-Card", nil, directors)
        end
    end
end

function SafetyTools.ClearXCard(entryid)
    local doc = SafetyTools.GetDoc()
    if (doc.data.xcards or {})[entryid] == nil then
        return
    end
    doc:BeginChange()
    doc.data.xcards[entryid] = nil
    doc:CompleteChange("X-Card cleared", { undoable = false })
end

--- Adds a Lines & Veils topic. Additions are anonymous: no user is recorded.
function SafetyTools.AddTopic(text, kind)
    text = (text or ""):trim()
    if text == "" then
        return
    end
    local doc = SafetyTools.GetDoc()
    doc:BeginChange()
    doc.data.topics = doc.data.topics or {}
    doc.data.topics[dmhub.GenerateGuid()] = {
        text = text,
        kind = kind or "line",
        t = dmhub.serverTime,
    }
    doc:CompleteChange("Safety topic added", { undoable = false })
end

function SafetyTools.RemoveTopic(topicid)
    local doc = SafetyTools.GetDoc()
    if (doc.data.topics or {})[topicid] == nil then
        return
    end
    doc:BeginChange()
    doc.data.topics[topicid] = nil
    doc:CompleteChange("Safety topic removed", { undoable = false })
end

function SafetyTools.GetMyChecklist()
    local doc = SafetyTools.GetDoc()
    local checklists = doc.data.checklists
    if checklists == nil then
        return {}
    end
    return checklists[dmhub.userid] or {}
end

local function SafetyChecklistWrite(itemid, fn)
    local doc = SafetyTools.GetDoc()
    doc:BeginChange()
    doc.data.checklists = doc.data.checklists or {}
    local mine = doc.data.checklists[dmhub.userid] or {}
    doc.data.checklists[dmhub.userid] = mine
    local entry = mine[itemid] or {}
    mine[itemid] = entry
    fn(entry)
    if entry.mark == nil and (entry.note == nil or entry.note == "") then
        mine[itemid] = nil
    end
    doc:CompleteChange("Safety checklist updated", { undoable = false })
end

function SafetyTools.SetChecklistMark(itemid, mark)
    SafetyChecklistWrite(itemid, function(entry)
        entry.mark = mark
    end)
end

function SafetyTools.SetChecklistNote(itemid, note)
    SafetyChecklistWrite(itemid, function(entry)
        entry.note = note
    end)
end

--- Merges anonymous custom topics with everyone's checklist marks into
--- { line = {...}, veil = {...}, notmypc = {...} }. For checklist items the
--- strongest mark across all users wins (line > veil > notmypc).
function SafetyTools.MergedTopics()
    local doc = SafetyTools.GetDoc()
    local result = { line = {}, veil = {}, notmypc = {} }

    for topicid,topic in pairs(doc.data.topics or {}) do
        local kind = topic.kind or "line"
        if result[kind] ~= nil then
            local list = result[kind]
            list[#list + 1] = { text = topic.text or "", topicid = topicid }
        end
    end

    local itemMarks = {}
    for _,checklist in pairs(doc.data.checklists or {}) do
        if type(checklist) == "table" then
            for itemid,entry in pairs(checklist) do
                local mark = entry.mark
                if mark ~= nil and g_safetyMarkRank[mark] ~= nil then
                    local existing = itemMarks[itemid]
                    if existing == nil or g_safetyMarkRank[mark] > g_safetyMarkRank[existing] then
                        itemMarks[itemid] = mark
                    end
                end
            end
        end
    end

    local itemText = {}
    for _,cat in ipairs(SafetyTools.Checklist) do
        for _,item in ipairs(cat.items) do
            itemText[item.id] = item.text
        end
    end

    for itemid,mark in pairs(itemMarks) do
        if itemText[itemid] ~= nil then
            local list = result[mark]
            list[#list + 1] = { text = itemText[itemid], itemid = itemid }
        end
    end

    for _,list in pairs(result) do
        table.sort(list, function(a, b)
            return a.text < b.text
        end)
    end

    return result
end

function SafetyTools.SubmitStarsWishes(star, wish)
    star = (star or ""):trim()
    wish = (wish or ""):trim()
    if star == "" and wish == "" then
        return false
    end

    local doc = SafetyTools.GetDoc()
    doc:BeginChange()
    doc.data.wishes = doc.data.wishes or {}
    doc.data.wishes[dmhub.GenerateGuid()] = {
        who = dmhub.userid,
        name = dmhub.userDisplayName,
        star = star,
        wish = wish,
        t = dmhub.serverTime,
        date = os.date("%Y-%m-%d"),
        journaled = false,
    }
    doc:CompleteChange("Stars & Wishes submitted", { undoable = false })

    if SendTitledChatMessage ~= nil then
        local directors = SafetyTools.DirectorUserIds()
        if #directors > 0 then
            SendTitledChatMessage(string.format("%s submitted Stars & Wishes feedback.", dmhub.userDisplayName), "Stars & Wishes", nil, directors)
        end
    end

    return true
end

function SafetyTools.UnjournaledWishes()
    local doc = SafetyTools.GetDoc()
    local pending = {}
    for id,w in pairs(doc.data.wishes or {}) do
        if not w.journaled then
            pending[#pending + 1] = { id = id, wish = w }
        end
    end
    table.sort(pending, function(a, b)
        return (a.wish.t or 0) < (b.wish.t or 0)
    end)
    return pending
end

--- Runs on the Director's client only: appends any new Stars & Wishes
--- submissions to the Director-private journal document, creating it under
--- the private journal folder if needed. If a journal document is close to
--- the document size cap, a fresh one is started and becomes the new target.
function SafetyTools.SyncWishesToJournal()
    if not dmhub.isDM then
        return
    end

    local pending = SafetyTools.UnjournaledWishes()
    if #pending == 0 then
        return
    end

    local entriesText = {}
    for _,p in ipairs(pending) do
        local w = p.wish
        local lines = {}
        lines[#lines + 1] = string.format("## %s - %s", w.date or os.date("%Y-%m-%d"), w.name or "Unknown")
        lines[#lines + 1] = ""
        if w.star ~= nil and w.star ~= "" then
            lines[#lines + 1] = string.format("**Star:** %s", w.star)
            lines[#lines + 1] = ""
        end
        if w.wish ~= nil and w.wish ~= "" then
            lines[#lines + 1] = string.format("**Wish:** %s", w.wish)
            lines[#lines + 1] = ""
        end
        entriesText[#entriesText + 1] = table.concat(lines, "\n")
    end
    local newEntries = table.concat(entriesText, "\n")

    local doc = SafetyTools.GetDoc()
    local documentsTable = dmhub.GetTable(CustomDocument.tableName) or {}
    local journal = nil
    if doc.data.journalDocId ~= nil then
        journal = documentsTable[doc.data.journalDocId]
        if journal ~= nil and journal.hidden then
            journal = nil
        end
    end

    local originalJournal = nil
    local existingText = ""
    if journal ~= nil then
        existingText = journal:GetTextContent() or ""
        if #existingText + #newEntries > CustomDocument.MaxLength - 512 then
            --this journal is nearly full; start a fresh one.
            journal = nil
            existingText = ""
        else
            originalJournal = DeepCopy(journal)
        end
    end

    if journal == nil then
        journal = MarkdownDocument.new{
            content = "",
            annotations = {},
        }
        journal.id = dmhub.GenerateGuid()
        journal.description = SafetyTools.journalTitle
        journal.parentFolder = "private"
        journal.hiddenFromPlayers = true
        existingText = "Session feedback collected by the Safety Tools panel.\n"
    end

    journal:SetTextContent(existingText .. "\n" .. newEntries)
    journal:Upload(originalJournal)

    doc:BeginChange()
    doc.data.journalDocId = journal.id
    for _,p in ipairs(pending) do
        local w = doc.data.wishes[p.id]
        if w ~= nil then
            w.journaled = true
        end
    end
    doc:CompleteChange("Stars & Wishes journaled", { undoable = false })
end

function SafetyTools.OpenJournal()
    if not dmhub.isDM then
        return
    end
    SafetyTools.SyncWishesToJournal()
    local doc = SafetyTools.GetDoc()
    if doc.data.journalDocId == nil then
        return
    end
    local journal = (dmhub.GetTable(CustomDocument.tableName) or {})[doc.data.journalDocId]
    if journal ~= nil then
        journal:ShowDocument()
    end
end

local function SafetyDescribeAgo(seconds)
    if seconds < 60 then
        return "just now"
    elseif seconds < 3600 then
        return string.format("%dm ago", round(seconds / 60))
    elseif seconds < 86400 then
        return string.format("%dh ago", round(seconds / 3600))
    else
        return string.format("%dd ago", round(seconds / 86400))
    end
end

local function SafetySectionHeader(text)
    return gui.Label{
        classes = { "sizeM", "bold" },
        width = "96%",
        height = "auto",
        halign = "center",
        text = text,
    }
end

local function SafetyCaption(text)
    return gui.Label{
        classes = { "fgMuted", "sizeXs" },
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 2,
        text = text,
    }
end

local function CreateXCardSection()
    local confirmLabel
    confirmLabel = gui.Label{
        classes = { "success", "sizeS", "collapsed" },
        width = "94%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        text = "The Director has been notified.",
    }

    local tapButton = gui.Panel{
        classes = { "bordered", "borderDanger", "hoverable" },
        width = "auto",
        height = 52,
        halign = "center",
        vmargin = 6,
        hpad = 24,
        flow = "horizontal",
        press = function(element)
            SafetyTools.InvokeXCard()
            confirmLabel:SetClass("collapsed", false)
            dmhub.Schedule(5, function()
                if mod.unloaded then
                    return
                end
                if confirmLabel ~= nil and confirmLabel.valid then
                    confirmLabel:SetClass("collapsed", true)
                end
            end)
        end,
        gui.Label{
            classes = { "danger", "bold", "sizeXl" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = "X",
        },
        gui.Label{
            classes = { "sizeS" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 10,
            text = "Tap the X-Card",
        },
    }

    local directorRows = gui.Panel{
        width = "94%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,
        refreshSafety = function(element)
            if not dmhub.isDM then
                element:SetClass("collapsed", true)
                return
            end

            local doc = SafetyTools.GetDoc()
            local entries = {}
            for id,entry in pairs(doc.data.xcards or {}) do
                entries[#entries + 1] = { id = id, name = entry.name, t = entry.t or 0 }
            end
            table.sort(entries, function(a, b)
                return a.t > b.t
            end)

            element:SetClass("collapsed", #entries == 0)

            local rows = {}
            for _,entry in ipairs(entries) do
                local entryid = entry.id
                rows[#rows + 1] = gui.Panel{
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    gui.Label{
                        classes = { "sizeS", "bold" },
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        text = entry.name or "Unknown",
                    },
                    gui.Label{
                        classes = { "sizeXs", "fgMuted" },
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 8,
                        text = SafetyDescribeAgo(dmhub.serverTime - entry.t),
                    },
                    gui.Panel{
                        classes = { "multiselectChipRemove" },
                        hidden = 0,
                        halign = "right",
                        valign = "center",
                        press = function()
                            SafetyTools.ClearXCard(entryid)
                        end,
                        gui.Label{
                            classes = { "multiselectChipRemove" },
                            text = "X",
                        },
                    },
                }
            end
            element.children = rows
        end,
    }

    local captionText = "Tapping quietly notifies the Director. Other players will not see anything, and play is not interrupted."
    if dmhub.isDM then
        captionText = "Players can tap this to quietly flag a scene. Only you see who tapped it; play is never interrupted."
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        pad = 6,
        borderBox = true,
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", not SafetyTools.ToolEnabled("xcard"))
        end,
        SafetySectionHeader("X-Card"),
        SafetyCaption(captionText),
        tapButton,
        confirmLabel,
        directorRows,
    }
end

local function CreateLinesVeilsSection()
    local groupsPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        refreshSafety = function(element)
            local merged = SafetyTools.MergedTopics()
            local groups = {
                { key = "line", title = "Lines", prefix = "X", chipClass = "danger", tooltip = "Excluded from the game entirely." },
                { key = "veil", title = "Veils", prefix = "~", chipClass = "info", tooltip = "Can exist in the world, but stays off screen." },
                { key = "notmypc", title = "Not My PC", prefix = "-", chipClass = "fgMuted", tooltip = "Fine in the story, as long as it does not impact that player's character." },
            }

            local children = {}
            for _,group in ipairs(groups) do
                local list = merged[group.key]
                if #list > 0 then
                    children[#children + 1] = gui.Label{
                        classes = { "sizeS", "bold" },
                        width = "100%",
                        height = "auto",
                        tmargin = 4,
                        text = group.title,
                    }

                    local chips = {}
                    for _,topic in ipairs(list) do
                        local topicid = topic.topicid
                        local chipChildren = {
                            gui.Label{
                                classes = { "multiselectChipText", group.chipClass },
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                text = string.format("%s %s", group.prefix, topic.text),
                            },
                        }
                        if dmhub.isDM and topicid ~= nil then
                            chipChildren[#chipChildren + 1] = gui.Panel{
                                classes = { "multiselectChipRemove" },
                                hidden = 0,
                                halign = "left",
                                valign = "center",
                                lmargin = 4,
                                press = function()
                                    SafetyTools.RemoveTopic(topicid)
                                end,
                                gui.Label{
                                    classes = { "multiselectChipRemove" },
                                    text = "X",
                                },
                            }
                        end

                        chips[#chips + 1] = gui.Panel{
                            classes = { "multiselectChip" },
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            flow = "horizontal",
                            hmargin = 2,
                            vmargin = 2,
                            pad = 4,
                            linger = gui.Tooltip(group.tooltip),
                            children = chipChildren,
                        }
                    end

                    children[#children + 1] = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        wrap = true,
                        children = chips,
                    }
                end
            end

            if #children == 0 then
                children[#children + 1] = gui.Label{
                    classes = { "fgMuted", "sizeS" },
                    width = "100%",
                    height = "auto",
                    text = "No topics yet. Add one below, or fill out the checklist.",
                }
            end

            element.children = children
        end,
    }

    local kindChosen = "line"
    local topicInput
    topicInput = gui.Input{
        classes = { "input" },
        width = "38%",
        height = 24,
        halign = "left",
        valign = "center",
        borderBox = true,
        placeholderText = "Add a topic...",
    }

    local addRow = gui.Panel{
        width = "96%",
        height = 28,
        halign = "center",
        tmargin = 6,
        flow = "horizontal",
        topicInput,
        gui.Dropdown{
            classes = { "sizeS" },
            width = 74,
            height = 24,
            halign = "left",
            valign = "center",
            lmargin = 4,
            options = {
                { id = "line", text = "Line" },
                { id = "veil", text = "Veil" },
            },
            idChosen = "line",
            change = function(element)
                kindChosen = element.idChosen
            end,
        },
        gui.Button{
            classes = { "sizeXs" },
            width = 56,
            height = 24,
            halign = "left",
            valign = "center",
            lmargin = 4,
            text = "Add",
            click = function(element)
                SafetyTools.AddTopic(topicInput.text, kindChosen)
                topicInput.text = ""
            end,
        },
    }

    local captionText = "Everyone sees this merged list. Additions are anonymous, and checklist marks appear here automatically."
    if dmhub.isDM then
        captionText = captionText .. " As Director you can remove custom topics."
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        pad = 6,
        borderBox = true,
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", not SafetyTools.ToolEnabled("linesveils"))
        end,
        SafetySectionHeader("Lines & Veils"),
        SafetyCaption(captionText),
        groupsPanel,
        addRow,
    }
end

local function CreateChecklistItemRow(item)
    local noteInput
    local markButtons = {}
    local orderedButtons = {}

    local function CurrentMark()
        local entry = SafetyTools.GetMyChecklist()[item.id]
        if entry == nil then
            return nil
        end
        return entry.mark
    end

    local function RefreshRow()
        local mark = CurrentMark()
        for markid,button in pairs(markButtons) do
            button:SetClass("selected", mark == markid)
        end
        noteInput:SetClass("collapsed", mark == nil)
    end

    for _,markDef in ipairs(g_safetyMarkDefs) do
        local markid = markDef.id
        local button = gui.Button{
            classes = { "sizeXxs" },
            width = 28,
            height = 20,
            halign = "right",
            valign = "center",
            hmargin = 1,
            text = markDef.text,
            linger = gui.Tooltip(markDef.tooltip),
            click = function(element)
                local newMark = markid
                if CurrentMark() == markid then
                    newMark = nil
                end
                SafetyTools.SetChecklistMark(item.id, newMark)
                RefreshRow()
            end,
        }
        markButtons[markid] = button
        orderedButtons[#orderedButtons + 1] = button
    end

    local existingEntry = SafetyTools.GetMyChecklist()[item.id]
    noteInput = gui.Input{
        classes = { "input", "collapsed" },
        width = "92%",
        height = 22,
        halign = "right",
        borderBox = true,
        vmargin = 2,
        placeholderText = "Notes (optional)",
        text = (existingEntry ~= nil and existingEntry.note) or "",
        change = function(element)
            SafetyTools.SetChecklistNote(item.id, element.text)
        end,
    }

    local row = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        refreshSafety = function(element)
            RefreshRow()
        end,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Label{
                classes = { "sizeS" },
                width = "55%",
                height = "auto",
                halign = "left",
                valign = "center",
                text = item.text,
            },
            orderedButtons[1],
            orderedButtons[2],
            orderedButtons[3],
        },
        noteInput,
    }

    RefreshRow()

    return row
end

local function CreateChecklistCategory(cat)
    local arrow
    local contentPanel

    contentPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { built = false },
    }

    --building a whole category's rows in one frame causes a visible hitch on
    --first expand (a 23-item category is ~27ms of widget construction before
    --layout), so rows are built in small batches spread across frames.
    local BUILD_BATCH_SIZE = 6

    local function BuildRowsIncrementally(index)
        if not contentPanel.valid then
            return
        end
        local limit = math.min(index + BUILD_BATCH_SIZE - 1, #cat.items)
        for i = index, limit do
            contentPanel:AddChild(CreateChecklistItemRow(cat.items[i]))
        end
        if limit < #cat.items then
            dmhub.Schedule(0.01, function()
                if mod.unloaded then
                    return
                end
                BuildRowsIncrementally(limit + 1)
            end)
        end
    end

    local function ToggleExpand()
        local nowExpanded = not arrow:HasClass("expanded")
        arrow:SetClass("expanded", nowExpanded)
        if nowExpanded and not contentPanel.data.built then
            contentPanel.data.built = true
            BuildRowsIncrementally(1)
        end
        contentPanel:SetClass("collapsed", not nowExpanded)
    end

    --the arrow is visual only: the header's press handles clicks anywhere in
    --the row, including on the arrow. Giving the arrow its own click handler
    --too made one click toggle twice (expand then instantly collapse).
    arrow = gui.ExpandoArrow{
        halign = "left",
        valign = "center",
        interactable = false,
    }

    --bgimage makes the whole row a hit target so clicks on the arrow and the
    --empty space land on this press, not just clicks on the text labels.
    local header = gui.Panel{
        classes = { "hoverable", "transparent" },
        bgimage = true,
        width = "100%",
        height = "auto",
        minHeight = 24,
        flow = "horizontal",
        press = function(element)
            ToggleExpand()
        end,
        arrow,
        gui.Label{
            classes = { "sizeS", "bold" },
            width = "60%",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 4,
            text = cat.name,
        },
        gui.Label{
            classes = { "sizeXs", "fgMuted" },
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            text = "",
            refreshSafety = function(element)
                local mine = SafetyTools.GetMyChecklist()
                local count = 0
                for _,item in ipairs(cat.items) do
                    local entry = mine[item.id]
                    if entry ~= nil and entry.mark ~= nil then
                        count = count + 1
                    end
                end
                if count > 0 then
                    element.text = string.format("%d marked", count)
                else
                    element.text = ""
                end
            end,
        },
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        header,
        contentPanel,
    }
end

local function CreateChecklistSection()
    local categories = {}
    for _,cat in ipairs(SafetyTools.Checklist) do
        categories[#categories + 1] = CreateChecklistCategory(cat)
    end

    local children = {
        SafetySectionHeader("Safety Checklist"),
        SafetyCaption("Mark any topic as a Line, a Veil, or Not My PC. Your answers are private; only the combined, anonymous topics appear above. Change them any time."),
    }
    for _,catPanel in ipairs(categories) do
        children[#children + 1] = catPanel
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        pad = 6,
        borderBox = true,
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", not SafetyTools.ToolEnabled("checklist"))
        end,
        children = children,
    }
end

local function CreateStarsWishesSection()
    local starInput = gui.Input{
        classes = { "input" },
        width = "94%",
        height = "auto",
        minHeight = 40,
        halign = "center",
        borderBox = true,
        vmargin = 2,
        multiline = true,
        placeholderText = "Star: something you loved this session",
    }

    local wishInput = gui.Input{
        classes = { "input" },
        width = "94%",
        height = "auto",
        minHeight = 40,
        halign = "center",
        borderBox = true,
        vmargin = 2,
        multiline = true,
        placeholderText = "Wish: something you would like to see in a future session",
    }

    local confirmLabel = gui.Label{
        classes = { "success", "sizeS", "collapsed" },
        width = "94%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        text = "Sent to the Director. Thank you!",
    }

    local playerForm = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", dmhub.isDM)
        end,
        starInput,
        wishInput,
        gui.Button{
            classes = { "sizeS" },
            halign = "center",
            vmargin = 4,
            text = "Send to Director",
            click = function(element)
                local submitted = SafetyTools.SubmitStarsWishes(starInput.text, wishInput.text)
                if submitted then
                    starInput.text = ""
                    wishInput.text = ""
                    confirmLabel:SetClass("collapsed", false)
                    dmhub.Schedule(5, function()
                        if mod.unloaded then
                            return
                        end
                        if confirmLabel ~= nil and confirmLabel.valid then
                            confirmLabel:SetClass("collapsed", true)
                        end
                    end)
                end
            end,
        },
        confirmLabel,
    }

    local dmCountLabel = gui.Label{
        classes = { "sizeS" },
        width = "94%",
        height = "auto",
        halign = "center",
        text = "",
    }

    local dmSummary = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        refreshSafety = function(element)
            if not dmhub.isDM then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)

            --keep the Director's Journal up to date with any new submissions.
            SafetyTools.SyncWishesToJournal()

            local doc = SafetyTools.GetDoc()
            local count = 0
            for _,_ in pairs(doc.data.wishes or {}) do
                count = count + 1
            end
            if count == 0 then
                dmCountLabel.text = "No feedback submitted yet."
            elseif count == 1 then
                dmCountLabel.text = "1 submission, collected in your Director's Journal."
            else
                dmCountLabel.text = string.format("%d submissions, collected in your Director's Journal.", count)
            end
        end,
        dmCountLabel,
        gui.Button{
            classes = { "sizeS" },
            width = 200,
            halign = "center",
            vmargin = 4,
            text = "Open Director's Journal",
            click = function(element)
                SafetyTools.OpenJournal()
            end,
        },
    }

    local captionText = "End-of-session feedback for the Director. Submissions include your name."
    if dmhub.isDM then
        captionText = "Players send a Star and a Wish at the end of a session. Entries land in your private Director's Journal."
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        pad = 6,
        borderBox = true,
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", not SafetyTools.ToolEnabled("starswishes"))
        end,
        SafetySectionHeader("Stars & Wishes"),
        SafetyCaption(captionText),
        playerForm,
        dmSummary,
    }
end

local function CreateToolsConfigSection()
    local toolDefs = {
        { id = "xcard", text = "X-Card" },
        { id = "linesveils", text = "Lines & Veils" },
        { id = "checklist", text = "Safety Checklist" },
        { id = "starswishes", text = "Stars & Wishes" },
    }

    local children = {
        SafetySectionHeader("Tools in Play"),
        SafetyCaption("Choose which safety tools are active for this campaign. Safety tools work best when the whole table opts in during session zero."),
    }

    for _,tool in ipairs(toolDefs) do
        local toolid = tool.id
        children[#children + 1] = gui.Check{
            classes = { "sizeS" },
            width = "94%",
            height = 22,
            minWidth = 0,
            halign = "center",
            text = tool.text,
            value = SafetyTools.ToolEnabled(toolid),
            change = function(element)
                SafetyTools.SetToolEnabled(toolid, element.value)
            end,
            refreshSafety = function(element)
                element.value = SafetyTools.ToolEnabled(toolid)
            end,
        }
    end

    return gui.Panel{
        classes = { "bordered" },
        width = "100%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        pad = 6,
        borderBox = true,
        flow = "vertical",
        refreshSafety = function(element)
            element:SetClass("collapsed", not dmhub.isDM)
        end,
        children = children,
    }
end

local function CreateSafetyToolsPanel()
    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        hpad = 6,
        flow = "vertical",
        bgimage = true,
        bgcolor = "clear",
        styles = ThemeEngine.GetStyles(),
        monitorGame = SafetyTools.Path(),
        refreshGame = function(element)
            element:FireEventTree("refreshSafety")
        end,
        create = function(element)
            element:FireEventTree("refreshSafety")
        end,
        CreateXCardSection(),
        CreateLinesVeilsSection(),
        CreateChecklistSection(),
        CreateStarsWishesSection(),
        CreateToolsConfigSection(),
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

DockablePanel.Register{
    name = "Safety Tools",
    icon = "icons/standard/Icon_App_Check.png",
    minHeight = 200,
    vscroll = true,
    dmonly = false,
    content = function()
        track("panel_open", {
            panel = "SafetyTools",
            dailyLimit = 30,
        })
        return CreateSafetyToolsPanel()
    end,
}


local mod = dmhub.GetModLoading()

local g_directlyLaunchingGame = false

local g_titlescreen = nil

for _, str in ipairs(dmhub.commandLineArguments) do
    if str == "--gameid" then
        g_directlyLaunchingGame = true
    end
end

if g_directlyLaunchingGame then
    return
end

local function ScaleDimensions(dim)
    return dim * math.max(1, (dmhub.screenDimensions.x / dmhub.screenDimensions.y) / (1920 / 1080))
end

local resistanceCurve = function(x)
    x = x * 2
    local negative = x < 0
    x = math.abs(x)
    local y = 1 - (1 - x) ^ 2
    if negative then
        y = -y
    end

    return y
end

local g_setRecommendedGraphics = setting{
    id = "setrecommendedgraphicssettings",
    storage = "preference",
    default = false,
}

if not g_setRecommendedGraphics:Get() then
    g_setRecommendedGraphics:Set(true)

    dmhub.SetSettingValue("backgroundfps", false)
    dmhub.SetSettingValue("perf:hdr", true)
    dmhub.SetSettingValue("perf:hidefdice", true)
    dmhub.SetSettingValue("perf:castshadows", true)
    local systemPower = dmhub.systemHardwareRating
    if systemPower < 1 then
        print("Setting recommended graphics settings for a low power system")
        dmhub.SetSettingValue("perf:postprocess", false)
        dmhub.SetSettingValue("perf:msaa", false)
        dmhub.SetSettingValue("blackbarsoff", false)
        dmhub.SetSettingValue("vsync", 0)
        dmhub.SetSettingValue("fps", 30)
    else
        print("Setting recommended graphics settings for a high power system")
        dmhub.SetSettingValue("perf:postprocess", true)
        dmhub.SetSettingValue("perf:msaa", true)
        dmhub.SetSettingValue("blackbarsoff", true)
        dmhub.SetSettingValue("vsync", 1)
        dmhub.SetSettingValue("fps", 60)
    end

end

local g_directorGamePageSetting = setting {
    id = "dirgamepage",
    storage = "preference",
    default = 1,
}

local g_playerGamePageSetting = setting {
    id = "playergamepage",
    storage = "preference",
    default = 1,
}

local g_streamerModeSetting = setting {
    id = "streamermode",
    description = "Streamer Mode",
    help = "When enabled, game codes are hidden",
    editor = "check",
    storage = "preference",
    section = "general",
    default = false,
}

local g_gamePageSetting = g_playerGamePageSetting

local function TooManyGamesDialog(element)
    local modal
    modal = gui.Panel {
        classes = { "framedPanel" },
        styles = {
            Styles.Default,
            Styles.Panel,
        },
        width = 600,
        height = 300,
        halign = "center",
        valign = "center",
        bgimage = true,
        flow = "vertical",
        floating  = true,

        gui.Label {
            classes = { "title" },
            text = "Too Many Games",
            fontSize = 20,
            width = "auto",
            halign = "center",
            valign = "top",
            bold = true,
        },

        gui.Label {
            classes = { "dialogMessage" },
            text = "You are already participating in too many games. Leave or delete some games before creating more.",
            fontSize = 20,
            width = "auto",
            maxWidth = 500,
            textAlignment = "center",
            halign = "center",
        },


        gui.Button {
            classes = { "dialogButton" },
            text = "Close",
            halign = "center",
            valign = "bottom",
            scale = 1.4,
            bmargin = 15,
            click = function(element)
                modal:DestroySelf()
            end,
        },

    }

    element.root:AddChild(modal)
end


local function EditHero(element, character)
    character:ShowSheet()

    g_titlescreen:SetClass("titlescreenHidden", true)
    print("TITLESCREEN:: HIDE")

    local handler
    handler = dmhub.RegisterEventHandler("characterSheetClosed", function()
        g_titlescreen:SetClass("titlescreenHidden", false)
        dmhub.DeregisterEventHandler(handler)
        print("TITLESCREEN:: SHOW")
        handler = nil
    end)
end

local function ImportForgeSteel(element)
    FSCIImporter.ImportCharacter(function(c)
        c:ModifyProperties {
            description = "Create Character",
            execute = function()
                c.properties.mtime = ServerTimestamp()
                c.properties.creatorid = dmhub.userid
            end,
        }
    end)
end

local function CreateHero(element)
    local heroType = nil
    local characterTypes = dmhub.GetTable(CharacterType.tableName)
    for k, v in pairs(characterTypes) do
        if (not (rawget(v, "hidden"))) and v.name == "Hero" then
            heroType = v
            break
        end
    end

    if heroType ~= nil then
        local charid = game.CreateCharacter("character", heroType)

        dmhub.Coroutine(function()
            for i = 1, 100 do
                local c = dmhub.GetCharacterById(charid)
                if c ~= nil then
                    if element ~= nil and element.valid then
                        c:ModifyProperties {
                            description = "Create Character",
                            execute = function()
                                c.properties.mtime = ServerTimestamp()
                                c.properties.originalid = charid
                                c.properties.creatorid = dmhub.userid
                            end,
                        }
                        EditHero(element, c)
                    end
                    return
                end

                coroutine.yield(0.01)
            end
        end)
    end
end

local function CreateJoinGameModal(tokenToImport)
    local resultPanel

    local function AlreadyInGame(gameid)
        local games = lobby.games
        for _, game in ipairs(games) do
            if game.gameid == gameid then
                return true
            end
        end

        return false
    end

    local m_password = ""

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = {
                Styles.Default,
                Styles.Panel,
                gui.Style {
                    selectors = { "label" },
                    width = "80%",
                    height = "auto",
                    textAlignment = "left",
                    halign = "center",
                    fontSize = 16,
                    vmargin = 4,
                },
                gui.Style {
                    selectors = { "input" },
                    width = "80%-16",
                    halign = "center",
                    fontSize = 16,
                    borderWidth = 1,
                    borderColor = Styles.textColor,
                },
            },
            classes = { "framedPanel" },
            bgimage = true,
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                classes = { "dialogTitle" },
                text = "Join Game",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Invite Code:",
            },

            gui.Input {
                classes = { "formInput" },
                text = "",
                placeholderText = "Enter Invite Code...",
                fontSize = 18,
                vpad = 8,
                editlag = 0.25,
                change = function(element)
                end,
                edit = function(element)
                    if element.text ~= "" then
                        resultPanel:FireEventTree("searchingForGame")

                        local text = element.text
                        lobby:LookupGame(text, function(gameInfo)
                            if text == element.text then
                                resultPanel:FireEventTree("lookupGame", gameInfo, text)
                            end
                        end)
                    else
                        resultPanel:FireEventTree("clearLookup")
                    end
                end,
            },

            gui.Label {
                text = "(Ask your Director for this code)",
            },

            gui.Label {
                classes = { "collapsed" },
                valign = "center",
                fontSize = 16,
                text = "Searching",
                data = {
                    n = 0,
                },
                thinkTime = 0.1,
                think = function(element)
                    element.data.n = element.data.n + 1
                    element.text = "Searching" .. string.rep(".", element.data.n % 4)
                end,
                searchingForGame = function(element)
                    element:SetClass("collapsed", false)
                end,
                lookupGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,
            },

            gui.Label {
                classes = { "collapsed" },
                valign = "center",
                fontSize = 16,
                text = "This game could not be found. Please check the invite code and try again.",
                searchingForGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                lookupGame = function(element, gameInfo)
                    element:SetClass("collapsed", false)
                    if gameInfo == nil then
                        element.text = "This game could not be found. Please check the invite code and try again."
                    elseif gameInfo.deleted then
                        element.text = "This game has been deleted."
                    elseif AlreadyInGame(gameInfo.gameid) then
                        element.text = "You are already in this game."
                    else
                        element:SetClass("collapsed", true)
                    end
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,
            },

            gui.Panel {
                classes = { "collapsed" },
                halign = "center",
                valign = "center",
                flow = "vertical",
                height = "auto",
                width = "80%",
                lookupGame = function(element, gameInfo)
                    element:SetClass("collapsed", gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid))
                end,
                searchingForGame = function(element)
                    element:SetClass("collapsed", true)
                end,
                clearLookup = function(element)
                    element:SetClass("collapsed", true)
                end,

                gui.Label {
                    fontSize = 28,
                    bold = true,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = gameInfo.description
                    end,
                },

                gui.Label {
                    fontSize = 16,
                    bold = true,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = string.format("Directed by %s", gameInfo.ownerDisplayName)
                    end,
                },

                gui.Label {
                    fontSize = 20,
                    width = "100%",
                    textAlignment = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.text = gameInfo.descriptionDetails
                    end,
                },

                gui.Panel {
                    bgcolor = "white",
                    width = "100%",
                    height = "56.25% width", --16:9 aspect ratio
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        element.data.coverart = gameInfo.coverart
                        element.thinkTime = 0.01
                    end,

                    think = function(element)
                        if element.data.coverart ~= nil then
                            element.bgimage = element.data.coverart
                        end
                    end,
                },
            },

            gui.Panel {
                classes = { "hidden" },
                flow = "horizontal",
                width = "80%",
                height = "auto",
                halign = "center",
                lookupGame = function(element, gameInfo)
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or gameInfo.password == nil or
                        gameInfo.password == "")
                end,
                gui.Label {
                    fontSize = 16,
                    width = "auto",
                    minWidth = 140,
                    text = "Password:",
                    textAlignment = "left",
                    halign = "left",
                },
                gui.Input {
                    password = true,
                    width = 180,
                    height = 20,
                    placeholderText = "Enter Password...",
                    fontSize = 16,
                    halign = "left",
                    lookupGame = function(element, gameInfo)
                        if gameInfo == nil then
                            return
                        end

                        m_password = ""
                        element.text = ""
                    end,
                    edit = function(element)
                        m_password = element.text
                        element.parent.parent:FireEventTree("passwordUpdated")
                    end,
                },
            },

            gui.Button {
                text = "Join Game",
                classes = { "hidden" },
                fontSize = 22,
                width = "auto",
                height = "auto",
                hpad = 12,
                vpad = 8,
                halign = "center",
                valign = "bottom",
                lookupGame = function(element, gameInfo)
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or
                        (gameInfo.password ~= nil and gameInfo.password ~= "" and gameInfo.password ~= m_password))
                    element.data.gameInfo = gameInfo
                end,
                passwordUpdated = function(element)
                    local gameInfo = element.data.gameInfo
                    if gameInfo == nil then
                        return
                    end
                    element:SetClass("hidden",
                        gameInfo == nil or gameInfo.deleted or AlreadyInGame(gameInfo.gameid) or
                        (gameInfo.password ~= nil and gameInfo.password ~= "" and gameInfo.password ~= m_password))
                end,
                searchingForGame = function(element)
                    element:SetClass("hidden", true)
                end,
                clearLookup = function(element)
                    element:SetClass("hidden", true)
                end,
                press = function(element)
                    local gameid = element.data.gameInfo.gameid

                    if tokenToImport ~= nil then
                        tokenToImport:ModifyProperties {
                            description = "Joining Game",
                            execute = function()
                                tokenToImport.properties.mtime = ServerTimestamp()
                                tokenToImport.properties.joinedCampaign = gameid
                            end,
                        }
                    end

                    lobby:JoinGame(gameid)
                    local root = element.root

                    dmhub.Coroutine(function()
                        for i = 1, 100 do
                            local games = lobby.games
                            for _, game in ipairs(games) do
                                if game.gameid == gameid then
                                    if root ~= nil and root.valid then
                                        local callback
                                        if tokenToImport ~= nil then
                                            dmhub.CopyTokenToClipboard(tokenToImport)
                                            callback = function()
                                                dmhub.PasteTokenFromClipboard(core.Loc { x = 0, y = 0 })
                                            end
                                        end
                                        root:FireEventTree("overrideLoadingScreenArt", game.coverart)
                                        lobby:EnterGame(game.gameid, callback)
                                    end
                                    return
                                end
                            end

                            coroutine.yield(0.1)
                        end
                    end)

                    resultPanel:DestroySelf()
                end,
            },

            gui.CloseButton {
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            }
        }
    }

    return resultPanel
end

local g_moduleOptions = {
    {
        id = "venla-deliantomb",
        text = "The Delian Tomb",
        descriptionDetails =
        "This is the classic starter adventure from Matt Colville's Running the Game series, expanded and updated for MCDM's new fantasy RPG Draw Steel! The Delian Tomb includes everything you need to get started including a step-by-step tutorial for both players and directors!",
        coverart = "panels/backgrounds/delian-tomb-bg.png",
    },
    {
        id = "mcdm-startermap",
        text = "Draw Steel! Custom Campaign",
        descriptionDetails =
        "Forge your own adventure with Draw Steel! We'll start you in a tavern with all the Draw Steel rules and you can take it from there.",
        coverart = "panels/backgrounds/mcdm-cinematic.jpeg",
    },
}

local function CreateGameEditor(options)
    local mode = options.mode or "create"
    local resultPanel

    local m_game = options.game

    local m_uploadCoverArt = nil

    print("CREATE EDITOR")

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = {
                Styles.Default,
                Styles.Panel,
                gui.Style {
                    selectors = { "label" },
                    width = "80%",
                    height = "auto",
                    textAlignment = "left",
                    halign = "center",
                    fontSize = 16,
                    vmargin = 4,
                },
                gui.Style {
                    selectors = { "input" },
                    width = "80%-16",
                    halign = "center",
                    fontSize = 16,
                    borderWidth = 1,
                    borderColor = Styles.textColor,
                },
            },
            classes = { "framedPanel" },
            bgimage = true,
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                classes = { "dialogTitle" },
                text = cond(mode == "create", "Create New Campaign", "Edit Campaign"),
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Campaign Name:",
            },

            gui.Input {
                classes = { "formInput" },
                text = m_game.description,
                placeholderText = "Enter Campaign Name",
                fontSize = 22,
                vpad = 4,
                change = function(element)
                    m_game.description = element.text
                end,
            },

            gui.Label {
                text = "Campaign Description:",
                tmargin = 8,
            },

            gui.Input {
                classes = { "formInput" },
                text = m_game.descriptionDetails,
                placeholderText = "Enter Campaign Details",
                fontSize = 16,
                multiline = true,
                height = 60,
                characterLimit = 240,
                textAlignment = "topleft",
                change = function(element)
                    m_game.descriptionDetails = element.text
                end,
            },

            gui.Label {
                text = "Cover Art:",
                tmargin = 8,
            },

            --cover art
            gui.Panel {
                id = "coverart",
                bgimage = m_game.coverart,
                bgcolor = "white",
                width = "80%",
                height = "56.25% width", --16:9 aspect ratio
                halign = "center",
                valign = "top",
                hmargin = 32,
                refreshGames = function(element)
                    element.bgimage = m_game.coverart
                end,

                press = function(element)
                    dmhub.OpenFileDialog {
                        id = "CoverArt",
                        extensions = { "jpeg", "jpg", "png", "mp4", "webm", "webp" },
                        prompt = string.format("Choose image or video to use for your game's cover art"),
                        open = function(path)
                            local imageid
                            imageid = m_game:UploadCoverArt {
                                path = path,
                                upload = function()
                                end,
                                error = function(message)
                                    local modal
                                    modal = gui.Panel {
                                        classes = { "framedPanel" },
                                        styles = {
                                            Styles.Default,
                                            Styles.Panel,
                                        },
                                        width = 600,
                                        height = 600,
                                        floating = true,
                                        halign = "center",
                                        valign = "center",
                                        bgimage = true,

                                        gui.Label {
                                            classes = { "title" },
                                            text = "Error Uploading Cover Art",
                                        },

                                        gui.Label {
                                            classes = { "dialogMessage" },
                                            text = message,
                                        },

                                        gui.Panel {
                                            classes = { "dialogButtonsPanel" },
                                            gui.Button {
                                                classes = { "dialogButton" },
                                                text = "Close",
                                                halign = "center",
                                                scale = 0.7,
                                                click = function(element)
                                                    modal:DestroySelf()
                                                end,
                                            },
                                        },
                                    }

                                    element.root:AddChild(modal)
                                end,
                            }
                        end,


                    }
                end,

                styles = {
                    {
                        transitionTime = 0.1,
                        selectors = { "hover" },
                        brightness = 0.5,
                    },
                },

                gui.Label {
                    gui.Label {
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
                            selectors = { "#coverartBand" },
                            hidden = 1,
                        },
                        {
                            transitionTime = 0.1,
                            selectors = { "#coverartBand", "parent:hover" },
                            hidden = 0,
                        },
                    },
                },
            },

            gui.Label {
                tmargin = 8,
                text = "Invite Code:",
            },

            gui.Panel {
                styles = {
                    {
                        selectors = { "infoPanel" },
                        bgimage = "panels/square.png",
                        bgcolor = "clear",
                        height = 60,
                        borderColor = Styles.textColor,
                        borderWidth = 2,
                        cornerRadius = 8,
                        beveledcorners = true,
                    },
                    {
                        selectors = { "infoPanel", "selectable", "hover" },
                        transitionTime = 0.2,
                        brightness = 1.5,
                    },
                    {
                        selectors = { "infoLabel" },
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
                        selectors = { "infoIcon" },
                        height = "70%",
                        width = "100% height",
                        bgcolor = Styles.textColor,
                        halign = "left",
                        valign = "center",
                        hmargin = 16,
                    },
                    {
                        selectors = { "infoIcon", "parentSelectable", "parent:hover" },
                        brightness = 1.5,
                        transitionTime = 0.1,
                    },

                },


                classes = { "infoPanel", "selectable" },
                height = 30,
                width = "80%",
                halign = "center",
                vmargin = 0,
                click = function(element)
                    local tooltip = gui.Tooltip { text = "Copied to Clipboard", valign = "top", borderWidth = 0 } (
                        element)
                    dmhub.CopyToClipboard(m_game.gameid)
                end,

                gui.Label {
                    classes = { "infoLabel" },
                    fontSize = 16,
                    minFontSize = 16,
                    width = "70%",
                    textAlignment = "center",
                    halign = "center",
                    text = m_game.gameid,
                },

                gui.Panel {
                    classes = { "infoIcon", "selectable", "parentSelectable" },
                    halign = "right",
                    bgimage = "icons/icon_app/icon_app_108.png",
                    hmargin = 8,
                    height = "70%",
                    width = "100% height",
                },
            },

            gui.Label {
                classes = { "fieldLabel" },
                tmargin = 8,
                text = "Password:",
            },

            gui.Input {
                characterLimit = lobby.maxGamePasswordLength,
                placeholderText = "(Optional) Enter a password here...",
                password = true,

                change = function(element)
                    m_game.password = element.text
                end,
            },

            gui.Panel {
                width = "80%",
                height = "auto",
                halign = "center",
                valign = "bottom",
                vmargin = 16,
                gui.Button {
                    text = "Confirm",
                    halign = "center",
                    height = 48,
                    width = 140,
                    fontSize = 26,
                    bold = true,
                    press = function(element)
                        if mode == "create" then
                            element.root:FireEventTree("overrideLoadingScreenArt", m_game.coverart)
                            lobby:EnterGame(m_game.gameid)
                        end
                        resultPanel:DestroySelf()
                    end,
                },

                gui.Button {
                    text = "Delete Game",
                    halign = "right",
                    valign = "bottom",
                    fontSize = 16,
                    height = 32,
                    width = 116,
                    press = function(element)
                        local modal
                        modal = gui.Panel {
                            classes = { "framedPanel" },
                            floating = true,
                            width = 600,
                            height = 600,
                            halign = "center",
                            valign = "center",
                            bgimage = true,
                            flow = "none",
                            styles = {
                                Styles.Default,
                                Styles.Panel,
                            },

                            gui.Label {
                                text = "Delete Game?",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                fontSize = 28,
                                valign = "top",
                                vmargin = 8,
                            },

                            gui.Label {
                                text = "Do you really want to delete this game?",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",
                                fontSize = 16,
                            },

                            gui.Panel {
                                valign = "bottom",
                                halign = "center",
                                flow = "horizontal",
                                width = "80%",
                                height = "auto",
                                vmargin = 8,
                                gui.Button {
                                    width = "auto",
                                    height = "auto",
                                    fontSize = 18,
                                    vpad = 6,
                                    hpad = 8,
                                    text = "Delete",
                                    halign = "center",
                                    click = function(element)
                                        m_game:Delete()
                                        modal:DestroySelf()
                                        resultPanel:DestroySelf()
                                    end,
                                },
                                gui.Button {
                                    width = "auto",
                                    height = "auto",
                                    fontSize = 18,
                                    vpad = 6,
                                    hpad = 8,
                                    text = "Cancel",
                                    halign = "center",
                                    escapeActivates = true,
                                    click = function(element)
                                        modal:DestroySelf()
                                    end,
                                },
                            },
                        }

                        element.root:AddChild(modal)
                    end,
                }
            },

            gui.CloseButton {
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            }
        }
    }

    return resultPanel
end



local function MakeGamePanel(gameIndex)
    local m_game = nil

    local addGameButton = gui.Panel {
        classes = { "hidden" },
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        width = "100%",
        height = "100%",

        press = function(element)
            element.root:FireEventTree("titlescreenCreateGame")
        end,

        gui.Panel {
            bgimage = "ui-icons/Plus.png",
            bgcolor = "white",
            width = 96,
            height = 96,
            halign = "center",
            valign = "center",
            styles = {
                {
                    brightness = 0.8,
                },
                {
                    selectors = { "parent:hover" },
                    scale = 1.1,
                    brightness = 1,
                    transitionTime = 0.1,
                }
            }
        }
    }

    --make game king panel
    local gamePanel = gui.Panel {

        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        width = "100%",
        height = "100%",


        flow = "horizontal",

        hover = function(element)
            element:SetClassTree("hovergame", true)
        end,

        dehover = function(element)
            element:SetClassTree("hovergame", false)
        end,

        refreshGames = function(element, orderedGames, baseIndex)
            local index = baseIndex + gameIndex
            m_game = orderedGames[index]
            if m_game == nil then
                element:SetClass("hidden", true)
                addGameButton:SetClass("hidden", #lobby.games >= 24)
                element:HaltEventPropagation()
                return
            end

            addGameButton:SetClass("hidden", true)
            element:SetClass("hidden", false)
        end,

        --game image panel
        gui.Panel {

            bgcolor = "white",
            width = "177.778% height",
            height = "100%",


            refreshGames = function(element)
                element.bgimage = m_game.coverart
            end,

            gui.Panel {
                styles = {
                    {
                        selectors = { "~hovergame" },
                        opacity = 0,
                        transitionTime = 0.1,
                    },
                    {
                        selectors = { "hover", "~label" },
                        brightness = 1.4,
                        scale = 1.04,
                    },
                    {
                        selectors = { "press" },
                        brightness = 0.7,
                    },
                },

                bgimage = "panels/titlescreen/button.png",
                bgcolor = "white",

                height = 131 * 0.4,
                width = 632 * 0.4,

                halign = "center",
                valign = "bottom",

                bmargin = 3,

                press = function(element)
                    element.root:FireEventTree("overrideLoadingScreenArt", m_game.coverart)
                    lobby:EnterGame(m_game.gameid)
                end,

                gui.Label {
                    text = "PLAY CAMPAIGN",
                    fontSize = 18,
                    fontFace = "newzald",
                    color = "white",
                    halign = "center",
                    valign = "center",
                    width = "auto",
                    height = "auto",
                    textAlignment = "center",
                    y = 2,
                }
            }
        },

        --game info king panel
        gui.Panel {

            halign = "right",
            width = "62%",
            height = "100%",

            gui.Panel {

                width = "100%",
                height = "100%",

                flow = "vertical",


                gui.Panel {

                    width = "100%",
                    height = "20%",

                    flow = "horizontal",
                    tmargin = 0,

                    gui.Label {

                        refreshGames = function(element)
                            element.text = string.upper(m_game.description)
                        end,

                        text = "The Delian Tomb",
                        fontSize = 30,
                        minFontSize = 12,
                        fontFace = "newzald",
                        bold = true,

                        halign = "left",
                        hpad = 5,
                        valign = "center",
                        textAlignment = "left",

                        width = "100%-100",
                        height = "100%",

                        flow = "horizontal",
                    },

                    --time the game has taken.
                    gui.Panel {
                        width = "auto",
                        height = "100%",
                        halign = "right",
                        flow = "horizontal",
                        hpad = 5,
                        gui.Label {
                            refreshGames = function(element)
                                local t = m_game.timePlayed
                                if t < 60 then
                                    element.text = "00:00"
                                    return
                                end

                                local minutes = math.floor(t / 60)
                                local hours = math.floor(minutes / 60)
                                minutes = minutes - hours * 60

                                element.text = string.format("%02d:%02d", hours, minutes)
                            end,
                            hmargin = 4,
                            fontSize = 25,
                            bold = true,
                            fontFace = "newzald",
                            halign = "center",
                            valign = "center",
                            textAlignment = "center",
                            width = "auto",
                            height = "auto",
                        },
                    }
                },

                gui.Label {
                    refreshGames = function(element)
                        element:SetClass("collapsed", m_game.owner == dmhub.loginUserid)
                        element.text = string.format(tr("<i>directed by</i> <b>%s</b>"), m_game.ownerDisplayName)
                    end,
                    fontSize = 14,
                    color = "grey",
                    tmargin = -8,
                    halign = "left",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    bold = false,
                    hpad = 5,
                    vpad = 2,
                },

                gui.Label {
                    refreshGames = function(element)
                        element.text = m_game.descriptionDetails
                    end,

                    text = "The Delian Tomb",
                    fontSize = 16,
                    fontFace = "newzald",

                    halign = "left",
                    hpad = 5,
                    valign = "top",
                    textAlignment = "topleft",

                    width = "100%",
                    height = "30%",

                    flow = "horizontal",
                },

                gui.Label {
                    textAlignment = "center",
                    color = "white",
                    fontSize = 14,
                    bold = true,
                    width = 360,
                    height = 36,
                    bgimage = true,
                    bgcolor = "white",
                    gradient = Styles.RichBlackGradient,
                    borderColor = "white",
                    borderWidth = 1,
                    beveledcorners = true,
                    cornerRadius = 10,
                    multimonitor = { "streamermode" },
                    valign = "bottom",
                    vmargin = 4,
                    hmargin = 4,
                    monitor = function(element)
                        element:FireEvent("refreshGames")
                    end,
                    refreshGames = function(element)
                        if m_game ~= nil then
                            local gameid = m_game.gameid
                            if g_streamerModeSetting:Get() then
                                gameid = string.format(
                                    "<alpha=#FF><mark=#FFFFFF><color=#FFFFFF>%s</alpha></mark></color>",
                                    string.rep("*", #m_game.gameid))
                            end
                            element.text = gameid
                        end
                    end,

                    click = function(element)
                        local tooltip = gui.Tooltip { text = "Copied to Clipboard", valign = "top", borderWidth = 0 } (
                            element)
                        dmhub.CopyToClipboard(m_game.gameid)
                    end,

                    gui.Panel {
                        halign = "left",
                        valign = "center",
                        height = "50%",
                        width = "100% height",
                        bgcolor = "white",
                        hmargin = 12,
                        bgimage = "icons/icon_app/icon_app_108.png",
                    },
                },


            },


        },

        gui.SettingsButton {
            styles = {
                {
                    selectors = { "~hovergame" },
                    opacity = 0,
                    hidden = 1,
                    transitionTime = 0.1,
                },
                {
                    selectors = { "~titlescreenDirector" },
                    hidden = 1,
                },
            },

            halign = "right",
            valign = "bottom",
            width = 24,
            height = 24,
            hmargin = 4,
            vmargin = 4,
            floating = true,
            press = function(element)
                local panel = CreateGameEditor {
                    game = m_game,
                    mode = "edit",
                }

                element.root:AddChild(panel)
            end,
        },

        gui.DeleteItemButton {
            styles = {
                {
                    selectors = { "~titlescreenPlayer" },
                    hidden = 1,
                },
                {
                    selectors = { "~hovergame" },
                    hidden = 1,
                },
            },

            halign = "right",
            valign = "bottom",
            width = 16,
            height = 16,
            hmargin = 4,
            vmargin = 4,
            floating = true,
            press = function(element)
                local modal
                modal = gui.Panel {
                    classes = { "framedPanel" },
                    floating = true,
                    width = 600,
                    height = 600,
                    halign = "center",
                    valign = "center",
                    bgimage = true,
                    flow = "none",
                    styles = {
                        Styles.Default,
                        Styles.Panel,
                    },

                    gui.Label {
                        text = "Leave Game?",
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        fontSize = 28,
                        valign = "top",
                        vmargin = 8,
                    },

                    gui.Label {
                        text = "Do you really want to leave this game?",
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        valign = "center",
                        fontSize = 16,
                    },

                    gui.Panel {
                        valign = "bottom",
                        halign = "center",
                        flow = "horizontal",
                        width = "80%",
                        height = "auto",
                        vmargin = 8,
                        gui.Button {
                            width = "auto",
                            height = "auto",
                            fontSize = 18,
                            vpad = 6,
                            hpad = 8,
                            text = "Leave Game",
                            halign = "center",
                            click = function(element)
                                m_game:Leave()
                                element.root:FireEventTree("refreshLobby")
                                modal:DestroySelf()
                            end,
                        },

                        gui.Button {
                            width = "auto",
                            height = "auto",
                            fontSize = 18,
                            vpad = 6,
                            hpad = 8,
                            text = "Cancel",
                            halign = "center",
                            escapeActivates = true,
                            click = function(element)
                                modal:DestroySelf()
                            end,
                        },
                    },
                }

                element.root:AddChild(modal)
            end,
        },



    }

    local resultPanel = gui.Panel {
        width = "100%",
        height = 176,
        bmargin = 10,
        gamePanel,
        addGameButton,
    }

    return resultPanel
end

function CreateGameLoadingScreen(moduleInfo)
    local resultPanel

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = {
                Styles.Default,
                Styles.Panel,
            },

            classes = { "framedPanel" },
            bgimage = true,
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                halign = "center",
                valign = "center",
                width = 160,
                height = "auto",
                fontSize = 18,
                text = "Creating Game",
                data = {
                    n = 0,
                },
                createdGame = function(element, gameid)
                    element.data.gameid = gameid
                end,
                thinkTime = 0.2,
                think = function(element)
                    element.data.n = (element.data.n + 1) % 4
                    local dots = string.rep(".", element.data.n)
                    element.text = "Creating Game" .. dots

                    if element.data.gameid ~= nil then
                        local gameid = element.data.gameid

                        local games = lobby.games or {}
                        for i, game in ipairs(games) do
                            print("CreateGame: Checking game", game.gameid, game.description, "vs", gameid)
                            if game.gameid == gameid then
                                local panel = CreateGameEditor {
                                    game = game,
                                }

                                print("CreateGame: Add panel")
                                resultPanel.root:AddChild(panel)
                                resultPanel:DestroySelf()

                                return
                            end
                        end
                    end
                end,
                error = function(element, message)
                    element.text = message
                    element.selfStyle.color = "red"
                end,
            },

            gui.CloseButton {
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            },
        }
    }


    lobby:CreateGame {
        description = moduleInfo.text,
        descriptionDetails = moduleInfo.descriptionDetails,
        coverart = moduleInfo.coverart,
        startingModule = moduleInfo.id,
        create = function(gameid)
            if resultPanel == nil or not resultPanel.valid then
                return
            end
            print("CreateGame: Callback in lua called", gameid)

            resultPanel:FireEventTree("createdGame", gameid)
        end,
        error = function(message)
            if resultPanel ~= nil and resultPanel.valid then
                resultPanel:FireEventTree("error", message)
            end
        end,
    }

    return resultPanel
end

function CreateGameDialog()
    local m_moduleid = g_moduleOptions[1].id
    local GetModule = function()
        for i, module in ipairs(g_moduleOptions) do
            if module.id == m_moduleid then
                return module
            end
        end
        return nil
    end

    local resultPanel

    resultPanel = gui.Panel {
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        floating = true,
        gui.Panel {
            styles = {
                Styles.Default,
                Styles.Panel,
            },

            classes = { "framedPanel" },
            bgimage = true,
            width = 800,
            height = 900,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label {
                classes = { "dialogTitle" },
                text = "Create New Campaign",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                fontSize = 32,
                textAlignment = "center",
            },

            gui.Divider {
                tmargin = 4,
                bmargin = 8,
            },

            gui.Label {
                text = "Choose Module:",
                width = "80%",
                height = "auto",
                fontSize = 20,
                textAlignment = "left",
                halign = "center",
            },

            gui.Dropdown {
                width = "80%",
                height = 32,
                halign = "center",
                fontSize = 20,
                options = g_moduleOptions,
                idChosen = m_moduleid,
                change = function(element)
                    m_moduleid = element.idChosen
                    resultPanel:FireEventTree("refreshModule")
                end,
            },

            gui.Label {
                fontSize = 28,
                width = "80%",
                height = 36,
                halign = "center",
                bold = true,
                tmargin = 8,
                refreshModule = function(element)
                    element.text = GetModule().text
                end,
            },

            gui.Panel {
                width = "80%",
                height = "56.25% width", --16:9 aspect ratio
                bgcolor = "white",
                halign = "center",
                vmargin = 4,
                refreshModule = function(element)
                    element.bgimage = GetModule().coverart
                end,
            },

            gui.Label {
                width = "80%",
                height = "auto",
                halign = "center",
                fontSize = 16,
                refreshModule = function(element)
                    element.text = GetModule().descriptionDetails
                end,
            },

            gui.Button {
                halign = "center",
                valign = "bottom",
                width = 240,
                height = 40,
                fontSize = 24,
                vmargin = 8,
                bold = true,
                text = "Create Campaign",
                click = function(element)
                    local loadingScreen = CreateGameLoadingScreen(GetModule())
                    element.root:AddChild(loadingScreen)
                    resultPanel:DestroySelf()
                end,
            },

            gui.CloseButton {
                floating = true,
                halign = "right",
                valign = "top",
                press = function(element)
                    resultPanel:DestroySelf()
                end,
            },
        }
    }

    resultPanel:FireEventTree("refreshModule")
    return resultPanel
end

local function MakeHeroPanel(heroIndex)
    local resultPanel

    local m_character = nil


    local addIcon = gui.Panel {
        classes = { "hiddenWithCharacter" },
        bgimage = "ui-icons/Plus.png",
        bgcolor = "white",
        floating = true,
        width = 96,
        height = 96,
        halign = "center",
        valign = "center",
        styles = {
            {
                brightness = 0.8,
            },
            {
                selectors = { "parent:hover" },
                scale = 1.1,
                brightness = 1,
                transitionTime = 0.1,
            }
        }
    }


    local avatarPanel = gui.Panel {
        classes = { "hiddenWithNoCharacter" },
        bgimage = true,
        bgcolor = "white",
        width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
        height = "100%",
        refreshCharacter = function(element, character)
            local portrait = character.offTokenPortrait
            element.bgimage = portrait
            element.selfStyle.imageRect = character:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight * 0.01,
                portrait)
        end,

        gui.Panel {
            styles = {
                {
                    selectors = { "~hoverchar" },
                    opacity = 0,
                    transitionTime = 0.1,
                },
                {
                    selectors = { "hover", "~label" },
                    brightness = 1.4,
                    scale = 1.04,
                },
                {
                    selectors = { "press" },
                    brightness = 0.7,
                },
            },

            bgimage = "panels/titlescreen/button-narrow.png",
            bgcolor = "white",

            height = 131 * 0.4,
            width = 336 * 0.4,
            halign = "center",
            valign = "bottom",

            bmargin = 3,

            press = function(element)
                EditHero(element, m_character)
            end,

            gui.Label {
                text = "VIEW",
                fontSize = 18,
                fontFace = "newzald",
                color = "white",
                halign = "center",
                valign = "center",
                width = "auto",
                height = "auto",
                textAlignment = "center",
                y = 2,
            }
        }
    }

    local nameLabel = gui.Label {
        classes = { "hiddenWithNoCharacter" },
        width = "100%-32",
        height = "auto",
        lmargin = 4,
        fontSize = 24,
        minFontSize = 8,
        bold = true,
        uppercase = true,
        valign = "top",
        halign = "left",
        textAlignment = "left",
        refreshCharacter = function(element, character)
            element.text = character.name or "Unnamed"
        end,
    }

    local detailsLabel = gui.Label {
        classes = { "hiddenWithNoCharacter" },
        width = "100%-32",
        height = "auto",
        lmargin = 4,
        fontSize = 16,
        minFontSize = 8,
        valign = "top",
        halign = "left",
        textAlignment = "left",
        refreshCharacter = function(element, token)
            local ancestry = token.properties:RaceOrMonsterType()

            local className = ""
            local subclassName = ""
            local classesTable = dmhub.GetTable('classes')

            local classes = token.properties:get_or_add("classes", {})
            for i, entry in ipairs(classes) do
                local classInfo = classesTable[entry.classid]
                if classInfo ~= nil then
                    className = classInfo.name
                    break
                end
            end

            local classes = token.properties:GetSubclasses()
            for i, entry in ipairs(classes) do
                subclassName = entry.name
                break
            end

            element.text = string.format("%s\n%s\n%s", ancestry, className, subclassName)
        end,
    }

    local joinGameButton = gui.Button {
        classes = { "hiddenWithNoCharacter" },
        width = "90%",
        fontSize = 18,
        height = 30,
        halign = "center",
        valign = "bottom",
        text = "JOIN A CAMPAIGN",
        click = function(element)
            element.root:FireEventTree("titlescreenCreateGame", m_character)
        end,
        refreshCharacter = function(element, token, game)
            element:SetClass("collapsed", game ~= nil)
        end,
    }

    local playingInCampaignBanner = gui.Panel {
        classes = { "collapsed", "banner" },
        width = "94%",
        height = "20% width",
        bgimage = true,
        bgcolor = "#2a211b",
        valign = "bottom",
        halign = "center",
        flow = "horizontal",
        styles = {
            {
                selectors = { "hover", "banner" },
                brightness = 1.5,
            },
            {
                selectors = { "parent:hover", "parent:banner" },
                brightness = 1.5,
            },
        },
        press = function(element)
            if element.data.game then
                element.root:FireEventTree("overrideLoadingScreenArt", element.data.game.coverart)
                lobby:EnterGame(element.data.game.gameid)
            end
        end,
        refreshCharacter = function(element, token, game)
            element.data.game = game
            element:SetClass("collapsed", game == nil)
        end,
        gui.Panel {
            width = string.format("%f%% height", (1920 / 1080) * 100),
            height = "100%",
            halign = "left",
            bgcolor = "white",
            bgimage = true,
            refreshCharacter = function(element, token, game)
                if game ~= nil then
                    element.bgimage = game.coverart
                end
            end,
        },
        gui.Panel {
            width = "60%",
            height = "100%",
            flow = "vertical",
            gui.Label {
                text = "Playing in Campaign",
                fontSize = 16,
                minFontSize = 8,
                color = "white",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            gui.Label {
                fontSize = 16,
                minFontSize = 8,
                color = "#bc9b7b",
                valign = "center",
                textWrap = false,
                maxWidth = "100%",
                width = "auto",
                height = "auto",
                refreshCharacter = function(element, token, game)
                    if game ~= nil then
                        element.text = game.description
                    end
                end,
            }
        }
    }

    local deleteButton = gui.DeleteItemButton {
        classes = { "parentHover", "hiddenWithNoCharacter" },
        floating = true,
        width = 16,
        height = 16,
        halign = "right",
        valign = "top",
        rmargin = 2,
        tmargin = 2,
        press = function(element)
            local modal
            modal = gui.Panel {
                classes = { "framedPanel" },
                floating = true,
                styles = {
                    Styles.Default,
                    Styles.Panel,
                },
                width = 600,
                height = 600,
                halign = "center",
                valign = "center",
                bgimage = true,

                gui.Label {
                    classes = { "title" },
                    text = "Delete Character?",
                    vmargin = 8,
                    halign = "center",
                    valign = "top",
                    bold = true,
                    fontSize = 28,
                    width = "auto",
                    height = "auto",
                },

                gui.Label {
                    fontSize = 16,
                    width = "80%",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    text = "Do you want to delete this character? This action cannot be undone.",
                },

                gui.Panel {
                    classes = { "dialogButtonsPanel" },
                    halign = "center",
                    valign = "bottom",
                    flow = "horizontal",
                    width = "80%",
                    height = "auto",
                    gui.Button {
                        classes = { "dialogButton" },
                        text = "Cancel",
                        fontSize = 24,
                        halign = "center",
                        click = function(element)
                            modal:DestroySelf()
                        end,
                    },
                    gui.Button {
                        classes = { "dialogButton" },
                        text = "Delete",
                        fontSize = 24,
                        halign = "center",
                        click = function(element)
                            game.DeleteCharacters({ m_character.charid })
                            modal:DestroySelf()
                        end,
                    },
                },
            }

            element.root:AddChild(modal)
            print("Delete Character:", m_character.charid)
        end,
    }

    resultPanel = gui.Panel {
        width = "48%",
        height = 176,
        halign = "center",
        bmargin = 10,
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        flow = "horizontal",

        styles = {
            {
                selectors = { "hiddenWithNoCharacter", "nocharacter" },
                hidden = 1,
            },
            {
                selectors = { "hiddenWithCharacter", "~nocharacter" },
                hidden = 1,
            },
        },

        press = function(element)
            if element:HasClass("nocharacter") then
                CreateHero(element)
            end
        end,

        hover = function(element)
            element:SetClassTree("hoverchar", true)
        end,
        dehover = function(element)
            element:SetClassTree("hoverchar", false)
        end,

        characters = function(element, chars, games)
            local c = chars[heroIndex]
            m_character = c

            print("CHARACTER:: REFRESH", heroIndex, "/", #chars, "HAVE", c ~= nil)
            element:SetClassTree("nocharacter", c == nil)
            if c ~= nil then
                local joinedCampaign = rawget(c.properties, "joinedCampaign")
                local joinedGame = nil
                for _, game in ipairs(games) do
                    if game.gameid == joinedCampaign then
                        joinedGame = game
                        break
                    end
                end


                element:FireEventTree("refreshCharacter", c, joinedGame)
            end
        end,


        addIcon,
        avatarPanel,
        gui.Panel {
            flow = "vertical",
            halign = "right",
            width = "67%",
            height = "100%",

            nameLabel,
            detailsLabel,
            joinGameButton,
            playingInCampaignBanner,
        },
        deleteButton,
    }

    return resultPanel
end

function CreateTitlescreen(dialog, options)
    local titlescreen

    local m_loadingScreenArt = nil

    local m_currentSearch = nil

    local m_states = { "starting-screen", "selection-screen", "games-screen" }
    local function SetTitlescreenState(state)
        for _, s in ipairs(m_states) do
            titlescreen:SetClassTree(s, s == state)
        end

        m_currentSearch = nil

        TopBar.UninstallSearchHandler(titlescreen.data.searchHandler)
        titlescreen.data.searchHandler = nil
        if state == "games-screen" then
            titlescreen.data.searchHandler = TopBar.InstallSearchHandler(function(text)
                m_currentSearch = text
                if m_currentSearch == "" then
                    m_currentSearch = nil
                end
                titlescreen:FireEventTree("refreshLobby")
            end)
        else
        end
    end

    local m_games = {}

    local function DirectorMode()
        return titlescreen:HasClass("titlescreenDirector")
    end

    local function GetNumPages()
        return math.ceil(#m_games / 4)
    end

    local function PageBaseIndex()
        local npage = clamp(round(g_gamePageSetting:Get()), 1, GetNumPages())
        return (npage - 1) * 4
    end

    local RefreshAllPanels
    RefreshAllPanels = function(t)
        t.selfStyle = t.selfStyle --force style recompute
        t.children = t.children
        for i, panel in ipairs(t.children) do
            RefreshAllPanels(panel)
        end
    end

    titlescreen = gui.Panel {
        id = "titlescreenRoot",
        classes = { 'main-panel', 'starting-screen' },

        styles = {
            Styles.Default,
            {
                selectors = { "hideOnStartingScreen", "starting-screen" },
                hidden = 1,
            },
            {
                selectors = { "hideOnSelectionScreen", "selection-screen" },
                hidden = 1,
            },
            {
                selectors = { "hideOnDirector", "titlescreenDirector" },
                hidden = 1,
            },
            {
                selectors = { "parent:main-panel", "parent:titlescreenHidden" },
                hidden = 1,
            }
        },

        width = 1920 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y),
        height = 1080,

        screenResized = function(element)
            RefreshAllPanels(element)
            element.selfStyle.width = 1920 * (dmhub.screenDimensions.x / dmhub.screenDimensions.y)
        end,

        halign = 'center',
        valign = 'bottom',


        --brightness = 0.3,


        flow = "vertical",

        create = function(element)
            SetTitlescreenState("starting-screen")
            --element:SetClassTree("starting-screen", false)
            --element:SetClass("selection-screen", false)
            --element:SetClass("games-screen", true)
        end,

        destroy = function(element)
            TopBar.UninstallSearchHandler(element.data.searchHandler)
            element.data.searchHandler = nil
        end,

        titlescreenCreateGame = function(element, tokenToImport)
            if #lobby.games >= 24 then
                TooManyGamesDialog(element)
                return
            end

            if DirectorMode() then
                local loadingScreen = CreateGameDialog()
                element.root:AddChild(loadingScreen)
            else
                local modal = CreateJoinGameModal(tokenToImport)
                element.root:AddChild(modal)
            end
        end,


        overrideLoadingScreenArt = function(element, artid)
            if artid ~= nil then
                m_loadingScreenArt = artid
            end
            print("EVENT::: overrideLoadingScreenArt", artid)
        end,

        loginFailed = function(element, message)
            print("EVENT::: loginFailed")
        end,


        beginLoading = function(element)
            print("EVENT::: beginLoading")
            if element.data.searchHandler ~= nil then
                TopBar.UninstallSearchHandler(element.data.searchHandler)
                element.data.searchHandler = nil
            end

            if m_loadingScreenArt ~= nil then
                if element.data.loadingScreen ~= nil then
                    element.data.loadingScreen:DestroySelf()
                    element.data.loadingScreen = nil
                end

                local quote = CodexQuotes.SelectQuote()
                local quoteText = ""
                if quote ~= nil then
                    quoteText = string.format("<i>%s</i>\n- %s", quote.quote, quote.speaker)
                end

                local loadingScreen = gui.Panel {
                    classes = { "loadingScreen" },
                    width = ScaleDimensions(1920),
                    height = ScaleDimensions(1080),
                    halign = "center",
                    valign = "center",
                    floating = true,
                    bgimage = m_loadingScreenArt,
                    bgimageAlpha = "panels/gamescreen/loadingscreen4.png",
                    fadeAwayAndDie = function(element)
                        element:SetClass("dying", true)
                        element:ScheduleEvent("destroySelf", 0.4)
                    end,
                    destroySelf = function(element)
                        element:DestroySelf()
                    end,

                    styles = {
                        {
                            selectors = { "loadingScreen" },
                            bgcolor = "#ffffffff",
                            alphaThresholdFade = 0.1,
                            alphaThreshold = 1,
                        },

                        {
                            classes = { "loadingScreen", "create" },
                            bgcolor = "#ffffff00",
                            alphaThreshold = -0.1,
                            transitionTime = 0.3,
                        },
                        {
                            classes = { "loadingScreen", "dying" },
                            bgcolor = "#ffffff00",
                            alphaThreshold = -0.1,
                            transitionTime = 0.4,
                        },
                    },


                    gui.Panel {
                        flow = "vertical",
                        width = 1200,
                        height = "auto",
                        halign = "center",
                        valign = "bottom",
                        bmargin = 80,

                        gui.Divider {
                            vmargin = 0,
                            height = 2,
                            y = 3.5,
                        },

                        gui.Divider {
                            gui.Label {
                                text = quoteText,
                                color = Styles.textColor,
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                textAlignment = "left",
                                halign = "center",
                                valign = "center",
                                maxWidth = 600,
                                markdown = true,
                            },

                            height = "auto",
                            vpad = 15,
                            minHeight = 60,
                            vmargin = 0,
                            width = "68%",

                            gradient = gui.Gradient {
                                easing = "EaseInCubic",
                                point_a = { x = 0, y = 0 },
                                point_b = { x = 1, y = 0 },
                                stops = {
                                    {
                                        position = 0,
                                        color = "#00000000",
                                    },
                                    {
                                        position = 0.2,
                                        color = "#000000ff",
                                    },
                                    {
                                        position = 0.8,
                                        color = "#000000ff",
                                    },
                                    {
                                        position = 1,
                                        color = "#00000000",
                                    },

                                },
                            },
                        },

                        gui.Divider {
                            vmargin = 0,
                            height = 2,
                            y = -3.5,
                        },
                    },

                    gui.ProgressDice{
                        floating = true,
                        halign = "right",
                        valign = "bottom",
                        hmargin = 28,
                        vmargin = 28,
                        width = 96,
                        height = 96,
                        thinkTime = 0.01,
                        think = function(element)
                            local progress = dmhub.gameLoadingProgress or 0
                            element:FireEventTree("progress", progress)
                        end,
                    },
                }

                titlescreen:AddChild(loadingScreen)
                element.data.loadingScreen = loadingScreen
            end
        end,

        endLoading = function(element)
            print("EVENT::: endLoading")
            if element.data.loadingScreen ~= nil then
                element.data.loadingScreen:FireEvent("fadeAwayAndDie")
                element.data.loadingScreen = nil
            end
        end,

        returnFromGame = function(element)
            --make the loading screen show.
            element:FireEvent("beginLoading")
        end,

        returnFromGameComplete = function(element)
            element:FireEvent("endLoading")
        end,

        error = function(element, message)
            print("EVENT::: ERROR")
        end,

        gui.Panel {
            width = 1920,
            height = 1080,
            halign = "center",
            valign = "center",
            flow = "vertical",
            endLoading = function(element)
                element:SetClass("hidden", true)
            end,
            returnFromGameComplete = function(element)
                element:SetClass("hidden", false)
            end,
            gui.Panel {
                classes = { "background" },

                bgimage = "panels/backgrounds/delian-tomb-bg.png",
                bgcolor = 'white',

                autosizeimage = true,
                width = 1.05 * ScaleDimensions(1920),
                height = 1.05 * ScaleDimensions(1080),

                screenResized = function(element)
                    element.selfStyle.width = 1.05 * ScaleDimensions(1920)
                    element.selfStyle.height = 1.05 * ScaleDimensions(1080)
                end,

                halign = 'center',
                valign = 'center',

                floating = true,

                thinkTime = 0.01,
                think = function(element)
                    local x = clamp(resistanceCurve(element.parent.mousePoint.x - 0.5), -1, 1)
                    local y = clamp(resistanceCurve(-(element.parent.mousePoint.y - 0.5)), -1, 1)

                    x = x * 6
                    y = y * 6

                    if element.data.x == nil then
                        element.data.x = x
                        element.data.y = y
                    end

                    element.data.x = element.data.x * 0.9 + x * 0.1
                    element.data.y = element.data.y * 0.9 + y * 0.1


                    local t = math.min(1, element.aliveTime)

                    if element.data.endtime == nil and not element:HasClass("starting-screen") then
                        element.data.endtime = element.aliveTime
                    end

                    if element.data.endtime ~= nil then
                        local dt = element.aliveTime - element.data.endtime
                        t = math.max(0, 1 - dt / 2)
                        if t <= 0 then
                            element.thinkTime = nil
                        end
                    end

                    element.x = element.data.x * t
                    element.y = element.data.y * t
                end,

                gui.Panel {
                    classes = { "starting-screen" },
                    bgimage = "panels/backgrounds/delian-tomb-bg-blur.png",
                    bgcolor = 'white',
                    width = "100%",
                    height = "100%",
                    brightness = 0.3,
                    styles = {
                        {
                            selectors = { "starting-screen" },
                            opacity = 0,
                            transitionTime = 1,
                        },
                        {
                            opacity = 1,
                            transitionTime = 0.4,
                        },
                    },
                },
            },

            gui.Button {
                classes = { "hideOnStartingScreen", "hideOnSelectionScreen" },
                fontSize = 16,
                halign = "left",
                valign = "top",
                floating = true,
                text = "<<Back",
                width = "auto",
                height = "auto",
                pad = 6,
                borderWidth = 1,
                hmargin = 8,
                vmargin = 24,
                captureEscape = true,
                escape = function(element)
                    element:FireEvent("escape")
                end,
                press = function(element)
                    SetTitlescreenState("selection-screen")
                end,
            },

            --top king panel
            gui.Panel {

                classes = { 'king-panel' },

                bgimage = true,

                width = "100%",
                height = "10%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                --empty
                gui.Panel {


                    width = "30%",
                    height = "100%",


                },

                --top title "tactical heroic fantasy"
                gui.Panel {

                    bgimage = true,

                    width = "40%",
                    height = "100%",


                    gui.Panel {

                        bgimage = "panels/titlescreen/tacticaltext.png",
                        bgcolor = "white",

                        halign = "center",
                        valign = "bottom",
                        width = 1150 * 0.5,
                        height = 60 * 0.5,



                    },



                },


                --buttons
                gui.Panel {


                    width = "30%",
                    height = "100%",


                },


            },

            --draw steel king panel
            gui.Panel {

                classes = { 'king-panel' },


                width = "100%",
                height = "13%",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {

                    bgimage = "panels/titlescreen/drawsteeltext.png",
                    bgcolor = "white",

                    halign = "center",
                    valign = "bottom",
                    width = 1670 * 0.5,
                    height = 235 * 0.5,




                },


            },

            --codex and swords king panel
            gui.Panel {

                classes = { 'king-panel' },

                bgimage = true,

                width = "100%",
                height = "7%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {


                    width = "35%",
                    height = "100%",



                },

                gui.Panel {

                    bgimage = true,

                    width = "30%",
                    height = "100%",


                    gui.Panel {

                        bgimage = "panels/titlescreen/sword2.png",
                        bgcolor = "white",

                        halign = "right",

                        width = 304 * 0.5,
                        height = 177 * 0.5,



                    },

                    gui.Panel {

                        bgimage = "panels/titlescreen/codextext.png",
                        bgcolor = "white",

                        halign = "center",
                        width = 608 * 0.5,
                        height = 177 * 0.5,




                    },

                    gui.Panel {

                        bgimage = "panels/titlescreen/sword1.png",
                        bgcolor = "white",

                        halign = "left",

                        width = 304 * 0.5,
                        height = 177 * 0.5,



                    },



                },


                gui.Panel {


                    width = "35%",
                    height = "100%",



                },

            },

            --middle empty panel
            gui.Panel {


                width = "100%",
                height = "60%",



            },

            --bottom king panel
            gui.Panel {

                classes = { 'king-panel' },
                bgimage = true,

                width = "100%",
                height = "10%",

                flow = "horizontal",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:starting-screen', 'king-panel' },
                        hidden = 0,
                    },


                },



                gui.Panel {

                    bgimage = "panels/titlescreen/starttext.png",
                    bgcolor = "white",

                    valign = "center",
                    halign = "center",
                    width = 1648 * 0.5,
                    height = 192 * 0.5,





                },





            },

            gui.Panel {

                classes = { 'king-panel' },

                bgimage = true,
                --bgcolor = "white",

                width = 1200,
                height = 700,

                floating = true,

                halign = "center",
                valign = "center",

                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:selection-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {

                    bgimage = "panels/titlescreen/directorsselect.png",
                    bgcolor = "white",
                    width = 500,
                    height = 700,

                    floating = true,

                    halign = "left",
                    valign = "center",


                    border = 1.5,
                    borderColor = "white",
                    cornerRadius = 2,

                    flow = "vertical",

                    classes = { "directorsselectsparent" },
                    styles = {
                        {
                            selectors = { "directorsselectsparent", "hover" },
                            --scale = 1.015,
                            transitionTime = 0.12,
                            imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                        }
                    },

                    click = function(element)
                        g_gamePageSetting = g_directorGamePageSetting
                        SetTitlescreenState("games-screen")
                        titlescreen:SetClassTree("titlescreenDirector", true)
                        titlescreen:SetClassTree("titlescreenPlayer", false)
                        titlescreen:FireEventTree("refreshLobby")
                    end,

                    gui.Panel {

                        bgimage = true,

                        height = "85%",
                        width = "100%",

                    },

                    gui.Panel {

                        bgimage = true,

                        height = "15%",
                        width = "100%",

                        gui.Panel {

                            bgimage = "panels/titlescreen/button.png",
                            bgcolor = "white",

                            height = 131 * 0.6,
                            width = 632 * 0.6,

                            halign = "center",
                            valign = "bottom",

                            bmargin = 3,


                            gui.Label {

                                text = "DIRECTOR",
                                fontSize = 30,
                                fontFace = "newzald",
                                color = "white",
                                halign = "center",
                                valign = "center",
                                textAlignment = "center",
                                y = 5,
                                width = "auto",
                            }

                        }

                    }



                },

                gui.Panel {

                    bgimage = "panels/titlescreen/playersselect.png",
                    bgcolor = "white",
                    width = 500,
                    height = 700,

                    floating = true,

                    halign = "right",
                    valign = "center",


                    border = 1.5,
                    borderColor = "white",
                    cornerRadius = 2,

                    click = function(element)
                        g_gamePageSetting = g_playerGamePageSetting
                        SetTitlescreenState("games-screen")
                        titlescreen:SetClassTree("titlescreenDirector", false)
                        titlescreen:SetClassTree("titlescreenPlayer", true)
                        titlescreen:FireEventTree("refreshLobby")
                    end,

                    flow = "vertical",

                    classes = { "playersselectparent" },
                    styles = {
                        {
                            selectors = { "playersselectparent", "hover" },
                            --scale = 1.015,
                            transitionTime = 0.12,
                            imageRect = { x1 = 0.02, x2 = 0.98, y1 = 0.02, y2 = 0.98 },
                        },
                    },

                    gui.Panel {

                        bgimage = true,

                        height = "85%",
                        width = "100%",

                    },

                    gui.Panel {

                        bgimage = true,

                        height = "15%",
                        width = "100%",



                        gui.Panel {

                            bgimage = "panels/titlescreen/button.png",
                            bgcolor = "white",

                            height = 131 * 0.6,
                            width = 632 * 0.6,

                            halign = "center",
                            valign = "bottom",

                            bmargin = 3,

                            gui.Label {

                                text = "PLAYER",
                                fontSize = 30,
                                fontFace = "newzald",
                                color = "white",
                                width = "auto",
                                halign = "center",
                                valign = "center",
                                textAlignment = "center",
                                y = 5,
                            }

                        }

                    }



                }

            },

            gui.Panel {


                classes = { 'king-panel' },

                flow = "vertical",

                width = 1900,
                height = 980,

                valign = "center",
                halign = "center",
                floating = true,
                styles = {

                    {
                        classes = { 'king-panel' },
                        hidden = 1,
                    },

                    {
                        classes = { 'parent:games-screen', 'king-panel' },
                        hidden = 0,
                    },


                },

                gui.Panel {

                    width = "100%",
                    height = "8%",


                },


                gui.Panel {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "100%",
                    height = "88%",
                    halign = "center",

                    flow = "horizontal",

                    gui.Panel {
                        classes = { "hideOnDirector" },

                        bgimage = true,
                        bgcolor = "clear",
                        width = "44%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",

                        gui.Panel {

                            width = "100%",
                            height = "15%",

                            flow = "horizontal",

                            gui.Label {

                                text = "HEROES",
                                fontSize = 70,
                                fontFace = "book",

                                halign = "center",
                                valign = "center",
                                textAlignment = "center",

                                width = "85%",
                                height = "100%",

                                flow = "horizontal",

                                --add hero button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    hover = function(element)
                                        gui.Tooltip("Create a Hero")(element)
                                    end,

                                    monitorGame = "/characters",
                                    refreshGame = function(element)
                                        local chars = table.values(dmhub.GetAllCharacters())
                                        element:SetClass("hidden", #chars >= 8)
                                    end,

                                    press = CreateHero,

                                    gui.Panel {
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "ui-icons/Plus.png",
                                        styles = {
                                            {
                                                bgcolor = Styles.textColor,
                                            },
                                            {
                                                selectors = { "parent:hover" },
                                                bgcolor = Styles.backgroundColor,
                                            },
                                        }
                                    },

                                },

                                --FS import button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    text = "FS",
                                    fontSize = 30,
                                    y = -10,

                                    hover = function(element)
                                        gui.Tooltip("Import a Hero from Forge Steel")(element)
                                    end,

                                    monitorGame = "/characters",
                                    refreshGame = function(element)
                                        local chars = table.values(dmhub.GetAllCharacters())
                                        element:SetClass("hidden", #chars >= 8)
                                    end,

                                    press = ImportForgeSteel,
                                },
                            }
                        },


                        gui.Panel {
                            flow = "horizontal",
                            wrap = true,
                            width = "100%",
                            height = "auto",

                            styles = {
                                {
                                    selectors = { "parentHover" },
                                    hidden = 1,
                                },
                                {
                                    selectors = { "parent:hover", "parentHover" },
                                    hidden = 0,
                                },
                            },

                            lobbyGameLoaded = function(element)
                                element.monitorGame = "/characters"
                                element:FireEvent("refreshGame")
                            end,

                            refreshGame = function(element)
                                local chars = table.values(dmhub.GetAllCharacters())
                                table.sort(chars, function(a, b)
                                    return (rawget(a.properties, "ctime") or 0) < (rawget(b.properties, "ctime") or 0)
                                end)
                                local games = lobby.games
                                element:FireEventTree("characters", chars, games)
                            end,

                            beginLoading = function(element)
                                element.monitorGame = nil
                            end,

                            returnFromGame = function(element)
                                --start monitoring, but give it a second to allow the game to exit.
                                element:ScheduleEvent("startMonitoring", 1)
                            end,

                            startMonitoring = function(element)
                                lobby:EnterLobbyGame(function()
                                    print("LOBBYGAME:: ENTERED!")
                                    g_titlescreen:FireEventTree("returnFromGameComplete")
                                end)

                                element.monitorGame = "/characters"
                            end,

                            refreshLobby = function(element)
                                element:FireEvent("refreshGame")
                            end,

                            create = function(element)
                            end,


                            MakeHeroPanel(1),
                            MakeHeroPanel(2),
                            MakeHeroPanel(3),
                            MakeHeroPanel(4),
                            MakeHeroPanel(5),
                            MakeHeroPanel(6),
                            MakeHeroPanel(7),
                            MakeHeroPanel(8),
                        },
                    },

                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "6%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",


                    },

                    gui.Panel {

                        width = "44%",
                        height = "100%",
                        halign = "center",

                        flow = "vertical",

                        create = function(element)
                            element:FireEvent("think")
                        end,

                        data = {
                            updateid = -1,
                        },

                        create = function(element)
                            --element:FireEvent("refreshLobby")
                        end,

                        refreshLobby = function(element)
                            local orderedGames = {}
                            local directorMode = DirectorMode()

                            print("REFRESH WITH DIRECTOR =", directorMode)

                            for i, game in ipairs(lobby.games or {}) do
                                local owner = (game.owner == dmhub.loginUserid)
                                if owner == directorMode and (m_currentSearch == nil or game:MatchesSearch(m_currentSearch)) then
                                    orderedGames[#orderedGames + 1] = game
                                end
                            end

                            m_games = orderedGames
                            element.root:FireEventTree("refreshGames", orderedGames, PageBaseIndex())
                        end,

                        gui.Panel {

                            width = "100%",
                            height = "15%",

                            flow = "horizontal",

                            gui.Label {

                                text = "CAMPAIGNS",
                                fontSize = 70,
                                fontFace = "book",

                                halign = "center",
                                valign = "center",
                                textAlignment = "center",

                                width = "85%",
                                height = "100%",

                                flow = "horizontal",

                                --add game button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    press = function(element)
                                        if #lobby.games >= 24 then
                                            TooManyGamesDialog(element)

                                            return
                                        end

                                        element.root:FireEventTree("titlescreenCreateGame")
                                    end,

                                    gui.Panel {
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "ui-icons/Plus.png",
                                        styles = {
                                            {
                                                bgcolor = Styles.textColor,
                                            },
                                            {
                                                selectors = { "parent:hover" },
                                                bgcolor = Styles.backgroundColor,
                                            },
                                        }
                                    },

                                },

                                --search button.
                                gui.Button {
                                    width = 48,
                                    height = 48,
                                    halign = "right",
                                    valign = "center",
                                    beveledcorners = true,
                                    cornerRadius = 8,
                                    y = -10,

                                    press = function(element)
                                        print("LOBBYGAME:: ENTERING...")
                                        TopBar.FocusSearchBar()
                                        --lobby:EnterLobbyGame(function()
                                        --    print("LOBBYGAME:: ENTERED!!")
                                        --end)
                                    end,

                                    gui.Panel {
                                        width = "80%",
                                        height = "80%",
                                        halign = "center",
                                        valign = "center",
                                        bgimage = "icons/icon_tool/icon_tool_42.png",
                                        styles = {
                                            {
                                                bgcolor = Styles.textColor,
                                            },
                                            {
                                                selectors = { "parent:hover" },
                                                bgcolor = Styles.backgroundColor,
                                            },
                                        }
                                    },

                                },
                            }


                        },

                        MakeGamePanel(1),
                        MakeGamePanel(2),
                        MakeGamePanel(3),
                        MakeGamePanel(4),
                    },

                    --paging panel
                    gui.Panel {
                        floating = true,
                        minWidth = 100,
                        width = "auto",
                        height = 60,
                        flow = "horizontal",
                        halign = "right",
                        valign = "bottom",
                        rmargin = 20,
                        y = 68,
                        bgimage = true,
                        bgcolor = "black",
                        opacity = 0.9,
                        refreshGames = function(element, games, baseIndex)
                            if GetNumPages() <= 1 then
                                element:SetClass("hidden", true)
                            else
                                element:SetClass("hidden", false)
                            end
                        end,

                        gui.PagingArrow {
                            facing = -1,
                            height = 24,
                            valign = "center",
                            halign = "center",
                            refreshGames = function(element, games, baseIndex)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                print("REFRESH::", npage, "/", numPages)
                                element:SetClass("hidden", npage <= 1)
                            end,
                            press = function(element)
                                g_gamePageSetting:Set(g_gamePageSetting:Get() - 1)
                                element.root:FireEventTree("refreshGames", m_games, PageBaseIndex())
                            end,
                        },

                        gui.Label {
                            textAlignment = "center",
                            width = "auto",
                            minWidth = 60,
                            height = 50,
                            fontSize = 20,
                            halign = "center",
                            valign = "center",
                            refreshGames = function(element)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                print("REFRESH::", npage, "/", numPages)
                                element.text = string.format("Page\n%d/%d", npage, numPages)
                            end,
                        },

                        gui.PagingArrow {
                            facing = 1,
                            height = 24,
                            halign = "center",
                            valign = "center",
                            refreshGames = function(element)
                                local numPages = GetNumPages()
                                local npage = clamp(round(g_gamePageSetting:Get()), 1, numPages)
                                element:SetClass("hidden", npage >= numPages)
                            end,
                            press = function(element)
                                g_gamePageSetting:Set(g_gamePageSetting:Get() + 1)
                                element.root:FireEventTree("refreshGames", m_games, PageBaseIndex())
                            end,
                        },
                    },

                },
            },

            --[[hacky debug log panel
            gui.Panel {
                bgimage = true,
                bgcolor = "black",
                floating = true,
                vmargin = 32,
                width = 500,
                height = 300,
                vscroll = true,
                valign = "bottom",
                gui.Label {
                    halign = "left",
                    valign = "top",
                    width = 500,
                    height = "auto",
                    fontSize = 14,
                    thinkTime = 0.1,
                    think = function(element)
                        local log = dmhub.debugLog
                        if #log == element.data.nlog then
                            return
                        end

                        element.data.nlog = #log

                        local startIndex = 1
                        if #log > 100 then
                            startIndex = #log - 100
                        end

                        local res = ""
                        for i = startIndex, #log do
                            local s = log[i]
                            if type(s) == "table" then
                                s = s.message
                            end
                            res = res .. s .. "\n"
                        end
                        element.text = res
                    end,
                },
            }
            --]]
        },
    }

    local initialScreen
    initialScreen = gui.Panel {
        bgimage = "panels/backgrounds/delian-tomb-bg.png",
        nostretch = true,
        floating = true,

        autosizeimage = true,
        width = 1.05 * ScaleDimensions(1920),
        height = 1.05 * ScaleDimensions(1080),

        screenResized = function(element)
            element.selfStyle.width = 1.05 * (1920 / dmhub.uiVerticalScale)
            element.selfStyle.height = "56.25% width"
        end,

        lobbyGameLoaded = function(element)
            dmhub.Schedule(0.7, function()
                if initialScreen ~= nil and initialScreen.valid then
                    initialScreen:SetClassTree("destroying", true)
                end
            end)


            dmhub.Schedule(1, function()
                if initialScreen ~= nil and initialScreen.valid then
                    initialScreen:DestroySelf()
                    initialScreen = nil
                end
            end)
        end,


        valign = "center",
        halign = "center",
        --saturation = 0.5,
        bgcolor = '#888888ff',
        styles = {
            {
                selectors = { "destroying" },
                transitionTime = 0.3,
                opacity = 0,
            }
        }
    }

    titlescreen:AddChild(initialScreen)

    local progressDice = gui.ProgressDice{
        styles = {
            {
                selectors = {"loaded", "hover"},
                brightness = 1.2,
            },
            {
                selectors = {"fade"},
                transitionTime = 0.2,
                opacity = 0,
                uiscale = 2,
            },
        },
        floating = true,
        width = 128,
        height = 128,
        halign = "center",
        valign = "center",
        progress = 0.0,
        thinkTime = 0.01,
        think = function(element)
            local progress = dmhub.gameLoadingProgress or 0
            element:FireEventTree("progress", progress)
            if progress >= 1 then
                if element.data.loadingFinished == nil then
                    element.data.loadingFinished = element.aliveTime
                end

                local t = element.aliveTime - element.data.loadingFinished
                element:SetClass("loaded", true)
                if element:HasClass("hover") then
                    element.selfStyle.scale = 1.05
                else
                    element.selfStyle.scale = 1 + math.sin(t * 10) * 0.05
                end
            end
        end,

        press = function(element)
            if (dmhub.gameLoadingProgress or 0) >= 1 then
                SetTitlescreenState("selection-screen")
                element:SetClassTree("fade", true)
                element:ScheduleEvent("destroySelf", 0.2)
                element.thinkTime = nil
            end
        end,

        destroySelf = function(element)
            element:DestroySelf()
        end,
    }

    titlescreen:AddChild(progressDice)

    dialog.sheet = titlescreen
    g_titlescreen = titlescreen
end

if rawget(_G, "TitlescreenVersion") ~= 2 then
    TitlescreenVersion = 2

    dmhub.debugLog = {}


    print("LOBBYGAME:: ENTERING...")
    dmhub.RecreateTitlescreen()
    lobby:EnterLobbyGame(function()
        g_titlescreen:FireEventTree("lobbyGameLoaded")
    end)
end

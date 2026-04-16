local mod = dmhub.GetModLoading()

local BackupsDialog

LaunchablePanel.Register{
    name = "Game Backups",
    icon = "icons/standard/Icon_App_GameBackups.png",
    menu = "game",
    halign = "center",
    valign = "center",
    dmonly = true,
    content = function()
        return BackupsDialog()
    end,
}

BackupsDialog = function()
    local resultPanel
    resultPanel = gui.Panel{
        width = 800,
        height = 800,
        pad = 16,
        flow = "vertical",
        halign = "center",
        valign = "center",

        gui.Label{
            classes = {"title"},
            valign = "top",
            halign = "center",
            text = "Backups",
            width = "auto",
            height = "auto",
        },

        gui.Panel{

            flow = "vertical",
            height = 720,
            width = "100%",

            gui.Panel{
                classes = {"collapsed"},

                startRestore = function(element, fname, type)
                    local info = backup.GetEntryInfo(fname)
                    if info == nil then
                        resultPanel:FireEventTree("error", "Could not read file")
                    else
                        local mbytesUse = info.bytes/(1024*1024)
                        local availableMB = dmhub.uploadQuotaRemaining/(1024*1024)

                        element:FireEventTree("usage", mbytesUse, availableMB)
                    end

                    element:SetClass("collapsed", false)
                end,

                cancelRestore = function(element)
                    element:SetClass("collapsed", true)
                end,

                width = 620,
                height = 600,
                halign = "center",
                valign = "center",
                flow = "vertical",

                gui.Button{
                    data = {
                        fname = "",
                        type = "",
                    },
                    fontSize = 28,
                    text = "Restore Backup",
                    halign = "center",
                    valign = "center",
                    width = 240,
                    height = 40,
                    startRestore = function(element, fname, type)
                        element.data.fname = fname
                        element.data.type = type
                    end,
                    usage = function(element, use, avail)
                        element:SetClass("hidden", use > avail)
                    end,

                    click = function(element)
                        element:SetClass("hidden", true)
                        backup.Restore{
                            type = element.data.type,
                            fname = element.data.fname,
                            success = function()
                                resultPanel:FireEventTree("success")
                            end,
                            error = function(msg)
                                msg = msg or "Unknown error"
                                resultPanel:FireEventTree("restoreError", msg)
                            end,
                        }

                    end,
                },

                gui.Button{
                    fontSize = 28,
                    text = "Cancel",
                    halign = "center",
                    valign = "center",
                    width = 240,
                    height = 40,

                    click = function(element)
                        resultPanel:FireEventTree("cancelRestore")
                    end,
                },

                gui.Label{
                    fontSize = 16,
                    valign = "bottom",
                    halign = "left",
                    width = "auto",
                    height = "auto",

                    usage = function(element, use, avail)
                        if use > avail then
                            element.text = string.format("Restoring from backup requires %.2fMB of bandwidth, but you only have %.2fMB available.", use, avail)
                        else
                            element.text = string.format("Restoring from backup requires %.2fMB of bandwidth. You have %.2fMB available.", use, avail)
                        end
                    end,

                    success = function(element)
                        element.text = "Backup restored successfully."
                    end,

                    error = function(element, error)
                        element.text = error
                    end,

                }

            },

            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = 740,

                startRestore = function(element)
                    element:SetClass("collapsed", true)
                end,

                cancelRestore = function(element)
                    element:SetClass("collapsed", false)
                end,

                gui.Panel{
                    flow = "vertical",
                    width = "100%",
                    height = "100%",

                    gui.Label{
                        classes = {"title"},
                        text = "Game Backups",
                        fontSize = 28,
                        width = "auto",
                        height = "auto",
                        halign = "center",
                    },

                    gui.Panel{
                        vscroll = true,

                        width = "100%",
                        height = 600,
                        halign = "left",
                        valign = "center",
                        flow = "vertical",

                        create = function(element)
                            element:FireEvent("refreshBackups")
                        end,
                        refreshBackups = function(element)
                            local children = {}
                            local manifest = backup.manifest
                            for _,entry in ipairs(manifest.entries) do
                                children[#children+1] = gui.Panel{
                                    flow = "horizontal",
                                    width = 600,
                                    height = 40,
                                    halign = "left",
                                    gui.Panel{
                                        flow = "vertical",
                                        width = "auto",
                                        height = "auto",
                                        halign = "left",
                                        gui.Label{
                                            text = entry.fname,
                                            halign = "left",
                                            valign = "center",
                                            width = "auto",
                                            height = "auto",
                                            fontSize = 16,
                                            color = Styles.textColor,
                                        },
                                        gui.Label{
                                            text = DescribeServerTimestamp(entry.timestamp),
                                            halign = "left",
                                            valign = "center",
                                            width = "auto",
                                            height = "auto",
                                            fontSize = 16,
                                            color = Styles.textColor,
                                        },
                                    },

                                    gui.Button{
                                        text = "Restore",
                                        fontSize = 14,
                                        halign = "right",
                                        valign = "center",
                                        click = function()
                                            resultPanel:FireEventTree("startRestore", entry.fname, "game")
                                        end,
                                    },

                                    gui.Button{
                                        text = "Delete",
                                        fontSize = 14,
                                        halign = "right",
                                        valign = "center",
                                        click = function()
                                            GameHud.instance:ModalMessage{
                                                title = "Delete Backup",
                                                message = "Are you sure you want to delete this backup?",
                                                options = {
                                                    {
                                                        text = "Cancel",
                                                    },
                                                    {
                                                        text = "Delete",
                                                        execute = function()
                                                            backup.DeleteBackup(entry.fname)
                                                            resultPanel:FireEventTree("refreshBackups")
                                                        end,
                                                    },
                                                }
                                            }
                                        end,
                                    },


                                }
                            end

                            local c = {}
                            for i = #children, 1, -1 do
                                c[#c+1] = children[i]
                            end

                            element.children = c
                        end,
                    },

                    gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = 40,
                        halign = "left",
                        valign = "bottom",
                        gui.Label{
                            fontSize = 18,
                            valign = "center",
                            text = "Auto-backup every",
                            width = "auto",
                            height = "auto",
                        },

                        gui.Input{
                            width = 40,
                            height = 30,
                            fontSize = 18,
                            valign = "center",
                            text = tostring(backup.autoBackupInterval),
                            change = function(element)
                                local val = tonumber(element.text)
                                if val == nil or round(val) ~= val or val < 1 then
                                    element.text = tostring(backup.autoBackupInterval)
                                    return
                                end

                                backup.autoBackupInterval = val
                            end,
                        },

                        gui.Label{
                            fontSize = 18,
                            valign = "center",
                            text = "minutes",
                            width = "auto",
                            height = "auto",
                        },

                    },

                    gui.Button{
                        valign = "bottom",
                        fontSize = 18,
                        text = "Backup Game",
                        click = function(element)
                            backup.BackupGame()
                            resultPanel:FireEventTree("refreshBackups")
                        end,
                    },
                },


            },
        },
    }

    return resultPanel
end

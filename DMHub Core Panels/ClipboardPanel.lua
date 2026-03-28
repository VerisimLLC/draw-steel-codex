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

local Selection = dmhub.Selection

local CreateClipboard

DockablePanel.Register{
	name = "Clipboard",
	icon = "icons/standard/Icon_App_Clipboard.png",
	vscroll = false,
    dmonly = true,
	minHeight = 250,
	maxHeight = 250,
	folder = "Map Editing",
	content = function()
		track("panel_open", {
			panel = "Clipboard",
			dailyLimit = 30,
		})
		return CreateClipboard{
			title = "Clipboard",
		}
	end,
}

local m_clipboardPanel = nil

local CreateClipboardLibrary

CreateClipboard = function(options)
    local contentPanel

    local createPreviewFloorFrame = nil
    local previewFloor = nil
    local previewFloorObj = nil
    local previewImage = nil

    local selectionEditor = CreateSettingsEditor("selectiontool")

    contentPanel = gui.Panel{
        id = "ClipboardPanel",
        styles = {
            Styles.Default,

            {
                selectors = {"clipping"},
                width = 64,
                height = 64,
                bgcolor = "white",
                cornerRadius = 6,
            },
            {
                selectors = {"clipping", "hover"},
                borderWidth = 2,
                borderColor = "#ffffff88",
            },
            {
                selectors = {"clipping", "focus"},
                borderWidth = 2,
                borderColor = "white",
            },
        },
        interactable = false,

        flow = "vertical",

        width = "100%",
        height = "auto",

        childfocus = function(element)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
        end,

        childdefocus = function(element, focusInfo)
            element:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
            dmhub.SetSettingValue("selectiontool", "none")
        end,

        selection = function(element)
            element:FireEventTree("refreshSelection")
        end,

        mainclipboard = function(element)
            element:FireEventTree("refreshMainClipboard")
        end,

        showpanel = function(element)
            if not gui.ChildHasFocus(element) then
                selectionEditor:FireEventTree("pressfirst")
            end
        end,

        hidepanel = function(element)
            if gui.ChildHasFocus(element) then
				gui.SetFocus(element) --focus here first.
                gui.SetFocus(nil)
            end
        end,

        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,

        selectionEditor,

        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            gui.Button{
                id = 'ClearSelectionButton',
                text = 'Clear',
                hmargin = 4,
                style = {
                    fontSize = 14,
                    width = 60,
                    height = 24,
                },
                events = {
                    press = function(element)
                        Selection.Clear()
                    end,
                },
            },

            gui.Button{
                id = 'CopySelectionButton',
                text = 'Copy',
                hmargin = 4,
                refreshSelection = function(element)
                    element:SetClass("hidden", Selection.empty)
                end,
                style = {
                    fontSize = 14,
                    bgcolor = 'white',
                    width = 60,
                    height = 24,
                },
                events = {
                    press = function(element)
                        Selection.CopyToMainClipboard()
                    end,
                },
            },
        },

        gui.Panel{
            id = "mainClipButton",
            classes = {"clipping", "hidden"},
            draggable = true,
            canDragOnto = function(element, target)
                return target:HasClass("clipboardFolder")
            end,
            width = 128,
            height = 128,
            halign = "center",
            vmargin = 4,
            data = {
                GetClip = function()
                    return Selection.mainClipboard
                end
            },
            events = {

                drag = function(element, target)
                    if target == nil then
                        return
                    end

                    Selection.mainClipboard.parentFolder = target.data.folderid

                    assets:UploadClipboardAsset{
                        guid = Selection.mainClipboard.guid,
                        item = Selection.mainClipboard,
                        inmemory = true,
                        path = Selection.mainClipboard.guid,
                        upload = function()
                        end,
                    }

                    target:FireEventTree("setExpanded", true)

                end,

                destroy = function(element)
                    if previewFloor ~= nil then
                        game.currentMap:DestroyPreviewFloor(previewFloor)
                        previewFloor = nil
                    end
                end,

                hover = function(element)
                    if previewImage == nil or element.popup ~= nil then
                        return
                    end

                    element.popupPositioning = gamehud.dialogWorldPanel

                    element.popup = gui.TooltipFrame(
                        gui.Panel{
                            bgimage = previewImage,
                            --bgimage = "#MapPreview" .. previewFloor.floorid,
                            bgcolor = "white",
                            width = 512,
                            height = 512,
                        },
                        {
                            interactable = false,
                            halign = "center",
                            valign = "center",
                        }
                    )

                end,

                dehover = function(element)
                    if element.popup ~= nil and element.popup:HasClass("tooltipFrame") then
                        element.popup = nil
                    end
                end,

                refreshMainClipboard = function(element)
                    element:SetClass("hidden", Selection.mainClipboard == nil)

                    if Selection.mainClipboard == nil then
                        if previewFloor ~= nil then
                            game.currentMap:DestroyPreviewFloor(previewFloor)
                            previewFloor = nil
                        end
                    elseif previewFloorObj ~= Selection.mainClipboard.guid then
                        previewFloorObj = Selection.mainClipboard.guid

                        previewFloor = game.currentMap:CreatePreviewFloor()
                        previewFloor.cameraWidth = 512
                        previewFloor.cameraHeight = 512
                        previewFloor.cameraPos = {x = 0, y = 0}
                        previewFloor.cameraSize = math.max(Selection.mainClipboard.dimensions.x, Selection.mainClipboard.dimensions.y)*0.5

                        Selection.mainClipboard:Paste{
                            pos = {x = 0, y = 0},
                            floorid = previewFloor.floorid,
                        }

                        game.Refresh{
                            currentMap = true,
                            floors = {previewFloor.floorid},
                        }

                        previewImage = nil

                        createPreviewFloorFrame = dmhub.FrameCount()

                        element:ScheduleEvent("preview", 0.2)
                    end
                end,

                preview = function(element)
                    if (not element.valid) or (previewFloor == nil) then
                        return
                    end

                    if dmhub.FrameCount() < createPreviewFloorFrame + 10 then
                        element:ScheduleEvent("preview", 0.2)
                        return
                    end

                    previewImage = dmhub.LoadLocalImage("#MapPreview" .. previewFloor.floorid, previewFloorObj)
                    element.bgimage = previewImage

                    --we got what we wanted from the camera, now destroy the preview floor.
                    game.currentMap:DestroyPreviewFloor(previewFloor)
                    previewFloor = nil
                end,

                press = function(element)
                    dmhub.SetSettingValue("selectiontool", "none")
                    gui.SetFocus(element)
                    Selection.Clear()
                end,
            }
        },

        gui.DockablePanelMaximizeButton(),

        gui.Panel{
            width = "auto",
            height = "auto",
            maximize = function(element)
                if #element.children == 0 then
                    element:AddChild(CreateClipboardLibrary())
                end
            end,
        }
    }

    Selection.events:Listen(contentPanel)

    m_clipboardPanel = contentPanel
    contentPanel:FireEventTree("refreshSelection")
    contentPanel:FireEventTree("refreshMainClipboard")

    return contentPanel
end

local ShowClippingProperties

local CreateClipboardFolder = function(folderid)

	local expanded = false
	local body

	local folder = assets.clipboardFoldersTable[folderid]

	local folderLabel = gui.Label{
			classes = {"folderLabel"},
			text = folder.description,
			change = function(element)
				element.editable = false
				if element.text == "" then
					element.text = folder.description
				end
				folder.description = element.text
				folder:Upload()
			end,
		}

	local beforeSearchExpanded = nil

	local header = gui.Panel{
		classes = {"folderHeader", cond(expanded, "expanded")},
		gui.Panel{
			classes = {"triangle"},
		},

		folderLabel,

		setExpanded = function(element, val)
			if cond(val, true, false) ~= element:HasClass("expanded") then
				element:FireEvent("press")
			end
		end,

		search = function(element, info)
			if beforeSearchExpanded == nil then
				beforeSearchExpanded = element:HasClass("expanded")
			end
			element:FireEvent("setExpanded", info.folders[folderid])
			element:SetClass("collapsed", not info.folders[folderid])
		end,

		clearsearch = function(element, info)
			element:SetClass("collapsed", false)
			if beforeSearchExpanded ~= nil then
				element:FireEvent("setExpanded", beforeSearchExpanded)
				beforeSearchExpanded = nil
			end
		end,

		press = function(element)
			expanded = not expanded
			element:SetClass("expanded", expanded)
			body:SetClass("collapsed-anim", not expanded)
			if expanded then
				body:FireEvent("refreshAssets")
			end
		end,


		rightClick = function(element)
            element.popupPositioning = nil
			element.popup = gui.ContextMenu{
				width = 180,
				entries = {
					{
						text = "Rename Folder",
						click = function()
							folderLabel.editable = true
							folderLabel:BeginEditing()

							element.popup = nil
						end,
					}
				}
			}
		end,
	}

	local assetEntries = {}

	body = gui.Panel{
		width = "100%",
		height = "auto",
		halign = "left",
		flow = "horizontal",
		classes = {cond(expanded, nil, "collapsed-anim")},
		wrap = true,

		monitorAssets = "clipboard",
		refreshAssets = function(element)
			if not expanded then
				return
			end

			local newChildren = {}
			local newAssetEntries = {}
            for k,asset in pairs(assets.clipboardTable) do
                if (not asset.hidden) and (asset.parentFolder == folderid) then
                    newAssetEntries[k] = assetEntries[k] or gui.Panel{
                        classes = {"clipping"},
                        bgimage = k,
                        width = 96,
                        height = 96,
                        halign = "center",
                        vmargin = 4,
                        halign = "left",
                        draggable = true,
                        canDragOnto = function(element, target)
                            return target:HasClass("clipboardFolder")
                        end,
                        data = {
                            GetClip = function()
                                return asset
                            end
                        },


                        hover = function(element)
                            if element.popup ~= nil then
                                return
                            end

                            element.popupPositioning = gamehud.dialogWorldPanel

                            element.popup = gui.TooltipFrame(
                                gui.Panel{
                                    flow = "vertical",
                                    height = "auto",
                                    width = "auto",

                                    gui.Label{
                                        bold = true,
                                        fontSize = 28,
                                        color = "white",
                                        width = "auto",
                                        height = "auto",
                                        maxWidth = 512,
                                        text = asset.description,
                                    },

                                    gui.Label{
                                        fontSize = 14,
                                        color = "white",
                                        width = "auto",
                                        height = "auto",
                                        maxWidth = 512,
                                        text = asset.details,
                                    },
                                    
                                    gui.Panel{
                                        bgimage = k,
                                        bgcolor = "white",
                                        width = 512,
                                        height = 512,
                                    },
                                },
                                {
                                    interactable = false,
                                    halign = "center",
                                    valign = "center",
                                }
                            )

                        end,
                        dehover = function(element)
                            if element.popup ~= nil and element.popup:HasClass("tooltipFrame") then
                                element.popup = nil
                            end
                        end,



                        drag = function(element, target)
                            if target == nil then
                                return
                            end

                            asset.parentFolder = target.data.folderid
                            asset:Upload()
                            target:FireEventTree("setExpanded", true)
                        end,

                        rightClick = function(element)
                            element.popupPositioning = nil
                            element.popup = gui.ContextMenu{
                                entries = {
                                    {
                                        text = "Properties...",
                                        click = function()
                                            element.popup = nil
                                            ShowClippingProperties(asset)
                                        end,
                                    },
                                    {
                                        text = "Delete Clipping",
                                        click = function()
                                            element.popup = nil
                                            gamehud:ModalMessage{
                                                title = "Delete Clipping?",
                                                message = "Are you sure you want to delete this clipping? It will be gone forever.",
                                                options = {
                                                    {
                                                        text = "Delete",
                                                        execute = function()
                                                            asset:Delete()
                                                            gui.SetFocus(nil)
                                                            if element ~= nil and element.valid then
                                                                element:SetClass("collapsed", true)
                                                            end
                                                        end,
                                                    },
                                                    {
                                                        text = "Cancel",
                                                        execute = function()
                                                        end,
                                                    },
                                                }
                                            }
                                        end,
                                    }
                                }
                            }
                        end,

                        press = function(element)
                            dmhub.SetSettingValue("selectiontool", "none")
                            gui.SetFocus(element)
                            Selection.Clear()
                        end,
                    }

                    newChildren[#newChildren+1] = newAssetEntries[k]
                end
            end

			assetEntries = newAssetEntries
			element.children = newChildren


		end,
	}

	return gui.Panel{
		classes = {"folderContainer", "clipboardFolder"},

		dragTarget = true,

		data = {
			folderid = folderid,
			ord = function()
				return folder.ord
			end,
		},

		header,
		body,
	}

end

local CreateClipboardLibraryItems = function()
    local clipboardFolderPanels = {}

    local resultPanel

    resultPanel = gui.Panel{
		styles = {
			Styles.FolderLibrary,
		},

        height = 700,

        vscroll = true,

        valign = "top",

		monitorAssets = "clipboard",

        create = function(element)
            element:FireEvent("refreshAssets")
        end,

		refreshAssets = function(element)

			local children = {}
			local newClipboardFolderPanels = {}
			for k,folder in pairs(assets.clipboardFoldersTable) do
				newClipboardFolderPanels[k] = clipboardFolderPanels[k] or CreateClipboardFolder(k)
				children[#children+1] = newClipboardFolderPanels[k]
			end

			table.sort(children, function(a,b) return a.data.ord() < b.data.ord() end)
			element.children = children

			clipboardFolderPanels = newClipboardFolderPanels

		end,
    }

    return resultPanel
end

CreateClipboardLibrary = function()
    local libraryItems = CreateClipboardLibraryItems()

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        maximize = function(element)
            element:SetClass("collapsed", false)
        end,

        minimize = function(element)
            element:SetClass("collapsed", true)
        end,


        --separator.
		gui.Panel{
			width = "100%",
			height = 2,
			bgimage = "panels/square.png",
			bgcolor = Styles.textColor,
		},


		gui.Panel{
			width = "auto",
			height = "auto",
			flow = "horizontal",
			vmargin = 4,
			halign = "center",
			gui.SearchInput{
				search = function(element, str)
					if str == "" then
						libraryItems:FireEventTree("clearsearch")
					else
						local clips = {}
						local folders = {}
					--for k,asset in pairs(assets.audioTable) do
					--	if (not audioAsset.hidden) and string.find(string.lower(audioAsset.description), str) then
					--		clips[k] = true
					--		folders[audioAsset.parentFolder or defaultFolder] = true
					--	end
					--end
					--audioLibraryItems:FireEventTree("search", { assets = clips, folders = folders })
					end
					
				end,
			},
		},

        libraryItems,

		gui.Panel{
			classes = {"clickableIcon"},
			width = 24,
			height = 24,
			halign = "right",
			bgimage = "game-icons/open-folder.png",
			press = function(element)
				assets:UploadNewClipboardFolder{
					description = "Clips",
				}
			end,
		},
    }

    return resultPanel
end

ShowClippingProperties = function(asset)
    local dialog
    local dirty = false

    dialog = gui.Panel{
        classes = {"framedPanel"},
        styles = {
            Styles.Panel,
            Styles.Form,
        },

        width = 800,
        height = 600,

        destroy = function(element)
            if dirty then
                asset:Upload()
            end
        end,

        gui.Label{
            classes = {"dialogTitle"},
            text = "Clipping Properties",
        },

		gui.CloseButton{
			halign = "right",
			valign = "top",
			floating = true,
			escapeActivates = true,
			escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
			click = function()
				gui.CloseModal()
			end,
		},

        gui.Panel{
            bgimage = asset.guid,
            bgcolor = "white",
            halign = "right",
            valign = "top",
            margin = 32,
            width = 256,
            height = 256,
        },

        gui.Panel{
            halign = "left",
            valign = "top",
            margin = 32,
            flow = "vertical",
            width = 400,
            height = "auto",

            gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = asset.description,
                    change = function(element)
                        dirty = true
                        asset.description = element.text
                    end,
                },
            },

            gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Description:",
                },
                gui.Input{
                    classes = {"formInput"},
                    text = asset.details,
                    height = "auto",
                    minHeight = 80,
                    multiline = true,
                    change = function(element)
                        dirty = true
                        asset.details = element.text
                    end,
                },
            },


        },
    }

    gui.ShowModal(dialog)
end

dmhub.SelectionToolEnabled = function()
    local result = m_clipboardPanel ~= nil and m_clipboardPanel.valid and m_clipboardPanel:FindParentWithClass("highlightPanel") ~= nil

    return result
end

dmhub.GetActiveClipboardItem = function()
    local focus = gui.GetFocus()
    if focus ~= nil and focus.valid and focus.data.GetClip ~= nil then
        return focus.data.GetClip()
    end

    return nil
end
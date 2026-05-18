local mod = dmhub.GetModLoading()


local g_modalDialog = nil

local g_addingObject = nil

local function ObjectFoldersPanel()

	local resultPanel
	resultPanel = gui.Panel{
		classes = {"foldersPanel"},
		vscroll = true,
		width = 350,
		height = "80%",
		flow = "vertical",
		valign = "top",
		monitorAssets = "objects",

		refreshAssets = function(element)
			element:ScheduleEvent("refreshAssetsEcho", 0.01)
		end,

		refreshAssetsEcho = function(element)
			if g_addingObject ~= nil then
				local output = { element = nil }
				element:FireEventTree("findnode", g_addingObject, output)
				g_addingObject = nil

				if output.element ~= nil then
					output.element:FireEvent("click")

					element.vscrollPosition = 0.2
				end
			end
		end,

		mod.shared.CreateObjectEditor{
			noinstances = true,
			hideobjects = true,
			selectfolders = true,
			temporary = true,
		},
	}

	return resultPanel
end

local function ImportObjectsDialog(filePaths, progressPanel)

	local imageDescriptions = {}

	--the base progress % shown just when we start.
	local baseProgress = 0.1

	local CreatePreview = function(info, imageid)
		imageDescriptions[imageid] = info.fname
		dmhub.Debug(string.format("IMAGE:: %s -> %s", info.fname, imageid))
		return gui.Panel{
			width = 128,
			height = 148,
			valign = "top",
			halign = "left",
			flow = "vertical",
			gui.Panel{
				width = 128,
				height = 128,

				gui.Panel{
					classes = {"image"},
					bgimage = imageid,
					uiscale = 1/2,
					maxWidth = 256,
					maxHeight = 256,
					width = "auto",
					height = "auto",
					autosizeimage = true,
					halign = "center",
					valign = "center",
				},
			},

			gui.Label{
				classes = {"sizeS"},
				text = info.fname,
				change = function(element)
					imageDescriptions[imageid] = element.text
				end,
				editable = true,
				minFontSize = 8,
				halign = "center",
				valign = "center",
				width = 100,
				height = 20,
				textAlignment = "center",
			}
		}
	end

	local foldersPanel = ObjectFoldersPanel()

	local addFolderButton = gui.Button{
		classes = {"sizeM"},
		tmargin = 6,
		text = "Add Folder",
		halign = "center",
		click = function(element)
			g_addingObject = dmhub.AddObjectFolder()
		end,
	}

	local rightPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",
		foldersPanel,
		addFolderButton,
	}

	local previewPanels = {}

	local importer = dmhub.CreateObjectImporter{ paths = filePaths, threshold = 0, breakup = dmhub.GetSettingValue("objectimport:breakup") }
	progressPanel:FireEventTree("progress", baseProgress)

	local artist = nil
	local artistPanel

	if dmhub.isAdminGame then

		local artistOptions = {
			{
				id = "none",
				text = "(None)",
			}
		}


		local artistOptions = { { id = 'null', text = '(None)' } }
		for key,option in pairs(assets.artists) do
			artistOptions[#artistOptions+1] = { id = key, text = option.name }
		end

		artistPanel = gui.Panel{
			flow = "horizontal",
			height = "auto",
			width = "auto",
			halign = "center",
			gui.Label{
				classes = {"sizeL"},
				width = "auto",
				height = "auto",
				text = "Artist:",
			},
			gui.Dropdown{
				width = 180,
				idChosen = 'null',
				options = artistOptions,
				change = function(element)
					if element.idChosen == 'null' then
						artist = nil
					else
						artist = element.idChosen
					end
				end,
			}
		}

	end

	local dialogPanel
	dialogPanel = gui.Panel{
		classes = {"collapsed"},
		width = "100%",
		height = "100%",
		flow = "vertical",

		destroy = function(element)
			importer:Destroy()
		end,

		output = function(element, info)
			dmhub.Debug(string.format("OPEN FILES: update = %s; sheets = %s", json(info), json(importer.sheets)))

			element:FireEventTree("refresh")
		end,

		error = function(element, msg)
			dmhub.Debug("ERROR: FIRED")
			progressPanel:FireEventTree("errorMessage", msg)
		end,

		gui.Panel{
			flow = "horizontal",
			margin = 8,
			width = "100%",
			height = "80%",
			valign = "top",
			halign = "center",

			gui.Panel{
				flow = "vertical",
				height = "100%",
				width = "auto",
				gui.Panel{
					vscroll = true,
					width = 532,
					height = "100%-20",
					gui.Panel{
						flow = "horizontal",
						height = "auto",
						width = 512,
						halign = "left",
						valign = "top",
						wrap = true,
						refresh = function(element)
							local children = {}
							local newPreviewPanels = {}

							local percentComplete = importer.percentComplete
							progressPanel:FireEventTree("progress", baseProgress + (1 - baseProgress)*percentComplete)

							printf("IMPORTER:: %f", percentComplete)

							local sheetList = importer.sheets
							for _,sheetInfo in ipairs(sheetList) do
								if sheetInfo.images then
									for _,image in ipairs(sheetInfo.images) do
										local preview = previewPanels[image] or CreatePreview(sheetInfo, image)
										newPreviewPanels[image] = preview
										children[#children+1] = preview
									end
								end
							end

							element.children = children
							previewPanels = newPreviewPanels

							if percentComplete == 1 then
								progressPanel:SetClass("collapsed", true)
								dialogPanel:SetClass("collapsed", false)
							end
						end,
					},
				},
				gui.Label{
					classes = {"sizeS"},
					width = "auto",
					height = "auto",
					refresh = function(element)
						local percentComplete = importer.percentComplete
						if percentComplete >= 1 then
							local numObjects = 0
							local sheetList = importer.sheets
							for _,sheetInfo in ipairs(sheetList) do
								numObjects = numObjects + #sheetInfo.images
							end

							element.text = string.format("Import %d %s from %d %s", numObjects, cond(numObjects == 1, "object", "objects"), #sheetList, cond(#sheetList == 1, "file", "files"))

						end
					end,
				},
			},

			rightPanel,
		},

		artistPanel,

		gui.Label{
			classes = {"sizeL"},
			maxWidth = 900,
			width = "auto",
			height = "auto",

			create = function(element)
				if importer.percentComplete >= 1 then
					local sizeInfo = importer.sizeInfo
					local uploadMB = sizeInfo.totalSize/(1024*1024)
					local availableMB = dmhub.uploadQuotaRemaining/(1024*1024)

					local largestMB = sizeInfo.largestFileSize/(1024*1024)
					local availableSingleMB = dmhub.singleFileUploadQuota/(1024*1024)

					if availableMB < uploadMB then
						element.text = string.format("You do not have enough upload bandwidth left. You are trying to upload %.2fMB and you only have %.2fMB more this month. You can support us on Patreon for an increased upload limit.", uploadMB, availableMB)
						element:SetClass("danger", true)
						dialogPanel:FireEventTree("errorBandwidth")
					elseif availableSingleMB < largestMB then
						element.text = string.format("You are trying to upload a %.2fMB file. You cannot upload files larger than %.2fMB.%s", largestMB, availableSingleMB, dmhub.singleFilePatreonUpgradeMessage)
						element:SetClass("danger", true)
						dialogPanel:FireEventTree("errorBandwidth")
					else
						element.text = string.format("Uploading %.2fMB, you can upload %.2fMB more this month.", uploadMB, availableMB)
						element:SetClass("danger", false)
					end



				else
					element.text = "Calculating size..."
					element:ScheduleEvent("create", 0.1)
				end
			end,
		},

		gui.Button{
			classes = {"sizeXl"},
			halign = "center",
			text = "Import Objects",
			errorBandwidth = function(element)
				element:SetClass("hidden", false)
			end,
			click = function(element)

				dmhub.Debug("IMPORT OBJECTS!!!")
				gui.CloseModal()

				g_modalDialog = nil


				local operation = dmhub.CreateNetworkOperation()
				operation.description = "Uploading Objects"
				operation.status = "Uploading..."
				operation.progress = 0.0
				operation:Update()


				local parentFolderInfo = {nodeid = nil}

				foldersPanel:FireEventTree("findselected", parentFolderInfo)
				local parentFolder = parentFolderInfo.nodeid

				importer:Upload{
					artist = artist,
					imageDescriptions = imageDescriptions,
					folder = parentFolder,
					progress = function(percent, desc)
						operation.progress = percent
						operation:Update()
					end,
					complete = function(guids)
						operation.progress = 1
						operation:Update()
					end,
					error = function()
					end,
				}
			end,

		}
	}


	importer.outputEvent:Listen(dialogPanel)

	dmhub.Debug(string.format("OPEN FILES: success = %d; fail = %d", importer.numSuccesses, importer.numErrors))

	return dialogPanel
end

setting{
	id = "objectimport:breakup",
	description = "Break up objects of multiple sheets",
	default = true,
	storage = "preference",
}

local function ProgressPanel()

	return gui.Panel{
		flow = "vertical",
		halign = "center",
		valign = "center",
		width = "100%",
		height = 256,

		gui.ProgressBar{
			width = "80%",
			height = 64,
			value = 0,
			errorMessage = function(element, msg)
				element:SetClass("collapsed", true)
			end,
		},

		gui.Label{
			classes = {"sizeM"},
			text = "Importing...",
			width = "auto",
			height = "auto",
			margin = 6,
			errorMessage = function(element, msg)
				element.text = msg
			end,
		},
	}
end

local function ImportObjectsWizard()

	local contentPanel

	contentPanel = gui.Panel{
		width = "95%",
		height = "85%",
		halign = "center",
		valign = "center",
		flow = "vertical",

		processFiles = function(element, paths)
			if paths ~= nil and #paths > 0 then
				local progressPanel = ProgressPanel()
				contentPanel.children = {progressPanel}
				dmhub.Schedule(0.01, function()
					if contentPanel ~= nil and contentPanel.valid then
						contentPanel.children = {progressPanel, ImportObjectsDialog(paths, progressPanel)}
					end
				end)
			end
		end,

		gui.Panel{
			classes = {"bordered", "hoverable"},
			width = "80%",
			height = "60%",
			valign = "center",

			dragAndDropExtensions = {".png", ".jpg", ".jpeg", ".webm", ".webp", ".mp4", ".avi", ".gif"},

			dropfiles = function(element, paths)
				contentPanel:FireEvent("processFiles", paths)
			end,

			gui.Label{
				classes = {"sizeXl"},
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "center",
				text = "Drag & Drop image or video files here",
			},
		},

		gui.Label{
			classes = {"sizeM"},
			valign = "center",
			halign = "center",
			width = "auto",
			height = "auto",
			text = "-or-",
		},

		gui.Button{
			classes = {"sizeXl"},
			text = "Choose Files",
			click = function(element)

				dmhub.OpenFileDialog{
					id = "ObjectImagePath",
					extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4", "avi", "gif"},
					multiFiles = true,
					prompt = "Choose images or videos to use as objects.",
					openFiles = function(paths)
						contentPanel:FireEvent("processFiles", paths)

					end,
				}

			end,
		},

		gui.Check{
			text = "Break up sheets containing multiple objects",
			width = 400,
			height = 24,
			value = dmhub.GetSettingValue("objectimport:breakup"),
			change = function(element)
				dmhub.SetSettingValue("objectimport:breakup", element.value)
			end,

		}

	}

	local dialogPanel
	dialogPanel = gui.Panel{
		id = "ImportObjectsDialog",
		classes = {"framedPanel"},
		styles = ThemeEngine.GetStyles(),
		width = 1200,
		height = 800,
		pad = 8,
		borderBox = true,
		flow = "vertical",

		destroy = function(element)
			if g_modalDialog == element then
				g_modalDialog = nil
			end
		end,

		output = function(element, info)
			dmhub.Debug(string.format("OPEN FILES: update = %s; sheets = %s", json(info), json(importer.sheets)))

			element:FireEventTree("refresh")
		end,

		gui.Label{
			classes = {"dialogTitle"},
			text = "Import Objects",
		},

		contentPanel,

	--gui.ProgressBar{
	--	width = "80%",
	--	height = 64,
	--	value = 0,
	--	thinkTime = 0.1,
	--	think = function(element)
	--		element.value = element.value + 0.01
	--	end,
	--},

		gui.Button{
			classes = {"closeButton"},
			halign = "right",
			valign = "top",
			floating = true,
			escapeActivates = true,
			escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
			click = function()
				gui.CloseModal()
			end,
		},

	}

	ThemeEngine.OnThemeChanged(mod, function()
		if dialogPanel ~= nil and dialogPanel.valid then
			dialogPanel.styles = ThemeEngine.GetStyles()
		end
	end)

	gui.ShowModal(dialogPanel)
	g_modalDialog = dialogPanel
end

mod.shared.ImportObjects = function()
	ImportObjectsWizard()
end

print("Import:: Registered object import")
dmhub.ObjectDirectImport = function(path, point)
    print("Import:: Object import:", path, point.x, point.y)

    dmhub.Coroutine(function()

        local importer = dmhub.CreateObjectImporter{ paths = {path}, threshold = 0, breakup = false }


		local operation = nil
        local finished = false
        
        local t = dmhub.Time()
        
        while importer.percentComplete < 1 do
            print("Import:: waiting...", importer.percentComplete)
            coroutine.yield(0.1)
        end

        --make sure the importer has to calculate the textures.
        local _ = importer.sizeInfo

        importer:Upload{
            progress = function(percent, desc)
                if operation ~= nil then
                    operation.progress = percent - 0.01
                    operation:Update()
                end
                print("Import:: progress...", percent)
            end,
            complete = function(guids)
                if operation ~= nil then
                    operation.progress = 0.99
                    operation:Update()
                end
                print("Import:: imported object", guids)
                for _,guid in ipairs(guids) do
                    dmhub.Coroutine(function()
                        --wait for the object to be spawnable.
                        for i=1,100 do
                            local obj = game.currentFloor:SpawnObjectLocal(guid, {
                            })

                            print("Import:: Spawned:", obj ~= nil)
                            if obj ~= nil then
                                obj.x = point.x
                                obj.y = point.y

                                obj:Upload()
                                break
                            else
                                coroutine.yield(0.01)
                            end
                        end

                    end)
                end

                finished = true

            end,
            error = function()
                finished = true
                print("Import:: Error importing")
            end,
        }

        while not finished do
            if operation == nil and dmhub.Time() > t + 1 then
                operation = dmhub.CreateNetworkOperation()
                operation.progress = 0
                operation.description = "Uploading Objects"
                operation.status = "Uploading..."
                operation:Update()
            end
            coroutine.yield(0.1)
        end

        if operation ~= nil then
            operation.progress = 1
            operation:Update()
        end
    end)
end
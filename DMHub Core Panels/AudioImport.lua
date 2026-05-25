local mod = dmhub.GetModLoading()

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
		},

		gui.Label{
			text = "Importing...",
			width = "auto",
			height = "auto",
			fontSize = 16,
			margin = 6,

            error = function(element, str)
                element.text = str
                element.selfStyle.color = "red"
            end,

            finished = function(element)
                element.text = "Import Complete"
            end,
		},
	}
end


local function ImportAudioWizard()

	local contentPanel

	contentPanel = gui.Panel{
		width = "95%",
		height = "85%",
		halign = "center",
		valign = "center",
		flow = "vertical",

		processFiles = function(element, paths)
			if paths ~= nil and #paths > 0 then
                local totalPercent = 0
				local progressPanel = ProgressPanel()
				contentPanel.children = {progressPanel}
                for i,path in ipairs(paths) do
                    local percentUploaded = 0
                    local assetid = assets:UploadAudioAsset{
                        path = path,
                        error = function(text)
                            totalPercent = totalPercent - percentUploaded
                            percentUploaded = 1
                            totalPercent = totalPercent + percentUploaded
                            progressPanel:FireEventTree("progress", totalPercent/#paths)

                            progressPanel:FireEventTree("error", text)
                        end,

                        upload = function(id)
                            totalPercent = totalPercent - percentUploaded
                            percentUploaded = 1
                            totalPercent = totalPercent + percentUploaded
                            progressPanel:FireEventTree("progress", totalPercent/#paths)

                            if totalPercent >= #paths then
                                progressPanel:FireEventTree("finished")
                            end
                        end,

                        progress = function(percent)
                            dmhub.Debug(string.format("PROGRESS:: %f", percent))
                            totalPercent = totalPercent - percentUploaded
                            percentUploaded = percent
                            totalPercent = totalPercent + percentUploaded
                            progressPanel:FireEventTree("progress", totalPercent/#paths)
                        end,
                    }
                end
			end
		end,

		gui.Panel{
			classes = "dropArea",
			bgimage = "panels/square.png",

			dragAndDropExtensions = {".ogg", ".mp3", ".wav", ".flac"},

			dropfiles = function(element, paths)
				contentPanel:FireEvent("processFiles", paths)
			end,

			styles = {
				{
					width = "80%",
					height = "60%",
					valign = "center",
					selectors = {"dropArea"},
					bgcolor = "#ffffff33",
					borderColor = "white",
					borderWidth = 6,
					cornerRadius = 16,
				},
				{
					selectors = {"dropArea","hover"},
					bgcolor = "#ffffff99",
				}

			},

			gui.Label{
				color = "white",
				fontSize = 24,
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "center",
				text = "Drag & Drop audio (mp3, wav, ogg, or flac) files here",
			},
		},

		gui.Label{
			valign = "center",
			halign = "center",
			fontSize = 16,
			color = "white",
			width = "auto",
			height = "auto",
			text = "-or-",
		},

		gui.FancyButton{
			text = "Choose Files",
			width = 320,
			height = 70,
			click = function(element)

				dmhub.OpenFileDialog{
					id = "AudioPath",
					extensions = {"ogg", "mp3", "wav", "flac"},
					multiFiles = true,
					prompt = "Choose audio files.",
					openFiles = function(paths)
						contentPanel:FireEvent("processFiles", paths)

					end,
				}

			end,
		}

	}

	local dialogPanel
	dialogPanel = gui.Panel{
		id = "ImportAudioDialog",
		classes = {"framedPanel"},
		width = 1200,
		height = 800,
		pad = 8,
		flow = "vertical",
		styles = {
			Styles.Default,
			Styles.Panel,
		},

		destroy = function(element)
		end,

		output = function(element, info)
			dmhub.Debug(string.format("OPEN FILES: update = %s; sheets = %s", json(info), json(importer.sheets)))

			element:FireEventTree("refresh")
		end,

		gui.Label{
			classes = {"dialogTitle"},
			text = "Import Audio",
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

	gui.ShowModal(dialogPanel)
end

mod.shared.ImportAudio = function()
	ImportAudioWizard()
end
local mod = dmhub.GetModLoading()

--- @class IconEditorArgs:PanelArgs
--- @field value nil|string The assetid of the image.
--- @field aspect nil|number
--- @field allowNone nil|boolean If set, an option is to have no image.
--- @field noneImage nil|string If set, uses this image as the 'none' image. Effectively, a default image.
--- @field allowPaste nil|boolean If set, allows the user to paste in images from the clipboard.
--- @field hideIcon nil|boolean
--- @field library nil|string Which "image library" to use
--- @field searchHidden nil|boolean If true, hides the search.
--- @field categoriesHidden nil|boolean if true, hides the categories. The user will *have to* select from the image library and cannot switch to a different image library.
--- @field restrictImageType nil|string

--- @class IconEditorPanel:Panel
--- @field value nil|string The assetid of the image.

--- Creates a panel for picking an image asset. Use the 'value' field to query the assetid of the image selected.
--- @param args IconEditorArgs
--- @return IconEditorPanel
function gui.IconEditor(args)
	args = table.shallow_copy(args)
	if args.value == '' then
		args.value = nil
	end
	local style = args.style or {}

	local aspect = args.aspect or 1
	args.aspect = nil

	local allowNone = args.allowNone or false
	args.allowNone = nil

	local noneImage = args.noneImage or nil
	args.noneImage = nil

	local allowPaste = args.allowPaste or nil
	args.allowPaste = nil

	local value = args.value or cond(allowNone, nil, 'ui-icons/d20.png')

	local shouldHideIcon = args.hideIcon
	args.hideIcon = nil

	local library = args.library
	args.library = nil

	local searchHidden = args.searchHidden
	args.searchHidden = nil

	local categoriesHidden = args.categoriesHidden
	args.categoriesHidden = nil

	local restrictImageType = args.restrictImageType
	args.restrictImageType = nil

	local resultPanel = nil

	local category = ''
	local useBuiltinIcons = false

	local stretch = args.stretch
	args.stretch = nil

	args.bgcolor = args.bgcolor or "white"

	local imageType = nil

	local imageDim = 96
	local iconImageStyle = {
		bgcolor = 'white',
		maxWidth = imageDim-4,
		maxHeight = imageDim*aspect-4,
		width = cond(stretch, imageDim-4, "auto"),
		height = cond(stretch, imageDim*aspect-4, "auto"),
		autosizeimage = cond(stretch, false, true),
		halign = "center",
		valign = "center",
	}

	local ImageTypeMapping = {
		Avatar = "Avatar",
		AvatarFrame = "AvatarFrame",
		WallShadow = "WallShadow",
		popoutavatars = "AvatarPopout",
	}

	if library ~= nil then
		imageType = ImageTypeMapping[library]
	end

	if args.rightClick == nil then

		args.rightClick = function(element)

            local entries = {}

            entries[#entries+1] = {
                text = "Copy Image",
                click = function()
                    element.popup = nil
                    if resultPanel.value ~= nil then
                        dmhub.CopyToInternalClipboard("IMAGE:" .. resultPanel.value)
                    end
                end,
            }

            local text = dmhub.GetInternalClipboard()
            if type(text) == "string" and text:sub(1, 6) == "IMAGE:" then
                entries[#entries+1] = {
                    text = "Paste Image",
                    click = function()
                        element.popup = nil
                        local imageId = text:sub(7)
                        element.value = imageId
                        resultPanel.value = imageId
                    end,
                }
            end

            if dmhub.GetSettingValue("dev") then
                entries[#entries+1] = {
                    text = "Open URL",
                    click = function()
                        element.popup = nil
                        dmhub.OpenImageAssetURL(resultPanel.value)
                    end,
                }
            end

			element.popup = gui.ContextMenu{
				entries = entries,
			}
		end
	end

	--deprecated
	args.hideButton = nil

	args.press = function(element)

		local popupPanel = nil


		local CreateImage = function()
			local m_imageid = nil
			local iconImage = gui.Panel{
				classes = {"icon-image"},
				style = iconImageStyle,
			}

			local resultImage
			resultImage = gui.Panel{
				bgimage = 'panels/square.png',
				classes = {'hidden', 'image-background'},
				styles = {
					{
						bgcolor = 'black',
						width = imageDim,
						height = imageDim*aspect,
						halign = 'center',
						valign = 'center',
					},
				},
				selfStyle = {
					vmargin = 2,
				},
				data = {
					setImage = function(imageid)
						m_imageid = imageid
						iconImage.bgimage = imageid
						iconImage:SetClass("deleted", false)
                        resultImage:SetClass("selected", m_imageid == value)
					end,
				},
				children = {
					iconImage
				},
				events = {
					click = function(element)
						resultPanel.value = iconImage.bgimage
						resultPanel.popup = nil
					end,

					rightClick = function(element)
						if library ~= nil and dmhub.isDM then
							local entries = {
								{
									text  = "Delete",
									click = function()
										iconImage:SetClass("deleted", true)
										dmhub.RemoveAndUploadImageFromLibrary(library, m_imageid)
										element.popup = nil
									end,
								}
							}

							if devmode() then
								entries[#entries+1] = {
									text = "Open Image URL",
									click = function()
										dmhub.OpenImageAssetURL(m_imageid)
									end,
								}
							end

							element.popup = gui.ContextMenu{
								entries = entries,
							}
						end
					end,
				},
			}

			return resultImage
		end

		local imageIds = {}
		local images = {}

		local rows = 5
		local cols = 6
		local npage = 1

		local GetNumPages = function()
			local numPages = math.ceil(#imageIds / (rows*cols))
			if numPages < 1 then
				numPages = 1
			end

			return numPages
		end

		while #images < rows*cols do
			images[#images+1] = CreateImage()
		end

		local messageText = gui.Label{
			classes = {"collapsed"},
			floating = true,
			halign = "center",
			valign = "center",
			width = "auto",
			height = "auto",
			maxWidth = 300,
			fontSize = 14,
			color = Styles.textColor,
			refreshSearch = function(element)
				if #imageIds > 0 or library ~= "secret" then
					element:SetClass("collapsed", true)
				else
					element:SetClass("collapsed", false)
					element.text = "Place images here to keep them hidden from your players"
				end
			end,
		}

		local imagesGrid = gui.Panel{
			style = {
				flow = 'horizontal',
				wrap = true,
				margin = 0,
				pad = 0,
				width = rows*(imageDim+4)+6,
				height = cols*(imageDim*aspect+4)+6,
			},

			selfStyle = {
				halign = 'center',
			},

			children = images,

			events = {
				refreshSearch = function()
					for i,image in ipairs(images) do
						local searchIndex = (npage-1)*rows*cols + i
						local imageId = imageIds[searchIndex]
						if imageId == nil then
							image:SetClass('hidden', true)
						else
							image.data.setImage(imageId)
							image:SetClass('hidden', false)
						end
					end
				end
			}
		}

		local pagingPanel = gui.Panel{
			id = 'paging-panel',
			styles = {
				{
					width = '100%',
					height = 32,
					flow = 'horizontal',
				},
				{
					selectors = {'hover', 'paging-arrow'},
					brightness = 2,
				},
				{
					selectors = {'press', 'paging-arrow'},
					brightness = 0.7,
				},
			},

			children = {
				gui.Panel{
					bgimage = 'panels/InventoryArrow.png',
					className = 'paging-arrow',
					style = {
						height = '100%',
						width = '50% height',
						halign = 'left',
						hmargin = 40,
					},

					events = {
						refreshSearch = function(element)
							element:SetClass('hidden', npage == 1)
						end,

						click = function(element)
							npage = npage - 1
							if npage < 1 then
								npage = 1
							end
							popupPanel:FireEventTree('refreshSearch')
						end,
					},

				},

				gui.Panel{
					style = {
						flow = 'horizontal',
						width = 'auto',
						height = 'auto',
						halign = 'center',
					},

					gui.Label{
						style = {
							fontSize = '35%',
							color = 'white',
							width = 'auto',
							height = 'auto',
							halign = 'center',
						},
						text = 'Page',
					},

					--padding.
					gui.Panel{
						style = {
							height = 1,
							width = 8,
						},
					},

					gui.Label{
						editable = true,
						style = {
							fontSize = '35%',
							color = 'white',
							width = 'auto',
							height = 'auto',
							halign = 'center',
                            minWidth = 16,
						},
						events = {
							refreshSearch = function(element)
								element.text = string.format('%d', math.tointeger(npage))
							end,
							change = function(element)
								local newPage = tonumber(element.text)
								if newPage == nil or newPage < 1 or newPage > GetNumPages() then
									newPage = npage
								end

								npage = newPage
								popupPanel:FireEventTree('refreshSearch')

							end,
						}
					},

					gui.Label{
						style = {
							fontSize = '35%',
							color = 'white',
							width = 'auto',
							height = 'auto',
							halign = 'center',
						},
						events = {
							refreshSearch = function(element)
								element.text = string.format('/%d', math.tointeger(GetNumPages()))
							end,
						}
					},

				},

				gui.Panel{
					bgimage = 'panels/InventoryArrow.png',
					className = 'paging-arrow',
					style = {
						scale = {x = -1, y = 1},
						height = '100%',
						width = '50% height',
						halign = 'right',
						hmargin = 40,
					},

					events = {
						refreshSearch = function(element)
							element:SetClass('hidden', npage == GetNumPages())
						end,

						click = function(element)
							npage = npage + 1
							if npage > GetNumPages() then
								npage = GetNumPages()
							end
							popupPanel:FireEventTree('refreshSearch')
						end,
					},
				},

			},
		}

		local lastSearch = nil
		local searchInput = gui.Input{
			placeholderText = 'Search for images...',
			hasFocus = true,
			style = {
				width = 200,
				height = 30,
				fontSize = '40%',
				bgcolor = 'black',
				hmargin = 8,
			},

			editlag = 0.2,

			events = {
				change = function(element)
					if element.text == lastSearch then
						return
					end

					lastSearch = element.text

					if useBuiltinIcons then
						local filter = string.lower(element.text or "")
						imageIds = {}
						for _, item in ipairs(assets.devOnlyBuiltinImagesList) do
							if item.path and type(item.path) == "string" and #item.path > 0 then
								if #filter == 0 or string.lower(item.path):find(filter, 1, true) then
									imageIds[#imageIds + 1] = item.path
								end
							end
						end
						table.sort(imageIds)
					else
						imageIds = dmhub.SearchImages((category or "") .. element.text, library)
					end
					if allowNone and element.text == "" then
						table.insert(imageIds, 1, '')
					end

					npage = 1
                    local val = resultPanel.value
                    for i=1,#imageIds do
                        if imageIds[i] == val then
                            npage = math.ceil(i / (rows*cols))
                            break
                        end
                    end

					popupPanel:FireEventTree('refreshSearch')
				end,

				edit = function(element)
					element:FireEvent("change")
				end,
			},
		}

		if searchHidden then
			searchInput:AddClass("collapsed")
		end

		local options = {
			{
				text = "All Equipment",
				id = "equipment",
				search = "",
			},
			{
				text = "Weapons",
				id = "weapons",
				search = "weapons ",
			},
			{
				text = "Armor",
				id = "armor",
				search = "armor ",
			},
			{
				text = "Skills",
				id = "skill",
				search = "skill ",
			},
			{
				text = "Gear",
				id = "gear",
				search = "resources ",
			},

			--libraries
			{
				text = "Abilities",
				id = "abilities",
				search = "",
				library = "abilities",
			},
			{
				text = "Ongoing Effects",
				id = "ongoingEffects",
				search = "",
				library = "ongoingEffects",
			},
			{
				text = "Avatar Frames",
				id = "AvatarFrame",
				search = "",
				library = "AvatarFrame",
			},
			{
				text = "Avatar",
				id = "Avatar",
				search = "",
				library = "Avatar",
				imageType = "Avatar",
			},
			{
				text = "Currency",
				id = "currency",
				search = "",
				library = "currency",
			},
			{
				text = "Gradients",
				id = "gradients",
				search = "",
				library = "gradients",
			},
			{
				text = "Resources",
				id = "resources",
				search = "",
				library = "resources",
			},
			{
				text = "Cover Art",
				id = "coverart",
				search = "",
				library = "coverart",
			},
		}

		options[#options+1] = {
			text = "Built-in Icons",
			id = "builtinIcons",
			search = "",
			builtinIcons = true,
		}

		if dmhub.GetSettingValue("popoutavatars") then
			options[#options+1] = {
				text = "Popout Avatars",
				id = "popoutavatars",
				search = "",
				library = "popoutavatars",
				imageType = "Avatar",
			}
		end

		if library == "journal" then
			options[#options+1] = {
				text = "Journal",
				id = "journal",
				search = "",
				library = "journal",
			}
		end

		if dmhub.isDM then
			options[#options+1] = {
				text = "GM Secret",
				id = "secret",
				search = "",
				library = "secret",
				imageType = "Avatar",
			}
		end

		local dataTable = assets.imageLibrariesTable
		if dataTable ~= nil then
			local extraOptions = {}
			for k,v in pairs(dataTable) do
				printf("Adding library %s: %s, %s; imageType = %s vs %s", k, json(v.extension), json(v.hidden), v.imageType, json(restrictImageType))
				if v.extension and (not v.hidden) and (dmhub.isDM or (not v.gmonly)) then
					extraOptions[#extraOptions+1] = {
						text = v.name,
						id = k,
						search = "",
						library = k,
						imageType = v.imageType,
					}
				end
			end

			table.sort(extraOptions, function(a,b) return a.text < b.text end)

			for _,option in ipairs(extraOptions) do
				options[#options+1] = option
			end
		end

		if restrictImageType ~= nil then
			for _,option in ipairs(options) do
				if option.imageType == nil or string.lower(option.imageType) ~= string.lower(restrictImageType) then
					option.hidden = true
				end
			end
		end

		local optionMap = {}
		for _,option in ipairs(options) do
			optionMap[option.id] = option
		end


		local categoriesPanel = gui.Panel{
			classes = {cond(categoriesHidden, "collapsed")},
			style = {
				width = 'auto',
				height = 30,
				fontSize = '40%',
				bgcolor = 'white',
				hmargin = 8,
				flow = 'horizontal',
			},
			children = {
				gui.Label{
					text = 'Category:',
					style = {
						width = 'auto',
						height = 'auto',
					},
				},
				gui.Dropdown{
					options = options,
					idChosen = library or "equipment",
					width = 260,
					height = "100%",

					events = {
						change = function(element)
							lastSearch = nil
							local selected = optionMap[element.idChosen]
							library = selected.library
							category = selected.search
							useBuiltinIcons = selected.builtinIcons == true
							imageType = ImageTypeMapping[library]
							searchInput:FireEvent('change')
						end,
					},

				},
			},
		}

		local uploadButton = gui.PrettyButton{
			text = 'Upload Image',
			width = 200,
			height = 44,
			fontSize = 20,
			hmargin = 12,
			events = {
				refreshSearch = function(element)
					element:SetClass("collapsed", useBuiltinIcons)
				end,
				click = function(element)
					dmhub.Debug(string.format("IMAGETYPE:: Upload image with type = %s", json(imageType)))
					dmhub.OpenFileDialog{
						id = "IconImages",
						extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4", "avi"},
						prompt = "Choose image or video to use for this icon",
						multiFiles = true,
						open = function(path)
							local uploadComplete = false
							local assetid = nil
							assetid = assets:UploadImageAsset{
								path = path,
								imageType = imageType,
								error = function(text)
									dmhub.Debug('Could not load image: ' .. text)
									resultPanel.popup = nil
									gui.ModalMessage{
										title = 'Error loading image: ' .. text,
										message = text,
									}
								end,
								upload = function(imageid)
									uploadComplete = true
									if library ~= nil and library ~= 'AvatarFrame' then
										dmhub.AddAndUploadImageToLibrary(library, imageid)
									end
								end,
							}

							popupPanel.children = {
								gui.Label{
									text = 'Uploading Image...',
									thinkTime = 0.1,
									events = {
										think = function(element)
											if assets.imagesTable[assetid] ~= nil then
												resultPanel.value = assetid
												resultPanel.popup = nil
											end
										end,
									},

									style = {
										fontSize = '70%',
										width = 'auto',
										height = 'auto',
										textAlignment = 'center',
										color = 'white',
										halign = 'center',
										valign = 'center',
									},
								}
							}
						end,
						
					}
				end,
			},
		}

		local pasteButton = nil
		
		if allowPaste then
			pasteButton = gui.PrettyButton{
				text = 'Paste Image',
				width = 200,
				height = 44,
				hmargin = 12,
				vmargin = 12,
				fontSize = 20,
				classes = {cond(dmhub.HaveImageInClipboard(), nil, 'disabled')},
				thinkTime = 0.2,
				events = {
					refreshSearch = function(element)
						element:SetClass("collapsed", useBuiltinIcons)
					end,
					think = function(element)
						element:SetClassTree("disabled", not dmhub.HaveImageInClipboard())
					end,
					click = function(element)
						if not dmhub.HaveImageInClipboard() then
							return
						end

						local uploadComplete = false
						local assetid = nil
						assetid = assets:UploadImageAsset{
							path = "CLIPBOARD",
							imageType = imageType,
							error = function(text)
								dmhub.Debug('Could not load image')
								resultPanel.popup = nil
								gui.ModalMessage{
									title = 'Error loading image',
									message = text,
								}
							end,
							upload = function(imageid)
								uploadComplete = true
								if library ~= nil and library ~= 'AvatarFrame' then
									dmhub.AddAndUploadImageToLibrary(library, imageid)
								end
							end,
						}

						popupPanel.children = {
							gui.Label{
								text = 'Uploading Image...',
								thinkTime = 0.1,
								events = {
									think = function(element)
										if assets.imagesTable[assetid] ~= nil then
											resultPanel.value = assetid
											resultPanel.popup = nil
										end
									end,
								},

								style = {
									fontSize = '70%',
									width = 'auto',
									height = 'auto',
									textAlignment = 'center',
									color = 'white',
									halign = 'center',
									valign = 'center',
								},
							}
						}
					end,
				},
			}
		end


		
		popupPanel = gui.Panel{
			classes = {"framedPanel"},
			styles = {
				Styles.Default,
				Styles.Panel,
				{
					flow = 'vertical',
					halign = 'left',
					valign = 'center',
					width = 600,
					height = 860,
					borderWidth = 0,
					bgcolor = 'white',
				},
				{
					selectors = {'image-background', 'selected'},
					borderWidth = 2,
					borderColor = '#ffffff88',
                },
				{
					selectors = {'image-background', 'hover'},
					borderWidth = 2,
					borderColor = 'white',
				},
				{
					selectors = {'icon-image', 'deleted'},
					brightness = 0.2,
				},
			},
			children = {
				searchInput,
				categoriesPanel,
				imagesGrid,
				messageText,
				pagingPanel,
				uploadButton,
				pasteButton,
			},
		}

		searchInput:FireEvent('change')

		resultPanel.popupPositioning = 'panel'
		resultPanel.popup = popupPanel
		--popupPanel:PulseClass("fadein")
	end

	local noneLabel = gui.Label{
		text = "(none)",
		fontSize = 14,
		color = "white",
		halign = "center",
		valign = "center",
		width = "auto",
		height = "auto",
		floating = true,
	}

    local hideIcon = nil

	if not shouldHideIcon then
		hideIcon = gui.Panel{
			styles = {
				{
					opacity = 0,
				},
				{
					selectors = {"parent:hover"},
					transitionTime = 0.2,
					opacity = 1,
				}
			},
			floating = true,
			width = "40%",
			height = "40%",
			maxWidth = 64,
			maxHeight = 64,
			halign = "center",
			valign = "center",
			bgimage = "ui-icons/pencil.png",
			borderColor = Styles.textColor,
			bgcolor = Styles.textColor,
		}



	end


	args.bgimage = value
	args.value = nil
    args.children = args.children or {}
    args.children[#args.children+1] = hideIcon
    args.children[#args.children+1] = noneLabel

	args.styles = args.styles or {}
	args.styles[#args.styles+1] = {
		bgcolor = args.bgcolor,
	}

	args.styles[#args.styles+1] = {
		selectors = {"hover"},
		bgcolor = "#777777",
		transitionTime = 0.2,
	}

	args.styles[#args.styles+1] = {
		selectors = {"none"},
		bgcolor = "black",
		transitionTime = 0.2,
	}

	args.bgcolor = nil

	args.dragAndDropExtensions = {".png", ".jpg", ".jpeg", ".webm", ".webp", ".mp4", ".avi"}

	args.dropfiles = function(element, files)
		for i,f in ipairs(files) do
			local uploadComplete = false
			local assetid = nil
			dmhub.Debug("Upload file: " .. f)
			assetid = assets:UploadImageAsset{
				path = f,
				imageType = imageType,
				error = function(text)
					dmhub.Debug('Could not load image')
					gui.ModalMessage{
						title = 'Error loading image',
						message = text,
					}
				end,
				upload = function(imageid)
					uploadComplete = true
					if library ~= nil then
						dmhub.AddAndUploadImageToLibrary(library, imageid)
					end

					if i == 1 then
						resultPanel.value = imageid
					end
					dmhub.Debug("drop files uploaded")
				end,
				addlocal = function(imageid)
					if library ~= nil then
						dmhub.AddImageToLibraryLocally(library, imageid)
					end

					if i == 1 then
						resultPanel.value = imageid
					end
					dmhub.Debug("drop files added locally")
				end,
			}
		end
	end

	args.GetValue = function(element)
		if element.bgimage == 'panels/square.png' then
			return ''
		end
		return element.bgimage
	end

	args.SetValue = function(element, val, firechange)
        value = val
		if val == nil or val == '' then
			if noneImage ~= nil then
				element:SetClass("none", false)
				element.bgimage = noneImage
				noneLabel:SetClass("hidden", true)
			else
				element:SetClass("none", true)
				element.bgimage = 'panels/square.png'
				noneLabel:SetClass("hidden", false)
			end

		else
			element.bgimage = val
			element:SetClass("none", false)
			noneLabel:SetClass("hidden", true)
		end

		if firechange ~= false then
			element:FireEvent('change')
		end
        
	end

	resultPanel = gui.Panel(args)

	args.SetValue(resultPanel, value, false)

	resultPanel.bgimageInit = true --Force the image to be initialized to show something at least.

	return resultPanel
end

local mod = dmhub.GetModLoading()

local CreateCodeDiffPanel = nil

local codeModEditingSetting = setting{
	id = "codemodediting",
	description = "Allow editing of core mods",
	storage = "preference",
	default = false,
}

setting{
	id = "codemodsorting",
	description = "Code Mod Sorting",
	storage = "preference",
	default = "alphabetical",
}

local g_searchInsensitiveSetting = setting{
	id = "codemodsearchinsensitive",
	description = "Code Mod Search Case Insensitive",
	storage = "preference",
	default = true,
}

local g_searchWholeWordSetting = setting{
	id = "codemodsearchwholeword",
	description = "Code Mod Search Whole Word",
	storage = "preference",
	default = false,
}

local g_searchRegexSetting = setting{
	id = "codemodsearchregex",
	description = "Code Mod Search Regex",
	storage = "preference",
	default = false,
}

CodeMod = {

CreateEditor = function(panelArgs)
	local resultPanel = nil
	local m_containerPanel

	local errorPanel = nil

	local mod = nil

	local expandedPanel = nil
	local selectedRevisionPanel = nil

	local submitPatch = false

	local searchStr = nil
	local sortby = dmhub.GetSettingValue("codemodsorting")

	local permissionsPanel = gui.Label{
		text = "",
		width = "auto",
		height = "auto",
		valign = "top",
		fontSize = 16,
		color = "white",
		maxWidth = 600,

		refreshMod = function(element)
			submitPatch = false
			if mod.isowner then
				element.text = ""
			elseif mod.canedit then
				element.text = "You do not own this mod, but you can edit as an admin."
			else
				submitPatch = true
				element.text = "You do not own this mod. You can edit it and submit a patch to be approved by the author. If you submit a patch to the original author you grant them permission to use your changes however they want."
			end
		end,
	}

	local devSettingsButton = gui.Button{
		fontSize = 14,
		text = "Dev Settings",
		click = function(element)
			code.UserEditCodeDevConfig()
		end,
	}

    local replicateToGitButton = gui.Button{
        hmargin = 8,
        text = "Replicate to Git",
        click = function(element)
            mod:ReplicateToGit()
            element:SetClass("collapsed", true)
        end,
        refreshMod = function(element)
            element:SetClass("collapsed", mod.isUsingGit or (not code.hasGit))
        end,
    }

    local gitStatusLabel = gui.Label{
        width = "auto",
        height = "auto",
        hmargin = 8,
        fontSize = 14,
        valign = "center",
        refreshMod = function(element)
            if mod.isUsingGit then
                element.text = "Managed by Git"
            else
                element.text = ""
            end
        end,
    }

	local idPanel = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			text = "ModID:",
			classes = {"formLabel"},
		},
		gui.Input{
			classes = {"formInput"},
			editable = false,
			refreshMod = function(element)
				element.text = mod.modid
			end,
		},
	}

	local namePanel = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			text = "Name:",
			classes = {"formLabel"},
		},
		gui.Input{
			classes = {"formInput"},
			change = function(element)
				mod.name = element.text
				mod:Upload()
			end,
			refreshMod = function(element)
				element.text = mod.name
			end,
		},
	}

	local descriptionPanel = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			text = "Description:",
			classes = {"formLabel"},
		},
		gui.Input{
			classes = {"formInput"},
			multiline = true,
			width = 600,
			height = "auto",
			minHeight = 100,
			change = function(element)
				mod.description = element.text
				mod:Upload()
			end,
			refreshMod = function(element)
				element.editable = mod.canedit
				element.text = mod.description
			end,
		},
	}

	local addDependencyDropdown = gui.Dropdown{
		width = 240,
		height = 30,
		fontSize = 16,
        sort = true,
        
		refreshMod = function(element)
			local options = {
				{
					id = "none",
					text = "Add Dependency...",
				}
			}

			local dependencies = mod.dependencies

			local modsLoaded = code.loadedMods
			for _,modid in pairs(modsLoaded) do
				if modid ~= mod.modid and not list_contains(dependencies, modid) then
					local dependencyMod = code.GetMod(modid)
					options[#options+1] = {
						id = dependencyMod.modid,
						text = dependencyMod.name,
					}
				end
			end

			element.options = options

			element.idChosen = "none"

			element:SetClass("collapsed", #options == 1)
		end,

		change = function(element)
			if element.idChosen ~= "none" then
				local dependencies = mod.dependencies
				dependencies[#dependencies+1] = element.idChosen
				mod.dependencies = dependencies
                mod:Upload()

				element.parent:FireEventTree("refreshMod")
			end
		end,
	}

	local dependenciesToPanels = {}

	local dependenciesPanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		addDependencyDropdown,

		refreshMod = function(element)
			local children = {}

            local newDependenciesToPanels = {}

			for _,dependencyid in ipairs(mod.dependencies) do
				local panel = newDependenciesToPanels[dependencyid] or gui.Panel{
					width = "auto",
					height = "auto",
					flow = "horizontal",
					vmargin = 4,
					gui.Label{
						fontSize = 14,
						width = "auto",
						height = "auto",
						valign = "center",
						minWidth = 220,
						text = code.GetMod(dependencyid).name,
					},

					gui.DeleteItemButton{
						width = 16,
						height = 16,
						click = function(element)
                            local dependencies = mod.dependencies
                            local newDependencies = {}
                            for _,d in ipairs(dependencies) do
                                if d ~= dependencyid then
                                    newDependencies[#newDependencies+1] = d
                                end
                            end
                            mod.dependencies = newDependencies
                            mod:Upload()

						end,
					},
				}

				newDependenciesToPanels[dependencyid] = panel
				children[#children+1] = panel
			end

            dependenciesToPanels = newDependenciesToPanels
			children[#children+1] = addDependencyDropdown

			element.children = children
		end,
	}

	local addFileButton = gui.AddButton{
		halign = "left",
		click = function(element)
			mod:AddFile()
		end,
	}

	local filePanels = {}

    local filesTable
	filesTable = gui.Panel{
		id = "codemod-files-table",
		width = "100%",
		height = "auto",
		flow = "vertical",
		styles = {
			{
				selectors = {"label", "~button"},
				fontSize = 14,
				color = "white",
				height = "auto",
				valign = "center",
				hmargin = 8,
			},
			{
				selectors = {"fileEntry", "drag-target"},
				borderWidth = 1,
				borderColor = "#ffffff66",
			},
			{
				selectors = {"fileEntry", "drag-target-hover"},
				borderWidth = 2,
				borderColor = "#ffffffff",
			},
		},
		addFileButton,
		refreshMod = function(element)
			local newFilePanels = {}
			local rows = {}

			for i,file in ipairs(mod.files) do
				local expanded = false
				local f = file
				local revisionPanels = {}

				--panel for a file includes the file header line as well as an expansion for
				--the full file revision history.
				local p = filePanels[f.fileid] or gui.Panel{
					classes = {"filerow"},
					flow = "vertical",
					width = "auto",
					height = "auto",

					data = {
						file = f,
						ord = i,
					},

					click = function(element)
						if (not expanded) and expandedPanel ~= nil and expandedPanel ~= element then
							expandedPanel:FireEvent("click")
						end

						expanded = not expanded
						element.parent:FireEventTree("refreshMod")

						if expanded then
							expandedPanel = element
						elseif expandedPanel == element then
							expandedPanel = nil
						end
					end,

					--the header.
					gui.Panel{
						classes = {"fileEntry"},
						bgimage = "panels/square.png",
						dragTarget = true,
						
						data = {
							ord = i
						},

						canDragOnto = function(element, target)
							return target:HasClass("fileEntry")
						end,

						drag = function(element, target)
							if target == nil then
								return
							end

							printf("REORDER: %d -> %d", element.data.ord, target.data.ord)
							mod:ReorderFiles(element.data.ord, target.data.ord)
							mod:Upload()
						end,

						gui.Label{
							classes = {"fileName"},
							characterLimit = 32,
							editable = true,
							width = 220,
							halign = "left",

							create = function(element)
								element:FireEvent("search")
							end,

							search = function(element)
								if searchStr == nil then
									element:SetClass("nomatch", false)
								else
									element:SetClass("nomatch", not f:MatchesSearch(searchStr, { ignorecase = g_searchInsensitiveSetting:Get(), wholeword = g_searchWholeWordSetting:Get(), regex = g_searchRegexSetting:Get()}))
								end
							end,

							refreshMod = function(element)
								element.text = f.name
							end,

							change = function(element)
								if element.text ~= '' then
									printf("Rename: %s -> %s", f.name, element.text)
									f.name = element.text
								end

								element.text = f.name
								mod:Upload()
							end,

						},

						gui.Button{
							classes = {"tiny"},
							text = "Edit",
							valign = "center",
							create = function(element)
								element:FireEvent("refreshMod")
							end,
							click = function(element)
                                local tryOpen
                                tryOpen = function(ntries)
								    local res = mod:OpenFile(f)
                                    if res or ntries <= 0 then
                                        return
                                    end

                                    print("CodeMod: Initial try failed, retrying...")
                                    dmhub.Schedule(0.2, function()
                                        tryOpen(ntries - 1)
                                    end)
                                end
                                
                                tryOpen(10)
							end,
							refreshMod = function(element)
                                element.text = cond(mod.checkedout or mod.isUsingGit, "Edit", "View")
								--element:SetClass("collapsed", not mod.checkedout)
							end,
						},

						gui.Button{
							classes = {"tiny"},
							text = "Merge",
							valign = "center",
							create = function(element)
								element:FireEvent("refreshMod")
							end,
							click = function(element)
                                local changeInfo = mod:GetFileMergeInfo(f)
                                local result
                                if type(changeInfo) == "table" and changeInfo.merged == changeInfo.target then
                                    result = mod:SaveMerged(f)
                                else
								    result = mod:OpenFileMerge(f)
                                end
                                print("Merge:: result =", result)
                                if result then
                                    element.parent:FireEventTree("merging")
                                end
                                --element:ScheduleEvent("refreshMod", 0.1)
							end,
							refreshMod = function(element)
                                local changeInfo = mod:GetFileMergeInfo(f)
								element:SetClass("collapsed", type(changeInfo) ~= "table")
                                if type(changeInfo) == "table" then
                                    if changeInfo.merged == changeInfo.target then
                                        element.text = "Auto-Merge"
                                    else
                                        element.text = "Merge"
                                    end
                                end
							end,
						},

                        gui.Button{
							classes = {"tiny", "collapsed"},
							text = "Accept Merge",
							valign = "center",
                            merging = function(element)
                                element:SetClass("collapsed", false)
                            end,

                            click = function(element)
                                mod:AcceptFileMerge(f)
                                element:SetClass("collapsed", true)
                            end,
                        },

						gui.Label{
							halign = "right",
							width = 140,
							hmargin = 8,
							refreshMod = function(element)
								element.text = dmhub.FormatTimestamp(f.changeTimestamp, "yyyy-MM-dd HH:mm")
							end,
						},

						gui.Label{
							halign = "right",
							width = 100,
							refreshMod = function(element)
								element.text = string.format("#%d", f.numRevisions)
							end,
						},

						gui.Label{
							halign = "right",
							text = "Local Changes",
							italics = true,
							width = "auto",

							refreshMod = function(element)
                                print("Merge:: refreshMod...")
                                local changeInfo = mod:GetFileMergeInfo(f)
                                if changeInfo ~= nil then
                                    if type(changeInfo) == "table" then
                                        if changeInfo.conflicts > 0 then
                                            element.text = string.format("%d conflicts", changeInfo.conflicts)
                                        else
                                            element.text = "Can Merge"
                                        end
                                        element:SetClass("hidden", false)
                                    else
                                        element.text = "Loading..."
                                        element:SetClass("hidden", false)
                                        element:ScheduleEvent("refreshMod", 0.1)
                                    end
                                elseif f.hasLocalChanges then
									element.text = "Local Changes"
									element:SetClass("hidden", false)
								else
									element:SetClass("hidden", true)
								end
							end,
						}
					},

					--the full revision history.
					gui.Panel{
						flow = "vertical",
						classes = {cond(expanded, nil, "collapsed")},
						height = "auto",
						width = 700,
						refreshMod = function(element)
							element:SetClass("collapsed", not expanded)
							if not expanded then
								return
							end

							local revisions = f.revisions
							local newRevisionPanels = {}
							local children = {}

							dmhub.Debug("MOD:: SHOWING REVISIONS FOR " .. #revisions .. " revisions")

							for i,rev in ipairs(revisions) do
								local p = revisionPanels[i] or gui.Panel{
									classes = {"revisionPanel"},
									bgimage = "panels/square.png",

									rightClick = function(element)
										element.popup = gui.ContextMenu{
											width = 300,
											entries = {
												{
													text = "Sync this version",
													click = function()
														f:SyncLocally(i)
													end,
												}
											},

											click = function()
												element.popup = nil
											end,
										}
									end,

									gui.Panel{
										classes = {"revisionHeader"},
										gui.Label{
											width = 200,
											height = "auto",
											fontSize = 14,
											text = dmhub.FormatTimestamp(rev.timestamp, "yyyy-MM-dd HH:mm"),
										},

										gui.Label{
											width = 80,
											height = "auto",
											fontSize = 14,
											text = string.format("#%d", i)
										},

										gui.Button{
											classes = {cond(i == 1, "hidden")},
											width = 40,
											height = 16,
											fontSize = 12,
											text = "Diff",
											click = function(element)

												local md5 = f.revisions[i].md5
												local md5prev
												if f.revisions[i-1] then
													md5prev = f.revisions[i-1].md5
												end

												printf("DIFF:: STARTING")
												code.LaunchExternalDiff(md5prev, md5)
											end,
										},

										gui.Label{
											width = 140,
											height = "auto",
											fontSize = 14,
											text = rev.engineVersion,
										},
									},
									gui.Label{
										width = "100%",
										height = "auto",
										text = rev.comment,
										italics = true,
									},

								}

								newRevisionPanels[i] = p

								table.insert(children, 1, p)
							end

							if f.hasLocalChanges then
								local p = revisionPanels["local"] or gui.Panel{
									classes = {"revisionPanel"},
									bgimage = "panels/square.png",
									minHeight = 30,

									gui.Panel{
										classes = {"revisionHeader"},
										gui.Label{
											width = 200,
											height = "auto",
											fontSize = 14,
											text = "Unsubmitted",
										},

										gui.Label{
											width = 140,
											height = "auto",
											fontSize = 14,
											text = string.format("#%d*", #revisions+1)
										},

										gui.Button{
											width = 40,
											height = 16,
											fontSize = 12,
											text = "Diff",
											click = function(element)
												printf("DIFF:: STARTING")
												f:LaunchExternalDiffWithLocal()

											--local md5 = f.revisions[i].md5
											--local md5prev
											--if f.revisions[i-1] then
											--	md5prev = f.revisions[i-1].md5
											--end

											--code.LaunchExternalDiff(md5prev, md5)
											end,
										},


									},
								}

								newRevisionPanels["local"] = p

								table.insert(children, 1, p)

							end

							revisionPanels = newRevisionPanels
							element.children = children
						end,
					},
				}

				local header = p.children[1]
				header.draggable = (sortby == "execution")
				header.data.ord = i

				rows[#rows+1] = p
				newFilePanels[f.fileid] = p
			end

			if sortby == "alphabetical" then
				table.sort(rows, function(a,b) return a.data.file.name < b.data.file.name end)
			end

			rows[#rows+1] = addFileButton

			filePanels = newFilePanels
			element.children = rows
		end,
	}

	local changelistEntries = {}
	local changelistTable = gui.Panel{

		id = "codemod-cl-table",
		width = "100%",
		height = "auto",
		flow = "vertical",
		selected = function(element, val)
			if val then
				element:FireEvent("refreshMod")
			end
		end,
		refreshMod = function(element)
			if element.parent == nil or element.parent:HasClass("collapsed") then
				return
			end

			local newChangelistEntries = {}
			local children = {}
			for k,changelist in pairs(mod.changelists) do
				local changelistEntry = changelistEntries[k] or gui.Panel{
					data = {
						changelist = changelist,
					},

					classes = {"filerow"},
					flow = "vertical",
					width = "auto",
					height = "auto",

					create = function(element)
						local children = {}

						children[#children+1] = 
							gui.Panel{
								classes = {"fileEntry"},
								bgimage = "panels/square.png",
								click = function(element)
									for i=2,#children do
										children[i]:SetClass("collapsed", not children[i]:HasClass("collapsed"))
									end
								end,

								gui.Label{
									classes = {"fileName", "fileEntry"},
									halign = "left",
									width = 340,
									fontSize = 14,
									textOverflow = "ellipsis",
									text = changelist.comment,
								},

								gui.Label{
									classes = {"fileName", "fileEntry"},
									halign = "left",
									width = 160,
									fontSize = 14,
									text = dmhub.FormatTimestamp(changelist.timestamp, "yyyy-MM-dd HH:mm")
								},

								gui.Label{
									classes = {"fileName", "fileEntry"},
									halign = "left",
									width = 160,
									fontSize = 14,
									text = changelist.engineVersion,
								},

                                gui.Label{
                                    classes = {"fileName", "fileEntry"},
									halign = "left",
                                    lmargin = 8,
									width = 360,
									fontSize = 14,
									text = changelist.guid,
                                }
							}
						
						for _,fname in ipairs(changelist.files) do
							children[#children+1] = gui.Panel{
								classes = {"fileEntry", "collapsed"},
								gui.Panel{
									--padding.
									width = 40,
									height = 10,
								},
								gui.Label{
									classes = {"fileName", "fileEntry"},
									halign = "left",
									width = 340,
									fontSize = 14,
									textOverflow = "ellipsis",
									text = fname,
								},
							}
						end

						element.children = children
					end,

				}

				newChangelistEntries[k] = changelistEntry
				children[#children+1] = changelistEntry
			end

			table.sort(children, function(a,b) return a.data.changelist.timestamp > b.data.changelist.timestamp end)

			element.children = children

			changelistEntries = newChangelistEntries
		end,
	}

	local checkoutButton = gui.PrettyButton{
		fontSize = 18,
		text = "Check Out Code",
		click = function(element)
			--force developer mode on.
			dmhub.SetSettingValue("dev", true)

			--we are checking out so delete any local files/changes/etc. Start fresh!
			mod:DeleteLocalFiles()

			mod.checkedout = true
			mod:RepairLocal()
			resultPanel:FireEventTree("refreshMod")

			if mod.localChangeEvent ~= nil then
				dmhub.Debug("MOD:: LISTEN FOR CHECK OUT CHANGES")
				mod.localChangeEvent:Listen(resultPanel)
			end

		end,

		refreshMod = function(element)
			element:SetClass("collapsed", mod.checkedout or mod.isUsingGit)

			element:SetClass("hidden", (not mod.canedit) and (not mod.isowner) and (not codeModEditingSetting:Get()))
		end,
	}

	local patchButton
    local cannotCheckinText
	local checkinButton
	local changenotesInput = gui.Input{
		id = "codemod-changenotesInput",
		width = 600,
		height = "auto",
		halign = "left",
		multiline = true,
		minHeight = 60,
		characterLimit = 256,
		textAlignment = "topleft",
		placeholderText = "Describe your changes...",
		refreshMod = function(element)
			element.placeholderText = cond(submitPatch, "Write patch notes...", "Describe your changes...")
			element:SetClass("collapsed", (not mod.checkedout) or (not mod.hasLocalChanges))
			if element:HasClass("collapsed") then
				element.text = ""
			end
		end,

		edit = function(element)
			cannotCheckinText:FireEvent("refreshMod")
			checkinButton:FireEvent("refreshMod")
			patchButton:FireEvent("refreshMod")
		end,
	}

	local engineVersionInput = gui.Input{
		id = "codemod-engineVersionInput",
		width = 160,
		height = 24,
		halign = "left",
		text = dmhub.version,
	}

    local engineVersionPanel = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        gui.Label{
            text = "Engine Version:",
            fontSize = 14,
            width = "auto",
            height = "auto",
            valign = "center",
        },
        engineVersionInput,
    }

    cannotCheckinText = gui.Label{
        classes = {"collapsed"},
        vmargin = 4,
        fontSize = 18,
        width = "auto",
        height = "auto",
        maxWidth = 800,
        text = "",
		refreshMod = function(element)
            if not mod.checkedout then
                element:SetClass("collapsed", true)
                return
            end
            if not mod.hasLocalChanges then
                element:SetClass("collapsed", false)
                element.text = "No changes to check in."
                return
            end

            if changenotesInput.text == "" then
                element:SetClass("collapsed", false)
                element.text = "Please enter a changelist comment to check-in."
                return
            end

            element:SetClass("collapsed", true)
		end,
    }

	checkinButton = gui.Button{
		fontSize = 18,
		text = "Check In Code",
		click = function(element)
            local mergingRequired = false
			for i,file in ipairs(mod.files) do
                local changeInfo = mod:GetFileMergeInfo(file)
                if changeInfo ~= nil and type(changeInfo) ~= "table" then
                    gui.ModalMessage{
                        title = "Error Merging",
                        message = "There is an error with merging.",
                        options = {
                            {
                                text = "Abort",
								execute = function()
								end,
                            }
                        }
                    }
                    return
                elseif changeInfo ~= nil and changeInfo.conflicts > 0 then
                    gui.ModalMessage{
                        title = "Error Merging",
                        message = "There are conflicts in the file " .. file.name .. ". Please resolve them before checking in.",
                        options = {
                            {
                                text = "Abort",
								execute = function()
								end,
                            }
                        }
                    }
                    return
                end
            end

            if mergingRequired then
                gui.ModalMessage{
                    title = "Merging Required",
                    message = "There are files that require merging. They can all be auto-merged, or you can look at them manually.",
                    options = {
                        {
                            text = "Cancel",
                            execute = function()
                            end,
                        },
                        {
                            text = "Auto-merge",
                            execute = function()
			                    for i,file in ipairs(mod.files) do
                                    mod:AutoMergeFile(file)
                                end

                                checkinButton:FireEvent("click")
                            end,
                        }
                    }
                }
                return
            end

			mod:CommitChanges(changenotesInput.text, engineVersionInput.text, function(error)
				if error ~= nil then
					gui.ModalMessage{
						title = "Commit Failed",
						message = "The commit had an error: " .. error,
						options = {
							{
								text = "Proceed",
								execute = function()
								end,
							},
						}
					}
				else
					print("COMMIT:: COMPLETE")
					mod.checkedout = false
				end
				resultPanel:FireEventTree("refreshMod")
			end)

			changenotesInput.text = ""
		end,
		refreshMod = function(element)
			element:SetClass("collapsed", (not mod.checkedout) or (not mod.hasLocalChanges) or changenotesInput.text == "" or (not mod.canedit))
            if mod.isUsingGit then
                element.text = "Deploy Changes to Users"
            else
                element.text = "Check In Code"
            end
		end,
	}

	patchButton = gui.PrettyButton{
		fontSize = 18,
		text = "Submit Patch",
		click = function(element)

			mod:SubmitPatch(changenotesInput.text, engineVersionInput.text)

			changenotesInput.text = ""
			mod.checkedout = false
			resultPanel:FireEventTree("refreshMod")
		end,
		refreshMod = function(element)
			element:SetClass("collapsed", (not mod.checkedout) or (not mod.hasLocalChanges) or changenotesInput.text == "" or (not submitPatch))
		end,
	}


	local editModButton = gui.PrettyButton{
		fontSize = 18,
		halign = "left",
		text = "Open Code Folder",
		click = function(element)
			mod:OpenLocal()
		end,
		refreshMod = function(element)
			element:SetClass("collapsed", not mod.checkedout)
		end,
	}

	local revertButton = gui.PrettyButton{
		fontSize = 18,
		halign = "left",
		text = "Revert Changes",
		click = function(element)
			gui.ModalMessage{
				title = "Revert Files",
				message = "This will revert all changes you have made to the lua files that you haven't checked in. Changes you have made will be lost. Are you sure you want to do this?",
				options = {
					{
						text = "Proceed",
						execute = function()
							mod.checkedout = false
							mod:RepairLocal()
							resultPanel:FireEventTree("refreshMod")
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
		refreshMod = function(element)
			element:SetClass("collapsed", (not mod.checkedout) or mod.isUsingGit)
		end,
	}

	local patchesPanels = {}

	local patchesPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",
		refreshMod = function(element)
			local newPatchesPanels = {}
			local children = {}
			local patches = mod.patches
			for k,patch in pairs(patches) do
				if mod.canedit or k == dmhub.loginUserid then
					local panel = patchesPanels[k] or gui.Panel{
						width = "auto",
						height = "auto",
						flow = "horizontal",

						gui.Label{
							text = patch.ownerName,
							width = 240,
							height = "auto",
							fontSize = 14,
						},

						gui.Label{
							text = DescribeServerTimestamp(patch.timestamp),
							width = 160,
							height = "auto",
							fontSize = 12,
						},

						gui.Button{
							classes = {cond(mod.checkedout, "hidden")},
							width = 70,
							height = 16,
							fontSize = 12,
							hmargin = 4,
							text = "Check Out",
							refreshMod = function(element)
								element:SetClass("hidden", mod.checkedout)
							end,
							click = function(element)
								mod:CheckOutPatch(k, function()
									resultPanel:FireEventTree("refreshMod")

									if mod.localChangeEvent ~= nil then
										mod.localChangeEvent:Listen(resultPanel)
									end
								end)
							end,
						},

						gui.Label{
							text = patch.comment,
							fontSize = 12,
							width = 300,
							height = "auto",
						},
					}

					newPatchesPanels[k] = panel
					children[#children+1] = panel
				end
			end

			patchesPanels = newPatchesPanels
			element.children = children
		end,
	}

	local filesLeftPanel = gui.Panel{
		id = "codemod-files-left-panel",
		width = 700,
		height = "auto",
		flow = "vertical",
		filesTable,
		editModButton,
		checkoutButton,
		engineVersionPanel,
		changenotesInput,
		checkinButton,
        cannotCheckinText,
		patchButton,
		revertButton,
		patchesPanel,
	}


	local filesLeftRightPanel = gui.Panel{
		id = "codemod-code-leftrightpanel",
		flow = "horizontal",
		valign = "top",
		width = "auto",
		height = "auto",
		filesLeftPanel,
	}

	local searchCaseCheck = gui.Check{
		height = 14,
		fontSize = 10,
		text = "Match Case",
        minWidth = 0,
		value = not g_searchInsensitiveSetting:Get(),
		change = function(element)
			g_searchInsensitiveSetting:Set(not element.value)
			m_containerPanel:FireEventTree("search", searchStr)
		end,
	}

	local searchWholeWordCheck = gui.Check{
        text = "Whole Word",
		height = 14,
		fontSize = 10,
        minWidth = 0,
		value = g_searchWholeWordSetting:Get(),
		change = function(element)
			g_searchWholeWordSetting:Set(element.value)
			m_containerPanel:FireEventTree("search", searchStr)
		end,
	}

	local searchRegexCheck = gui.Check{
        text = "Regex",
		height = 14,
		fontSize = 10,
        minWidth = 0,
		value = g_searchRegexSetting:Get(),
		change = function(element)
			g_searchRegexSetting:Set(element.value)
			m_containerPanel:FireEventTree("search", searchStr)
		end,
	}

    local searchOptions = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        searchCaseCheck,
        searchWholeWordCheck,
        searchRegexCheck,
    }

	local searchInput = gui.Input{
		placeholderText = "Search...",
		text = "",
		halign = "left",
		valign = "top",
		editlag = 0.25,

		edit = function(element)
			if element.text == "" then
				searchStr = nil
			else
				searchStr = element.text
			end

			m_containerPanel:FireEventTree("search", searchStr)
		end,
	}

	local sortOrder = gui.Dropdown{
		options = {
			{
				id = "alphabetical",
				text = "Alphabetical Order",
			},
			{
				id = "execution",
				text = "Execution Order",
			},
		},

		idChosen = sortby,
		hmargin = 16,
		width = 240,
		height = 30,
		fontSize = 16,

		change = function(element)
			sortby = element.idChosen
			dmhub.SetSettingValue("codemodsorting", sortby)
			filesTable:FireEventTree("refreshMod")
		end,
	}

	local searchAndOrderingPanel = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",

		gui.Panel{
			flow = "vertical",
			width = "auto",
			height = "auto",
			searchInput,
			searchOptions,
		},
		sortOrder,
	}

	local codePanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		valign = "top",
		searchAndOrderingPanel,
		filesLeftRightPanel,
	}

	local changesPanel = gui.Panel{
		classes = {"collapsed"},
		flow = "vertical",
		width = "auto",
		height = "auto",
		valign = "top",
		changelistTable,
	}

	local resourceNameUsed = function(str)
		local currentResources = mod.resources
		for _,resource in ipairs(currentResources) do
			if resource.name == str then
				return true
			end
		end

		return false
	end

	local imageRows = {}
	local addImageButton = gui.AddButton{
		click = function()
			local imageSeq = 1
			while resourceNameUsed(string.format("image%d", imageSeq)) do
				imageSeq = imageSeq+1
			end

			mod:AddResource{
				name = string.format("image%d", imageSeq)
			}

			mod:Upload()
		end,
	}

	local imagesPanel = gui.Panel{
		classes = {"collapsed"},
		flow = "vertical",
		width = 1200,
		height = "auto",

		addImageButton,

		refreshMod = function(element)
			local children = {}
			local newImageRows = {}

			for i,resource in ipairs(mod.resources) do
				local panel = imageRows[resource.guid] or gui.Panel{
					flow = "horizontal",
					width = 600,
					height = 80,
					gui.Label{
						hmargin = 8,
						fontSize = 16,
						width = 140,
						height = "auto",
						text = "Name:",
						halign = "left",
					},

					gui.Input{
						width = 200,
						fontSize = 16,
						height = 20,
						text = resource.name,
						change = function(element)
							element.text = trim(element.text)
							local valid = element.text ~= ""
							for _,otherResource in ipairs(mod.resources) do
								if otherResource.guid ~= resource.guid and otherResource.name == element.text then
									valid = false
								end
							end

							if valid then
								resource.name = element.text
								mod:Upload()
							else
								element.text = resource.name
							end
						end,
					},

					gui.IconEditor{
						library = "resources",
						width = 64,
						height = 64,
						halign = "right",
						value = resource.assetGuid,
						change = function(element)
							resource.assetGuid = element.value
                            resource:AssetUpdated()
							mod:Upload()
						end,
					},
				}

				children[#children+1] = panel
				newImageRows[resource.name] = panel
			end

			children[#children+1] = addImageButton

			element.children = children
			imageRows = newImageRows
		end,
	}

	local CreateTabHeading = function(text, panel)
		return gui.Label{
			classes = {"tab", cond(panel:HasClass("collapsed"), nil, "selected")},
			bgimage = "panels/square.png",
			text = text,
			click = function(element)
				for _,el in ipairs(element.parent.children) do
					el:FireEvent("selected", el == element)
				end
			end,

			selected = function(element, val)
				element:SetClass("selected", val)
				panel:SetClass("collapsed", not val)
				panel:FireEventTree("selected", val)
			end,
		}
	end

	local tabHeading = gui.Panel{
		styles = {
			{
				selectors = {"tab"},
				width = 180,
				height = "auto",
				textAlignment = "left",
				halign = "left",
				fontSize = 20,
				hmargin = 20,
				color = "#999999",
				bgcolor = "clear",
			},
			{
				selectors = {"tab", "hover"},
				color = "#cccccc",
			},
			{
				selectors = {"tab", "press"},
				color = "#777777",
			},
			{
				selectors = {"tab", "selected"},
				color = "white",
				transitionTime = 0.2,
				bgcolor = "#ff000044",
			},
		},
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "top",
		vmargin = 12,
		flow = "horizontal",
		CreateTabHeading("Code", codePanel),
		CreateTabHeading("Changes", changesPanel),
		CreateTabHeading("Images", imagesPanel),
	}


	errorPanel = gui.Panel{
		flow = "vertical",
		vscroll = true,
		width = "90%",
		height = "20%",
		halign = "left",
		create = function(element)
			code.logEvent:Listen(element)
		end,
		log = function(element, str, color)
			color = color or "white"
			element:AddChild(gui.Label{
				text = str,
				width = "100%-16",
				height = "auto",
				halign = "center",
				textAlignment = "left",
				fontSize = 14,
				color = color,
			})
		end,
		error = function(element, str)
			element:FireEvent("log", "#ff7777")
		end,
	}

	resultPanel = gui.Panel{
		width = 1060,
		height = "100%",
		flow = "vertical",
		classes = {"hidden"},
		styles = {
			Styles.Form,
			{
				selectors = {"formLabel"},
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"formInput"},
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"fileName"},
				width = 160,
				halign = "left",
				color = "white",
			},
			{
				selectors = {"fileName", "nomatch"},
				color = "grey",
				priority = 2,
			},
			{
				selectors = {"fileEntry"},
				bgcolor = "#333333ff",
				fontSize = 18,
				height = 20,
				width = "100%",
				flow = "horizontal",
				textAlignment = "left",
			},
			{
				selectors = {"fileEntry", "hover"},
				bgcolor = "#883333ff",
			},
			{
				selectors = {"fileEntry", "press"},
				bgcolor = "#553333ff",
			},
			{
				selectors = {"revisionPanel"},
				bgcolor = "black",
				flow = "vertical",
				height = "auto",
				width = "100%",
			},
			{
				selectors = {"revisionPanel", "selected"},
				bgcolor = "#666600",
			},
			{
				selectors = {"revisionPanel", "hover"},
				bgcolor = "#880000",
			},
			{
				selectors = {"revisionHeader"},
				flow = "horizontal",
				height = 18,
				width = "100%",
			},
		},

		codechange = function(element)
		dmhub.Debug("CODE CHANGE, REFRESHING")
			element.parent:FireEventTree("refreshAssets")
			element:FireEventTree("refreshMod")
		end,

		setmod = function(element, modid)
			mod = code.GetMod(modid)
			if mod == nil then
				element:SetClass("hidden", true)
				return
			end

			code.monitorid = modid
			code.modifyEvent:Listen(element)

			if mod.checkedout and mod.localChangeEvent ~= nil then
				dmhub.Debug("INSTALL LOCAL CHANGE LISTENER")
				mod.localChangeEvent:Listen(element)
			end

			element:SetClass("hidden", false)
			element:FireEventTree("refreshMod")
		end,

		gui.Panel{
			vscroll = true,
			flow = "vertical",
			width = "100%",
			height = "80%",

			gui.Panel{
				width = "100%-16",
				height = "auto",
				vpad = 16,
				flow = "vertical",
				halign = "left",
				hmargin = 6,
				idPanel,
				namePanel,
				descriptionPanel,
				dependenciesPanel,
				permissionsPanel,

                gui.Panel{
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    width = "auto",
                    height = "auto",
				    devSettingsButton,
                    replicateToGitButton,
                    gitStatusLabel,
                },

                gui.Panel{
                    flow = "vertical",
                    width = "auto",
                    height = "auto",
                    data = {
                        panels = {},
                    },
		            refreshMod = function(element)
                        if not mod.isUsingGit then
                            element:SetClass("collapsed", true)
                            return
                        end

                        local unmanagedFiles = mod.unmanagedGitFiles
                        if unmanagedFiles == nil then
                            element:SetClass("collapsed", true)
                            return
                        end

                        element:SetClass("collapsed", false)

                        local children = {}
                        local panels = element.data.panels
                        local newPanels = {}

                        for _,file in ipairs(unmanagedFiles) do
                            local panel = panels[file] or gui.Panel{
                                flow = "horizontal",
                                width = "auto",
                                height = "auto",

                                gui.Label{
                                    text = file,
                                    fontSize = 14,
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 180,
                                    valign = "center",
                                },

                                gui.Label{
                                    text = "Not in Mod",
                                    fontSize = 14,
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 100,
                                    valign = "center",
                                },

                                gui.Button{
                                    halign = "left",
                                    text = "Add to Mod",
                                    fontSize = 12,
                                    width = 100,
                                    height = 20,
                                    hmargin = 8,
                                    valign = "center",
                                    click = function(element)
                                        mod:AddFile(file)
                                    end,
                                },
                            }

                            newPanels[file] = panel
                            children[#children+1] = panel
                        end

                        element.data.panels = newPanels
                        element.children = children
                    end,
                },

                --files missing from git.
                gui.Panel{
                    flow = "vertical",
                    width = "auto",
                    height = "auto",
                    data = {
                        panels = {},
                    },
		            refreshMod = function(element)
                        if not mod.isUsingGit then
                            element:SetClass("collapsed", true)
                            return
                        end

                        local unmanagedFiles = mod.filesMissingFromGit
                        if unmanagedFiles == nil then
                            element:SetClass("collapsed", true)
                            return
                        end

                        element:SetClass("collapsed", false)

                        local children = {}
                        local panels = element.data.panels
                        local newPanels = {}

                        for _,file in ipairs(unmanagedFiles) do
                            local panel = panels[file] or gui.Panel{
                                flow = "horizontal",
                                width = "auto",
                                height = "auto",

                                gui.Label{
                                    text = file,
                                    fontSize = 14,
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 180,
                                    valign = "center",
                                },

                                gui.Label{
                                    text = "Not in Git",
                                    fontSize = 14,
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 100,
                                    valign = "center",
                                },

                                gui.Button{
                                    halign = "left",
                                    text = "Add to Mod",
                                    fontSize = 12,
                                    width = 100,
                                    height = 20,
                                    hmargin = 8,
                                    valign = "center",
                                    click = function(element)
                                        mod:ReplicateFileToGit(file)
						                element.root:FireEventTree("refreshMod")
                                    end,
                                },
                            }

                            newPanels[file] = panel
                            children[#children+1] = panel
                        end

                        element.data.panels = newPanels
                        element.children = children
                    end,
                },

				tabHeading,
				codePanel,
				changesPanel,
				imagesPanel,
			},
		},

		errorPanel,
	}

	local containerPanelArgs = {
		width = 1260,
		height = "100%",
		hmargin = 80,
		hpad = 10,
		resultPanel,

		setmod = function(element, modid)
			resultPanel:FireEvent("setmod", modid)
		end,
	}

	for k,v in pairs(panelArgs or {}) do
		containerPanelArgs[k] = v
	end

	m_containerPanel = gui.Panel(containerPanelArgs)

	return m_containerPanel
end

}

CreateCodeDiffPanel = function()
	local resultPanel
	resultPanel = gui.Panel{
		id = "codemod-code-listing-panel",
		classes = {'framedPanel', 'hidden'},
		floating = true,
		width = 1000,
		height = 900,

		styles = {
			Styles.Panel,
			{
				selectors = {"codeline"},
				width = "95%",
				height = "auto",
				halign = "left",
				hmargin = 4,
				fontSize = 14,
				height = "auto",
				pad = 2,
				bgimage = "panels/square.png",
				bgcolor = "black",
			},
			{
				selectors = {"codeline", "delete"},
				bgcolor = "#770000",
			},
			{
				selectors = {"codeline", "add"},
				bgcolor = "#007700",
			},
		},

		showdiff = function(element, diff)
			element:SetClass("hidden", false)
			element.children[1]:FireEvent("showdiff", diff)
		end,

		gui.Panel{
			flow = "vertical",

			halign = "center",
			valign = "center",
			vscroll = true,

			width = 940,
			height = 840,

			showdiff = function(element, diff)
				local lines = {}
				for _,entry in ipairs(diff) do
					if entry.common ~= nil then
						for _,line in ipairs(entry.common) do
							lines[#lines+1] = gui.Label{
								classes = {"codeline"},
								text = line,
							}
						end
					end

					if entry.a ~= nil then
						for _,line in ipairs(entry.a) do
							lines[#lines+1] = gui.Label{
								classes = {"codeline", "delete"},
								text = line,
							}
						end
					end

					if entry.b ~= nil then
						for _,line in ipairs(entry.b) do
							lines[#lines+1] = gui.Label{
								classes = {"codeline", "add"},
								text = line,
							}
						end
					end

				end

				element.children = lines
			end,
		},

		gui.CloseButton{
			halign = "right",
			valign = "top",
			width = 24,
			height = 24,
			hmargin = 8,
			vmargin = 8,
			click = function(element)
				resultPanel:SetClass("hidden", true)
			end,
		},
	}

	return resultPanel
end
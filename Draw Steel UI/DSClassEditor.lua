local mod = dmhub.GetModLoading()

local g_registeredCharacterChoices = {}

function CharacterChoice.RegisterChoice(options)
    g_registeredCharacterChoices[options.id] = options
end


local CreateFeatureSummary = function(feature, featuresList, index, parentPanel, DescribeFeature, options)
	options = options or {}

	local pointsCostPanel = nil
	
    local points = options.points
    options.points = nil
	if points then
		pointsCostPanel = gui.Input{
			width = 60,
			height = 20,
			fontSize = 16,
			characterLimit = 3,
			placeholderText = "Points...",
			text = tostring(feature:try_get("pointsCost", "")),
			change = function(element)
				local num = tonumber(element.text)
				if num ~= nil and num >= 1 then
					feature.pointsCost = num
					element.text = tostring(num)
				else
					feature.pointsCost = nil
					element.text = ""
				end
				element:FireEventTree("refreshFeatures")
				parentPanel:FireEvent("change")
			end,
		}
	end


    local importedLabel = nil
    if feature:try_get("imported", false) then
        importedLabel = gui.Label{
            classes = {cond(feature:try_get("importOverride", false), "override", "imported")},
            text = cond(feature:try_get("importOverride", false), "Overwrite", "Imported"),
            bold = true,
            fontSize = 16,
            halign = "right",
            valign = "center",
            width = 100,
            height = "auto",
        }
    end

	DescribeFeature = DescribeFeature or function(f) return f.name end
	local name = DescribeFeature(feature)
	local featurePanel
	featurePanel =  gui.Panel{
		classes = {"formPanel", "hideOnSearchMismatch"},
		width = 600,
		refreshModifier = function(element)
			element:FireEventTree("refreshFeatures")
			parentPanel:FireEvent("change")
		end,

        searchCompendium = function(element, text)
            if text == "" then
                element:SetClassTree("searching", false)
                element:SetClassTree("matchSearch", false)
                return
            end

            element:SetClassTree("searching", true)
            if MatchesSearchRecursive(feature, text) then
                element:SetClassTree("matchSearch", true)
            else
                element:SetClassTree("matchSearch", false)
            end
        end,

		gui.Label{
			text = name,
			refreshFeatures = function(element)
				element.text = DescribeFeature(feature)
			end,
            classes = {cond(feature:try_get("imported", false), cond(feature:try_get("importOverride", false), "override", "imported"))},
			fontSize = 20,
			valign = 'center',
			halign = 'left',
			width = 340,
			textWrap = true,
			height = 'auto',

            create = function(element)
            end,

			rightClick = function(element)
				local clipboardItem = dmhub.GetInternalClipboard()
				if clipboardItem ~= nil then
					clipboardItem.guid = dmhub.GenerateGuid()
				end

				local entries = {
						{
							text = 'Copy Feature...',
							click = function()
								element.popup = nil
								dmhub.CopyToInternalClipboard(feature)
							end,
						}
					}

				if index > 1 then
					entries[#entries+1] = {
						text = 'Move Up',
						click = function()
							table.remove(featuresList, index)
							table.insert(featuresList, index-1, feature)
							parentPanel:FireEvent("change")
							parentPanel:FireEvent("create")
						end,
					}
				end

				if index < #featuresList then
					entries[#entries+1] = {
						text = 'Move Down',
						click = function()
							table.remove(featuresList, index)
							table.insert(featuresList, index+1, feature)
							parentPanel:FireEvent("change")
							parentPanel:FireEvent("create")
						end,
					}
				end

				if clipboardItem ~= nil and (clipboardItem.typeName == 'CharacterFeature' or clipboardItem.typeName == 'CharacterFeatureChoice') then

					entries[#entries+1] = {
						text = 'Paste Before',
						click = function()
							element.popup = nil
							parentPanel:FireEvent('paste', clipboardItem, index)
						end,
					}

					entries[#entries+1] = {
						text = 'Paste After',
						click = function()
							element.popup = nil
							parentPanel:FireEvent('paste', clipboardItem, index+1)
						end,
					}

				end

                if feature:try_get("imported", false) then
                    entries[#entries+1] =
                    {
                        text = cond(feature:try_get("importOverride", false), "Revert Override", "Override Import"),
                        click = function()
                            element.popup = nil
                            feature.importOverride = not feature:try_get("importOverride", false)
                            parentPanel:FireEvent("change")
                            parentPanel:FireEvent("create")
                        end,
                    }
                end

				element.popup = gui.ContextMenu{
					entries = entries
				}
			end,
		},

        importedLabel,

		pointsCostPanel,

		gui.ImplementationStatusIcon{
			halign = "right",
            valign = "center",
			implementation = feature:try_get("implementation", 1),
			refreshFeatures = function(element)
				element:FireEvent("implementation", feature:try_get("implementation", 1))
			end,
		},

		gui.SettingsButton{
			width = 16,
			height = 16,
			halign = "right",
			hmargin = 12,
			click = function(element)
				local fn = function(element, feature)
					local editor = feature:PopupEditor()
					editor.data.notifyElement = featurePanel --will receive refreshModifier events.
					element.root:AddChild(editor)	
				end

				print("Compendium:: Firing...")
				element.root:FireEventTree("editCompendiumFeature", feature, fn)

				fn(element, feature)
			end,
		},

		gui.DeleteItemButton{
			halign = "right",
			width = 16,
			height = 16,
            requireConfirm = true,
			click = function(element)
				table.remove(featuresList, index)
				parentPanel:FireEvent("change")
				parentPanel:FireEvent("create")
			end,
		},
	}
	return featurePanel
end

--this handles choices and feature lists.
local CreateChoiceEditor = function(feature, featuresList, index, parentPanel, classOrRace, options)

	local pointsCostPanel = nil
	
    local points = options.points
    options.points = nil
	if points then
		pointsCostPanel = gui.Input{
			width = 60,
			height = 20,
			fontSize = 16,
			characterLimit = 3,
			placeholderText = "Points...",
			text = tostring(feature:try_get("pointsCost", "")),
			change = function(element)
				local num = tonumber(element.text)
				if num ~= nil and num >= 1 then
					feature.pointsCost = num
					element.text = tostring(num)
				else
					feature.pointsCost = nil
					element.text = ""
				end
				element:FireEventTree("refreshFeatures")
				parentPanel:FireEvent("change")
			end,
		}
	end


	local resultPanel

	local children = {}
	--some kind of choice.

	local tri = gui.Panel{
		classes = {"triangle"},
		height = "30%",
		width = "100% height",
		hmargin = 4,
		styles = Styles.triangleStyles,
	}

	local body

	local nameLabel = gui.Label{
            classes = {cond(feature:try_get("imported", false), cond(feature:try_get("importOverride", false), "override", "imported"))},
			fontSize = 18,
			bold = true,
			width = 400,
			height = 'auto',
			valign = "center",
            textAlignment = "left",
			text = feature:Describe(),
		}

    local importedLabel = nil
    if feature:try_get("imported", false) then
        importedLabel = gui.Label{
            classes = {cond(feature:try_get("importOverride", false), "override", "imported")},
            text = cond(feature:try_get("importOverride", false), "Overwrite", "Imported"),
            bold = true,
            fontSize = 16,
            halign = "right",
            valign = "center",
            width = 100,
            height = "auto",
        }
    end

	children[#children+1] = gui.Panel{

		bgimage = "panels/square.png",
		styles = {
			{
				selectors = {"header"},
				bgcolor = "black",
			},
			{
				selectors = {"header","hover"},
				bgcolor = "#664444ff",
			},
		},

		classes = {"header"},

		hmargin = 8,

		flow = "horizontal",
		height = 30,
		width = 600,
		tri,
		nameLabel,
        pointsCostPanel,
        importedLabel,

		gui.DeleteItemButton{
			halign = "right",
			width = 16,
			height = 16,
            requireConfirm = true,
			click = function(element)
				resultPanel:FireEvent("delete")
			end,
		},

		click = function(element)
			body:SetClass('collapsed-anim', not body:HasClass('collapsed-anim'))
			tri:SetClass("expanded", not tri:HasClass("expanded"))
		end,

		rightClick = function(element)

			local entries = {
				{
					text = 'Copy Choice...',
					click = function()
						element.popup = nil
						dmhub.CopyToInternalClipboard(feature)
					end,
				},
			}

            local ref = CompendiumReference.CreateFromObject(feature)
            if ref ~= nil then
                entries[#entries+1] = {
                    text = "Copy Reference...",
                    click = function()
                        element.popup = nil
						dmhub.CopyToInternalClipboard(ref)
                        dmhub.CopyToClipboard(ref.targetTable .. "/" .. ref.targetid .. "/" .. ref.targetPath)
                    end,
                }
            end

			if index > 1 then
				entries[#entries+1] = {
					text = 'Move Up',
					click = function()
						table.remove(featuresList, index)
						table.insert(featuresList, index-1, feature)
						parentPanel:FireEvent("change")
						parentPanel:FireEvent("create")
					end,
				}
			end

			if index < #featuresList then
				entries[#entries+1] = {
					text = 'Move Down',
					click = function()
						table.remove(featuresList, index)
						table.insert(featuresList, index+1, feature)
						parentPanel:FireEvent("change")
						parentPanel:FireEvent("create")
					end,
				}
			end

            if feature:try_get("imported", false) then
                entries[#entries+1] =
                {
                    text = cond(feature:try_get("importOverride", false), "Revert Override", "Override Import"),
                    click = function()
                        element.popup = nil
                        feature.importOverride = not feature:try_get("importOverride", false)
                        parentPanel:FireEvent("change")
                        parentPanel:FireEvent("create")
                    end,
                }
            end

			element.popup = gui.ContextMenu{
				entries = entries
			}
		end,
	}

	local tagEditor = nil
	if feature.typeName == "CharacterFeatChoice" then

        tagEditor = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
        }


        local RefreshTags

        RefreshTags = function()
            local tags = {
                feat = true,
            }

            local featsTable = dmhub.GetTable(CharacterFeat.tableName) or {}

            for k,feat in pairs(featsTable) do
                if not feat:try_get("hidden", false) then
                    for _,tag in ipairs(feat:Tags()) do
                        tags[string.lower(tag)] = true
                    end
                end
            end

            local options = {}
            for k,_ in pairs(tags) do
                options[#options+1] = {
                    id = k,
                    text = k,
                }
            end

            table.sort(options, function(a,b) return a.text < b.text end)

            local element = tagEditor
            element.children = {}

            local currentTags = feature:Tags()
                    print("TAGS:: REFRESH", feature.tag, "is", currentTags)
            for _,tag in ipairs(currentTags) do
                local tagPanel = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        text = "Tag:",
                        classes = {"formLabel"},
                        minWidth = 160,
                    },
                    gui.Dropdown{
                        width = 240,
                        options = options,
                        idChosen = tag,
                        change = function(element)
                            local newTags = {}
                            for _,tag in ipairs(currentTags) do
                                if tag ~= element.idChosen then
                                    newTags[#newTags+1] = tag
                                else
                                    newTags[#newTags+1] = element.idChosen
                                end
                            end
                            feature.tag = string.join(newTags,",")
                            resultPanel:FireEvent("change")
                            RefreshTags()
                        end,
                    },

                    gui.DeleteItemButton{
                        classes = cond(#currentTags == 1, {"hidden"}),
                        floating = true,
                        halign = "right",
                        valign = "center",
                        x = 16,
                        width = 12,
                        height = 12,
                        requireConfirm = true,
                        click = function(element)
                            local newTags = {}
                            for _,t in ipairs(currentTags) do
                                if t ~= tag then
                                    newTags[#newTags+1] = t
                                end
                            end
                            feature.tag = string.join(newTags,",")
                            resultPanel:FireEvent("change")
                            RefreshTags()
                        end,
                    }
                }
                element:AddChild(tagPanel)
            end

            element:AddChild(gui.Dropdown{
                width = 240,
                halign = "right",
                textOverride = "Add Tag...",
                options = options,
                change = function(element)
                    local newTags = DeepCopy(currentTags)
                    newTags[#newTags+1] = element.idChosen
                    feature.tag = string.join(newTags,",")
                    print("TAGS:: SET", feature.tag, "HAVE", feature:Tags())
                    resultPanel:FireEvent("change")
                    RefreshTags()
                end,
            })
        end --end of RefreshTags function.

        RefreshTags()
       
	elseif feature.typeName == "CharacterSingleFeat" then

		local options = {
			{
				id = "none",
				text = "Choose Feat...",
				hidden = true,
			}
		}
		local featsTable = dmhub.GetTable(CharacterFeat.tableName) or {}

		for k,feat in pairs(featsTable) do
			options[#options+1] = {
				id = k,
				text = feat.name,
			}
		end

		table.sort(options, function(a,b) return a.text < b.text end)


		body = gui.Panel{
			width = "100%",
			height = "auto",
			hmargin = 40,
			flow = "vertical",
			classes = {'collapsed-anim'},

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					text = "Feat:",
					classes = {"formLabel"},
					minWidth = 160,
				},
				gui.Dropdown{
					width = 240,
					options = options,
					idChosen = feature.featid,
					hasSearch = true,
					change = function(element)
						feature.featid = element.idChosen
						resultPanel:FireEvent("change")
						nameLabel.text = feature:Describe()
					end,
				}
			}
		}
	end

	local prerequisitesEditor = nil
	if feature.typeName == "CharacterFeatureList" then
		local dropdown = gui.Dropdown{
			height = 30,
			width = 220,
			fontSize = 14,
			halign = "left",

			idChosen = "none",
			options = CharacterPrerequisite.options, 
			change = function(element)
				if element.idChosen ~= 'none' then
					feature:get_or_add("prerequisites", {})
					feature.prerequisites[#feature.prerequisites+1] = CharacterPrerequisite.Create{
						type = element.idChosen,
					}
					resultPanel:FireEvent("change")

					element.idChosen = 'none'
					prerequisitesEditor:FireEvent("create")
				end
			end,
		}

		prerequisitesEditor = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			children = {dropdown},

			create = function(element)
				local children = {dropdown}

				for i,pre in ipairs(feature:try_get("prerequisites", {})) do
					children[#children+1] = pre:Editor{
						change = function(element)
							resultPanel:FireEvent("change")
						end,
						delete = function(element)
							table.remove(feature.prerequisites, i)
							resultPanel:FireEvent("change")
							prerequisitesEditor:FireEvent('create')
						end
					}
				end

				element.children = children
			end,
		}
	end

	local rulesTextEditor = nil

	if feature:try_get("rulesText") ~= nil then
		rulesTextEditor = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Rules Text:",
				classes = {"formLabel"},
				minWidth = 160,
			},
			gui.Input{
				width = 400,
				text = feature.rulesText,
				placeholderText = "Enter text...",
				change = function(element)
					feature.rulesText = element.text
					resultPanel:FireEvent("change")
				end,
			}
		}
	end


	if body == nil then
		body = gui.Panel{
			width = "100%",
			height = "auto",
			hmargin = 40,
			flow = "vertical",
			classes = {'collapsed-anim'},

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					text = "Name:",
					classes = {"formLabel"},
					minWidth = 160,
				},
				gui.Input{
					width = 240,
					text = feature.name,
					change = function(element)
						feature.name = element.text
						resultPanel:FireEvent("change")
						nameLabel.text = feature:Describe()
					end,
				}
			},


			prerequisitesEditor,

			tagEditor,

			rulesTextEditor,


			gui.Input{
				multiline = true,
				height = 'auto',
				minHeight = 30,
				width = 540,
				placeholderText = "Enter prompt text...",
				text = feature.description,
				characterLimit = 2000,

				change = function(element)
					feature.description = element.text
					resultPanel:FireEvent("change")
				end,

			},

			feature:CreateEditor(classOrRace, {
				change = function(element)
					resultPanel:FireEvent("change")
				end
			}),
		}
	end

	children[#children+1] = body

	local args = {
        classes = {"hideOnSearchMismatch"},
		flow = "vertical",
		width = "auto",
		height = "auto",
		children = children,

        searchCompendium = function(element, text)
            if text == "" then
                element:SetClassTree("searching", false)
                element:SetClassTree("matchSearch", false)
                return
            end

            element:SetClassTree("searching", true)
            if MatchesSearchRecursive(feature, text) then
                element:SetClassTree("matchSearch", true)
            else
                element:SetClassTree("matchSearch", false)
            end
        end,
	}

	for k,option in pairs(options or {}) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

function ClassLevel:CreateEditor(classOrRace, levelNum, params)
	local classid = nil
	local raceid = nil
	if classOrRace.typeName == "Class" then
		classid = classOrRace.id
    elseif classOrRace.typeName == "Race" then
        raceid = classOrRace.id
	end

	local resultPanel

	local DescribeFeature = function(feature)
		local isupgrade = false
		if levelNum > 0 then
			for i=0,levelNum-1 do
				local previousLevel = classOrRace:GetLevel(i)
				for j,previousFeature in ipairs(previousLevel.features) do
					if previousFeature.typeName == 'CharacterFeature' and previousFeature.name == feature.name then
						isupgrade = true
					end
				end
			end
		end

		if isupgrade then
			return string.format("%s (Upgrade)", feature.name)
		else
			return feature.name
		end
	end

	local args = {
		width = "100%",
		height = "auto",
		bgimage = "panels/square.png",
		bgcolor = "black",
		flow = "vertical",

		styles = {
			Styles.ImplementationIcon,
            {
                selectors = {"imported"},
                color = "#999999",
            },
            {
                selectors = {"imported", "hover"},
                color = "#bbbbbb",
            },
            {
                selectors = {"override"},
                color = "#77bb77",
            },
		},

		paste = function(element, item, index)
			item = DeepCopy(item)
			item:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
			item:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
			table.insert(self.features, index, item)
			element:FireEvent("change")
			element:FireEvent("create")
		end,

		create = function(element)
			local children = {}

			for i,feature in ipairs(self.features) do
				local index = i
				if feature.typeName == 'CharacterFeature' then
					children[#children+1] = CreateFeatureSummary(feature, self.features, index, resultPanel, DescribeFeature)
				else
					children[#children+1] = CreateChoiceEditor(feature, self.features, index, resultPanel, classOrRace, {
						change = function(element)
							resultPanel:FireEvent("change")
						end,

						delete = function(element)
							table.remove(self.features, i)
							resultPanel:FireEvent("change")
							resultPanel:FireEvent("create")
						end,
					})
				end
			end

			local featureOptions = {
					{
						id = 'none',
						text = 'Add Features...',
					},
					{
						id = 'feature',
						text = 'Single Feature',
					},
					{
						id = 'multiple',
						text = 'Multiple Features',
					},
					{
						id = 'choice',
						text = 'Choice',
					},
					{
						id = 'feat',
						text = 'Choice of a Feat',
					},
					{
						id = 'onefeat',
						text = 'Specific Feat',
					},
				}

            for k,v in pairs(g_registeredCharacterChoices) do
                featureOptions[#featureOptions+1] = v
            end

			featureOptions[#featureOptions+1] = {
				id = "paste",
				text = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    if clipboardItem == nil or (clipboardItem.typeName ~= 'CharacterFeature' and clipboardItem.typeName ~= 'CharacterFeatureChoice' and clipboardItem.typeName ~= 'CharacterFeatChoice' and clipboardItem.typeName ~= 'CharacterSkillChoice') then
                        return "Paste"
                    end
                    return "Paste " .. clipboardItem.name
                end,
                hidden = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    return clipboardItem == nil or (clipboardItem.typeName ~= 'CharacterFeature' and clipboardItem.typeName ~= 'CharacterFeatureChoice' and clipboardItem.typeName ~= 'CharacterFeatChoice' and clipboardItem.typeName ~= 'CharacterSkillChoice')
                end,
			}

			if classOrRace.typeName == 'Class' then
				featureOptions[#featureOptions+1] =
					{
						id = 'subclass',
						text = 'Subclass',
					}
			end

            if classOrRace.typeName == 'Race' then
                featureOptions[#featureOptions+1] =
                    {
                        id = 'ancestryinheritance',
                        text = 'Ancestry Former Life',
                    }
            end

			CharacterFeaturePrefabs.FillDropdownOptions(featureOptions)

			children[#children+1] = gui.Dropdown{

				idChosen = 'none',
				options = featureOptions,

				width = 340,
				height = 30,
				fontSize = 16,
				
				change = function(element)
                    if g_registeredCharacterChoices[element.idChosen] ~= nil then
                        local t = g_registeredCharacterChoices[element.idChosen].type
						self.features[#self.features+1] = t.Create{
							source = classOrRace:FeatureSourceName(),
							classid = classid,
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'feature' then
						self.features[#self.features+1] = CharacterFeature.Create{
							source = classOrRace:FeatureSourceName(),
							classid = classid,
							canHavePrerequisites = true,
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'subclass' then
						self.features[#self.features+1] = CharacterSubclassChoice.CreateNew{
							classid = classid,
						}
						resultPanel:FireEvent("change", self)
                    elseif element.idChosen == 'ancestryinheritance' then
                        self.features[#self.features+1] = CharacterAncestryInheritanceChoice.CreateNew{
                            ancestryid = raceid,
                        }
                        resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'multiple' then
						self.features[#self.features+1] = CharacterFeatureList.CreateNew{
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'choice' then
						self.features[#self.features+1] = CharacterFeatureChoice.CreateNew()
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'feat' then
						self.features[#self.features+1] = CharacterFeatChoice.CreateNew()
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'onefeat' then
						self.features[#self.features+1] = CharacterSingleFeat.CreateNew()
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'paste' then
			            local clipboardItem = dmhub.GetInternalClipboard()
						local clone = DeepCopy(clipboardItem)
						clone:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
						clone:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
						self.features[#self.features+1] = clone
						resultPanel:FireEvent("change", self)
					else
						local prefab = CharacterFeaturePrefabs.FindPrefab(element.idChosen)
						if prefab ~= nil then
							local clone = DeepCopy(prefab)
							clone.prefab = element.idChosen
							clone:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
							clone:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
							self.features[#self.features+1] = clone
							resultPanel:FireEvent("change", self)
						end
					end

					--recreate this panel.
					resultPanel:FireEvent("create")
				end,
			}

			element.children = children
		end,
	}

	for k,v in pairs(params) do
		args[k] = v
	end
	resultPanel = gui.Panel(args)

	return resultPanel
end

function Class:CustomEditor(UploadFn, panels)
end

local SetClass = function(tableName, classPanel, classid)
	local classTable = dmhub.GetTable(tableName) or {}
	local class = classTable[classid]

    if classPanel.data.DoUploadIfNeeded ~= nil then
        classPanel.data.DoUploadIfNeeded()
    end

    classPanel.data.DoUploadIfNeeded = function()
        if classPanel.data.dataChanged ~= nil then
            dmhub.SetAndUploadTableItem(tableName, class)
            classPanel.data.dataChanged = nil
        end
    end

	local UploadClass = function()
        if classPanel.data.dataChanged == nil then
            classPanel.data.dataChanged = classPanel.aliveTime
        end
	end

	local children = {}

	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 196,
		height = "auto",
		floating = true,
		halign = "right",
		valign = "top",
		gui.IconEditor{
		value = class.portraitid,
		library = "Avatar",
		width = 196,
		height = "150% width",
		autosizeimage = true,
		allowPaste = true,
		borderColor = Styles.textColor,
		borderWidth = 2,
		change = function(element)
			class.portraitid = element.value
			UploadClass()
		end,
		},

		gui.Label{
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
			color = Styles.textColor,
			fontSize = 12,
		},
	}

	--the name of the class.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			classes = {"formLabel"},
			minWidth = 160,
		},
		gui.Input{
			text = class.name,
			change = function(element)
				class.name = string.gsub(element.text, "[-+%d]", "")
				element.text = class.name
				UploadClass()
			end,
		},
	}

	--hit die
	if (not class.isSubclass) and GameSystem.haveHitDice then
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Hit Die:',
				valign = 'center',
				minWidth = 160,
			},
			gui.Dropdown{
				options = CharacterResource.diceTypeOptionsNoNil,
				idChosen = tostring(class.hit_die),
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					class.hit_die = tonumber(element.idChosen)
					UploadClass()
				end,
			},
		}
	end

	if class.isSubclass then
		local options = {}

		local mainClassesTable = dmhub.GetTable("classes")
		for k,classInfo in pairs(mainClassesTable) do
			if not classInfo:try_get("hidden", false) then
				options[#options+1] = {
					id = k,
					text = classInfo.name,
				}
			end
		end

		table.sort(options, function(a,b) return a.text < b.text end)

		if class.primaryClassId == "" then
			options[#options+1] = {
				id = "",
				text = "Choose Primary Class...",
			}
		end

		children[#children+1] = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Primary Class:",
				valign = "center",
				minWidth = 160,
			},
			gui.Dropdown{
				options = options,
				idChosen = class.primaryClassId,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					class.primaryClassId = element.idChosen
					class:ForceDomains()
					UploadClass()
				end,
			},
		}
	end

	--class details.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Description:",
			valign = "center",
			minWidth = 240,
		},
		gui.Input{
			text = class.details,
			multiline = true,
			minHeight = 50,
			height = 'auto',
			width = 400,
			textAlignment = "topleft",
			change = function(element)
				class.details = element.text
				UploadClass()
			end,
		}
	}

	class:CustomEditor(UploadClass, children)

    children[#children+1] = gui.Label{
        fontSize = 22,
        width = "auto",
        height = "auto",
        bold = true,
        text = "Tutorial",
    }

	Class.CreateLevelEditor(children, class, UploadClass, 1, 4, "tutorial")


    children[#children+1] = gui.Label{
        fontSize = 22,
        width = "auto",
        height = "auto",
        bold = true,
        text = "Levels",
    }

	Class.CreateLevelEditor(children, class, UploadClass, 1, GameSystem.numLevels)

	classPanel.children = children

end

function Class.CreateLevelEditor(children, class, UploadClass, startLevel, finishLevel, subkey)

	for i=startLevel,finishLevel do
		local text
		if i == 0 then
			text = "Proficiencies for Primary Class"
		elseif i == -1 then
			text = "Proficiencies for Multiclass"
        elseif subkey == "tutorial" then
            text = string.format("Encounter %d", i)
		else
			text = string.format("Level %d", i)
		end

		local tri = gui.Panel{
			classes = {"triangle"},
			height = "30%",
			width = "100% height",
			styles = Styles.triangleStyles,
		}

		local classLevel = class:GetLevel(i, subkey)

		local summaryLabel = gui.Label{
			fontSize = 20,
			color = "white",
			halign = "left",
			valign = "center",
			width = "auto",
			height = "auto",
			text = cond(#classLevel.features > 0, string.format("(%d %s)", #classLevel.features, cond(#classLevel.features > 1, "features", "feature")), ''),
			update = function(element)
				element.text = cond(#classLevel.features > 0, string.format("(%d %s)", #classLevel.features, cond(#classLevel.features > 1, "features", "feature")), '')
			end,
		}

		local editorPanel = classLevel:CreateEditor(class, i, {
			classes = {"collapsed-anim"},
			hmargin = 40,
			change = function(element)
				class:ForceDomains()
				UploadClass()
				summaryLabel:FireEvent("update")
			end,
		})

		local header = gui.Panel{
			classes = {"header"},
			height = 30,
			width = "100%",
			flow = "horizontal",
			bgimage = "panels/square.png",
			styles = {
				{
					selectors = {"header"},
					bgcolor = "black",
				},
				{
					selectors = {"header","hover"},
					bgcolor = "#664444ff",
				},
			},
			tri,
			gui.Label{
                classes = {"searchableLabel"},
				hmargin = 8,
				fontSize = 20,
				halign = "left",
				valign = "center",
				width = "auto",
				height = "auto",
				text = text,
			},

			summaryLabel,

			click = function(element)
				editorPanel:SetClass("collapsed-anim", not editorPanel:HasClass("collapsed-anim"))
				tri:SetClass("expanded", not editorPanel:HasClass("collapsed-anim"))
			end,

            searchCompendium = function(element, text)
                if text == "" then
                    element:SetClassTree("searching", false)
                    element:SetClassTree("matchSearch", false)
                    return
                end

                element:SetClassTree("searching", true)
                if MatchesSearchRecursive(classLevel, text) then
                    element:SetClassTree("matchSearch", true)
                else
                    element:SetClassTree("matchSearch", false)
                end
            end,

		}

		local panel = gui.Panel{
			height = 'auto',
			width = 1100,
			flow = 'vertical',
			halign = "left",

			header,
			editorPanel,
		}

		children[#children+1] = panel
	end
end

function Class.CreateEditor()
    local m_search = ""
	local classPanel
	classPanel = gui.Panel{
		data = {
			SetClass = function(tableName, classid)
				SetClass(tableName, classPanel, classid)
                if m_search ~= "" then
                    classPanel:FireEventTree("searchCompendium", m_search)
                end
			end,
		},
        
        searchCompendium = function(element, text)
            m_search = text
        end,

        thinkTime = 1,
        think = function(element)
            if classPanel.data.DoUploadIfNeeded ~= nil and classPanel.data.dataChanged ~= nil and classPanel.aliveTime - classPanel.data.dataChanged > 20 then
                classPanel.data.DoUploadIfNeeded()
            end
        end,

        destroy = function(element)
            if classPanel.data.DoUploadIfNeeded ~= nil then
                classPanel.data.DoUploadIfNeeded()
            end
        end,

		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = "100%-160",
				height = '90%',
				maxWidth = 1200,
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			},

			Styles.ImplementationIcon,
		},
	}

	return classPanel
end

function CharacterChoice:CreateEditor(class, params)
	return nil
end

function CharacterFeatureChoice:CreateEditor(classOrRace, params)
	params = params or {}


	local resultPanel

	local args = {
		width = "100%",
		height = 'auto',
		flow = 'vertical',
		vpad = 4,

		paste = function(element, item, index)
			if item.typeName == "CharacterFeature" or item.typename == "CharacterFeatureList" then
				item = DeepCopy(item)
				item:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
				item:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
				table.insert(self.options, index, item)
				resultPanel:FireEvent('create')
				resultPanel:FireEvent('change')
			end
		end,

		create = function(element)
			local children = {}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Choices:",
					valign = "center",
				},
				gui.GoblinScriptInput{
					width = 180,
					value = self.numChoices,
					change = function(element)
						self.numChoices = element.value
						resultPanel:FireEvent('create')
						resultPanel:FireEvent('change')
					end,

					documentation = {
						help = string.format("This GoblinScript is used to determine the number of choices the character gets for this creature."),
						output = "number",
						examples = {
							{
								script = "1",
								text = "One option may be chosen",
							},
							{
								script = "Max(1, Intelligence Modifier)",
								text = "A number of options equal to your intelligence modifier may be chosen (At least 1).",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that possesses this feature",
						--symbols = self:HelpAdditionalSymbols(),
					},

				},
			}

			children[#children+1] = gui.Check{
				text = "Allow Duplicate Choices",
				classes = {cond(tonumber(self.numChoices) ~= 1, nil, "hidden")},
				value = self.allowDuplicateChoices,
				change = function(element)
					self.allowDuplicateChoices = element.value
					resultPanel:FireEvent('change')
				end,
			}

			children[#children+1] = gui.Check{
				text = "Choices Cost Points",
				classes = {cond(tonumber(self.numChoices) ~= 1, nil, "collapsed")},
				value = self.costsPoints,
				change = function(element)
					self.costsPoints = element.value
					resultPanel:FireEvent('create')
					resultPanel:FireEvent('change')
				end,
			}

            children[#children+1] = gui.Check{
                text = "Allow Choices from Former Life",
				classes = {cond(tonumber(self.numChoices) ~= 1, nil, "collapsed")},
                value = self.allowFormerLifeChoices,
                change = function (panel)
                    self.allowFormerLifeChoices = panel.value
                    resultPanel:FireEvent('create')
                    resultPanel:FireEvent('change')
                end
            }

            if self.inheritChoice then
                for i,ref in ipairs(self.inheritChoice) do
                    local resolved = ref:Resolve()
                    local label = nil
                    if resolved == nil then
                        label = gui.Label{
                            text = "Inheriting choices from an invalid reference.",
                            color = "#ff5555",
                        }
                    else
                        label = gui.Label{
                            text = string.format("Inheriting choices from: %s", resolved.name),
                            color = "#55ff55",
                        }
                    end

                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        label,
                        gui.DeleteItemButton{
                            floating = true,
                            halign = "right",
                            valign = "center",
                            x = 16,
                            width = 12,
                            height = 12,
                            requireConfirm = true,
                            click = function(element)
                                table.remove(self.inheritChoice, i)
                                resultPanel:FireEvent('create')
                                resultPanel:FireEvent('change')
                            end,
                        }
                    }
                end
            end

            local clipboardRef = dmhub.GetInternalClipboard()
            if clipboardRef ~= nil and clipboardRef.typeName == "CompendiumReference" then
                local ref = clipboardRef:Resolve()
                local alreadyHave = false
                if self.inheritChoice then
                    for _,existingRef in ipairs(self.inheritChoice) do
                        if dmhub.DeepEqual(existingRef, clipboardRef) then
                            alreadyHave = true
                            break
                        end
                    end
                end

                if (not alreadyHave) and ref ~= nil and (ref.typeName == "CharacterFeatureChoice") and ref ~= self and (rawget(ref,"id") or rawget(ref,"guid")) ~= (rawget(self,"id") or rawget(self,"guid")) then
                    children[#children+1] = gui.Button{
                        text = string.format("Inherit Choices from %s", ref.name),
                        width = 440,
                        height = 30,
                        click = function(element)
                            self.inheritChoice = self.inheritChoice or {}
                            self.inheritChoice[#self.inheritChoice+1] = clipboardRef
                            resultPanel:FireEvent('create')
                            resultPanel:FireEvent('change')
                        end,
                    }
                end
            end

			children[#children+1] = gui.Input{
				width = 200,
				height = 24,
				fontSize = 20,
				characterLimit = 32,
				placeholderText = "Enter name of points...",
				classes = {cond(tonumber(self.numChoices) ~= 1 and self.costsPoints, nil, "collapsed")},
				text = self.pointsName,
				change = function(element)
					self.pointsName = element.text
					resultPanel:FireEvent('change')
				end,
			}

			for i,feature in ipairs(self.options) do
				local index = i
				if feature.typeName == 'CharacterFeature' then
					children[#children+1] = CreateFeatureSummary(feature, self.options, index, resultPanel, nil, {points = self.costsPoints})
				else
					children[#children+1] = CreateChoiceEditor(feature, self.options, index, resultPanel, classOrRace, {
                        points = self.costsPoints,
						change = function(element)
							resultPanel:FireEvent("change")
						end,
						delete = function(element)
							table.remove(self.options, i)
							resultPanel:FireEvent("change")
							resultPanel:FireEvent("create")
						end,
					})
				end
			end

			local featureOptions = {
					{
						id = 'none',
						text = 'Add Option...',
					},
					{
						id = 'feature',
						text = 'Single Feature',
					},
					{
						id = 'multiple',
						text = 'Multiple Features',
					},
					{
						id = 'choice',
						text = 'Choice',
					},
					{
						id = 'feat',
						text = 'Choice of a Feat',
					},
					{
						id = 'onefeat',
						text = 'Specific Feat',
					},
				}

			featureOptions[#featureOptions+1] = {
				id = "paste",
				text = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    if clipboardItem == nil then
                        return "Paste"
                    end
                    return "Paste " .. clipboardItem.name
                end,
                hidden = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    return clipboardItem == nil or (clipboardItem.typeName ~= 'CharacterFeature' and clipboardItem.typeName ~= 'CharacterFeatureChoice' and clipboardItem.typeName ~= 'CharacterSkillChoice')
                end,
			}

			CharacterFeaturePrefabs.FillDropdownOptions(featureOptions)


			children[#children+1] = gui.Dropdown{

				idChosen = 'none',
				options = featureOptions,

				width = 160,
				height = 30,
				fontSize = 16,
				
				change = function(element)
					if element.idChosen == 'feature' then
						self.options[#self.options+1] = CharacterFeature.Create{
							source = classOrRace:FeatureSourceName(),
							canHavePrerequisites = true,
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'choice' then
						self.options[#self.options+1] = CharacterFeatureChoice.CreateNew{
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'multiple' then
						self.options[#self.options+1] = CharacterFeatureList.CreateNew{
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'feat' then
						self.options[#self.options+1] = CharacterFeatChoice.CreateNew{
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'onefeat' then
						self.options[#self.options+1] = CharacterSingleFeat.CreateNew{
						}
						resultPanel:FireEvent("change", self)
					elseif element.idChosen == 'paste' then
                        local clipboardItem = dmhub.GetInternalClipboard()
						local clone = DeepCopy(clipboardItem)
						clone:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
						clone:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
						self.options[#self.options+1] = clone
						resultPanel:FireEvent("change", self)
					else
						local prefab = CharacterFeaturePrefabs.FindPrefab(element.idChosen)
						if prefab ~= nil then
							local clone = DeepCopy(prefab)
							clone.prefab = element.idChosen
							clone:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
							clone:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
							self.options[#self.options+1] = clone
							resultPanel:FireEvent("change", self)
						end
					end

					--recreate this panel.
					resultPanel:FireEvent("create")
				end
			}

			children[#children+1] = gui.Panel{
				bgimage = "panels/square.png",
				width = 300,
				height = 1,
				bgcolor = "#999999",
				vmargin = 8,
			}

			element.children = children
		end,
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

function CharacterSubclassChoice:CreateEditor(class, params)
	params = params or {}

	local resultPanel

	local args = {
		width = 400,
		height = 'auto',
		flow = 'vertical',
		vpad = 4,

		create = function(element)
			local children = {}
			local subclassesTable = dmhub.GetTable("subclasses") or {}
			for k,subclass in pairs(subclassesTable) do
				if subclass.primaryClassId == self.classid and subclass:try_get("hidden", false) == false then
					children[#children+1] = gui.Panel{
						width = '100%',
						height = 20,

						gui.Label{
							text = subclass.name,
							height = 'auto',
							width = 'auto',
							minWidth = 200,
							fontSize = 16,
							color = 'white',
							valign = 'center',
						},
					}
				end
			end

--		local subclassesTable = dmhub.GetTable("subclasses") or {}
--		for i,option in ipairs(self.options) do
--			local index = i
--			local subclass = subclassesTable[option]
--			if subclass ~= nil then
--				children[#children+1] = gui.Panel{
--					width = '100%',
--					height = 20,
--					flow = 'horizontal',
--
--					gui.Label{
--						text = subclass.name,
--						height = 'auto',
--						width = 'auto',
--						minWidth = 200,
--						fontSize = 16,
--						color = 'white',
--						valign = 'center',
--					},
--
--					gui.DeleteItemButton{
--						width = 16,
--						height = 16,
--						valign = 'center',
--						click = function(element)
--							table.remove(self.options, index)
--							resultPanel:FireEvent('create')
--							resultPanel:FireEvent('change')
--						end,
--					},
--				}
--			end
--		end
--
--		local options = {
--			{
--				id = 'none',
--				text = 'Add Choice...',
--			}
--		}
--
--		for k,subclass in pairs(subclassesTable) do
--			local alreadyHas = false
--			for i,option in ipairs(self.options) do
--				if option == k then
--					alreadyHas = true
--				end
--			end
--
--			if alreadyHas == false then
--				options[#options+1] = {
--					id = k,
--					text = subclass.name,
--				}
--			end
--		end
--
--		local dropdown = gui.Dropdown{
--			options = options,
--			idChosen = 'none',
--			width = 160,
--			height = 30,
--			fontSize = 16,
--			change = function(element)
--				if element.idChosen ~= 'none' then
--					self.options[#self.options+1] = element.idChosen
--					resultPanel:FireEvent('create')
--					resultPanel:FireEvent('change')
--				end
--			end,
--		}
--
--		children[#children+1] = dropdown

			element.children = children
		end,
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end

function CharacterFeatureList:CreateEditor(class, params)
	local subpanel = ClassLevel.CreateEditor(self, class, -1, params)

	return subpanel
end

mod.shared.StartingEquipmentEditor = function(options)

	local RefreshChildren

	local resultPanel

	--featureInfo is e.g. a class or a background.
	local featureInfo = options.featureInfo
	options.featureInfo = nil

	--startingEquipment : { { options : { { items : { { itemid : string, quantity : number } } } } } }
	local startingEquipment = featureInfo:try_get("startingEquipment", {})

	local Change = function()
		featureInfo.startingEquipment = startingEquipment
		resultPanel:FireEvent("change")
		RefreshChildren()
	end
	
	local itemOptions = {}

	local inventoryTable = dmhub.GetTable("tbl_Gear")
	for k,item in pairs(inventoryTable) do
		if (not item:try_get("hidden", false)) and (not EquipmentCategory.IsTreasure(item)) and (not EquipmentCategory.IsMagical(item)) then
			itemOptions[#itemOptions+1] = {
				id = k,
				text = item.name,
			}
		end
	end

	local equipmentCategoriesTable = dmhub.GetTable(EquipmentCategory.tableName)
	for k,item in pairs(equipmentCategoriesTable) do
		itemOptions[#itemOptions+1] = {
			id = k,
			text = string.format("%s (Category)", item.name),
		}
	end

	local currencyTable = dmhub.GetTable(Currency.tableName)
	for k,item in pairs(currencyTable) do
		itemOptions[#itemOptions+1] = {
			id = k,
			text = string.format("%s (Currency)", item.name)
		}
	end

	table.sort(itemOptions, function(a, b) return a.text < b.text end)

	itemOptions[#itemOptions+1] = {
		id = "add",
		text = "Add Item...",
	}
	
	RefreshChildren = function()
		local children = {}

		for i,equipmentEntry in ipairs(startingEquipment) do

			local entryChildren = {
				gui.Label{
					fontSize = 22,
					underline = true,
					text = string.format(tr("Starting Equipment %d"), i),
					bold = true,
					halign = "left",
					width = "auto",
					height = "auto",

					gui.DeleteItemButton{
						floating = true,
						x = 32,
						width = 16,
						height = 16,
						valign = "top",
						halign = "right",
                        requireConfirm = true,
						click = function(element)
							table.remove(startingEquipment, i)
							Change()
						end,
					},

				}
			}
			for j,option in ipairs(equipmentEntry.options) do
				if #equipmentEntry.options > 1 then
					entryChildren[#entryChildren+1] = gui.Label{
						fontSize = 18,
						text = string.format(tr("Option %d"), j),
						halign = "left",
						width = "auto",
						height = "auto",

						gui.DeleteItemButton{
							floating = true,
							x = 16,
							width = 16,
							height = 16,
							valign = "top",
							halign = "right",
                            requireConfirm = true,
							click = function(element)
								table.remove(equipmentEntry.options, j)
								Change()
							end,
						},
					}
				end

				for itemIndex,itemEntry in ipairs(option.items) do
					entryChildren[#entryChildren+1] = gui.Panel{
						x = 32,
						flow = "horizontal",
						width = "100%",
						height = 32,
						gui.Label{
							fontSize = 16,
							halign = "left",
							valign = "center",
							width = 200,
							height = "auto",
							text = (inventoryTable[itemEntry.itemid] or equipmentCategoriesTable[itemEntry.itemid] or currencyTable[itemEntry.itemid]).name,
						},
						gui.Input{
							fontSize = 16,
							width = 60,
							height = 20,
							valign = "center",
							text = tostring(itemEntry.quantity),
							change = function(element)
								local n = tonumber(element.text)
								if n ~= nil then
									if n <= 0 then
										table.remove(option.items, itemIndex)
									else
										itemEntry.quantity = n
									end
								end
								Change()
							end,
						}
					}
				end

				
				entryChildren[#entryChildren+1] = gui.Dropdown{
					options = itemOptions,
					idChosen = "add",
					hasSearch = true,
					vmargin = 8,
					x = 32,
					change = function(element)
						if element.idChosen ~= "add" then
							option.items[#option.items+1] = {
								guid = dmhub.GenerateGuid(),
								itemid = element.idChosen,
								quantity = 1,
							}
						end

						Change()
					end,
				}

			end

			entryChildren[#entryChildren+1] = gui.Button{
				fontSize = 18,
				vmargin = 8,
				text = "Add Option",
				click = function(element)
					equipmentEntry.options[#equipmentEntry.options+1] = {
						guid = dmhub.GenerateGuid(),
						items = {},
					}
					Change()
				end,
			}

			local entryPanel = gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				vmargin = 16,
				children = entryChildren,
			}

			children[#children+1] = entryPanel

		end

		children[#children+1] = gui.Button{
			fontSize = 18,
			text = "Add Equipment",
			click = function(element)
				startingEquipment[#startingEquipment+1] = {
					guid = dmhub.GenerateGuid(),
					options = {
						{
							guid = dmhub.GenerateGuid(),
							items = {},
						}
					}
				}
				Change()
			end,
		}

		resultPanel.children = children
	end

	local args = {
		vmargin = 8,
		bgimage = "panels/clear.png",
		borderWidth = 2,
		borderColor = Styles.color,
		pad = 8,
		width = 400,
		height = "auto",
		flow = "vertical",
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Panel(args)
	RefreshChildren()
	return resultPanel
end
local mod = dmhub.GetModLoading()

local g_registeredCharacterChoices = {}

function CharacterChoice.RegisterChoice(options)
    g_registeredCharacterChoices[options.id] = options
end

local g_validFeatureTypes = {
	CharacterFeature = true,
	CharacterFeatureChoice = true,
	CharacterFeatChoice = true,
	CharacterSingleFeat = true,
	CharacterFeatureList = true,
	CharacterSubclassChoice = true,
	CharacterAncestryInheritanceChoice = true,
	CharacterSkillChoice = true,
}

local IsCharacterFeatureType = function(item)
	return item ~= nil and g_validFeatureTypes[item.typeName] == true
end

-- Class/ancestry editor search filter. The shared Search.MatchesObject caps its
-- recursive walk at depth 6, but feature NAMES in deeply-nested structures (a
-- level's "Domain Feature" choice -> a domain list -> the feature) land at depth
-- 7. That made deep features (Censor "Blessing of Iron", elementalist wards)
-- fail this filter and get hidden entirely. This is a private, editor-only copy
-- of that matcher with a deeper cap so those features match. It is the SAME
-- algorithm as Search.MatchesObject (verbatim needle, lowered haystack, the same
-- multi-term AND split), only with a higher depth limit -- so every match the
-- old filter found is still found, plus the deep ones. The shared
-- Search.MatchesObject is deliberately NOT changed, so no other consumer (the
-- compendium-browser list filter, language picker, ...) shifts behaviour or pays
-- the extra walk cost. Cap 10 covers the deepest real nesting (7) with headroom
-- (a choice inside a domain feature would be 9); names never sit deeper.
local FEATURE_SEARCH_DEPTH = 10

local function MatchesFeatureNeedleSingle(obj, needle, depth)
	depth = depth or 0
	if depth > FEATURE_SEARCH_DEPTH then
		return false
	end
	if type(obj) == "table" then
		for k,v in pairs(obj) do
			if MatchesFeatureNeedleSingle(k, needle, depth+1) or MatchesFeatureNeedleSingle(v, needle, depth+1) then
				return true
			end
		end
	elseif type(obj) == "string" then
		if string.find(string.lower(obj), needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- Drop-in replacement for the old MatchesSearchRecursive(obj, search) calls in
-- this editor.
-- Mirrors Search.MatchesObject's contract exactly (needle used verbatim, terms
-- AND-matched) so it is a strict superset of the previous behaviour.
local function MatchesFeatureSearch(obj, search)
	local terms = Search.SplitTerms(search)
	if terms == nil then
		return MatchesFeatureNeedleSingle(obj, search, 0)
	end
	for _,term in ipairs(terms) do
		if not MatchesFeatureNeedleSingle(obj, term, 0) then
			return false
		end
	end
	return true
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
            classes = {cond(feature:try_get("importOverride", false), "accent", ""), "sizeM", "bold"},
            text = cond(feature:try_get("importOverride", false), "Overwrite", "Imported"),
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
		width = "70%",
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
            if MatchesFeatureSearch(feature, text) then
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
            classes = {cond(feature:try_get("imported", false), cond(feature:try_get("importOverride", false), "accent", "")), "sizeL"},
			valign = "center",
			halign = "left",
			width = 340,
			textWrap = true,
			height = "auto",

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

				if IsCharacterFeatureType(clipboardItem) then

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

		gui.Button{
			classes = {"settingsButton", "sizeXs"},
			halign = "right",
			valign = "center",
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

		gui.Button{
			classes = {"deleteButton", "sizeXs"},
			halign = "right",
			valign = "center",
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
    local nested = options.nested
    options.nested = nil
	if points then
		pointsCostPanel = gui.Input{
			width = 60,
			height = 20,
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
	local m_lastSearch = ""

	local children = {}
	--some kind of choice.

	local tri = gui.ExpandoArrow{
		floating = true,
		halign = "left",
		valign = "center",
		x = 2,
	}

	local body

	local nameLabel = gui.Label{
            classes = {cond(feature:try_get("imported", false), cond(feature:try_get("importOverride", false), "accent", "")), "sizeL", "bold"},
			width = 320,
			lmargin = 20,
			height = "auto",
			halign = "left",
			valign = "center",
			textWrap = true,
            textAlignment = "left",
			text = feature:Describe(),
		}

    local importedLabel = nil
    if feature:try_get("imported", false) then
        importedLabel = gui.Label{
            classes = {cond(feature:try_get("importOverride", false), "accent", ""), "sizeM", "bold"},
            text = cond(feature:try_get("importOverride", false), "Overwrite", "Imported"),
            halign = "right",
            valign = "center",
            width = 100,
            height = "auto",
        }
    end

	children[#children+1] = gui.Panel{
		classes = {"featureCardHeader"},
		tri,
		nameLabel,
        pointsCostPanel,
        importedLabel,

		gui.Button{
			classes = {"deleteButton", "sizeXs"},
			halign = "right",
			valign = "center",
			hmargin = 8,
            requireConfirm = true,
			click = function(element)
				resultPanel:FireEvent("delete")
			end,
		},

		click = function(element)
			if body:HasClass('collapsed-anim') and body.data ~= nil and body.data.EnsureBuilt ~= nil then
				--expanding: build the deferred body now.
				body.data.EnsureBuilt()
			end
			body:SetClass('collapsed-anim', not body:HasClass('collapsed-anim'))
			tri:SetClass("expanded", not tri:HasClass("expanded"))
			element:SetClass("expanded", tri:HasClass("expanded"))
		end,

		rightClick = function(element)

			local clipboardItem = dmhub.GetInternalClipboard()
			if clipboardItem ~= nil then
				clipboardItem.guid = dmhub.GenerateGuid()
			end

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

			if IsCharacterFeatureType(clipboardItem) then

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

			element.popup = gui.ContextMenu{
				entries = entries
			}
		end,
	}

	-- The body's sub-editors are constructed by builder functions invoked from
	-- BuildChoiceBody (lazily, on first expansion). Constructing them eagerly
	-- here would orphan them when the body never builds: the engine warns about
	-- (and never garbage-collects) panels created but not attached to a parent.
	local BuildTagEditor = nil
	if feature.typeName == "CharacterFeatChoice" then

        BuildTagEditor = function()
            local tagOptions = (function()
                local tags = { feat = true }
                local featsTable = dmhub.GetTable(CharacterFeat.tableName) or {}
                for _,feat in pairs(featsTable) do
                    if not feat:try_get("hidden", false) then
                        for _,tag in ipairs(feat:Tags()) do
                            tags[string.lower(tag)] = true
                        end
                    end
                end
                local result = {}
                for k,_ in pairs(tags) do
                    result[#result+1] = { id = k, text = k }
                end
                table.sort(result, function(a,b) return a.text < b.text end)
                return result
            end)()

            local tagValue = (function()
                local v = {}
                for _,tag in ipairs(feature:Tags()) do
                    v[string.lower(tag)] = true
                end
                return v
            end)()

            return gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Tags:",
                },
                gui.Multiselect{
                    classes = {"formStacked"},
                    addItemText = "Add Tag...",
                    options = tagOptions,
                    value = tagValue,
                    change = function(element, value)
                        local newTags = {}
                        for tag,_ in pairs(value) do
                            newTags[#newTags+1] = tag
                        end
                        table.sort(newTags)
                        feature.tag = string.join(newTags, ",")
                        resultPanel:FireEvent("change")
                    end,
                },
            }
        end

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
					classes = {"form"},
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
	local BuildPrerequisitesEditor = nil
	if feature.typeName == "CharacterFeatureList" then
		BuildPrerequisitesEditor = function()
			local dropdown = gui.Dropdown{
				height = 30,
				width = 220,
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

			return prerequisitesEditor
		end
	end

	local BuildRulesTextEditor = nil

	if feature:try_get("rulesText") ~= nil then
		BuildRulesTextEditor = function()
			return gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					text = "Rules Text:",
					classes = {"form"},
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
	end


	if body == nil then
		-- Lazy body build: defer creating the body's editor panels (including the
		-- recursive feature/choice editor subtree) until first expansion. See the
		-- matching comment in ClassLevel:CreateEditor -- the engine pays a large
		-- per-panel layout cost inside vscroll containers, and collapsed bodies
		-- are most of the class editor's panel count.
		local BuildChoiceBody

		body = gui.Panel{
			classes = {"featureCardBody", "collapsed-anim"},
			data = {},

			create = function(element)
				if element:HasClass("collapsed-anim") then
					element.data.pendingBuild = true
					return
				end
				element.data.pendingBuild = false
				BuildChoiceBody(element)
				-- See ClassLevel:CreateEditor's create: re-apply any filter that
				-- was broadcast before this deferred build ran.
				if m_lastSearch ~= "" then
					element:FireEventTree("searchCompendium", m_lastSearch)
				end
			end,
		}

		body.data.EnsureBuilt = function(searchText)
			if not body.data.pendingBuild then
				return false
			end
			body.data.pendingBuild = false
			BuildChoiceBody(body)
			local s = searchText or m_lastSearch
			if s ~= nil and s ~= "" then
				body:FireEventTree("searchCompendium", s)
			end
			return true
		end

		BuildChoiceBody = function(element)
			local bodyChildren = {}

			bodyChildren[#bodyChildren+1] = gui.Panel{
				classes = {"formStackedRow"},
				gui.Label{
					classes = {"formStacked"},
					text = "Name:",
				},
				gui.Input{
					classes = {"formStacked"},
					text = feature.name,
					change = function(element)
						feature.name = element.text
						resultPanel:FireEvent("change")
						nameLabel.text = feature:Describe()
					end,
				}
			}

			if BuildPrerequisitesEditor ~= nil then
				bodyChildren[#bodyChildren+1] = BuildPrerequisitesEditor()
			end
			if BuildTagEditor ~= nil then
				bodyChildren[#bodyChildren+1] = BuildTagEditor()
			end
			if BuildRulesTextEditor ~= nil then
				bodyChildren[#bodyChildren+1] = BuildRulesTextEditor()
			end

			bodyChildren[#bodyChildren+1] = gui.Panel{
				classes = {"formStackedRow"},
				gui.Label{
					classes = {"formStacked"},
					text = "Description:",
				},
				gui.Input{
					classes = {"formStacked"},
					multiline = true,
					height = 'auto',
					minHeight = 30,
					placeholderText = "Enter prompt text...",
					text = feature.description,
					characterLimit = 2000,

					change = function(element)
						feature.description = element.text
						resultPanel:FireEvent("change")
					end,
				},
			}

			bodyChildren[#bodyChildren+1] = feature:CreateEditor(classOrRace, {
				change = function(element)
					resultPanel:FireEvent("change")
				end
			})

			element.children = bodyChildren
		end
	end

	children[#children+1] = body

	local args = {
        classes = nested and {"featureCard", "featureCardNested", "hideOnSearchMismatch"} or {"featureCard", "hideOnSearchMismatch"},
		height = "auto",
		children = children,

        searchCompendium = function(element, text)
            m_lastSearch = text or ""
            if text == "" then
                element:SetClassTree("searching", false)
                element:SetClassTree("matchSearch", false)
                return
            end

            element:SetClassTree("searching", true)
            if MatchesFeatureSearch(feature, text) then
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
	local m_lastSearch = ""
	local BuildBody

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
		flow = "vertical",

		-- No per-level styles: re-declaring the full theme stylesheet on every
		-- level editor costs ~265ms/14-panels vs ~4ms inheriting the class-editor
		-- root's cascade. (The dominant class-open cost was panel volume under
		-- vscroll, addressed by the lazy body build below -- but keep inheriting.)
		-- CALLER CONTRACT: this editor carries no theme of its own, so whatever
		-- host mounts it MUST own the theme cascade (via ThemeEngine.MergeStyles).
		-- Every current caller does -- Class.CreateEditor, RaceEditor, and the
		-- compendium library-panel that hosts the Feat / GlobalRuleMod / Career /
		-- Title / etc. editors. A new standalone host must add the cascade too,
		-- or the editor will render unstyled.

		data = {},

		paste = function(element, item, index)
			item = DeepCopy(item)
			item:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
			item:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
			table.insert(self.features, index, item)
			element:FireEvent("change")
			element:FireEvent("create")
		end,

		-- Track the active compendium filter so a lazily-built body can apply it
		-- to its freshly created children (they were not mounted when the filter
		-- was broadcast across the tree).
		searchCompendium = function(element, text)
			m_lastSearch = text or ""
		end,

		-- Lazy body build: when this editor is a collapsed level body, defer
		-- building its feature cards until first expansion. The engine pays a
		-- large constant layout cost PER PANEL inside a vscroll container
		-- (measured ~3ms/panel, ~40x the cost outside vscroll), and ~98% of the
		-- class editor's panels live inside collapsed bodies the user may never
		-- open. Building them upfront froze the UI ~20s for a large class.
		create = function(element)
			if element:HasClass("collapsed-anim") then
				element.data.pendingBuild = true
				return
			end
			element.data.pendingBuild = false
			BuildBody(element)
			-- A search broadcast may already have expanded this body before
			-- create fired (create runs at end of frame, after SetClass fires
			-- searchCompendium). Re-apply it so the new children filter.
			if m_lastSearch ~= "" then
				element:FireEventTree("searchCompendium", m_lastSearch)
			end
		end,
	}

	-- Builds the body now if it was deferred. Returns true if it built.
	-- searchText (optional) is applied to the new children; falls back to the
	-- last broadcast filter.
	args.data.EnsureBuilt = function(searchText)
		if resultPanel == nil or not resultPanel.data.pendingBuild then
			return false
		end
		resultPanel.data.pendingBuild = false
		BuildBody(resultPanel)
		local s = searchText or m_lastSearch
		if s ~= nil and s ~= "" then
			resultPanel:FireEventTree("searchCompendium", s)
		end
		return true
	end

	BuildBody = function(element)
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
                    if not IsCharacterFeatureType(clipboardItem) then
                        return "Paste"
                    end
                    return "Paste " .. clipboardItem.name
                end,
                hidden = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    return not IsCharacterFeatureType(clipboardItem)
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

				idChosen = "none",
				options = featureOptions,

				width = 340,
				height = 30,

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
	end

	for k,v in pairs(params) do
		args[k] = v
	end
	resultPanel = gui.Panel(args)

	return resultPanel
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMClass.lua:312
function Class:CustomEditor(UploadFn, panels)
end
--]==]

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
		classes = {"portraitImage"},
		value = class.portraitid,
		library = "Avatar",
		autosizeimage = true,
		allowPaste = true,
		change = function(element)
			class.portraitid = element.value
			UploadClass()
		end,
		},

		gui.Label{
			classes = {"sizeXs"},
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
		},
	}

	--the name of the class.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
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
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Primary Class:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				options = options,
				idChosen = class.primaryClassId,
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
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Description:",
		},
		gui.Input{
			classes = {"formStacked"},
			multiline = true,
			height = "auto",
			minHeight = 30,
			maxHeight = 300,
			vscroll = true,
			textAlignment = "topleft",
			characterLimit = 4000,
			text = class.details,
			change = function(element)
				class.details = element.text
				UploadClass()
			end,
		}
	}

	class:CustomEditor(UploadClass, children)

    children[#children+1] = gui.Label{
        classes = {"sizeXl", "bold"},
        width = "auto",
        height = "auto",
        text = "Tutorial",
    }

	Class.CreateLevelEditor(children, class, UploadClass, 1, 4, "tutorial")


    children[#children+1] = gui.Label{
        classes = {"sizeXl", "bold"},
        width = "auto",
        height = "auto",
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

		local tri = gui.ExpandoArrow{
			floating = true,
			halign = "left",
			valign = "center",
			x = 2,
		}

		local classLevel = class:GetLevel(i, subkey)

		local summaryLabel = gui.Label{
			classes = {"sizeL"},
			halign = "left",
			valign = "center",
			width = "auto",
			height = "auto",
			text = cond(#classLevel.features > 0, string.format("(%d %s)", #classLevel.features, cond(#classLevel.features > 1, "features", "feature")), ""),
			update = function(element)
				element.text = cond(#classLevel.features > 0, string.format("(%d %s)", #classLevel.features, cond(#classLevel.features > 1, "features", "feature")), "")
			end,
		}

		local editorPanel = classLevel:CreateEditor(class, i, {
			classes = {"featureCardBody", "collapsed-anim"},
			change = function(element)
				class:ForceDomains()
				UploadClass()
				summaryLabel:FireEvent("update")
			end,
		})

		local header = gui.Panel{
			classes = {"featureCardHeader"},
			tri,
			gui.Label{
				classes = {"searchableLabel", "sizeL", "bold"},
				lmargin = 20,
				hmargin = 8,
				halign = "left",
				valign = "center",
				width = "auto",
				height = "auto",
				text = text,
			},

			summaryLabel,

			click = function(element)
				if editorPanel:HasClass("collapsed-anim") then
					--expanding: build the deferred body now.
					editorPanel.data.EnsureBuilt()
				end
				editorPanel:SetClass("collapsed-anim", not editorPanel:HasClass("collapsed-anim"))
				tri:SetClass("expanded", not editorPanel:HasClass("collapsed-anim"))
				element:SetClass("expanded", tri:HasClass("expanded"))
			end,

			searchCompendium = function(element, text)
				if text == "" then
					element:SetClassTree("searching", false)
					element:SetClassTree("matchSearch", false)
					return
				end

				element:SetClassTree("searching", true)
				if MatchesFeatureSearch(classLevel, text) then
					element:SetClassTree("matchSearch", true)
				else
					element:SetClassTree("matchSearch", false)
				end
			end,
		}

		local panel = gui.Panel{
			classes = {"featureCard", "hideOnSearchMismatch"},
			height = "auto",
			width = 1100,
			halign = "left",

			-- Collapse the whole level card when no feature in this level matches
			-- the filter. SetClass (element-only, NOT SetClassTree) so a matching
			-- level does not force-show its non-matching inner feature cards --
			-- those keep collapsing individually via their own handler. A matching
			-- level also auto-expands its body so the matched feature is actually
			-- visible (the body is collapsed by default); clearing the filter
			-- restores the default collapsed state.
			searchCompendium = function(element, text)
				if text == "" then
					element:SetClass("searching", false)
					element:SetClass("matchSearch", false)
					editorPanel:SetClass("collapsed-anim", true)
					tri:SetClass("expanded", false)
					header:SetClass("expanded", false)
					return
				end

				element:SetClass("searching", true)
				local matched = MatchesFeatureSearch(classLevel, text)
				element:SetClass("matchSearch", matched)
				if matched then
					--auto-expanding to show the match: build the deferred body.
					editorPanel.data.EnsureBuilt(text)
				end
				editorPanel:SetClass("collapsed-anim", not matched)
				tri:SetClass("expanded", matched)
				header:SetClass("expanded", matched)
			end,

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
		-- The class-editor root owns the theme cascade ONCE; all descendant
		-- level/feature editors inherit it instead of each re-declaring the full
		-- stylesheet. In the compendium the library-panel host already provides
		-- the cascade, but merging it here keeps the editor self-sufficient in any
		-- standalone host without re-introducing the per-panel cost.
		styles = ThemeEngine.MergeStyles({
			{
				classes = {"class-panel"},
				width = "100%-160",
				height = "90%",
				maxWidth = 1200,
				halign = "left",
				flow = "vertical",
				pad = 20,
			},
		}),
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
			item = DeepCopy(item)
			item:VisitRecursive(function(a) a.source = classOrRace:FeatureSourceName() end)
			item:VisitRecursive(function(a) a.guid = dmhub.GenerateGuid() end)
			table.insert(self.options, index, item)
			resultPanel:FireEvent('create')
			resultPanel:FireEvent('change')
		end,

		create = function(element)
			local children = {}

			children[#children+1] = gui.Panel{
				classes = {"formStackedRow"},
				gui.Label{
					classes = {"formStacked"},
					text = "Choices:",
				},
				gui.GoblinScriptInput{
					classes = {"formStacked"},
					value = self.numChoices,
					multiline = false,
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
				classes = {cond(tonumber(self.numChoices) ~= 1, nil, "collapsed")},
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
                            classes = {"danger"},
                            text = "Inheriting choices from an invalid reference.",
                        }
                    else
                        label = gui.Label{
                            classes = {"success"},
                            text = string.format("Inheriting choices from: %s", resolved.name),
                        }
                    end

                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        label,
                        gui.Button{
                            classes = {"deleteButton", "sizeXs"},
                            floating = true,
                            halign = "right",
                            valign = "center",
                            x = 16,
                            requireConfirm = true,
                            click = function(element)
                                table.remove(self.inheritChoice, i)
                                resultPanel:FireEvent("create")
                                resultPanel:FireEvent("change")
                            end,
                        },
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

			children[#children+1] = gui.Panel{
				classes = {"formStackedRow", cond(tonumber(self.numChoices) ~= 1 and self.costsPoints, nil, "collapsed")},
				gui.Label{
					classes = {"formStacked"},
					text = "Points name:",
				},
				gui.Input{
					classes = {"formStacked"},
					characterLimit = 32,
					placeholderText = "Enter name of points...",
					text = self.pointsName,
					change = function(element)
						self.pointsName = element.text
						resultPanel:FireEvent('change')
					end,
				},
			}

			for i,feature in ipairs(self.options) do
				local index = i
				if feature.typeName == 'CharacterFeature' then
					children[#children+1] = CreateFeatureSummary(feature, self.options, index, resultPanel, nil, {points = self.costsPoints})
				else
					children[#children+1] = CreateChoiceEditor(feature, self.options, index, resultPanel, classOrRace, {
                        points = self.costsPoints,
                        nested = true,
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
                    if not IsCharacterFeatureType(clipboardItem) then
                        return "Paste"
                    end
                    return "Paste " .. clipboardItem.name
                end,
                hidden = function()
			        local clipboardItem = dmhub.GetInternalClipboard()
                    return not IsCharacterFeatureType(clipboardItem)
                end,
			}

			CharacterFeaturePrefabs.FillDropdownOptions(featureOptions)


			children[#children+1] = gui.Panel{
				classes = {"formStackedRow"},
				tmargin = 12,
				gui.Dropdown{
					classes = {"formStacked"},

					idChosen = 'none',
					options = featureOptions,

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
				},
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
					local rowClass = (#children % 2 == 0) and "evenRow" or "oddRow"
					children[#children+1] = gui.Panel{
						classes = {"row", rowClass},
						width = "100%",
						height = 20,

						gui.Label{
							classes = {"sizeM"},
							text = subclass.name,
							height = "auto",
							width = "auto",
							minWidth = 200,
							valign = "center",
						},
					}
				end
			end

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
					classes = {"sizeXl", "bold", "underline"},
					text = string.format(tr("Starting Equipment %d"), i),
					halign = "left",
					width = "auto",
					height = "auto",

					gui.Button{
						classes = {"deleteButton", "sizeXs"},
						floating = true,
						x = 32,
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
						classes = {"sizeL"},
						text = string.format(tr("Option %d"), j),
						halign = "left",
						width = "auto",
						height = "auto",

						gui.Button{
							classes = {"deleteButton", "sizeXs"},
							floating = true,
							x = 16,
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
							classes = {"sizeM"},
							halign = "left",
							valign = "center",
							width = 200,
							height = "auto",
							text = (inventoryTable[itemEntry.itemid] or equipmentCategoriesTable[itemEntry.itemid] or currencyTable[itemEntry.itemid]).name,
						},
						gui.Input{
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
						},
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
				classes = {"sizeS"},
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
			classes = {"sizeS"},
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

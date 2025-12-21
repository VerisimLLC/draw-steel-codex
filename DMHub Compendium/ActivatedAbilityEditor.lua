local mod = dmhub.GetModLoading()


function CreateAbilityTooltip(spell, options)
	return CreateCompendiumItemTooltip(spell, options)
end

function CreateCompendiumItemTooltip(spell, options)
    if type(spell) ~= "table" or getmetatable(spell) == nil then
        return nil
    end

	if spell:try_get("notooltip") == true then
		return nil
	end

	--some heuristics to grow the width if we are rendering a very long spell
	local width = options.width or (400 + math.floor(#spell.description/1000)*100)

	local result = spell:Render({
		pad = 0,
		cornerRadius = 0,
		bgimage = 'panels/square.png',
		bgcolor = '#000000fb',
		borderWidth = 0,
		borderFade = false,
        blurBackground = true,
		width = width,
        opacity = 1,
	}, options)

	if result == nil then
		return result
	end

	if options.halign ~= nil then
		result.selfStyle.halign = options.halign
	end

	if options.valign ~= nil then
		result.selfStyle.valign = options.valign
	end

	return result
end


--This implements the editor pages for activated abilities.
ActivatedAbility.CatHelpSymbols = function(a,b)
	local res = DeepCopy(a)
	for k,v in pairs(b) do
		res[k] = v
	end

	return res
end

function ActivatedAbility:GenerateEditor()

	local resourceOptions = {}
	local resultPanel

	local resourceTable = dmhub.GetTable("characterResources")
	for k,resource in pairs(resourceTable) do
		if resource.grouping ~= "Actions" and not resource:try_get("hidden", false) then
			resourceOptions[#resourceOptions+1] = {
				id = k,
				text = resource.name,
			}
		end
	end

	table.sort(resourceOptions, function(a,b) return a.text < b.text end)
	table.insert(resourceOptions, 1, {
		id = "none",
		text = "None",
	})

	local spellGuidField = nil
	if devmode() then
		spellGuidField = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "GUID:",
			},
			gui.Input{
				classes = "formInput",
				text = self.guid,
				editable = false,
			},
		}
	end

	local attrPanel = nil

	if self.typeName ~= 'Spell' and GameSystem.abilitiesHaveAttribute then
		local options = {
			{
				id = "no_attribute",
				text = "None",
			},
			{
				id = "none",
				text = "Spellcasting Modifier",
			},
			{
				id = "multiple",
				text = "Multiple (use highest)",
			},
		}

		for i,attrid in ipairs(creature.attributeIds) do
			options[#options+1] = {
				id = attrid,
				text = creature.attributesInfo[attrid].description,
			}
		end

		--the panel to tell which attribute to use for this ability, including support of multiple possible attributes.
		attrPanel = gui.Panel{
			id = {"attributesPanel"},
			classes = {"abilityInfo"},
			width = "auto",
			height = "auto",
			flow = "vertical",

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Attribute:",
				},

				gui.Dropdown{
					classes = "formDropdown",
					options = options,
					idChosen = self:try_get("attributeOverride", "none"),
					change = function(element)
						local val = element.idChosen
						if val == "none" then
							val = nil
						end

						if val ~= "multiple" then
							self.attributeOverrideMulti = nil
						elseif not self:has_key("attributeOverrideMulti") then
							self.attributeOverrideMulti = {"str"}
						end

						self.attributeOverride = val
						resultPanel:FireEventTree("refreshAbility")
					end,
				},
			},

			--If we have multiple possible attributes we can list them all here.
			gui.Panel{
				width = "auto",
				height = "auto",
				flow = "vertical",
				data = {
					numAttr = -1,
				},
				create = function(element)
					element:FireEvent("refreshAbility")
				end,
				refreshAbility = function(element)
					local multiattr = self:try_get("attributeOverrideMulti", {})
					if element.data.numAttr == #multiattr then
						return
					end

					local children = {}

					element.data.numAttr = #multiattr

					for i,attr in ipairs(multiattr) do

						local options = {
							{
								id = "none",
								text = "(Remove)",
							},
						}
						for i,attrid in ipairs(creature.attributeIds) do
							options[#options+1] = {
								id = attrid,
								text = creature.attributesInfo[attrid].description,
							}
						end

						children[#children+1] = gui.Panel{
							classes = {"formPanel"},
							gui.Label{
								classes = "formLabel",
								text = "Attr. Choice:",
							},

							gui.Dropdown{
								classes = "formDropdown",
								options = options,
								idChosen = attr,
								change = function(element)
									local val = element.idChosen
									if val == "none" then
										table.remove(self.attributeOverrideMulti, i)
									else
										self.attributeOverrideMulti[i] = val
									end
									resultPanel:FireEventTree("refreshAbility")
								end,
							},
						}
						
					end

					if self:try_get("attributeOverride") == "multiple" then

						local options = {
							{
								id = "none",
								text = "Add Attribute...",
							},
						}
						for i,attrid in ipairs(creature.attributeIds) do
							options[#options+1] = {
								id = attrid,
								text = creature.attributesInfo[attrid].description,
							}
						end

						children[#children+1] = gui.Panel{
							classes = {"formPanel"},
							gui.Label{
								classes = "formLabel",
								text = "Attr. Choice:",
							},

							gui.Dropdown{
								classes = "formDropdown",
								options = options,
								idChosen = "none",
								change = function(element)
									local val = element.idChosen
									if val == "none" then
										return
									else
										local multi = self:get_or_add("attributeOverrideMulti", {})
										multi[#multi+1] = val
									end
									resultPanel:FireEventTree("refreshAbility")
								end,
							},
						}
					end

					element.children = children
				end,
			},
		}
	end

	local ActionIsReaction = function()
		local resourceid = self:ActionResource() or "none"
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil then
			return resourceInfo.isreaction
		end

		return false
	end

	local ActionHasQuantity = function()
		local resourceid = self:ActionResource() or "none"
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil then
			return resourceInfo.useQuantity
		end

		return false
	end

	local ResourceHasQuantity = function()
		local resourceid = self.resourceCost
		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil then
			return resourceInfo.useQuantity
		end

		return false
	end

	local castEffectOptions = {
		{
			id = "none",
			text = "(None)",
		},
	}

	for k,emoji in pairs(assets.emojiTable) do
		if emoji.emojiType == "Spellcasting" then
			castEffectOptions[#castEffectOptions+1] = {
				id = emoji.description,
				text = emoji.description,
			}
		end
	end

	local categorizationPanel = nil
	if GameSystem.hasAbilityCategorization then
		local options = {}
		for category,_ in pairs(GameSystem.abilityCategories) do
			options[#options+1] = {
				id = category,
				text = category,
			}
		end
		categorizationPanel = gui.Panel{
			classes = {"abilityInfo", "formPanel"},
			gui.Label{
				classes = "formLabel",
				text = "Category:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				idChosen = self.categorization,
				options = options,
				sort = true,
				change = function(element)
					self.categorization = element.idChosen
					resultPanel:FireEventTree("refreshAbility")
				end,
			},
		}
	end

    local villainActionPanel = gui.Panel{
        classes = {"formPanel", cond(self:try_get("categorization") == "Villain Action", nil, "collapsed-anim")},
        refreshAbility = function(element)
            element:SetClass("collapsed-anim", self:try_get("categorization") ~= "Villain Action")
        end,
        gui.Label{
            classes = "formLabel",
            text = "Villain Action:",
        },
        gui.Dropdown{
            classes = "formDropdown",
            idChosen = self:try_get("villainAction", "none"),
            options = {
                {
                    id = "none",
                    text = "None",
                },
                {
                    id = "Villain Action 1",
                    text = "Villain Action 1",
                },
                {
                    id = "Villain Action 2",
                    text = "Villain Action 2",
                },
                {
                    id = "Villain Action 3",
                    text = "Villain Action 3",
                },
            },
            change = function(element)
                self.villainAction = element.idChosen
                resultPanel:FireEventTree("refreshAbility")
            end,
        },
    }

    local m_source = self:try_get("sourceReference")
    if m_source == nil then
        m_source = SourceReference.new{}
    end

	local keywordsPanel = nil
	if GameSystem.hasAbilityKeywords then

		local addDropdown = gui.Dropdown{
			classes = "formDropdown",
			sort = true,
			textOverride = "Add Keyword...",
            hasSearch = true,
			idChosen = "none",
			create = function(element)
				local keywordOptions = {}

				for keyword,_ in pairs(GameSystem.abilityKeywords) do
					if not self.keywords[keyword] then
						keywordOptions[#keywordOptions+1] = {
							id = keyword,
							text = keyword,
						}
					end
				end
				element.options = keywordOptions
				element:SetClass("collapsed", #keywordOptions == 0)
			end,
			refreshKeywords = function(element)
				element:FireEvent("create")
			end,
			change = function(element)
				if element.idChosen ~= "none" then
					self:AddKeyword(element.idChosen)
				end

				resultPanel:FireEventTree("refreshKeywords")
			end,
		}

		keywordsPanel = gui.Panel{
			flow = "vertical",
			width = "auto",
			height = "auto",

			addDropdown,

			create = function(element)
				local children = {}

				for keyword,_ in pairs(self.keywords) do
					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
						data = {
							ord = keyword,
						},
						gui.Label{
							classes = "formLabel",
							text = keyword,
						},
						gui.DeleteItemButton{
							halign = "right",
							width = 16,
							height = 16,
							click = function(element)
								self:RemoveKeyword(keyword)
								resultPanel:FireEventTree("refreshKeywords")
							end,
						},
					}
				end

				table.sort(children, function(a,b) return a.data.ord < b.data.ord end)
	
				children[#children+1] = addDropdown
				element.children = children
			end,

			refreshKeywords = function(element)
				element:FireEvent("create")
			end,
		}
	end

    print("PROPERTIES: ", ActivatedAbility.registeredProperties)
    local propertyEditorPanel = gui.SetEditor{
        value = self:try_get("properties"),
        addItemText = "Add Special Property...",
        options = ActivatedAbility.registeredProperties,
        change = function(element, value)
            self.properties = value
        end,
    }

	resultPanel = gui.Panel{
		id = "abilityEditorPanel",
		classes = "abilityEditor",
		styles = {
			Styles.Form,

			{
				classes = {"formPanel"},
				width = 340,
			},
			{
				classes = {"formLabel"},
				halign = "left",
			},
			{
				classes = {"abilityEditor"},
				width = '100%',
				height = 'auto',
				flow = "horizontal",
				valign = "top",
			},
			{
				classes = "mainPanel",
				width = "40%",
				height = "auto",
				flow = "vertical",
				valign = "top",
			},

		},

		gui.Panel{
			id = "leftPanel",
			width = "50%",
			classes = "mainPanel",
			spellGuidField,

			gui.Panel{
				classes = {"abilityInfo", "formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Name:",
				},
				gui.Input{
					classes = "formInput",
					text = self.name,
					change = function(element)
						self.name = element.text
					end,
				},
			},

			categorizationPanel,
            villainActionPanel,

			gui.Panel{
				classes = {"abilityInfo", "formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Action:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					idChosen = self:ActionResource() or "none",
					options = CharacterResource.GetActionOptions(),
					change = function(element)
						self.actionResourceId = element.idChosen
						resultPanel:FireEventTree("refreshAbility")
					end,
				},
			},

			--reaction/trigger panel.
			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(not ActionIsReaction(), "collapsed-anim")},
				width = "100%",
				height = "auto",

				data = {
					init = false,
				},

				create = function(element)
					element:FireEvent("refreshAbility")
				end,

				refreshAbility = function(element)
					local isreaction = ActionIsReaction()
					element:SetClass("collapsed-anim", not isreaction)
					if not isreaction then
						return
					end

					if element.data.init == false then
						element.data.init = true

						element.children = {
							gui.Panel{
								classes = {"abilityInfo", "formPanel"},
								gui.Label{
									classes = "formLabel",
									text = "Reaction Trigger:",
								},
								gui.Dropdown{
									classes = "formDropdown",
									idChosen = self:GetReactionInfo().type,
									options = ActivatedAbilityReaction.types,
									change = function(element)
										self:GetOrAddReactionInfo().type = element.idChosen
										resultPanel:FireEventTree("refreshAbility")
									end,
								}
							}
						}
					end

					
				end,
			},

			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(not ActionHasQuantity(), "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", not ActionHasQuantity())
				end,

				gui.Label{
					classes = "formLabel",
					text = "Num. Actions:",
				},

				gui.GoblinScriptInput{
					classes = "formInput",
					value = tostring(self.actionNumber),
					width = 200,
					change = function(element)
						if type(element.value) == "string" and tonumber(element.value) ~= nil then
							self.actionNumber = tonumber(element.value)
							element.value = tostring(self.actionNumber)
						else
							self.actionNumber = element.value
						end
						resultPanel:FireEventTree("refreshAbility")
					end,


					documentation = {
						domains = self.domains,
						help = "This GoblinScript is used to determine how many actions an <color=#00FFFF><link=ability>ability</link></color> costs. It is typically a flat number, but sometimes you may want to calculate the number of actions based on a formula or table.",
						output = "number",
						examples = {
							{
								script = "1",
								text = "The ability costs 1 action to use.",
							},
							{
								script = "1 + 1 when level <= 5",
								text = "The ability costs 2 to use when the character's level is 5 or less, otherwise it only costs one action to use.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is using the ability.",
						symbols = {
							mode = ActivatedAbility.helpCasting.mode,
						},
					},
				},

			},

			keywordsPanel,

            propertyEditorPanel,

            gui.Check{
                classes = {cond(self:HasKeyword("Melee") and self:HasKeyword("Ranged"), nil, "collapsed-anim")},
                text = "Split into Melee and Ranged",
                value = not self.disableSplitIntoMeleeAndRanged,
                change = function(element)
                    self.disableSplitIntoMeleeAndRanged = not element.value
                    resultPanel:FireEventTree("refreshAbility")
                end,
                refreshKeywords = function(element)
                    element:SetClass("collapsed-anim", not self:HasKeyword("Melee") or not self:HasKeyword("Ranged"))
                end,
            },

			gui.Panel{
				classes = {"abilityInfo", "formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Resource Cost:",
				},

				gui.Dropdown{
					classes = "formDropdown",
					idChosen = self.resourceCost,
					options = resourceOptions,
					change = function(element)
						self.resourceCost = element.idChosen
						resultPanel:FireEventTree("refreshAbility")
					end,
				},

			},


			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(not ResourceHasQuantity(), "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", not ResourceHasQuantity())
				end,
				gui.Label{
					classes = "formLabel",
					text = "Num. Resources:",
				},

				gui.GoblinScriptInput{
					classes = "formInput",
					halign = "right",
					width = 240,
					value = self:try_get("resourceNumber", "1"),
					change = function(element)
						self.resourceNumber = element.value
						resultPanel:FireEventTree("refreshAbility")
					end,

					documentation = {
						domains = self.domains,
						help = "This GoblinScript is used to determine the resource cost of an Ability. It is typically a flat number, but sometimes you may want to calculate the cost based on a formula or table.",
						output = "number",
						examples = {
							{
								script = "3",
								text = "The ability cost 3 of the selected resource.",
							},
							{
								script = "Mode = 2 then 3 else 1",
								text = "If the Mode selected is 2, the ability costs 3 resources, otherwise it costs 1.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature using the ability.",
						symbols = {
							mode = {
								name = "Mode",
								type = "number",
								desc = "When using an ability that has multiple modes, this is the number of the mode the player chose when using the ability. You can set an ability up with modes on the ability's property page. Mode will be equal to 1 if the player chose the first mode, 2 for the second mode, and so forth. Mode is always 1 for abilities that don't have multiple modes.",
							},
						},
					},
				},

			},

			gui.Panel{
				classes = {"abilityInfo", "formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Channel Resource:",
				},

				gui.Dropdown{
					classes = "formDropdown",
					idChosen = self.channeledResource,
					options = resourceOptions,
					change = function(element)
						self.channeledResource = element.idChosen
						resultPanel:FireEventTree("refreshAbility")
					end,
				},
			},

			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(self.channeledResource == "none", "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", self.channeledResource == "none")
				end,
				gui.Label{
					classes = "formLabel",
					text = "Max Channel:",
				},

				gui.GoblinScriptInput{
					classes = "formInput",
					halign = "right",
					width = 240,
					value = self:try_get("maxChannel", ""),
					change = function(element)
						self.maxChannel = element.value
						resultPanel:FireEventTree("refreshAbility")
					end,

					documentation = {
						domains = self.domains,
						help = "This GoblinScript is used to determine the maximum amount of a resource that can be channeled. It is typically a flat number, but sometimes you may want to calculate the maximum amount based on a formula or table. You may leave it blank to have no limit.",
						output = "number",
						examples = {
							{
								script = "3",
								text = "A maximum of 3 resources can be channeled.",
							},
							{
								script = "Level",
								text = "A number of resources equal to your level can be channeled.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature using the ability.",
					},
				},
			},

			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(self.channeledResource == "none", "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", self.channeledResource == "none")
				end,
				gui.Label{
					classes = "formLabel",
					text = "Cost per Charge:",
				},

                gui.Input{
                    classes = "formInput",
                    text = self.channelIncrement,
                    characterLimit = 2,
                    change = function(element)
                        self.channelIncrement = tonumber(element.text)
                        element.text = self.channelIncrement
                    end,
                },
			},


			gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(self.channeledResource == "none", "collapsed")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", self.channeledResource == "none")
				end,
				gui.Label{
					classes = "formLabel",
					text = "Description:",
				},

				gui.Input{
					classes = "formInput",
					width = 240,
					characterLimit = 160,
					text = self.channelDescription,
					placeholderText = "Describe the channeling...",
					change = function(element)
						self.channelDescription = element.text
						resultPanel:FireEventTree("refreshAbility")
					end,

				},
			},

			attrPanel,


			self:BehaviorEditor(),
		},

		gui.Panel{
			id = "rightPanel",
			classes = "mainPanel",

			self:IconEditorPanel(),

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Flavor Text:",
				},
			},

			gui.Panel{
				classes = {"formPanel"},
				gui.Input{
					classes = "formInput",
					placeholderText = "Enter Flavor Text...",
					multiline = true,
					width = "100%",
					height = "auto",
					halign = "center",
					margin = 8,
					minHeight = 100,
					textAlignment = "topleft",
					text = self.flavor,
					change = function(element)
						self.flavor = element.text
					end,
				},
			},


			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Effect Before Power Roll:",
				},
			},

			gui.Panel{
				classes = {"formPanel"},
				gui.Input{
					classes = "formInput",
					placeholderText = "Enter Effect Details...",
					multiline = true,
					width = "80%",
					height = "auto",
					halign = "center",
					margin = 8,
					minHeight = 20,
					textAlignment = "topleft",
					text = self:try_get("preDescription", ""),
					change = function(element)
						self.preDescription = element.text
					end,
				},
			},

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = "formLabel",
					text = "Effect After Power Roll:",
				},
			},

			gui.Panel{
				classes = {"formPanel"},
				gui.Input{
					classes = "formInput",
					placeholderText = "Enter Effect Details...",
					multiline = true,
					width = "80%",
					height = "auto",
					halign = "center",
					margin = 8,
					minHeight = 100,
					textAlignment = "topleft",
					text = self.description,
					change = function(element)
						self.description = element.text
					end,
				},
			},

            gui.Panel{
                classes = {"formPanel"},
                create = function(element)
                    --element:SetClass("collapsed", self.effectImplemented)
                end,
                gui.Label{
                    classes = "formLabel",
                    text = "Implementation:",
                },
                gui.ImplementationStatusPanel{
                    value = self:try_get("implementation", 1),
                    change = function(element)
                        self.implementation = element.value
						resultPanel:FireEventTree("refreshImplementation")
                    end,
                },
            },

			gui.Panel{
				classes = {"formPanel", cond(self:try_get("implementation", 1) == 1, "collapsed-anim")},
				refreshAbility = function(element)
					element:SetClass("collapsed-anim", self:try_get("implementation", 1) == 1)
				end,
				refreshImplementation = function(element)
					element:SetClass("collapsed-anim", self:try_get("implementation", 1) == 1)
				end,
				gui.Input{
					classes = "formInput",
					placeholderText = "Enter Implementation Details...",
					multiline = true,
					width = "80%",
					height = "auto",
					halign = "center",
					margin = 8,
					minHeight = 60,
					textAlignment = "topleft",
					text =self:try_get("implementationDetails"),
					change = function(element)
						self.implementationDetails = element.text
					end,
				},
			},

            m_source:Editor{
                object = self,
                change = function(element)
                    self.sourceReference = m_source
                end,
            },

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Display Order:",
				},
				gui.Input{
					classes = "formInput",
					text = tostring(self.displayOrder),
					change = function(element)
						if tonumber(element.text) ~= nil then
							self.displayOrder = tonumber(element.text)
						end

						element.text = tostring(self.displayOrder)
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Cast Effect:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					options = castEffectOptions,
					idChosen = self:try_get("castingEmote", "none"),
					change = function(element)
						if element.idChosen == "none" then
							self.castingEmote = nil
						else
							self.castingEmote = element.idChosen
						end
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Impact Effect:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					options = castEffectOptions,
					idChosen = self:try_get("impactEmote", "empty"),
					change = function(element)
						if element.idChosen == "empty" then
							self.impactEmote = nil
						else
							self.impactEmote = element.idChosen
						end
					end,
				},
			},

			gui.Panel{
				classes = "formPanel",
				gui.Label{
					classes = "formLabel",
					text = "Projectile:",
				},
				gui.Dropdown{
					classes = "formDropdown",
					create = function(element)
						local options = {
							{
								id = "none",
								text = "Choose Projectile...",
							},
						}

						local projectileFolderId = "14d073f8-d00a-4ab4-b184-0545124c9940"
						local objectProjectilesFolder = assets:GetObjectNode(projectileFolderId);
						for i,projectileObject in ipairs(objectProjectilesFolder.children) do
							if not projectileObject.isfolder then
								options[#options+1] = {
									id = projectileObject.id,
									text = projectileObject.description,
								}
							end
						end

						element.options = options
						element.idChosen = self.projectileObject

					end,
					change = function(element)
						self.projectileObject = element.idChosen
					end,
				},
			},
		},
	}

	resultPanel:FireEventTree("refreshAbility")

	return resultPanel
	
end

function ActivatedAbility:IconEditorPanel()


	--the spell's icon.
	local iconEditor = gui.IconEditor{
		library = "abilities",
		bgcolor = self.display['bgcolor'] or '#ffffffff',
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = self.iconid,
		change = function(element)
			self.iconid = element.value
		end,
		create = function(element)
			element.selfStyle.hueshift = self.display['hueshift']
			element.selfStyle.saturation = self.display['saturation']
			element.selfStyle.brightness = self.display['brightness']
		end,
	}

	local iconColorPicker = gui.ColorPicker{
		value = self.display['bgcolor'] or '#ffffffff',
		hmargin = 8,
		width = 24,
		height = 24,
		halign = "left",
		valign = 'center',
		borderWidth = 2,
		borderColor = '#999999ff',

		confirm = function(element)
			iconEditor.selfStyle.bgcolor = element.value
			self.display['bgcolor'] = element.value
		end,

		change = function(element)
			iconEditor.selfStyle.bgcolor = element.value
		end,
	}

	local CreateDisplaySlider = function(options)
		return gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = options.label,
			},
			gui.Slider{
				style = {
					height = 30,
					width = 200,
					fontSize = 14,
				},

				sliderWidth = 140,
				labelWidth = 50,
				value = self.display[options.attr],
				minValue = options.minValue,
				maxValue = options.maxValue,

				formatFunction = function(num)
					return string.format('%d%%', round(num*100))
				end,

				deformatFunction = function(num)
					return num*0.01
				end,

				events = {
					change = function(element)
						self.display = dmhub.DeepCopy(self.display)
						self.display[options.attr] = element.value
						iconEditor:FireEvent('create')
					end,
					confirm = function(element)
						self.display = dmhub.DeepCopy(self.display)
						self.display[options.attr] = element.value
						iconEditor:FireEvent('create')
					end,
				}
			},
		}
	end

	local iconPanel = gui.Panel{
		width = '100%',
		height = 'auto',
		flow = 'horizontal',
		halign = 'right',
		iconEditor,
		iconColorPicker,
	}

	local appearancePanel = gui.Panel{
		classes = {"appearance"},
		width = "auto",
		height = "auto",
		flow = "vertical",
		iconPanel,
		CreateDisplaySlider{ label = "Hue:", attr = 'hueshift', minValue = 0, maxValue = 1, },
		CreateDisplaySlider{ label = "Saturation:", attr = 'saturation', minValue = 0, maxValue = 2, },
		CreateDisplaySlider{ label = "Brightness:", attr = 'brightness', minValue = 0, maxValue = 2, },
	}
	
	return appearancePanel

end

function ActivatedAbility:IsPersistent()
	return self:get_or_add("persistence", {}).enabled == true
end

function ActivatedAbility:Persistence()
	return self:try_get("persistence", {})
end

ActivatedAbility.PersistenceModes = {
	{
		id = "none",
		text = "None",
	},
	
	--the ability will recast at start of turn, allowing new targets.
	{
		id = "recast",
		text = "Recast",
	},

	--the ability will recast at start of turn, costing a maneuver.
	{
		id = "recast_maneuver",
		text = "Recast as Maneuver",
	},

	--the ability will recast on the same target.
	{
		id = "recast_target",
		text = "Recast on Same Target",
	},

    --recast, but only with one target.
    {
        id = "recast_with_one_target",
        text = "Recast With One Target",
    },
}

function ActivatedAbility:IsStrain()
    return self:get_or_add("strain", {}).enabled == true
end

function ActivatedAbility:StrainPanel()
	local resultPanel

	resultPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",
		gui.Check{
			value = self:try_get("strain", {}).enabled,
			text = "Strain",
			change = function(element)
				local strain = self:get_or_add("strain", {})
				strain.enabled = not strain.enabled
				resultPanel:FireEventTree("refreshStrain")
			end,
		},

		gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "100%",

			refreshStrain = function(element)
				element:SetClass("collapsed", not self:IsStrain())
			end,
		}
	}

	resultPanel:FireEventTree("refreshStrain")

	return resultPanel
end

function ActivatedAbility:PersistencePanel()
	local resultPanel

	resultPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",
		gui.Check{
			value = self:try_get("persistence", {}).enabled,
			text = "Persistence",
			change = function(element)
				local persistence = self:get_or_add("persistence", {})
				persistence.enabled = not persistence.enabled
				resultPanel:FireEventTree("refreshPersistence")
			end,
		},

		gui.Panel{
			flow = "vertical",
			height = "auto",
			width = "100%",

			refreshPersistence = function(element)
				element:SetClass("collapsed", not self:IsPersistent())
			end,

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Persistent:",
				},
				gui.Input{
					width = 60,
					height = 20,
					fontSize = 16,
					characterLimit = 2,
					text = self:Persistence().cost or 1,
					change = function(element)
						local persistence = self:get_or_add("persistence", {})
						persistence.cost = tonumber(element.text) or 1
						element.text = persistence.cost
					end,
				}
			},

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Behavior:",
				},
				gui.Dropdown{
					options = ActivatedAbility.PersistenceModes,
					idChosen = self:Persistence().mode or "recast",
					change = function(element)
						local persistence = self:get_or_add("persistence", {})
						persistence.mode = element.idChosen
						resultPanel:FireEventTree("refreshPersistence")
					end,

				}
			},

			gui.Check{
				text = "Target Must Be In Range",
				value = self:Persistence().inrange or false,
				refreshPersistence = function(element)
					element:SetClass("collapsed", self:Persistence().mode ~= "recast_target")
				end,
				change = function(element)
					local persistence = self:get_or_add("persistence", {})
					persistence.inrange = element.value
				end,
			},
		}
	}

	resultPanel:FireEventTree("refreshPersistence")

	return resultPanel
end


ActivatedAbility.ForcedMovementTypes = {
    {
        id = "slide",
        text = "Slide",
    },
    {
        id = "push",
        text = "Push",
    },
    {
        id = "pull",
        text = "Pull",
    },
    {
        id = "vertical_slide",
        text = "Vertical Slide",
    },
    {
        id = "vertical_push",
        text = "Vertical Push",
    },
    {
        id = "vertical_pull",
        text = "Vertical Pull",
    },
}

--This gets a full list of options to display in the dropdown
function ActivatedAbility:GetDisplayedTargetTypeOptions()
    local targetTypes = self:GetTargetTypes()

    local result = {}
    for _,option in ipairs(targetTypes) do
        result[#result+1] = option

        --just "target" means "target" with objectTarget = false.
        if option.id == "target" then
            result[#result+1] = {
                id = "target_object",
                text = "Creature or Object",
            }

            --targetAllegiance = "ally"
            result[#result+1] = {
                id = "target_ally",
                text = "Allied Creature",
            }

            --targetAllegiance = "enemy"
            result[#result+1] = {
                id = "target_enemy",
                text = "Enemy Creature",
            }

            --targetAllegiance = "none"
            result[#result+1] = {
                id = "target_object_only",
                text = "Object",
            }

            --targetAllegiance = "dead"
            result[#result+1] = {
                id = "target_dead",
                text = "Dead Creature",
            }
        end
    end

    return result
end

function ActivatedAbility:GetChosenTargetTypeInDropdown()
    if self.targetType == "target" then
        if self.targetAllegiance == "ally" then
            return "target_ally"
        elseif self.targetAllegiance == "enemy" then
            return "target_enemy"
        elseif self.objectTarget and self.targetAllegiance == "none" then
            return "target_object_only"
        elseif self.targetAllegiance == "dead" then
            return "target_dead"
        elseif self.objectTarget then
            return "target_object"
        else
            return "target"
        end
    end

    return self.targetType
end

function ActivatedAbility:SetChosenTargetTypeFromDropdown(idChosen)
    if idChosen == "target" then
        self.targetType = "target"
        self.targetAllegiance = nil
        self.objectTarget = false
    elseif idChosen == "target_ally" then
        self.targetType = "target"
        self.targetAllegiance = "ally"
        self.objectTarget = false
    elseif idChosen == "target_enemy" then
        self.targetType = "target"
        self.targetAllegiance = "enemy"
        self.objectTarget = false
    elseif idChosen == "target_object" then
        self.targetType = "target"
        self.targetAllegiance = nil
        self.objectTarget = true
    elseif idChosen == "target_object_only" then
        self.targetType = "target"
        self.targetAllegiance = "none"
        self.objectTarget = true
    elseif idChosen == "target_dead" then
        self.targetType = "target"
        self.targetAllegiance = "dead"
        self.objectTarget = false
    else
        self.targetType = idChosen
        self.targetAllegiance = nil
    end
end


function ActivatedAbility:TargetTypeEditor()
	local radiusItems = {sphere = true, cylinder = true, line = true, cube = true}

	local resultPanel

	local strainPanel = self:StrainPanel()
	local persistencePanel = self:PersistencePanel()

	local modesPanel
	modesPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Modes:",
            },

            gui.Dropdown{
                classes = {"formDropdown"},
                idChosen = self.multipleModes,
                options = {
                    {
                        id = false,
                        text = "No Modes",
                    },
                    {
                        id = true,
                        text = "Multiple Modes",
                    },
                    {
                        id = "variations",
                        text = "Ability Variations",
                    },
                },
                change = function(element)
                    self.multipleModes = element.idChosen
                    if self.multipleModes and self:try_get("modeList") == nil then
                        self.modeList = {
                        }
                    end

                    resultPanel:FireEventTree("refreshAbility")
                    modesPanel:FireEventTree("refreshModes")
                end,
            }
        },

		gui.Panel{
			classes = {cond(self.multipleModes, nil, "collapsed-anim")},
			flow = "vertical",
			height = "auto",
			refreshAbility = function(element)
				element:SetClass("collapsed-anim", not self.multipleModes)
			end,
			refreshModes = function(element)
				if self:try_get("modeList") == nil then
					return
				end

				local children = {
					gui.Panel{
						classes = "formPanel",
						height = "auto",
						gui.Label{
							fontSize = 14,
							width = "100%",
							height = "auto",
							text = "This ability has multiple modes. Enter text describing the different ways in which it can be cast. GoblinScripts can use <b>mode</b> to see what mode is being used when casting it and change its behavior.",
						}
					}
				}
				for i,modeEntry in ipairs(self.modeList) do
					children[#children+1] = gui.Panel{
						width = "100%",
						height = "auto",
						flow = "vertical",
						gui.Panel{
							classes = "formPanel",
							gui.Label{
								classes = "formLabel",
								text = string.format("Mode %d:", i),
							},
							gui.Input{
								classes = "formInput",
								text = modeEntry.text,
								change = function(element)
									modeEntry.text = element.text
									resultPanel:FireEventTree("refreshAbility")
								end,
							},
							gui.DeleteItemButton{
								halign = "right",
								width = 16,
								height = 16,
								click = function(element)
									table.remove(self.modeList, i)
									resultPanel:FireEventTree("refreshAbility")
									modesPanel:FireEventTree("refreshModes")
								end,
							},
						},

						gui.Panel{
							classes = "formPanel",
							gui.Label{
								classes = "formLabel",
								text = "Mode Details:",
							},

							gui.Input{
								classes = "formInput",
                                text = modeEntry.rules or "",
                                multiline = true,
                                minHeight = 30,
                                maxHeight = 100,
                                height = "auto",
                                characterLimit = 300,
                                placeholderText = "Enter rules details...",
                                change = function(element)
									modeEntry.rules = element.text
									resultPanel:FireEventTree("refreshAbility")
                                end,
							},
						},

						gui.Panel{
							classes = "formPanel",
							gui.Label{
								classes = "formLabel",
								text = "Mode Condition:",
							},

							gui.GoblinScriptInput{
								classes = "formInput",
								halign = "right",
								width = 240,
								value = modeEntry.condition or "",
								change = function(element)
									modeEntry.condition = element.value
									resultPanel:FireEventTree("refreshAbility")
								end,

								documentation = {
									domains = self.domains,
									help = "This GoblinScript is used to determine whether the mode is available.",
									output = "boolean",
									examples = {
										{
											script = "hitpoints >= Max Hitpoints / 2",
											text = "This mode is available only if the creature's hitpoints are above half of their maximum hitpoints.",
										},
									},
									subject = creature.helpSymbols,
									subjectDescription = "The creature using the ability.",
								},
							},

						},

                        gui.Panel{
                            classes = {"formPanel", cond(self.multipleModes ~= "variations", "collapsed")},
                            flow = "horizontal",
                            width = "auto",
                            height = "auto",
                            gui.Check{
                                text = "Has Ability",
                                minWidth = 130,
                                width = 130,
                                value = modeEntry.hasAbility,
                                change = function(element)
                                    modeEntry.hasAbility = element.value
                                    element.parent.children[2]:SetClass("hidden", not modeEntry.hasAbility)
                                    resultPanel:FireEventTree("refreshAbility")
                                end,
                            },

                            gui.Button{
                                classes = {"formButton", cond(not modeEntry.hasAbility, "hidden")},
                                text = "Edit Ability",
                                click = function(element)
                                    if modeEntry.variation == nil then
                                        modeEntry.variation = ActivatedAbility.Create{
                                            name = self.name,
                                            categorization = self.categorization,
                                            iconid = self.iconid,
                                            description = modeEntry.rules,
                                            domains = self.domains,
                                        }
                                    end

                                    element.root:AddChild(modeEntry.variation:ShowEditActivatedAbilityDialog{})
                                end,
                            }
                        },
					}
				end

				children[#children+1] = gui.Panel{
					classes = "formPanel",
					gui.Label{
						classes = "formLabel",
						text = "New Mode:",
					},
					gui.Input{
						classes = "formInput",
						text = "",
						placeholderText = "Enter new mode...",
						change = function(element)
							self.modeList[#self.modeList+1] = {
								text = element.text
							}
							resultPanel:FireEventTree("refreshAbility")
							modesPanel:FireEventTree("refreshModes")
						end,
					},

					--this delete item button is always hidden and kept for easy consistent alignment.
					gui.DeleteItemButton{
						classes = {"hidden"},
						halign = "right",
						width = 16,
						height = 16,
					},
				}

				element.children = children
			end,
		},
	}

	modesPanel:FireEventTree("refreshModes")

	local durationPanel = nil

	if GameSystem.abilitiesHaveDuration then
		durationPanel = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Duration:",
			},

			gui.Dropdown{
				classes = "formDropdown",
				options = Spell.durationTypes,
				idChosen = self.durationType,
				change = function(element)
					self.durationType = element.idChosen
					resultPanel:FireEventTree("refreshSpell")
				end,
			},
		}
	end

    local abilityFilters = self:try_get("abilityFilters", {})

    local abilityFilterPanel
    abilityFilterPanel = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        refreshFilters = function(element)
            local panels = {}

            for i,filter in ipairs(abilityFilters) do
                panels[#panels+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = "formLabel",
                        text = "Filter:",
                    },
                    gui.GoblinScriptInput{
                        classes = "formInput",
                        halign = "right",
                        width = 240,
                        value = filter.formula,
                        change = function(element)
                            filter.formula = element.value
                            self.abilityFilters = abilityFilters
                            abilityFilterPanel:FireEvent("refreshFilters")
                        end,

                        documentation = {
                            domains = self.domains,
                            help = "This GoblinScript is used to determine whether the ability should be filtered out.",
                            output = "boolean",
                            examples = {
                                {
                                    script = "Level >= 5",
                                    text = "This filter will only allow abilities that are available at level 5 or higher.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature using the ability.",
                        },
                    },

                    gui.DeleteItemButton{
                        halign = "right",
                        width = 12,
                        height = 12,
                        click = function(element)
                            table.remove(abilityFilters, i)
                            abilityFilterPanel:FireEvent("refreshFilters")
                        end,
                    },
                }

                panels[#panels+1] = gui.Panel{
                    classes = "formPanel",
                    gui.Label{
                        classes = "formLabel",
                        text = "Reason:",
                    },
                    gui.Input{
                        classes = "formInput",
                        width = 240,
                        text = filter.reason or "",
                        change = function(element)
                            filter.reason = element.text
                            self.abilityFilters = abilityFilters
                            abilityFilterPanel:FireEvent("refreshFilters")
                        end,
                    },
                }
            end

            panels[#panels+1] = gui.Button{
                text = "Add Ability Filter",
                press = function(element)
                    abilityFilters[#abilityFilters+1] = {
                        formula = "",
                        reason = "",
                    }
                    self.abilityFilters = abilityFilters
                    abilityFilterPanel:FireEvent("refreshFilters")
                end,
            }

            element.children = panels
        end,
    }

    abilityFilterPanel:FireEvent("refreshFilters")

	resultPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",

		modesPanel,
        strainPanel,
		persistencePanel,

		durationPanel,

		gui.Panel{
			classes = "formPanel",

			refreshSpell = function(element)
				element:SetClass('hidden', Spell.durationTypesById[self.durationType].noquantity)
			end,

			gui.Input{
				classes = "formInput",
				width = 60,
				characterLimit = 2,
				text = tostring(self.durationLength),
				textAlignment = "left",
				change = function(element)
					local num = tonumber(element.text)
					if num == nil then
						num = self.durationLength
					end

					self.durationLength = num
					element.text = tostring(self.durationLength)
					resultPanel:FireEventTree("refreshSpell")
				end,
			},
			gui.Label{
				classes = "formLabel",
				refreshSpell = function(element)
					local durationType = Spell.durationTypesById[self.durationType]
					element.text = cond(self.durationLength == 1, durationType.textSingle, durationType.text)
				end,
			},

			gui.Check{
				text = "Concentration",
				minWidth = 100,
				value = self.concentration,
				change = function(element)
					self.concentration = element.value
				end,
			},
		},

        abilityFilterPanel,

		gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Range Text:",
            },
            gui.Input{
                classes = {"formInput"},
                text = self:try_get("rangeTextOverride", ""),
                placeholderText = self:DescribeRange(),
                change = function(element)
                    self.rangeTextOverride = element.text
                end,
                refreshAbility = function(element)
                    element.placeholderText = self:DescribeRange()
                end,
            },
        },

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Target Text:",
            },
            gui.Input{
                classes = {"formInput"},
                text = self:try_get("targetTextOverride", ""),
                placeholderText = self:DescribeTarget(),
                change = function(element)
                    self.targetTextOverride = element.text
                end,
                refreshAbility = function(element)
                    element.placeholderText = self:DescribeTarget()
                end,
            },
        },

		gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Target Type:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				options = self:GetDisplayedTargetTypeOptions(),
				idChosen = self:GetChosenTargetTypeInDropdown(),
				change = function(element)
                    self:SetChosenTargetTypeFromDropdown(element.idChosen)
					resultPanel:FireEventTree("refreshAbility")
				end,
			},
		},

        gui.Panel{
            classes = {"formPanel", cond(self.targetType ~= "areatemplate", "collapsed-anim")},
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType ~= "areatemplate")
			end,

            gui.Label{
                classes = {"formLabel"},
                text = "Object ID:",
            },

            gui.Input{
                classes = {"formInput"},
                text = self:try_get("areaTemplateObjectId", ""),
                width = 240,
                placeholderText = "Enter Object ID...",
                change = function(element)
                    self.areaTemplateObjectId = element.text
                end,
            }
        },

		gui.Check{
			text = "Can Target Self",
			value = self.selfTarget,
			classes = cond(self.targetType == 'self', 'collapsed-anim'),
			change = function(element)
				self.selfTarget = element.value
			end,
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType == 'self')
			end,
		},

		gui.Panel{
			classes = {"formPanel", cond(not self:IsTargetTypeAOE(), 'collapsed-anim')},
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', not self:IsTargetTypeAOE())
			end,
			gui.Label{
				classes = "formLabel",
				text = "Affects:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				options = {
                    {
                        id = "all",
                        text = "Creatures",
                    },
                    {
                        id = "all_and_objects",
                        text = "Creatures and Objects",
                    },
                    {
                        id = "ally",
                        text = "Allied Creatures",
                    },
                    {
                        id = "enemy",
                        text = "Enemy Creatures",
                    },
                },
				idChosen = cond(self.objectTarget, "all_and_objects",
                           cond(self.targetAllegiance == "ally", "ally",
                           cond(self.targetAllegiance == "enemy", "enemy", "all"))),
				change = function(element)
                    if element.idChosen == "all" then
                        self.objectTarget = false
                        self.targetAllegiance = nil
                    elseif element.idChosen == "all_and_objects" then
                        self.objectTarget = true
                        self.targetAllegiance = nil
                    elseif element.idChosen == "ally" then
                        self.objectTarget = false
                        self.targetAllegiance = "ally"
                    elseif element.idChosen == "enemy" then
                        self.objectTarget = false
                        self.targetAllegiance = "enemy"
                    else
                        self.objectTarget = false
                        self.targetAllegiance = nil
                    end

					resultPanel:FireEventTree("refreshAbility")
				end,
			},
		},

		gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Targeting:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				options = {
					{
						id = "direct",
						text = "Direct",
					},
					{
						id = "pathfind",
						text = "Pathfinding",
					},
					{
						id = "straightpath",
						text = "Direct Path",
					},
					{
						id = "straightpathignorecreatures",
						text = "Direct Path, Ignoring Creatures",
					},
					{
						id = "straightline",
						text = "Forced Movement",
					},
                    {
                        id = "vacated",
                        text = "Vacated Space",
                    }
				},
				idChosen = self:try_get("targeting", "direct"),
				change = function(element)
					self.targeting = element.idChosen
					resultPanel:FireEventTree("refreshAbility")
				end,
			},
			refreshAbility = function(element)
				element:SetClass("collapsed", self.targetType ~= "emptyspace" and self.targetType ~= "anyspace")
			end,
		},

		gui.Panel{
			classes = {"formPanel", cond(self:try_get("targeting") ~= "straightline", 'collapsed')},
			gui.Label{
				classes = "formLabel",
				text = "Forced Movement:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				options = ActivatedAbility.ForcedMovementTypes,

				idChosen = self:try_get("forcedMovement", "slide"),
				change = function(element)
					self.forcedMovement = element.idChosen
					resultPanel:FireEventTree("refreshAbility")
				end,
			},
			refreshAbility = function(element)
				element:SetClass("collapsed", self:try_get("targeting") ~= "straightline")
			end,
		},


        gui.Panel{
            classes = {"formPanel"},
            height = "auto",
            flow = "vertical",
            create = function(element)
                element:FireEvent("refreshAbility")
            end,

            refreshAbility = function(element)
                local children = {}
                local reasonedFilters = self:try_get("reasonedFilters", {})
                for filterIndex,filter in ipairs(reasonedFilters) do
                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = "formLabel",
                            text = "Formula:",
                        },
                        gui.GoblinScriptInput{
                            classes = "formInput",
                            value = filter.formula,
                            change = function(element)
                                filter.formula = element.value
                            end,

                            documentation = {
                                domains = self.domains,
                                help = "This GoblinScript is used when you use an <color=#00FFFF><link=ability>ability</link></color>. It determines whether a creature included in the ability's area of effect should be affected by the ability. The script is evaluated once for each creature in the ability's area of effect. Creatures for whom the script produces a result of <b>true</b> are affected by the ability, while creatures for whom the script produces a result of <b>false</b> are not. If left empty, all creatures in the area of effect will be affected.",
                                output = "boolean",
                                examples = {
                                    {
                                        script = "enemy",
                                        text = "Make the ability affect creatures that are enemies of the ability's caster.",
                                    },
                                    {
                                        script = "not enemy and type is not undead",
                                        text = "Make the ability affect creatures that are not enemies of the ability's caster. The ability won't affect undead creatures.",
                                    },
                                    {
                                        script = "Target Number = 2",
                                        text = "Make this behavior affect only the second target of the spell.",
                                    },
                                },
                                subject = creature.helpSymbols,
                                subjectDescription = "A creature in the ability's area of effect ",
                                symbols = {
                                    caster = {
                                        name = "Caster",
                                        type = "creature",
                                        desc = "The caster of this spell.",
                                    },
                                    enemy = {
                                        name = "Enemy",
                                        type = "boolean",
                                        desc = "True if the subject is an enemy of the creature casting the ability. Otherwise this is False.",
                                    },
                                    target = {
                                        name = "Target",
                                        type = "creature",
                                        desc = "The target of this spell. This is the same as the subject of this GoblinScript.",
                                    },
                                    targetnumber = {
                                        name = "Target Number",
                                        type = "number",
                                        desc = "1 for the first target, 2 for the second target, etc.",
                                    },
                                    numberoftargets = {
                                        name = "Number of Targets",
                                        type = "number",
                                        desc = "The number of creatures this spell is targeting.",
                                    },
                                },
                            },
                        },

                        gui.DeleteItemButton{
                            halign = "right",
                            width = 16,
                            height = 16,
                            click = function(element)
                                table.remove(reasonedFilters, filterIndex)
                                resultPanel:FireEventTree("refreshAbility")
                            end
                        }
                    }

                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Input{
                            classes = "formInput",
                            width = 360,
                            text = filter.reason,
                            lmargin = 60,
                            change = function(element)
                                filter.reason = element.text
                            end,
                            placeholderText = "Enter reason for this filter...",
                        }
                    }
                end
                element.children = children
            end,
        },

        gui.Button{
            text = "Add Reasoned Filter",
            width = "auto",
            height = "auto",
            pad = 4,
            press = function(element)
                local reasonedFilters = self:get_or_add("reasonedFilters", {})
                reasonedFilters[#reasonedFilters+1] = {
                    formula = "",
                    reason = "",
                }
				resultPanel:FireEventTree("refreshAbility")
            end,
        },

		gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Target Filter:",
			},
			gui.GoblinScriptInput{
				classes = "formInput",
				value = self.targetFilter,
				change = function(element)
					self.targetFilter = element.value
				end,

				documentation = {
					domains = self.domains,
					help = "This GoblinScript is used when you use an <color=#00FFFF><link=ability>ability</link></color>. It determines whether a creature included in the ability's area of effect should be affected by the ability. The script is evaluated once for each creature in the ability's area of effect. Creatures for whom the script produces a result of <b>true</b> are affected by the ability, while creatures for whom the script produces a result of <b>false</b> are not. If left empty, all creatures in the area of effect will be affected.",
					output = "boolean",
					examples = {
						{
							script = "enemy",
							text = "Make the ability affect creatures that are enemies of the ability's caster.",
						},
						{
							script = "not enemy and type is not undead",
							text = "Make the ability affect creatures that are not enemies of the ability's caster. The ability won't affect undead creatures.",
						},
						{
							script = "Target Number = 2",
							text = "Make this behavior affect only the second target of the spell.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "A creature in the ability's area of effect ",
					symbols = {
						caster = {
							name = "Caster",
							type = "creature",
							desc = "The caster of this spell.",
						},
						enemy = {
							name = "Enemy",
							type = "boolean",
							desc = "True if the subject is an enemy of the creature casting the ability. Otherwise this is False.",
						},
						target = {
							name = "Target",
							type = "creature",
							desc = "The target of this spell. This is the same as the subject of this GoblinScript.",
						},
						targetnumber = {
							name = "Target Number",
							type = "number",
							desc = "1 for the first target, 2 for the second target, etc.",
						},
						numberoftargets = {
							name = "Number of Targets",
							type = "number",
							desc = "The number of creatures this spell is targeting.",
						},
					},
				},

			},
		},

		gui.Panel{
			classes = {"formPanel", cond(not radiusItems[self.targetType], 'collapsed-anim')},
			gui.Label{
				classes = "formLabel",
				text = "Radius:",
				create = function(element)
					element:FireEvent("refreshAbility")
				end,
				refreshAbility = function(element)
					if self.targetType == 'line' then
						element.text = 'Width:'
					elseif self.targetType == 'cube' then
						element.text = 'Edge:'
					else
						element.text = 'Radius:'
					end
				end,
			},

			gui.GoblinScriptInput{
				classes = "formInput",
				value = self:try_get("radius", ""),
				change = function(element)
					self.radius = element.value
				end,
				documentation = {
					domains = self.domains,
					help = " This GoblinScript is used to determine the radius of this <color=#00FFFF><link=ability>ability</link></color>. It produces a number which is used as the range of the ability, given in feet. If left empty, the ability will have a range of 5.",
					output = "number",
					examples = {
						{
							script = "2",
							text = "The ability will have a radius of 2 squares.",
						},
						{
							script = "2 + level",
							text = "The ability will have a range of 2 squares plus 1 for each level of the caster.",
						},
					},

					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = table.union({
						ability = {
							name = "Ability",
							type = "ability",
							desc = "The ability being used.",
						},
					}, ActivatedAbility.helpCasting),
				}
			},

			refreshAbility = function(element)
				element:SetClass('collapsed-anim', not radiusItems[self.targetType])
			end,
		},

		gui.Panel{
			classes = {"formPanel", cond(self.targetType ~= 'target' and self.targetType ~= 'emptyspace' and self.targetType ~= 'anyspace', 'collapsed-anim')},
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType ~= 'target' and self.targetType ~= 'emptyspace' and self.targetType ~= 'anyspace')
			end,
			gui.Label{
				classes = "formLabel",
				text = "Target Count:",
			},
			gui.GoblinScriptInput{
				classes = "formInput",
				value = self.numTargets,
				change = function(element)
					self.numTargets = element.value
					resultPanel:FireEventTree("refreshAbility")
				end,

				documentation = {
					domains = self.domains,
					help = "This GoblinScript is used when you use an <color=#00FFFF><link=ability>ability</link></color>. It determines the number of targets for the ability.",
					output = "number",
					examples = {
						{
							script = "3",
							text = "Make the ability have 3 targets. A simple number is the most common way to use this field.",
						},
						{
							script = "3 + Upcast",
							text = "Used for spell abilities that can be upcast. The spell targets 3 targets, plus an additional target for each slot level above the spell's level.",
						},
						{
							script = "1 + 1 when level >= 5",
							text = "Make the ability have one target, or two targets when the caster's level is 5 or higher.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = ActivatedAbility.helpCasting,
				},

			},
		},

        gui.Check{
            classes = {cond(self.targetType ~= "self", "collapsed-anim")},
            text = "Cast immediately when clicked",
            value = self.castImmediately,
            refreshAbility = function(element)
                element:SetClass("collapsed-anim", self.targetType ~= "self")
            end,
            change = function(element)
				self.castImmediately = element.value
				resultPanel:FireEventTree("refreshAbility")
            end,

        },

        gui.Check{
            text = "Can Choose Lower Range",
            value = self.canChooseLowerRange,
            classes = cond(self.targetType ~= 'line', 'collapsed-anim'),
            change = function(element)
                self.canChooseLowerRange = element.value
            end,
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType ~= 'line')
			end,
        },

		gui.Check{
			text = "Allow Duplicate Targeting",
			value = self.repeatTargets,
			classes = cond(self.targetType ~= 'target' or tonumber(self.numTargets) == 1, 'collapsed-anim'),
			change = function(element)
				self.repeatTargets = element.value
			end,
			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType ~= 'target' or tonumber(self.numTargets) == 1)
			end,
		},

		gui.Check{
			text = "Proximity Targeting",
			value = self.proximityTargeting,
			classes = cond(self.targetType ~= 'target' or tonumber(self.numTargets) == 1, 'collapsed-anim'),
			refreshAbility = function(element)
				element:SetClass("collapsed-anim", self.targetType ~= 'target' or tonumber(self.numTargets) == 1)
			end,
			linger = function(element)
				return gui.Tooltip("If checked, every target after the first must be in a certain proximity of the first target.")(element)
			end,
			change = function(element)
				self.proximityTargeting = element.value
				resultPanel:FireEventTree("updateProximityTargeting")
			end,
		},

		gui.Panel{
			classes = {"formPanel", cond(self.targetType ~= 'target' or (not self.proximityTargeting) or tonumber(self.numTargets) == 1, 'collapsed-anim')},
			refreshAbility = function(element)
				element:SetClass("collapsed-anim", self.targetType ~= 'target' or (not self.proximityTargeting) or tonumber(self.numTargets) == 1, 'collapsed-anim')
			end,
			updateProximityTargeting = function(element)
				element:FireEvent("refreshAbility")
			end,
			gui.Label{
				classes = "formLabel",
				text = "Proximity:",
			},

			gui.GoblinScriptInput{
				classes = "formInput",
				value = self.proximityRange,
				change = function(element)
					self.proximityRange = element.value
				end,

				documentation = {
					domains = self.domains,
					help = "This GoblinScript is used when you use an <color=#00FFFF><link=ability>ability</link></color>. It determines the <color=#00FFFF><link=proximity>proximity range</link></color> for the ability.",
					output = "number",
					examples = {
						{
							script = "5",
							text = "Make the ability have a proximity range of 5 feet. All targets after the first target must be within 5 feet of the main target.",
						},
						{
							script = "5 + Upcast*5",
							text = "Used for spell abilities that can be upcast. Make the spell have a proximity range of 5 feet, with an additional 5 feet for each level that the used spell slot is above the spell's level.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
				},

			},

		},

        gui.Panel{
            classes = {"formPanel", cond(self.targetType ~= "line", "collapsed-anim")},
            refreshAbility = function(element)
                element:SetClass("collapsed-anim", self.targetType ~= "line")
            end,
	
			gui.Label{
				classes = "formLabel",
				text = "Distance:",
			},

			gui.GoblinScriptInput{
				classes = "formInput",
				value = self.lineDistance,
				change = function(element)
					self.lineDistance = element.value
					resultPanel:FireEventTree("refreshAbility")
				end,
				documentation = {
					domains = self.domains,
					help = " This GoblinScript is used to determine the distance of this <color=#00FFFF><link=ability>ability</link></color>'s line. The number it produces is the number of squares away from the caster that the line can start.",
					output = "number",
					examples = {
						{
							script = "4",
							text = "The ability will have a distance of 4 squares.",
						},
						{
							script = "1 + level",
							text = "The ability will have a distance of 1 square, plus an additional 1 square for each level the creature using the ability has.",
						},
					},

					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = table.union({
						ability = {
							name = "Ability",
							type = "ability",
							desc = "The ability being used.",
						},
					}, ActivatedAbility.helpCasting),
				}
			},


        },

		gui.Panel{
			classes = {"formPanel", cond(self.targetType == 'self' or self.targetType == 'map', 'collapsed-anim')},

			refreshAbility = function(element)
				element:SetClass('collapsed-anim', self.targetType == 'self' or self.targetType == 'map')
			end,
			
			gui.Label{
				classes = "formLabel",
				text = "Range:",
                refreshAbility = function(element)
                    if self.targetType == 'line' then
                        element.text = 'Length:'
                    else
                        element.text = 'Range:'
                    end
                end,
			},

			gui.GoblinScriptInput{
				classes = "formInput",
				value = self.range,
				change = function(element)
					self.range = element.value
					resultPanel:FireEventTree("refreshAbility")
				end,
				documentation = {
					domains = self.domains,
					help = " This GoblinScript is used to determine the range of this <color=#00FFFF><link=ability>ability</link></color>. It produces a number which is used as the range of the ability, given in feet. If left empty, the ability will have a range of 5.",
					output = "number",
					examples = {
						{
							script = "10",
							text = "The ability will have a range of 10 squares.",
						},
						{
							script = "10 + level*2",
							text = "The ability will have a distance of 10 squares, plus an additional 2 squares for each level the creature using the ability has.",
						},
					},

					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = table.union({
						ability = {
							name = "Ability",
							type = "ability",
							desc = "The ability being used.",
						},
					}, ActivatedAbility.helpCasting),
				}
			},


		},

	}

	resultPanel:FireEventTree("refreshSpell")

	return resultPanel
end


function ActivatedAbility:BehaviorEditor(options)
	options = options or {}

	local resultPanel
	local behaviorPanel = nil

	local activatedAbilityOptions = DeepCopy(self.Types)
	table.remove(activatedAbilityOptions, 1)
	table.sort(activatedAbilityOptions, function(a,b) return a.text < b.text  end)

	local activatedAbilityOptionsWithoutMono = DeepCopy(self.GetTypesWithoutMono())
	table.remove(activatedAbilityOptionsWithoutMono, 1)
	table.sort(activatedAbilityOptionsWithoutMono, function(a,b) return a.text < b.text  end)

	local optionsAvailable = DeepCopy(cond(#self.behaviors == 0, activatedAbilityOptions, activatedAbilityOptionsWithoutMono))

    optionsAvailable[#optionsAvailable + 1] = {
        hidden = function()
            local clipboardItem = dmhub.GetInternalClipboard()
            if clipboardItem ~= nil and string.starts_with(clipboardItem.typeName or "", "ActivatedAbility") and string.ends_with(clipboardItem.typeName, "Behavior") then
                return false
            end

            return true
        end,
        id = "clipboard",
        text = "Paste Behavior",
    }

	local dropdown = gui.Dropdown{
			classes = "formDropdown",
			textOverride = "Add Behavior...",
			width = 240,
            hasSearch = true,
			options = optionsAvailable,
			--idChosen = self.abilityType,
			idChosen = "none",
			change = function(element)
				if element.idChosen == "none" then
					return
				end

				if element.idChosen == "clipboard" then
                    local clipboardItem = dmhub.GetInternalClipboard()
                    if clipboardItem ~= nil and string.starts_with(clipboardItem.typeName or "", "ActivatedAbility") and string.ends_with(clipboardItem.typeName, "Behavior") then
                        local item = DeepCopy(clipboardItem)
                        item.guid = dmhub.GenerateGuid()
					    self.behaviors[#self.behaviors+1] = DeepCopy(item)
                    end
				else

					if self.TypesById[element.idChosen].createBehavior then
						self.behaviors[#self.behaviors+1] = self.TypesById[element.idChosen].createBehavior()
					end
				end
				
				resultPanel:FireEvent("refreshAbility")
			end,
		}

	local commonPanel = nil
	
	if not options.behaviorOnly then
		commonPanel = self:TargetTypeEditor{
			refreshAbility = function(element)
				resultPanel:FireEvent("refreshAbility")
			end
		}
	end

	local behaviorDropdown = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Behavior:",
			},
			dropdown,
		}

	resultPanel = gui.Panel{
		flow = "vertical",
		height = "auto",
		width = "100%",

		refreshAbility = function(element)
			behaviorPanel = nil

			local children = {commonPanel}

			for i,behavior in ipairs(self.behaviors) do
				children[#children+1] = behavior:CreateEditor(self, {
					moveup = cond(i > 1, function(element)
						if i > 1 then
							local temp = self.behaviors[i-1]
							self.behaviors[i-1] = self.behaviors[i]
							self.behaviors[i] = temp
							resultPanel:FireEventTree("refreshAbility")
						end
					end),

					movedown = cond(i < #self.behaviors, function(element)
						if i < #self.behaviors then
							local temp = self.behaviors[i+1]
							self.behaviors[i+1] = self.behaviors[i]
							self.behaviors[i] = temp
							resultPanel:FireEventTree("refreshAbility")
						end
					end),
					delete = function(element)
						table.remove(self.behaviors, i)
						resultPanel:FireEventTree("refreshAbility")
					end,
				})
			end


			local optionsAvailable = DeepCopy(cond(#self.behaviors == 0, activatedAbilityOptions, activatedAbilityOptionsWithoutMono))
			local clipboardItem = dmhub.GetInternalClipboard()
			if clipboardItem ~= nil and string.starts_with(clipboardItem.typeName or "", "ActivatedAbility") and string.ends_with(clipboardItem.typeName, "Behavior") then
				optionsAvailable[#optionsAvailable+1] = {
					id = "clipboard",
					text = "Paste Behavior",
				}
			end

			dropdown.options = optionsAvailable
			dropdown.idChosen = "none"

			children[#children+1] = behaviorDropdown

			behaviorDropdown:SetClass("collapsed", cond(#self.behaviors == 1 and self.behaviors[1].mono, true, false))

			element.children = children
		end,
	}

	resultPanel:FireEventTree("refreshAbility")

	return resultPanel
end

function ActivatedAbilityBehavior:ApplyToEditor(parentPanel, list)

	local ability = parentPanel.data.parentAbility
	local behaviors = ability:get_or_add("behaviors", {})

	local firstBehavior = (behaviors ~= nil and behaviors[1] == self) and ability.abilityModification == false

	local dropdownOptions = {
		{
			id = "targets",
			text = "Targets",
		},
		{
			id = "caster",
			text = "Caster",
		},
		{
			id = "caster_and_targets",
			text = "Caster and Targets",
		},
		{
			id = "caster_riders",
			text = "Caster's Riders",
		},
		{
			id = "caster_minions",
			text = "Caster's Minions",
		},
		{
			id = "first_target",
			text = "First Target",
		},
		{
			id = "other_than_first_target",
			text = "Targets Other than First",
		},
		{
			id = "target_proximity",
			text = "Targets and Proximity",
		},
		{
			id = "proximity_only",
			text = "Proximity Only",
		},
        {
            id = "original_targets",
            text = "Original Targets",
        },
        {
            id = "subject",
            text = "Trigger Subject",
        },
        {
            id = "none",
            text = "None",
        },
	}

	for _,applyto in ipairs(GameSystem.ApplyToTargetsList) do
		if ((not firstBehavior) and (not applyto.deprecated)) or self.applyto == applyto.id then
			dropdownOptions[#dropdownOptions+1] = {
				id = applyto.id,
				text = applyto.text,
			}
		end
	end

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Apply To:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = dropdownOptions,
			idChosen = self.applyto,
			change = function(element)
				self.applyto = element.idChosen
				parentPanel:FireEvent('refreshBehavior')
			end,
		},
	}

	if self:try_get("applyto") == "target_proximity" or self:try_get("applyto") == "proximity_only" then
		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Proximity Range:",
			},
			gui.Input{
				classes = "formInput",
				text = self:try_get("target_proximity_range", "1"),
				width = 300,
				characterLimit = 5,
				change = function(element)
					self.target_proximity_range = element.text
				end,
			},
		}
	end

	if GameSystem.GetApplyToInfo(self:try_get("applyto","")).attack_hit then

		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Description:",
			},
			gui.Input{
				classes = "formInput",
				text = self:try_get("hitDescription", ""),
				width = 600,
				change = function(element)
					self.hitDescription = element.text
				end,
			},
		}

		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Details:",
			},
			gui.Input{
				classes = {"formInput"},
				textAlignment = "topleft",
				multiline = true,
				height = "auto",
				minHeight = 40,
				width = 600,
				text = self:try_get("hitDetails", ""),
				change = function(element)
					self.hitDetails = element.text
				end,
			},
		}

	end
end

function ActivatedAbilityBehavior:AttackTypeEditor(parentPanel, list)

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Attack Type:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = {"Melee", "Ranged"},
			idChosen = self:try_get('attackType', 'Ranged'),
			change = function(element)
				self.attackType = element.idChosen
			end,
		},
	}
	
	if parentPanel.data.parentAbility.typeName ~= 'Spell' then
		

		list[#list+1] = gui.Check{
			text = "Override hit modifier",
			value = self:try_get("hit", nil) ~= nil,
			change = function(element)
				self.hit = cond(element.value, "5", nil)
				parentPanel:FireEvent('refreshBehavior')
			end,
		}

		list[#list+1] = gui.Panel{
			classes = {"formPanel", cond(not self:has_key("hit"), "collapsed-anim")},
			refreshBehavior = function(element)
				element:SetClass('collapsed-anim', not self:has_key("hit"))
			end,
			gui.Label{
				classes = "formLabel",
				text = "Hit Modifier:",
			},
			gui.GoblinScriptInput{
				classes = "formInput",
				value = self:try_get("hit", ""),
				change = function(element)
					self.hit = element.value
				end,
				documentation = {
					domains = parentPanel.data.parentAbility.domains,
					help = string.format("This GoblinScript is used to determine the hit modifier for this ability."),
					output = "number",
					examples = {
						{
							script = "5",
							text = "The bonus will be 5.",
						},

						{
							script = "Strength Modifier + Proficiency Bonus",
							text = "The bonus will be the creature's Strength Modifier added to its Proficiency Bonus.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = ActivatedAbility.helpCasting,
				},
			},
		}

		list[#list+1] = gui.Check{
			text = "Apply Attribute Modifier to Damage",
			value = self:try_get("attrModDamage", false),
			change = function(element)
				self.attrModDamage = cond(element.value, true, nil)
			end,
		}

	end

	if GameSystem.attacksCanHaveWeaponProperties then
		for propertyid,_ in pairs(self:try_get("weaponProperties", {})) do
			local property = WeaponProperty.GetTable()[propertyid]
			if property ~= nil then
				list[#list+1] = gui.Panel{
					flow = "horizontal",
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						text = property.name,
					},
					gui.DeleteItemButton{
						halign = 'right',
						valign = 'center',
						click = function(element)
							self.weaponProperties[propertyid] = nil
							parentPanel:FireEvent("refreshBehavior")
						end,
					}
				}
			end
		end

		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Properties:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				options = WeaponProperty.DropdownOptions({isWeapon = true}),
				idChosen = nil,
				textOverride = "Add Property...",
				change = function(element)
					self:get_or_add("weaponProperties", {})[element.idChosen] = true
					parentPanel:FireEvent("refreshBehavior")
				end,
			},
		}

	end
end

ActivatedAbilityBehavior.rollName = "Roll"
ActivatedAbilityAttackBehavior.rollName = "Damage"

ActivatedAbilityBehavior.rollHelp = "the roll for this ability"
ActivatedAbilityAttackBehavior.rollHelp = "the damage for this ability"
ActivatedAbilityDamageBehavior.rollHelp = "the damage for this ability"
ActivatedAbilityHealBehavior.rollHelp = "the healing for this ability"

function ActivatedAbilityBehavior:FilterEditor(parentPanel, list)

	local helpCasting = dmhub.DeepCopy(ActivatedAbility.helpCasting)
	helpCasting.target = {
		name = "Target",
		type = "creature",
		desc = "The creature that we are considering whether it should be affected by this behavior.",
		examples = {
			"Target.Hitpoints < 20",
		},
	}

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Apply To Filter:",
		},

		gui.GoblinScriptInput{
			classes = "formInput",
			value = self.filterTarget,
			change = function(element)
				self.filterTarget = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine if this %s behavior should apply to a target. The script will be run for every target, and the behavior will only affect targets if the script results in a true value.", self.summary),
				output = "boolean",
				examples = {
					{
						script = "target.CR <= 1",
						text = "Only creatures with a Challenge Rating of 1 or less will be affected.",
					},
					{
						script = "target.Wisdom < Wisdom",
						text = "Only creatures with a Wisdom score lower than the caster's Wisdom score will be affected.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature targeted by the spell",

				symbols = ActivatedAbility.CatHelpSymbols(helpCasting, {
					caster = {
						name = "Caster",
						type = "creature",
						desc = "The caster of this spell.",
					},
					target = {
						name = "Target",
						type = "creature",
						desc = "The target of this spell. This is the same as the subject of this GoblinScript.",
					},
				}),
			},

		},

	}

end

function ActivatedAbilityBehavior:ModifiersEditor(parentPanel, list)

	local contentPanel

	local Refresh
	Refresh = function()
		local children = {}

		for j,mod in ipairs(self.modifiers) do

			local behaviorPanel = gui.Panel{
				classes = {'behavior-panel'},

				create = function(element)
					local typeInfo = CharacterModifier.TypeInfo[mod.behavior] or {}
					local createEditor = typeInfo.createEditor
					if createEditor ~= nil then
						createEditor(mod, element)
					end
				end,

				refreshModifier = function(element)
					contentPanel:FireEventTree("modifiersChanged")
				end,
			}

			children[#children+1] = gui.Panel{
				classes = {'modifierEditorPanel'},
				gui.Label{
					classes = {'modifierHeadingLabel'},
					text = CharacterModifier.TypesById[mod.behavior].text,
					gui.DeleteItemButton{
						classes = {cond(mod:try_get("deletable") == false, "hidden")},
						floating = true,
						halign = 'right',
						valign = 'center',
						click = function(element)
							table.remove(self.modifiers, j)
							Refresh()
						end,
					}
				},

				behaviorPanel,
			}
		end

		contentPanel.children = children
	end

	contentPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		styles = CharacterFeature.ModifierStyles,
	}

	Refresh()

	list[#list+1] = contentPanel


	local options = dmhub.DeepCopy(CharacterModifier.Types)
	options[1].text = 'Add Modifier...'
	list[#list+1] = gui.Dropdown{
		selfStyle = {
			height = 30,
			width = 260,
			fontSize = 16,
			halign = "left",
		},

		dropdownHeight = 240,

		options = options,
		idChosen = 'none',

		change = function(element)
			if element.idChosen ~= 'none' then
				local domains = nil
				--if self:has_key("domains") then
				--	domains = dmhub.DeepCopy(self.domains)
				--end
				local modifier = CharacterModifier.new{
					guid = dmhub.GenerateGuid(),
					sourceguid = parentPanel.data.parentAbility:try_get("guid"),
					name = parentPanel.data.parentAbility.name,
					source = "Ability Modifier",
					description = parentPanel.data.parentAbility.description,
					behavior = element.idChosen,
					domains = parentPanel.data.parentAbility.domains,
				}
				local typeInfo = CharacterModifier.TypeInfo[modifier.behavior] or {}
				if typeInfo.init then
					--initialize our new behavior type.
					typeInfo.init(modifier)
				end

				self.modifiers[#self.modifiers+1] = modifier

				element.idChosen = "none"

				Refresh()
			end
		end
	}
	
end

function ActivatedAbilityBehavior:RollEditor(parentPanel, list)

	local helpCasting = dmhub.DeepCopy(ActivatedAbility.helpCasting)
	if self.summary == "Damage" then
		helpCasting.target = {
			name = "Target",
			type = "creature",
			desc = "The creature targeted with damage.\n\n<color=#ffaaaa><i>This field is only available for abilities that target a single target or have separate damage roll for each target enabled.</i></color>",
			examples = {
				"1d8 when Target.Hitpoints = Target.Maximum Hitpoints else 1d12",
			},
		}
	elseif self.summary == "Heal" then
		helpCasting.target = {
			name = "Target",
			type = "creature",
			desc = "The creature targeted with healing.\n\n<color=#ffaaaa><i>This field is only available for abilities that target a single target.</i></color>",
			examples = {
				"1d8 when Target.Hitpoints = Target.Maximum Hitpoints else 1d12",
			},
		}
	end


	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = self.rollName .. ":",
		},
		gui.GoblinScriptInput{
			classes = "formInput",
			value = self.roll,
			change = function(element)
				self.roll = element.value
			end,

			displayTypes = {
				{
					id = "level",
					text = "Table by Character Level",
					value = GoblinScriptTable.new{
						id = "level",
						field = "Level",
						valueLabel = self.rollName,
						entries = {
							{
								threshold = 1,
								script = "",
							},
						},
					}
				},
				{
					id = "upcast",
					text = "Table by Higher Level Spell Slot",
					value = GoblinScriptTable.new{
						id = "upcast",
						field = "Upcast",
						baseLabel = "Base",
						upcastStyle = true,
						entries = {
							{
								threshold = 0,
								script = "",
							},
							{
								threshold = 1,
								script = "",
							},
						},
					}
				}

			},

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine %s.", self.rollHelp),
				output = "roll",
				examples = {
					{
						script = "2d6",
						text = "2d6 will be rolled.",
					},
					{
						script = "5d8 + upcast d8",
						text = "5d8 will be rolled, with an additional d8 rolled for every level the spell slot used for this spell is above the spell's level.",
					},
					{
						script = "4d6 when level < 5 else 6d6 when level < 12 else 8d6",
						text = "4d6 will be rolled if the creature using this ability is a level lower than 5, 6d6 if its level is 5-11, otherwise 8d6 will be rolled.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature using the ability",
				symbols = helpCasting,
			},

		},
	}

end

function ActivatedAbilityBehavior:SeparateRollsEditor(parentPanel, list)
	list[#list+1] = gui.Check{
		text = "Separate roll for each target",
		halign = "left",
		value = self:try_get('separateRolls'),
		change = function(element)
			self.separateRolls = cond(element.value, true, nil)
		end,
		refreshBehavior = function(element)
			--local numTargets = parentPanel.data.parentAbility.numTargets
			--element:SetClass('collapsed-anim', numTargets == '0' or numTargets == '1' or numTargets == 1)
		end,
	}
end

function ActivatedAbilityBehavior:OngoingEffectEditor(parentPanel, list, options)
	options = options or {}

	local duration = self:try_get("duration")
	local idChosen = 'rounds'
	if duration == "momentary" then
		idChosen = 'momentary'
	elseif duration == "save_ends" then
		idChosen = "save_ends"
	elseif duration == "eoe_or_dying" then
		idChosen = "eoe_or_dying"
	elseif duration == "eoe" then
		idChosen = "eoe"
	elseif duration == 0 then
		idChosen = 'turn'
	elseif duration == 'end_of_next_turn' or duration == 'until_rest' or duration == 'until_long_rest' or duration == 'endround' or duration =='endnextround' or duration == 'eoe' then
		idChosen = duration
	elseif not duration then
		idChosen = 'indefinite'
	elseif self.durationUntilEndOfTurn then
		idChosen = 'rounds_end_turn'
	end

	if self:try_get("dc", "none") ~= "none" then
		list[#list+1] = gui.Check{
			text = "Repeat save each round",
			value = self.repeatSave,
			halign = "left",
			change = function(element)
				self.repeatSave = element.value
				parentPanel:FireEvent('refreshBehavior')
			end,
		}
	end

	local optionsSkills = {
		{
			id = 'none',
			text = 'None',
		},
	}

	for i,skill in ipairs(Skill.skillsDropdownOptions) do
		optionsSkills[#optionsSkills+1] = {
			id = skill.id,
			text = skill.text,
		}
	end

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Duration:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			width = 240,
			options = CharacterOngoingEffect.durationOptions,
			idChosen = idChosen,
			change = function(element)
				if element.idChosen == 'turn' then
					self.duration = 0
				elseif element.idChosen == 'rounds' or element.idChosen == 'rounds_end_turn' then
					self.duration = tonumber(self:try_get('duration', '1')) or 1
					if self.duration <= 0 then
						self.duration = 1
					end
					self.durationUntilEndOfTurn = (element.idChosen == 'rounds_end_turn')
				elseif element.idChosen == 'momentary' then
					self.duration = "momentary"
				elseif element.idChosen == 'end_of_next_turn' or element.idChosen == 'until_rest' or element.idChosen == 'until_long_rest' or element.idChosen == 'endround' or element.idChosen == 'save_ends' or element.idChosen == "eoe_or_dying" or element.idChosen == "eoe" or element.idChosen == 'endnextround' or element.idChosen == 'eoe' then
					self.duration = element.idChosen
				else
					self.duration = nil
				end
				parentPanel:FireEvent('refreshBehavior')
			end
		},
	}

	if idChosen == 'rounds' or idChosen == 'rounds_end_turn' then
		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "",
			},
			gui.Input{
				classes = "formInput",
				text = tostring(self.duration),
				events = {
					change = function(element)
						self.duration = math.floor(tonumber(element.text)) or 1
					end
				}
			},
		}
	end

	if self.stacks ~= false then
		list[#list+1] = gui.Panel{
			classes = "formPanel",
			gui.Label{
				classes = "formLabel",
				text = "Stacks:",
			},
			gui.GoblinScriptInput{
				value = self.stacks,
				change = function(element)
					self.stacks = element.value
				end,

				documentation = {
					domains = parentPanel.data.parentAbility.domains,
					help = string.format("This GoblinScript is used to determine the number of stacks of the ongoing effect to apply."),
					output = "number",
					examples = {
						{
							script = "1",
							text = "1 stack will be applied. Using a simple number is a common use of this script.",
						},
						{
							script = "2 + upcast",
							text = "2 stacks will be applied, and an additional stack will be applied for every level the spell slot used for this spell is above the spell's level.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature using the ability",
					symbols = ActivatedAbility.helpCasting,
				},
			},
		}
	end

	local ongoingEffectsChoices = {}
	if not self:has_key("ongoingEffect") then
		ongoingEffectsChoices[#ongoingEffectsChoices+1] = {
			id = "none",
			text = "Custom Effect",
		}
	end

	local ongoingEffectTable = dmhub.GetTable("characterOngoingEffects") or {}
	for k,effect in pairs(ongoingEffectTable) do
		if not effect:try_get("hidden") then
			ongoingEffectsChoices[#ongoingEffectsChoices+1] = {
				id = k,
				text = effect.name,
			}
		end
	end

	table.sort(ongoingEffectsChoices, function(a,b) return a.text < b.text end)

	local editEffectButton = nil

	if (not self:try_get("ongoingEffect")) or (self.ongoingEffect == self:try_get("ongoingEffectCustom")) or (not self:has_key("ongoingEffectCustom")) then
		editEffectButton = gui.Button{
			width = 120,
			height = 28,
			halign = "right",
			text = "Edit Effect",
			fontSize = 16,
			click = function(element)
				local ongoingEffectTable = dmhub.GetTable("characterOngoingEffects") or {}
				if not self:try_get("ongoingEffect") or ongoingEffectTable[self.ongoingEffect] == nil then
					local ongoingEffect = CharacterOngoingEffect.Create()
					ongoingEffect.custom = true --marks this as attached to an ability. Maybe don't show as a general effect?
					if options.transform then
						ongoingEffect.name = "Transformation"
						ongoingEffect.transformation = true
						ongoingEffect.modifiers = {
							dmhub.DeepCopy(CharacterModifier.StandardModifiers.TransformIntoBeast)
						}
						ongoingEffect.modifiers[1].deletable = false
					end

					self.ongoingEffect = dmhub.SetAndUploadTableItem("characterOngoingEffects", ongoingEffect)
					self.ongoingEffectCustom = self.ongoingEffect
				end

				element.root:AddChild(CharacterOngoingEffect.CreateOngoingEffectEditorDialog{
					ongoingEffectid = self.ongoingEffect
				})
			end,
		}
	end

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Ongoing Effect:",
		},

		gui.Dropdown{
			classes = "formDropdown",
			options = ongoingEffectsChoices,
			hasSearch = true,
			idChosen = self:try_get("ongoingEffect", "none"),
			change = function(element)
				if element.idChosen ~= "none" then
					self.ongoingEffect = element.idChosen
					if not self:has_key("ongoingEffectCustom") then
						self.ongoingEffectCustom = false
					end
					parentPanel:FireEvent('refreshBehavior')
				end
			end,
		},

		editEffectButton
	}

    local ongoingEffect = dmhub.GetTable("characterOngoingEffects")[self:try_get("ongoingEffect", "none")]

    if ongoingEffect ~= nil and ongoingEffect.casterTracking == "set" then
	    local helpCasting = dmhub.DeepCopy(ActivatedAbility.helpCasting)
        list[#list+1] = gui.Panel{
            classes = "formPanel",
            gui.Label{
                classes = "formLabel",
                text = "Caster ID:",
            },

            gui.GoblinScriptInput{
                value = self:try_get("casteridFormula", ""),
                change = function(element)
                    self.casteridFormula = element.value
                end,

                documentation = {
                    domains = parentPanel.data.parentAbility.domains,
                    help = string.format("This GoblinScript is used to determine the creature who will be considered to have inflicted the ongoing effect."),
                    output = "number",
                    examples = {
                        {
                            script = "target.id",
                            text = "The target will be considered to have inflicted the ongoing effect.",
                        },
                    },
                    subject = creature.helpSymbols,
                    subjectDescription = "The caster is the subject of this GoblinScript.",
                    symbols = helpCasting,
                },
            }
        }
    end
end

function ActivatedAbilityBehavior:DamageTypeEditor(parentPanel, list)

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Damage Type:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = rules.damageTypesAvailable,
			idChosen = self.damageType,
			change = function(element)
				self.damageType = element.idChosen
			end,
		},
	}
	
end

function ActivatedAbilityBehavior:AttackTriggeredAbilityEditor(parentPanel, list)

	list[#list+1] = gui.Check{
		text = "Trigger effect on hit",
		value = self:has_key("attackTriggeredAbility"),
		halign = "left",
		change = function(element)
			if element.value == false then
				self.attackTriggeredAbility = nil
			else
				self.attackTriggeredAbility = AttackTriggeredAbility.Create()
			end
			parentPanel:FireEvent('refreshBehavior')
		end,
	}

	if self:has_key("attackTriggeredAbility") then
		list[#list+1] = gui.Button{
			width = 160,
			height = 32,
			halign = "left",
			text = "Edit Effect",
			fontSize = 20,
			click = function(element)
				element.root:AddChild(self.attackTriggeredAbility:ShowEditActivatedAbilityDialog{})
			end,
		}
	end
	
end

function ActivatedAbilityBehavior:AuraEditor(parentPanel, list)

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Duration:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = {
                {
                    id = "none",
                    text = "Indefinite",
                },
				{
					id = "endturn",
					text = "Until End of Turn",
				},
                {
                    id = "nextturn",
                    text = "Until Start of Next Turn",
                },
                {
                    id = "endnextturn",
                    text = "Until End of Next Turn",
                },
                {
                    id = "endround",
                    text = "Until End of Round",
                },
                {
                    id = "endnextround",
                    text = "Until End of Next Round",
                },
                {
                    id = "eoe",
                    text = "Until End of Encounter",
                },
            },
			idChosen = self.duration,
			change = function(element)
				self.duration = element.idChosen
				parentPanel:FireEvent('refreshBehavior')
			end,
		},
	}

    list[#list+1] = gui.Check{
        text = "Destroy on Death",
        value = not self:try_get("aliveafterdeath", false),
        change = function(element)
            self.aliveafterdeath = not element.value
			parentPanel:FireEvent('refreshBehavior')
        end,
    }

	list[#list+1] = gui.Button{
		width = 160,
		height = 32,
		halign = "left",
		text = "Edit Aura",
		fontSize = 20,
		click = function(element)
			if not self:has_key("aura") then
				self.aura = Aura.Create{}
			end
			element.root:AddChild(self.aura:ShowEditDialog{})
		end,
	}
end

function ActivatedAbilityBehavior:MomentaryEffectEditor(parentPanel, list)

	list[#list+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Effect Name:",
		},

		gui.Input{
			classes = "formInput",
			text = tostring(self.momentaryEffect:try_get("name", "")),
			events = {
				change = function(element)
					self.momentaryEffect.name = element.text

					--make sure any modifiers also get the name
					for i,mod in ipairs(self.momentaryEffect.modifiers) do
						mod.name = element.text
					end
				end
			}
		},
	}

	list[#list+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Description:",
		},

		gui.Input{
			classes = "formInput",
			text = tostring(self.momentaryEffect:try_get("description", "")),
			events = {
				change = function(element)
					self.momentaryEffect.description = element.text

					--make sure any modifiers also get the description
					for i,mod in ipairs(self.momentaryEffect.modifiers) do
						mod.description = element.text
					end
				end
			}
		},
	}

    list[#list+1] = gui.Check{
        text = "Apply Instantly at Start",
        value = self.instant,
        change = function(element)
            self.instant = element.value
        end,
    }

	list[#list+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Linger Time:",
		},

		gui.Input{
			classes = "formInput",
			text = tostring(self:try_get("lingerTime", 0)),
			events = {
				change = function(element)
					self.lingerTime = tonumber(element.text) or 0
				end
			}
		},
	}

	list[#list+1] = self.momentaryEffect:EditorPanel{collapseDescription = true, noscroll = true}
end

function ActivatedAbilityBehavior:ForcedMovementEditor(parentPanel, list)
	local helpCasting = dmhub.DeepCopy(ActivatedAbility.helpCasting)
	helpCasting.target = {
		name = "Target",
		type = "creature",
		desc = "The creature being targeted by this ability.",
		examples = {
			"10 when Target.Size <= 2 else 5",
		},
	}

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Movement Type:",
		},
		gui.Dropdown{
			classes = "formDropdown",
			options = ActivatedAbilityForcedMovementBehavior.moveTypeOptions,
			idChosen = self.moveType,
			change = function(element)
				self.moveType = element.idChosen

				parentPanel:FireEvent('refreshBehavior')
			end,
		},
	}

	
	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "Distance:",
		},
		gui.GoblinScriptInput{
			value = self.distance,
			change = function(element)
				self.distance = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine the distance this ability moves its targets, in feet"),
				output = "number",
				examples = {
					{
						script = "20",
						text = "Targets will be moved 20 feet by this ability",
					},
					{
						script = "20 when Target.Size < Size else 10",
						text = "Targets smaller than the creature using the ability will be moved 20 feet, other creatures will be moved 10 feet.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability is the main subject.",
				symbols = helpCasting,
			},

		},
	}
end

--'half'/'none'
ActivatedAbilityBehavior.dcsuccess = 'half'

function ActivatedAbilityBehavior:DCEditor(parentPanel, list)

	local options = {
		{
			id = 'none',
			text = 'None',
		},
		{
			id = 'multi',
			text = 'Multiple',
		},
	}

	for i,saveInfo in ipairs(creature.savingThrowDropdownOptions) do
		options[#options+1] = saveInfo
	end

	local idChosen = self:try_get('dc', 'none')
	if type(idChosen) == "table" then
		idChosen = 'multi'
	end

end

function ActivatedAbilityBehavior:TemporaryHitpointsEditor(parentPanel, list)
	list[#list+1] = gui.Check{
		text = "Gain Temporary Stamina",
		value = self.hasTemporaryHitpoints,
		change = function(element)
			self.hasTemporaryHitpoints = element.value
			element.root:FireEventTree("refreshTemporaryHitpoints")
		end,
	}

	list[#list+1] = gui.Panel{
		classes = {"formPanel", cond(self.hasTemporaryHitpoints, nil, "collapsed-anim")},
		refreshTemporaryHitpoints = function(element)
			element:SetClass("collapsed-anim", not self.hasTemporaryHitpoints)
		end,
		gui.Label{
			classes = "formLabel",
			text = "Temporary Stamina:",
		},
		gui.GoblinScriptInput{
			classes = "formInput",
			value = self.temporaryHitpoints,
			change = function(element)
				self.temporaryHitpoints = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = "This GoblinScript is used to determined the amount of temporary stamina granted by an <color=#00FFFF><link=ability>ability</link></color>.",
				output = "number",
				examples = {
					{
						script = "5",
						text = "Make the ability grant 5 temporary stamina.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature using the ability",
			},
		},
	}
end

function ActivatedAbilityAugmentedAbilityBehavior.AbilityModifierEditor(self, parentPanel, list)
	local element = gui.Panel{
		x = 20,
		width = "auto",
		height = "auto",
		flow = "vertical",
	}

	local typeInfo = CharacterModifier.TypeInfo[self.modifier.behavior] or {}
	local createEditor = typeInfo.createEditor
	if createEditor ~= nil then
		createEditor(self.modifier, element)
	end

	list[#list+1] = element
end

function ActivatedAbilityCastSpellBehavior.AbilityModifierEditor(self, parentPanel, list)

	list[#list+1] = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",

		create = function(element)
			element:FireEvent("refreshCastSpell")
		end,
		refreshCastSpell = function(element)
			local children = {}

			for k,v in pairs(self.spells) do
				local name = dmhub.GetTable(Spell.tableName)[k].name
				local panel = gui.Panel{
					data = {
						ord = name
					},
					width = 240,
					height = 22,
					flow = "horizontal",
					gui.Label{
						classes = {"formLabel"},
						width = 200,
						text = name,
					},
					gui.DeleteItemButton{
						width = 16,
						height = 16,
						click = function(element)
							self.spells[k] = nil
							parentPanel:FireEventTree("refreshCastSpell")
						end,
					},
				}

				children[#children+1] = panel
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			element.children = children
		end,
	}

	local options = {}
	for k,v in pairs(dmhub.GetTable(Spell.tableName) or {}) do
		options[#options+1] = {
			id = k,
			text = v.name,
		}
	end

	table.sort(options, function(a,b) return a.text < b.text end)

	list[#list+1] = gui.Dropdown{
		hasSearch = true,
		options = options,
		idChosen = nil,
		textOverride = "Add Spell...",
		change = function(element)
			self.spells[element.idChosen] = true
			element.idChosen = nil
			parentPanel:FireEventTree("refreshCastSpell")
		end,
	}

	ActivatedAbilityAugmentedAbilityBehavior.AbilityModifierEditor(self, parentPanel, list)
end

function ActivatedAbilityBehavior:CheckTypeEditor(parentPanel, title, attributeName, list)

	local attributes = self:get_or_add(attributeName, {})
	local attrSet = {}
	for i,attr in ipairs(attributes) do
		attrSet[attr] = true
	end

	local options = {
		{
			id = "none",
			text = "Add Roll Option...",
		}
	}


	for i,attrid in ipairs(creature.attributeIds) do
		if not attrSet[attrid] then
			options[#options+1] = {
				id = attrid,
				text = creature.attributesInfo[attrid].description,
			}
		end
	end

	for i,skillInfo in ipairs(Skill.SkillsInfo) do
		if not attrSet[skillInfo.id] then
			options[#options+1] = {
				id = skillInfo.id,
				text = string.format("%s (%s)", skillInfo.name, creature.attributesInfo[skillInfo.attribute].description),
			}
		end
	end

	for i,attr in ipairs(attributes) do
		local deleteItem = nil

		if #attributes > 1 then
			deleteItem = gui.DeleteItemButton{
				halign = "right",
				width = 16,
				height = 16,
				click = function(element)
					table.remove(attributes, i)
					parentPanel:FireEvent('refreshBehavior')
				end,
			}
		end

		local name = ActivatedAbilityContestedAttackBehavior.CheckNameFromId(attr)
		local attributeOptions = DeepCopy(options)
		attributeOptions[1].text = name

		list[#list+1] = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = "formLabel",
				text = title,
			},

			gui.Dropdown{
				classes = "formDropdown",
				options = attributeOptions,
				idChosen = "none",
				change = function(element)
					if element.idChosen ~= "none" then
						attributes[i] = element.idChosen
					end
					parentPanel:FireEvent('refreshBehavior')
				end,
			},

			deleteItem,
		}
	end

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Dropdown{
			classes = "formDropdown",
			options = options,
			idChosen = "none",
			change = function(element)
				if element.idChosen ~= "none" then
					attributes[#attributes+1] = element.idChosen
				end
				parentPanel:FireEvent('refreshBehavior')
			end
		},
	}

end

local g_modalPanelStyles = {
    gui.Style{
        selectors = {"label"},

        borderWidth = 2,
        halign = "left",
        bgimage = "panels/square.png",
        borderColor = Styles.backgroundColor,
        bgcolor = Styles.backgroundColor,
        bold = true,
        color = Styles.textColor,
        width = "auto",
        height = "auto",
        fontSize = 16,
        textAlignment = "left",
        hpad = 12,
        vpad = 4,
    },
    gui.Style{
        selectors = {"label", "selected"},
        color = "#000000AA",
        bgcolor = Styles.textColor,
        transitionTime = 0.2,
    },
    gui.Style{
        selectors = {"label", "selected", "disabled"},
        bgcolor = "#ff4444",
    },
    gui.Style{
        selectors = {"label", "hover"},
        brightness = 1.5,
        borderColor = Styles.textColor,
        transitionTime = 0.2,
    },
}

function ActivatedAbilityBehavior:CreateEditor(parentAbility, options)
	local resultPanel

    local modalPanel = gui.Panel{
        styles = g_modalPanelStyles,
        classes = {"collapsed"},
        data = {
            shown = false,
            modeList = nil,
            modesSelected = nil,
        },

        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,

        calculateModal = function(element)
            if element.data.shown == parentAbility.multipleModes and (element.data.shown == false or (dmhub.DeepEqual(element.data.modeList, parentAbility:try_get("modeList", {})) and dmhub.DeepEqual(element.data.modesSelected, self:try_get("modesSelected", {})))) then
                return
            end
            
            element.data.shown = parentAbility.multipleModes

            element:SetClass("collapsed", not parentAbility.multipleModes)

            if not parentAbility.multipleModes then
                return
            end

            element.data.modesSelected = dmhub.DeepCopy(self:try_get("modesSelected", {}))
            element.data.modeList = dmhub.DeepCopy(parentAbility:try_get("modeList", {}))

            local children = {}

            children[#children+1] = gui.Label{
                text = "All Modes",
                classes = {cond(#self:try_get("modesSelected", {}) == 0, "selected")},
                press = function(element)
                    self.modesSelected = nil
                    element.parent:FireEvent("calculateModal")
                end,
            }

            children[#children+1] = gui.Label{
                text = "Disabled",
                classes = {"disabled", cond(table.contains(self:try_get("modesSelected", {}), -1), "selected")},
                press = function(element)
                    self.modesSelected = {-1}
                    element.parent:FireEvent("calculateModal")
                end,
            }

            for i,mode in ipairs(parentAbility.modeList) do
                children[#children+1] = gui.Label{
                    text = mode.text,
                    classes = {cond(table.contains(self:try_get("modesSelected", {}), i), "selected")},
                    press = function(element)
                        if not self:has_key("modesSelected") then
                            self.modesSelected = {}
                        end

                        table.remove_value(self.modesSelected, -1)
                        if table.contains(self.modesSelected, i) then
                            table.remove_value(self.modesSelected, i)
                        else
                            self.modesSelected[#self.modesSelected+1] = i
                        end

                        element.parent:FireEvent("calculateModal")
                    end,
                }
            end

            element.children = children

        end,
    }

    modalPanel:FireEvent("calculateModal")

    local m_tierCache = nil

    local tierPanel = gui.Panel{
        styles = g_modalPanelStyles,
        classes = {"collapsed"},
        data = {
            shown = false,
        },

        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,

        calculateTier = function(element)

            for i,behavior in ipairs(parentAbility.behaviors) do
                if behavior == self then
                    element:SetClass("collapsed", true)
                    return
                end

                if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                    break
                end
            end

            element:SetClass("collapsed", false)

            local tierInfo = {tiersSelected = self:try_get("tiersSelected")}
            if dmhub.DeepEqual(tierInfo, m_tierCache) then
                return
            end

            m_tierCache = dmhub.DeepCopy(tierInfo)

            local children = {}

            children[#children+1] = gui.Label{
                text = "All Tiers",
                classes = {cond(#self:try_get("tiersSelected", {}) == 0, "selected")},
                press = function(element)
                    self.tiersSelected = nil
                    element.parent:FireEvent("calculateTier")
                end,
            }

            children[#children+1] = gui.Label{
                text = "Disabled",
                classes = {"disabled", cond(table.contains(self:try_get("tiersSelected", {}), -1), "selected")},
                press = function(element)
                    self.tiersSelected = {-1}
                    element.parent:FireEvent("calculateTier")
                end,
            }

            for i=1,3 do
                children[#children+1] = gui.Label{
                    text = "Tier " .. i,
                    classes = {cond(table.contains(self:try_get("tiersSelected", {}), i), "selected")},
                    press = function(element)
                        if not self:has_key("tiersSelected") then
                            self.tiersSelected = {}
                        end

                        table.remove_value(self.tiersSelected, -1)
                        if table.contains(self.tiersSelected, i) then
                            table.remove_value(self.tiersSelected, i)
                        else
                            self.tiersSelected[#self.tiersSelected+1] = i
                        end

                        element.parent:FireEvent("calculateTier")
                    end,
                }
            end

            element.children = children

        end,
    }

    tierPanel:FireEvent("calculateTier")


    local m_strainCache = nil

    local strainPanel = gui.Panel{
        styles = g_modalPanelStyles,
        classes = {"collapsed"},
        data = {
            shown = false,
        },

        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,

        calculateStrain = function(element)
            local hasStrain = parentAbility:IsStrain()

            if not hasStrain then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local strainInfo = {strainSelection = self:try_get("strainSelection")}
            if dmhub.DeepEqual(strainInfo, m_strainCache) then
                return
            end

            m_strainCache = dmhub.DeepCopy(strainInfo)

            local children = {}

            children[#children+1] = gui.Label{
                text = "Always",
                classes = {cond(self:try_get("strainSelection") == nil, "selected")},
                press = function(element)
                    self.strainSelection = nil
                    element.parent:FireEvent("calculateStrain")
                end,
            }

            children[#children+1] = gui.Label{
                text = "Unstrained",
                classes = {cond(self:try_get("strainSelection") == "unstrained", "selected")},
                press = function(element)
                    self.strainSelection = "unstrained"
                    element.parent:FireEvent("calculateStrain")
                end,
            }

            children[#children+1] = gui.Label{
                text = "Strained",
                classes = {cond(self:try_get("strainSelection") == "strained", "selected")},
                press = function(element)
                    self.strainSelection = "strained"
                    element.parent:FireEvent("calculateStrain")
                end,
            }

            element.children = children
        end,
    }

    strainPanel:FireEvent("calculateStrain")


	local headerPanel = gui.Panel{
		flow = "horizontal",
		height = 20,
		width = "90%",
		halign = "left",

        thinkTime = 0.2,
        think = function(element)
            modalPanel:FireEvent("calculateModal")
            tierPanel:FireEvent("calculateTier")
            strainPanel:FireEvent("calculateStrain")
        end,

		gui.Label{
			fontSize = 18,
			bold = true,
			text = self.summary,
			width = "auto",
			height = "auto",
			halign = "left",
			rightClick = function(element)

				local entries = {
					{
						text = "Copy Behavior...",
						click = function()
                            element.popup = nil
							dmhub.CopyToInternalClipboard(self)
							resultPanel:FireEventTree("refreshAbility")
						end,
					}
				}

				if options.moveup then
					table.insert(entries, {
						text = "Move Up",
						click = function()
                            element.popup = nil
							options.moveup(self)
						end,
					})
				end

				if options.movedown then
					table.insert(entries, {
						text = "Move Down",
						click = function()
                            element.popup = nil
							options.movedown(self)
						end,
					})
				end
				element.popup = gui.ContextMenu{
					entries = entries,
				}

			end,
		},
		gui.DeleteItemButton{
			halign = "right",
			width = 16,
			height = 16,
			click = function(element)
				resultPanel:FireEvent("delete")
			end,
		},
	}


	local args = {
		flow = "vertical",
		height = "auto",
		width = "100%",

		data = {
			parentAbility = parentAbility,
		},

		refreshBehavior = function(element)
			local children = self:EditorItems(element)
			table.insert(children, 1, modalPanel)
			table.insert(children, 1, tierPanel)
			table.insert(children, 1, strainPanel)
			table.insert(children, 1, headerPanel)
			element.children = children
		end,
	}

	for k,op in pairs(options) do
		args[k] = op
	end

	resultPanel = gui.Panel(args)

	resultPanel:FireEventTree("refreshBehavior")

	return resultPanel
end


function ActivatedAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:RollEditor(parentPanel, result)
	return result
end

ActivatedAbilityDamageBehavior.titleText = ""
ActivatedAbilityDamageBehavior.chatMessage = ""

function ActivatedAbilityDamageBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Roll Title:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.titleText,
            events = {
                change = function(element)
                    self.titleText = element.text
                end
            }
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Log Message:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.chatMessage,
            events = {
                change = function(element)
                    self.chatMessage = element.text
                end
            }
        },
    }


	self:DCEditor(parentPanel, result)
	self:RollEditor(parentPanel, result)
	self:DamageTypeEditor(parentPanel, result)

    result[#result+1] = gui.Check{
        text = "Cannot be Reduced",
        value = self:try_get("cannotBeReduced", false),
        change = function(element)
            self.cannotBeReduced = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Does not Trigger",
        value = self:try_get("doesNotTrigger", false),
        change = function(element)
            self.doesNotTrigger = element.value
        end,
    }

	self:SeparateRollsEditor(parentPanel, result)
	return result
end

function ActivatedAbilityAttackBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:AttackTypeEditor(parentPanel, result)
	self:RollEditor(parentPanel, result)
	self:SeparateRollsEditor(parentPanel, result)
	self:DamageTypeEditor(parentPanel, result)
	self:AttackTriggeredAbilityEditor(parentPanel, result)
	return result
end

function ActivatedAbilityApplyOngoingEffectBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:DCEditor(parentPanel, result)
	self:TemporaryHitpointsEditor(parentPanel, result)
	self:OngoingEffectEditor(parentPanel, result)
	return result
end

function ActivatedAbilityCastSpellBehavior:EditorItems(parentPanel)
	local result = {}
	self:AbilityModifierEditor(parentPanel, result)
	return result
end

function ActivatedAbilityAugmentedAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:AbilityModifierEditor(parentPanel, result)
	return result
end

function ActivatedAbilityAuraBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:AuraEditor(parentPanel, result)
	return result
end

function ActivatedAbilityApplyMomentaryEffectBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:MomentaryEffectEditor(parentPanel, result)
	return result
end

function ActivatedAbilityContestedAttackBehavior:EditorItems(parentPanel)
	local result = {}
	self:CheckTypeEditor(parentPanel, "Attacker Roll", "attackAttributes", result)
	self:CheckTypeEditor(parentPanel, "Defender Roll", "defenseAttributes", result)
	return result
end

function ActivatedAbilityForcedMovementBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:ForcedMovementEditor(parentPanel, result)
	return result
end

function ActivatedAbilityModifiersBehavior:EditorItems(parentPanel)
	local result = {}
	self:FilterEditor(parentPanel, result)
	self:ModifiersEditor(parentPanel, result)
	return result
end


function ActivatedAbility:ShowEditActivatedAbilityDialog(options)
	options = options or {}

	local activatedAbility = self

	local dialogWidth = 1200
	local dialogHeight = 980

	local resultPanel = nil

	local styles = {
		{
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1100,
			height = 840,
		},
	}

	local title = options.title or "Edit Ability"
	options.title = nil


	if options.hide ~= nil then
		for _,item in ipairs(options.hide) do
			styles[#styles+1] = {
				selectors = {item},
				collapsed = 1,
				priority = 10,
			}
		end
	end
	options.hide = nil

	local mainFormPanel = gui.Panel{
		styles = styles,
		vscroll = true,
	}

	local newItem = nil
	
	local deleteButton = nil
	if options.delete ~= nil then
		--we have a delete handler so show a delete button.
		deleteButton = gui.PrettyButton{
			floating = true,
			styles = {
				{
					selectors = {"pretty-button-label"},
					color = "red",
				},
			},
			text = "DELETE",
			halign = "right",
			valign = "bottom",
			vmargin = 60,
			click = function(element)
				resultPanel:FireEvent("delete")
				resultPanel.data.close()
			end,
		}
	end

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},
		}

	if options.add ~= nil then

		closePanel:AddChild(gui.PrettyButton{
			text = 'Create',
			events = {
				click = function(element)
					resultPanel:FireEvent("add")
					resultPanel.data.close()
				end,
			},
		})

		closePanel:AddChild(gui.PrettyButton{
			text = 'Cancel',
			events = {
				click = function(element)
					resultPanel:FireEvent("cancel")
					resultPanel.data.close()
				end,
			},
		})

	else

		closePanel:AddChild(gui.PrettyButton{
			text = 'Close',
			events = {
				click = function(element)
					resultPanel.data.close()
				end,
			},
		})

	end

	if deleteButton ~= nil then
		closePanel:AddChild(deleteButton)
	end

	local titleLabel = gui.Label{
		text = title,
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

	local args = {
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},

		classes = {"framedPanel"},
		styles = Styles.Panel,

		floating = true,

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			element.data.close()
		end,

		data = {
			show = function(editItem)
				newItem = nil

				mainFormPanel.children = {
					editItem:GenerateEditor(),
				}

			end,
			close = function()
				resultPanel:FireEvent("close")
				resultPanel:DestroySelf()
			end,
		},

		children = {

			gui.Panel{
				id = 'content',
				styles = {
					{
						halign = 'center',
						valign = 'center',
						width = '94%',
						height = '94%',
						flow = 'vertical',
					},
				},
				children = {
					titleLabel,
					mainFormPanel,
					closePanel,

				},
			},
		},
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)

	resultPanel.data.show(activatedAbility)

	return resultPanel
end


local mod = dmhub.GetModLoading()

	

function TriggeredAbility:GenerateEditor(options)
	options = options or {}

	local leftPanel = gui.Panel{
		id = "leftPanel",
		halign = "left",
		width = "55%",
		classes = "mainPanel",
	}

	local Refresh
	Refresh = function()
		local children = {}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			children = {
				gui.Label{
					text = "Name:",
					classes = {"formLabel"},
				},
				gui.Input{
					classes = "formInput",
					placeholderText = "Enter Trigger Name...",
					text = self.name,
					change = function(element)
						self.name = element.text
					end,
				},

			},
		}

		if not options.excludeTriggerCondition then

            children[#children+1] = gui.Panel{
                classes = {"abilityInfo", 'formPanel'},
                children = {
                    gui.Label{
                        text = "Subject:",
                        classes = {"formLabel"},
                    },
                    gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
                        options = {
                            {id = "self", text = "Self"},
                            {id = "any", text = "Self or Other Creatures"},
                            {id = "selfandheroes", text = "Self or Other Heroes"},
                            {id = "otherheroes", text = "Other Heroes"},
                            {id = "selfandallies", text = "Self or Allies"},
                            {id = "allies", text = "Allies"},
                            {id = "enemy", text = "Enemy"},
                            {id = "other", text = "Other Creatures"},
                        },
                        idChosen = self:try_get("subject", "self"),
                        change = function(element)
                            self.subject = element.idChosen
                            Refresh()
                        end,
                    },
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"abilityInfo", 'formPanel'},
                children = {
                    gui.Label{
                        text = "When:",
                        classes = {"formLabel"},
                    },
                    gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
                        options = {
                            {id = "always", text = "Always"},
                            {id = "combat", text = "In Combat"},
                        },
                        idChosen = self:try_get("whenActive", "always"),
                        change = function(element)
                            self.whenActive = element.idChosen
                            Refresh()
                        end,
                    },
                },
            }

            local conditionOptions = {
                {id = "none", text = "None"},
            }
            CharacterCondition.FillDropdownOptions(conditionOptions)
            children[#children+1] = gui.Panel{
                classes = {"abilityInfo", 'formPanel'},
                children = {
                    gui.Label{
                        text = "Has Condition:",
                        classes = {"formLabel"},
                    },
                    gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
                        options = conditionOptions,
                        idChosen = self:try_get("characterConditionRequired", "none"),
                        change = function(element)
                            if element.idChosen == "none" then
                                self.characterConditionRequired = nil
                            else
                                self.characterConditionRequired = element.idChosen
                            end
                            Refresh()
                        end,
                    },
                },
            }

            if self:try_get("characterConditionRequired", "none") ~= "none" then
                children[#children+1] = gui.Check{
                    classes = {"abilityInfo"},
                    text = "Condition must be inflicted by you",
                    value = self:try_get("characterConditionInflictedBySelf", false),
                    change = function(element)
                        self.characterConditionInflictedBySelf = element.value
                        Refresh()
                    end,
                }
            end

			local triggerPromptPanel = nil
			local heroicResourceCostPanel = nil

            local chooseTriggerLocal

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Triggering:",
                },
                gui.Dropdown{
                    options = TriggeredAbility.mandatoryTriggerSettings,
                    idChosen = self.mandatory,
                    change = function(element)
                        self.mandatory = element.idChosen
                        heroicResourceCostPanel:SetClass("collapsed", not self:MayBePrompted())
                        triggerPromptPanel:SetClass("collapsed", not self:MayBePrompted())
                        chooseTriggerLocal:SetClass("collapsed", not self:MayBePrompted())
                    end,
                }
            }

            children[#children+1] = gui.Check{
    			classes = {"abilityInfo"},
                text = "Create manual version of this trigger",
                value = self:try_get("hasManualVersion", false),
                change = function(element)
                    self.hasManualVersion = element.value
                end,
            }

            chooseTriggerLocal = children[#children]

            triggerPromptPanel = gui.Panel{
                classes = {"formPanel", cond(not self:MayBePrompted(), "collapsed")},
                gui.Label{
                    text = "Prompt:",
                    classes = {"formLabel"},
                },
                gui.Input{
                    classes = {"formInput"},
                    characterLimit = 300,
                    text = self:try_get("triggerPrompt", ""),
                    change = function(element)
                        self.triggerPrompt = element.text
                    end,
                },
            }

            children[#children+1] = triggerPromptPanel

			heroicResourceCostPanel = gui.Panel{
				classes = {"abilityInfo", "formPanel", cond(not self:MayBePrompted(), "collapsed")},
				gui.Label{
					text = "Resource Cost:",
					classes = {"formLabel"},
				},
				gui.Input{
					classes = {"formInput"},
					placeholderText = "Cost...",
					characterLimit = 3,
					text = cond(self.resourceCost == "none", "", self.resourceNumber),
					change = function(element)
						local text = trim(element.text)
						if tonumber(text) ~= nil then
							self.resourceCost = character.resourceid
							self.resourceNumber = tonumber(text)
						else
							self.resourceCost = "none"
						end

						element.text = cond(self.resourceCost == "none", "", self.resourceNumber)
					end,
				}
			}

			children[#children+1] = heroicResourceCostPanel

            if self:try_get("subject", "self") ~= "self" then
                children[#children+1] = gui.Panel{
                    classes = {"abilityInfo", 'formPanel'},
                    children = {
                        gui.Label{
                            text = "Range:",
                            classes = {"formLabel"},
                        },
						gui.GoblinScriptInput{
							value = self:try_get("subjectRange", ""),
							change = function(element)
								self.subjectRange = element.value
							end,

							documentation = {
								help = string.format("This GoblinScript is used to determine the range at which triggered ability can activate."),
								output = "number",
								subject = creature.helpSymbols,
								subjectDescription = "The creature the ability will trigger on",
								symbols = {subject = {
									name = "Subject",
									type = "creature",
									desc = "The creature that the event occurred on. This will be the same as Self for triggered abilities that only affect self.",
								}
								},
							},

						},
                    }
                }
            end

			--the condition that starts the trigger.
			children[#children+1] = gui.Panel{
				classes = {"abilityInfo", 'formPanel'},
				children = {
					gui.Label{
						text = 'Trigger:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},

						options = TriggeredAbility.GetTriggerDropdownOptions(),
						idChosen = self.trigger,
                        hasSearch = true,

						events = {
							change = function(element)
								self.trigger = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}
		end

		local actionOptions = CharacterResource.GetActionOptions()
		actionOptions[#actionOptions+1] = {
			id = "none",
			text = "None",
		}
		printf("RESOURCE: %s", json(self:ActionResource()))
		children[#children+1] = gui.Panel{
			classes = {"abilityInfo", "formPanel"},
			gui.Label{
				classes = "formLabel",
				text = "Action:",
			},
			gui.Dropdown{
				classes = "formDropdown",
				idChosen = self:ActionResource() or "none",
				options = actionOptions,
				change = function(element)
					if element.idChosen == "none" then
						self.actionResourceId = nil
					else
						self.actionResourceId = element.idChosen
					end
				end,
			},
		}

        children[#children+1] = gui.Panel{
            classes = {"abilityInfo", "formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Despawned Target:",
            },
            gui.Dropdown{
                classes = "formDropdown",
                idChosen = self.despawnBehavior,
                options = self.DespawnBehaviors,
                change = function(element)
                    self.despawnBehavior = element.idChosen
                end,
            }
        }

		local helpSymbols = {
			caster = {
				name = "Caster",
				type = "creature",
				desc = "The creature that controls the aura triggering this ability.\n\n<color=#ffaaaa><i>This field is only available for triggered abilities that are triggered by an aura.</i></color>",
			},
            subject = {
                name = "Subject",
                type = "creature",
                desc = "The creature that the event occurred on. This will be the same as Self for triggered abilities that only affect self.",
            },
		}

		local examples = {
			{
				script = "hitpoints < 5",
				text = "The triggered ability only activates when hitpoints are below 5.",
			},
		}

        local triggerInfo = TriggeredAbility.GetTriggerById(self.trigger)
        if triggerInfo ~= nil then
            for k,v in pairs(triggerInfo.symbols or {}) do
                helpSymbols[k] = v
            end

            for _,example in ipairs(triggerInfo.examples or {}) do
                examples[#examples+1] = example
            end
        end

		children[#children+1] = gui.Panel{
			classes = {'abilityInfo', 'formPanel'},
			gui.Label{
				classes = {'formLabel'},
				text = 'Condition:',
			},
			gui.GoblinScriptInput{
				value = self.conditionFormula,
				change = function(element)
					self.conditionFormula = element.value
				end,

				documentation = {
					help = string.format("This GoblinScript is used to determine whether the triggered ability activates."),
					output = "boolean",
					examples = examples,
					subject = creature.helpSymbols,
					subjectDescription = "The creature the ability will trigger on",
					symbols = helpSymbols,
				},

			},
		}

		children[#children+1] = self:BehaviorEditor()

		leftPanel.children = children
	end

	Refresh()

	local rightPanel = nil

	if not options.excludeAppearance then
		rightPanel = gui.Panel{
			id = "rightPanel",
			classes = "mainPanel",

			self:IconEditorPanel(),

			gui.Input{
				classes = "formInput",
				placeholderText = "Enter Ability Details...",
				multiline = true,
				width = "80%",
				height = "auto",
				halign = "center",
				margin = 8,
				minHeight = 100,
				textAlignment = "topleft",
				characterLimit = 8192,
				text = self.description,
				change = function(element)
					self.description = element.text
				end,
			},
		}
	end

	local resultPanel = gui.Panel{
		styles = {
			Styles.Form,
			{
				classes = {"formPanel"},
				width = 340,
			},
			{
				classes = {"formLabel"},
				halign = "left",
				valign = "center",
			},
			{
				classes = "mainPanel",
				width = "40%",
				height = "auto",
				flow = "vertical",
				valign = "top",
			},
		},
		
		height = "auto",
		width = "100%",
		valign = "top",
		flow = "horizontal",

		leftPanel,

		rightPanel,

	}
	return resultPanel
	
end


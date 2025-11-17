local mod = dmhub.GetModLoading()

local CreateNegotiationDialog

LaunchablePanel.Register {
	name = "Negotiation",
    menu = "game",
	icon = "icons/standard/Icon_App_Negotiation.png",
	halign = "center",
	valign = "center",
	--filtered = function()
	--	return not dmhub.isDM
	--end,
	content = function(options)
		return CreateNegotiationDialog(options)
	end,
}


CreateNegotiationDialog = function(options)
	local token

	if options ~= nil and options.charid ~= nil then
		token = dmhub.GetTokenById(options.charid)
		print("got token", token ~= nil)
	else
		token = dmhub.currentToken
		print("got token 2", token ~= nil)
	end

	if token == nil then
        if options == nil or options.charid == nil then
            gui.ModalMessage {
                title = 'No character selected',
                message = 'You have to choose a character to start a negotiation',
            }
        end

		return
	end



	if token.properties:has_key("negotiation") == false then
		token:BeginChanges()
		token.properties.negotiation = MCDMNegotiation.Create {}
		token:CompleteChanges("Added Negotiation")
	end

	local revealed = false

	local dialog


	--king panel
	dialog = gui.Panel {
		id = "negotiation-dialog",
		monitorGame = token.monitorPath,
		refreshGame = function(self)
			self:FireEventTree("characterupdated")
		end,

		revealed = function(self)
            if revealed then
			    GameHud.PresentDialogToUsers(self, "Negotiation", { charid = token.charid })
            else
                GameHud.HidePresentedDialog()
            end
		end,

		width = 1000,
		height = 800,
		flow = "vertical",

		styles = {

			{

				selectors = { "playeronly", "dm" },
				collapsed = 1,

			},

			{

				selectors = { "dmonly", "player" },
				collapsed = 1,

			},


		},

		--title panel "negotiation"
		gui.Panel {
			flow = "vertical",
			width = "100%",
			height = "auto",

			gui.Label {
				vmargin = 0,
				interactable = false,
				text = "Negotiation",
				width = "auto",
				height = "auto",
				halign = "center",
				tmargin = 7,
				fontSize = 25,
				color = Styles.textColor,
				bold = true,
				minWidth = 160,
				textAlignment = "center",
			},

			gui.Divider {
				vmargin = 4,
			},
		},





		--parent panel for motivations, npc and pitfalls	
		gui.Panel {

			flow = "none",
			width = "100%",
			height = "auto",
			tmargin = 20,

			--mot and pitfalls parent
			gui.Panel {

				flow = "vertical",
				width = "auto",
				height = "auto",
				halign = "left",
				lmargin = 30,

				--motivations text label
				gui.Label {

					text = "Motivations",
					width = "auto",
					height = "auto",
					halign = "center",
					fontSize = 30,






				},

				--motivations parent panel
				gui.Panel {

					flow = "vertical",
					width = 320,
					height = 180,
					halign = "center",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					vscroll = true,







					--1 motivation parent panel
					gui.Panel {

						tmargin = 7,
						flow = "vertical",
						width = "100%",
						height = "auto",
						x = 10,


						characterupdated = function(self)
							local motivationPanels = {}
							local motivations = token.properties.negotiation.motivations

							for motivationname, motivationinfo in pairs(motivations) do
								motivationPanels[#motivationPanels + 1] =

								--motivation diamond + text parent (square bg)
									gui.Panel {

										bgimage = "panels/square.png",
										bgcolor = "black",
										halign = "center",
										bmargin = 7,
										width = 250,
										height = 38,
										border = 3,
										borderColor = Styles.textColor,


										rightClick = function(self)
											if not dmhub.isDM then
												return
											end

											self.popup = gui.ContextMenu {

												halign = "right",
												entries = {

													{

														text = "delete",
														click = function()
															self.popup = nil
															local motivations = token.properties.negotiation.motivations
															token:BeginChanges()
															motivations[motivationname] = nil

															token:CompleteChanges("Added motivation")
														end,

													}


												}




											}
										end,

										--motivation checkbutton parent
										gui.Diamond {


											valign = "center",
											lmargin = -15,
											value = motivationinfo.revealed,
											editable = dmhub.isDM,
											change = function(self)
												print("vvv gobliini")

												token:BeginChanges()
												motivationinfo.revealed = self.value
												token:CompleteChanges("Reveal motivation")

												self.parent:SetClassTree("revealed", motivationinfo.revealed)
											end,

											create = function(self)
												self.parent:SetClassTree("revealed", motivationinfo.revealed)
											end,

										},



										--? text label
										gui.Label {




											valign = "center",
											text = motivationname,
											width = "auto",
											height = "auto",
											halign = "center",
											fontSize = 30,
											floating = true,

											styles = {

												{

													selectors = "~revealed",
													color = "red",
													strikethrough = true,


												},

												{

													selectors = { "~revealed", "player" },
													collapsed = true,

												},



											},






										},

										gui.Label {




											valign = "center",
											text = "?",
											width = "auto",
											height = "auto",
											halign = "center",
											fontSize = 30,
											floating = true,

											styles = {

												{

													selectors = "~player",
													collapsed = true,



												},

												{

													selectors = "revealed",
													collapsed = true,

												},



											},






										},

									}
							end


							self.children = motivationPanels
						end,

					},

					gui.AddButton {

						classes = { "hideForPlayers" },
						halign = "center",
						tmargin = 5,
						tooltip = "Add Motivation",
						popupPositioning = "panel",
						click = function(self)
							self.tooltip = nil

							local entries = {}

							for motivationname, motivation in pairs(MCDMMotivation.GetMotivations()) do
								entries[#entries + 1] = {


									text = motivation.name,
									click = function()
										self.popup = nil

										local motivations = token.properties.negotiation.motivations
										token:BeginChanges()
										motivations[motivationname] = {

											revealed = false, used = false

										}
										token:CompleteChanges("Added motivation")
									end,


								}
							end

							self.popup = gui.ContextMenu {

								halign = "center",
								entries = entries




							}
						end

					},

				},

				--pitfalls text label
				gui.Label {

					text = "Pitfalls",
					width = "auto",
					height = "auto",
					halign = "center",
					fontSize = 30,



				},

				--pitfalls parent panel
				gui.Panel {

					flow = "vertical",
					width = 320,
					height = 180,
					halign = "center",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					vscroll = true,





					--1 pitfall parent panel
					gui.Panel {

						tmargin = 7,
						flow = "vertical",
						width = "100%",
						height = "auto",
						x = 10,



						characterupdated = function(self)
							local pitfallPanels = {}
							local pitfalls = token.properties.negotiation.pitfalls

							for pitfallname, pitfallinfo in pairs(pitfalls) do
								pitfallPanels[#pitfallPanels + 1] =

								--pitfall diamond + text parent (square bg)
									gui.Panel {

										bgimage = "panels/square.png",
										bgcolor = "black",
										halign = "center",
										bmargin = 7,
										width = 250,
										height = 38,
										border = 3,
										borderColor = Styles.textColor,

										rightClick = function(self)
											if not dmhub.isDM then
												return
											end

											self.popup = gui.ContextMenu {

												halign = "right",
												entries = {

													{

														text = "delete",
														click = function()
															self.popup = nil
															local pitfalls = token.properties.negotiation.pitfalls
															token:BeginChanges()
															pitfalls[pitfallname] = nil

															token:CompleteChanges("Added pitfall")
														end,

													}


												}




											}
										end,

										--pitfall checkbutton parent
										gui.Diamond {


											valign = "center",
											lmargin = -15,
											value = pitfallinfo.revealed,
											editable = dmhub.isDM,
											change = function(self)
												print("vvv gobliini2")

												token:BeginChanges()
												pitfallinfo.revealed = self.value
												token:CompleteChanges("Reveal pitfall")

												self.parent:SetClassTree("revealed", pitfallinfo.revealed)
											end,

											create = function(self)
												self.parent:SetClassTree("revealed", pitfallinfo.revealed)
											end,

										},






										--? text label
										gui.Label {

											valign = "center",
											text = pitfallname,
											width = "auto",
											height = "auto",
											halign = "center",
											fontSize = 30,
											floating = true,



											styles = {

												{

													selectors = "~revealed",
													color = "red",
													strikethrough = true,


												},

												{

													selectors = { "~revealed", "player" },
													collapsed = true,

												},



											},






										},

										gui.Label {




											valign = "center",
											text = "?",
											width = "auto",
											height = "auto",
											halign = "center",
											fontSize = 30,
											floating = true,

											styles = {

												{

													selectors = "~player",
													collapsed = true,



												},

												{

													selectors = "revealed",
													collapsed = true,

												},



											},






										},


									}
							end


							self.children = pitfallPanels
						end,

					},




					gui.AddButton {

						classes = { "hideForPlayers" },
						halign = "center",
						tmargin = 5,
						tooltip = "Add Pitfall",
						popupPositioning = "panel",
						click = function(self)
							self.tooltip = nil

							local entries = {}

							for pitfallname, pitfall in pairs(MCDMPitfall.GetPitfalls()) do
								entries[#entries + 1] = {


									text = pitfall.name,
									click = function()
										self.popup = nil

										local pitfalls = token.properties.negotiation.pitfalls
										token:BeginChanges()
										pitfalls[pitfallname] = {

											revealed = false, used = false

										}
										token:CompleteChanges("Added pitfall")
									end,


								}
							end

							self.popup = gui.ContextMenu {

								halign = "center",
								entries = entries




							}
						end

					},





				},

			},


			--npc parent panel
			gui.Panel {

				flow = "vertical",
				width = "auto",
				height = "auto",
				halign = "center",


				--npc image panel
				gui.Panel {

					bgimage = token.portrait,
					imageRect = token:GetPortraitRectForAspect(220 / 300),
					bgcolor = "white",
					width = 220,
					height = 300,

					borderWidth = 3.5,
					borderColor = Styles.textColor,



				},

				-- npc name label
				gui.Label {

					text = cond(token.namePrivate, "???", token:GetNameMaxLength(30)),
					textAlignment = "center",
					fontSize = 30,
					bgimage = "panels/square.png",
					tmargin = -2,
					width = 220,
					height = 40,
					valign = "top",
					halign = "center",
					border = { x1 = 3.5, y1 = 3.5, x2 = 3.5, y2 = 0 },
					borderColor = Styles.textColor,


				},

			},


			--speechbubble and offer parent panel
			gui.Panel {

				flow = "vertical",
				width = "auto",
				height = "auto",
				halign = "right",
				rmargin = 25,



				--bubble triangel image
				gui.Panel {

					bgimage = mod.images.bubble,
					bgcolor = "white",
					width = 84,
					height = 120,
					valign = "top",
					halign = "left",
					y = 60,
					floating = true,






				},

				--speechbubble panel
				gui.Label {

					text = "\"Fine! I suppose I can spare some of them...\"",
					textAlignment = "center",
					fontSize = 20,
					bgimage = "panels/square.png",
					bgcolor = "black",
					width = 340,
					height = 130,
					valign = "top",
					border = 2.5,
					borderColor = Styles.textColor,
					editable = dmhub.isDM,

					characterupdated = function(self)
						local text = token.properties.negotiation.dialog.interest
							[token.properties.negotiation.interest + 1]
						self.text = text

						if token.properties.negotiation.switch == false then
							local text = token.properties.negotiation.dialog.patience
								[token.properties.negotiation.patience + 1]
							self.text = text
						end
					end,

					change = function(self)
						token:BeginChanges()

						if token.properties.negotiation.switch == false then
							token.properties.negotiation.dialog.patience[token.properties.negotiation.patience + 1] =
								self.text
						else
							token.properties.negotiation.dialog.interest[token.properties.negotiation.interest + 1] =
								self.text
						end

						token:CompleteChanges("Dialog changed")
					end,

					--square panel
					gui.Panel {

						classes = { "hideForPlayers" },
						height = "100%-4",
						width = "100%-4",
						bgimage = "panels/square.png",
						bgcolor = "black",
						opacity = 0.96,
						floating = true,
						halign = "center",
						valign = "center",
						interactable = false,


						styles = {

							{

								hidden = true,
								selectors = { "~pencil" },

							},

							{

								selectors = { "parent:hover", "~parent:editing" },
								hidden = false,

							},

							{

								selectors = { "hideForPlayers", "player" },
								hidden = true,

							},

						},



						gui.Panel {


							width = 30,
							height = 30,
							bgimage = "ui-icons/pencil.png",
							bgcolor = Styles.textColor,
							halign = "center",
							valign = "center",
							interactable = false,

							classes = { "pencil", "hideForPlayers" },


						},


					},


				},

				--offer text
				gui.Label {

					text          = "Offer",
					textAlignment = "center",
					fontSize      = 30,
					bgimage       = "panels/square.png",
					bgcolor       = "clear",
					width         = 100,
					height        = 20,
					halign        = "center",
					valign        = "top",
					tmargin       = 40,



				},

				--offer panel
				gui.Label {

					text = "Velalyn will let the peasants go but she will execute the nobles.",
					editable = dmhub.isDM,
					textAlignment = "center",
					fontSize = 20,
					bgimage = "panels/square.png",
					bgcolor = "clear",
					width = 340,
					height = 130,
					tmargin = 10,
					valign = "top",
					border = 2.5,
					borderColor = Styles.textColor,

					characterupdated = function(self)
						local text = token.properties.negotiation.dialog.offer
						[token.properties.negotiation.interest + 1]
						self.text = text
					end,

					change = function(self)
						token:BeginChanges()

						token.properties.negotiation.dialog.offer[token.properties.negotiation.interest + 1] = self.text

						token:CompleteChanges("Offer Dialog changed")
					end,

					--square panel
					gui.Panel {

						classes = { "hideForPlayers" },
						height = "100%-4",
						width = "100%-4",
						bgimage = "panels/square.png",
						bgcolor = "black",
						opacity = 0.96,
						floating = true,
						halign = "center",
						valign = "center",
						interactable = false,


						styles = {

							{

								hidden = true,
								selectors = { "~pencil" },

							},

							{

								selectors = { "parent:hover", "~parent:editing" },
								hidden = false,

							},

							{

								selectors = { "hideForPlayers", "player" },
								hidden = true,

							},



						},



						gui.Panel {


							width = 30,
							height = 30,
							bgimage = "ui-icons/pencil.png",
							bgcolor = Styles.textColor,
							halign = "center",
							valign = "center",
							interactable = false,

							classes = { "pencil", "hideForPlayers" },


						},


					},


					-- button accept
					gui.Button {

						text = "Accept",
						fontSize = 22,
						width = 220,
						height = 40,
						valign = "bottom",
						halign = "center",
						bmargin = -20,
						classes = { "playeronly" },

						click = function(self)
							if token.properties.negotiation.accepted[dmhub.userid] ~= true then
								self.text = "Cancel"
								token:BeginChanges()
								token.properties.negotiation.accepted[dmhub.userid] = true
								token:CompleteChanges("Accepted by player")
							else
								self.text = "Accept"
								token:BeginChanges()
								token.properties.negotiation.accepted[dmhub.userid] = false
								token:CompleteChanges("Cancel Accept")
							end
						end,



					},


				},


				--offer checkbutton parent
				gui.Panel {

					minWidth = 200,
					width = "auto",
					height = "auto",
					flow = "horizontal",
					halign = "center",
					valign = "top",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					tmargin = 20,


					create = function(self)
						local diamonds = {}
						local users = dmhub.users
						for i, userid in ipairs(users) do
							--create diamond here
							if not dmhub.IsUserDM(userid) then
								local sessionInfo = dmhub.GetSessionInfo(userid)
								diamonds[#diamonds + 1] =
									gui.Diamond {

										characterupdated = function(self)
											self.value = token.properties.negotiation.accepted[userid]
											print("vvv working!", userid, token.properties.negotiation.accepted[userid])
										end,
										click = function(self)
											if dmhub.isDM then
												token:BeginChanges()
												token.properties.negotiation.accepted[userid] = not token.properties
													.negotiation.accepted[userid]
												token:CompleteChanges("Director override offer")
											end
										end,

										hover = function(element)
											print("VENLA: hover");
											if token.properties.negotiation.accepted[userid] ~= true then
												gui.Tooltip(string.format("%s has not accepted", sessionInfo.displayName))(
													element)
											else
												gui.Tooltip(string.format("%s has accepted", sessionInfo.displayName))(
													element)
											end
										end,
										halign = "center",
										fillColor = sessionInfo.displayColor,
										--tooltip = sessionInfo.displayName,


									}
							end
						end

						self.children = diamonds
					end,

					gui.Diamond {

						halign = "center",
						fillColor = "red",

					},


					gui.Diamond {

						halign = "center",
						fillColor = "green",

					},


					gui.Diamond {

						halign = "center",
						fillColor = "blue",



					},

				},


			},

		},


		gui.Panel {

			--interest and patience parent panel + buttons
			flow = "vertical",
			width = 900,
			height = 470,
			tmargin = 10,
			halign = "center",
			bgimage = "panels/square.png",

			--interest text
			gui.Label {

				width = "auto",
				text = "Interest",
				fontSize = 30,
				halign = "center",



			},

			--interest bar parent panel
			gui.Panel {

				flow = "none",
				width = 1000,
				height = 30,
				halign = "center",
				bgimage = "panels/square.png",
				bgcolor = "clear",


				--interest minus button
				gui.Panel {

					classes = { "hideForPlayers" },
					bgimage = "panels/square.png",
					bgcolor = "clear",
					width = 20,
					height = 20,
					valign = "center",
					halign = "left",
					lmargin = 15,
					borderWidth = 1.5,
					cornerRadius = 1,
					borderColor = Styles.textColor,
					click = function(self)
						token:BeginChanges()
						token.properties.negotiation.interest = token.properties.negotiation.interest - 1
						token.properties.negotiation.switch = true


						if token.properties.negotiation.interest < 0 then
							token.properties.negotiation.interest = 0
						end
						token:CompleteChanges("Increased Interest")

						dialog:FireEventTree("refresh")
					end,

					gui.Label {

						width = 20,
						height = 20,
						text = "-",
						fontFace = "dubai",
						textAlignment = "center",







					},



				},

				--interest bar
				gui.Panel {

					flow = "horizontal",
					width = 900,
					height = 18,
					valign = "center",
					halign = "center",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					border = 2.5,
					borderColor = Styles.textColor,


					--interest fill
					gui.Panel {

						id = "interest",
						flow = "horizontal",
						floating = true,
						height = 18,
						valign = "center",
						halign = "left",
						bgimage = "panels/square.png",
						bgcolor = "white",
						border = 2.5,
						borderColor = Styles.textColor,

						styles = {


							{

								gradient = Styles.healthGradient,

							},

							{
								selectors = "bloodied",
								transitionTime = 0.35,
								gradient = Styles.bloodiedGradient,

							},

							{
								selectors = "damaged",
								transitionTime = 0.35,
								gradient = Styles.damagedGradient,

							},


						},

						refresh = function(self)
							TransitionStyle(self, 0.35, {

								width = 900 * token.properties.negotiation.interest / 5


							})



							if token.properties.negotiation.interest == 1 then
								self:SetClass("damaged", true)
								self:SetClass("bloodied", false)
							end

							if token.properties.negotiation.interest == 2 or token.properties.negotiation.interest == 3 then
								self:SetClass("damaged", false)
								self:SetClass("bloodied", true)
							end

							if token.properties.negotiation.interest == 4 or token.properties.negotiation.interest == 5 then
								self:SetClass("damaged", false)
								self:SetClass("bloodied", false)
							end
						end,





					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 18,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 18,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 18,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 18,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},



				},

				--interest plus button
				gui.Panel {

					classes = { "hideForPlayers" },
					bgimage = "panels/square.png",
					bgcolor = "clear",
					width = 20,
					height = 20,
					valign = "center",
					halign = "right",
					rmargin = 15,
					borderWidth = 1.5,
					cornerRadius = 1,
					borderColor = Styles.textColor,

					click = function(self)
						token:BeginChanges()
						token.properties.negotiation.interest = token.properties.negotiation.interest + 1
						token.properties.negotiation.switch = true

						if token.properties.negotiation.interest > 5 then
							token.properties.negotiation.interest = 5
						end

						token:CompleteChanges("Increased Interest")

						dialog:FireEventTree("refresh")
					end,

					gui.Label {

						width = 20,
						height = 20,
						text = "+",
						fontFace = "dubai",
						textAlignment = "center",







					},

				},


			},

			--patience text
			gui.Label {

				width = "auto",
				text = "Patience",
				fontSize = 30,
				halign = "center",



			},

			--patience bar parent panel
			gui.Panel {

				flow = "none",
				width = 1000,
				height = 30,
				halign = "center",
				bgimage = "panels/square.png",
				bgcolor = "clear",

				--patience minus button
				gui.Panel {

					classes = { "hideForPlayers" },
					bgimage = "panels/square.png",
					bgcolor = "clear",
					width = 20,
					height = 20,
					valign = "center",
					halign = "left",
					lmargin = 15,
					borderWidth = 1.5,
					borderColor = Styles.textColor,
					cornerRadius = 1,
					click = function(self)
						token:BeginChanges()
						token.properties.negotiation.patience = token.properties.negotiation.patience - 1
						token.properties.negotiation.switch = false

						if token.properties.negotiation.patience < 0 then
							token.properties.negotiation.patience = 0
						end
						token:CompleteChanges("Decreased Patience")
						dialog:FireEventTree("refresh")
					end,

					gui.Label {

						width = 20,
						height = 20,
						text = "-",
						fontFace = "dubai",
						textAlignment = "center",







					},



				},




				--patience bar
				gui.Panel {

					flow = "horizontal",
					width = 900,
					height = 20,
					valign = "center",
					halign = "center",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					border = 2.5,
					borderColor = Styles.textColor,


					--patience fill
					gui.Panel {

						id = "patience",
						flow = "horizontal",
						floating = true,
						height = 20,
						valign = "center",
						halign = "left",
						bgimage = "panels/square.png",
						bgcolor = "white",
						border = 2.5,
						borderColor = Styles.textColor,

						styles = {


							{

								gradient = Styles.healthGradient,

							},

							{
								selectors = "bloodied",
								transitionTime = 0.35,
								gradient = Styles.bloodiedGradient,

							},

							{
								selectors = "damaged",
								transitionTime = 0.35,
								gradient = Styles.damagedGradient,

							},


						},

						refresh = function(self)
							TransitionStyle(self, 0.35, {

								width = 900 * token.properties.negotiation.patience / 5


							})


							if token.properties.negotiation.patience == 1 then
								self:SetClass("damaged", true)
								self:SetClass("bloodied", false)
							end

							if token.properties.negotiation.patience == 2 or token.properties.negotiation.patience == 3 then
								self:SetClass("damaged", false)
								self:SetClass("bloodied", true)
							end

							if token.properties.negotiation.patience == 4 or token.properties.negotiation.patience == 5 then
								self:SetClass("damaged", false)
								self:SetClass("bloodied", false)
							end
						end,





					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 20,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 20,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 20,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

					gui.Panel {

						flow = "vertical",
						width = 180,
						height = 20,
						bgimage = "panels/square.png",
						bgcolor = "clear",
						borderColor = Styles.textColor,
						border = { x1 = 0, y1 = 0, x2 = 2.5, y2 = 0 },

					},

				},

				--patience plus button
				gui.Panel {

					classes = { "hideForPlayers" },
					bgimage = "panels/square.png",
					bgcolor = "clear",
					width = 20,
					height = 20,
					valign = "center",
					halign = "right",
					rmargin = 15,
					borderWidth = 1.5,
					cornerRadius = 1,
					borderColor = Styles.textColor,

					click = function(self)
						token:BeginChanges()
						token.properties.negotiation.patience = token.properties.negotiation.patience + 1
						token.properties.negotiation.switch = false

						if token.properties.negotiation.patience > 5 then
							token.properties.negotiation.patience = 5
						end
						token:CompleteChanges("Increased Patience")
						dialog:FireEventTree("refresh")
					end,

					gui.Label {

						width = 20,
						height = 20,
						text = "+",
						fontFace = "dubai",
						textAlignment = "center",







					},



				},

			},

			gui.Panel {

				flow = "horizontal",
				width = "auto",
				height = "auto",
				halign = "center",
				tmargin = 20,


				-- button reveal (director)
				gui.Button {

					classes = { "dmonly" },
					text = "Reveal to players",
					fontSize = 22,
					width = 220,
					height = 40,
					valign = "top",
					halign = "center",
					rmargin = 20,
					vmargin = 0,

					click = function()
						revealed = true

						dialog:FireEventTree("revealed")
					end,

					revealed = function(self)
						self:SetClass("collapsed", revealed)
					end,

				},

				-- button hide (director)
				gui.Button {

					classes = { "dmonly", "collapsed" },
					text = "Hide from players",
					fontSize = 22,
					width = 220,
					height = 40,
					valign = "top",
					halign = "center",
					rmargin = 20,
					vmargin = 0,

					click = function()
						revealed = false

						dialog:FireEventTree("revealed")
					end,

					revealed = function(self)
						self:SetClass("collapsed", not revealed)
					end,



				},


				-- button discover
				gui.Button {

					classes = { "playeronly" },
					text = "Discover Motivation",
					fontSize = 22,
					width = 220,
					height = 40,
					valign = "top",
					halign = "center",
					rmargin = 20,
					vmargin = 0,




				},

				-- button argument
				gui.Button {

					classes = { "playeronly" },
					text = "Make Argument",
					fontSize = 22,
					width = 220,
					height = 40,
					valign = "top",
					halign = "center",
					vmargin = 0,


				},

			},

		},

		gui.Panel {


			halign = "center",
			valign = "center",
			floating = true,
			width = 1,
			height = 1000,
			bgimage = "panels/square.png",
			bgcolor = "clear",
			draggable = true,


		},



	}
	dialog:FireEventTree("refresh")
	return dialog
end

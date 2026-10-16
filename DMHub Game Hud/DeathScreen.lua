local mod = dmhub.GetModLoading()

function Hud:CreateDeathPanel(token)
	local deathpanel
	local death = token.properties:GetNumDeathSavingThrowFailures()
	local life = token.properties:GetNumDeathSavingThrowSuccesses()


	local styles ={
			Styles.Default,

			{
				halign = "center",
				valign = "center",
			},
			
			{
				classes = {"label"},
				fontFace = "sellyoursoul",
			},
			
			{
				classes = {"life", "selected"},
				brightness = 5,
			},
			
			{
				classes = {"death", "selected"},
				brightness = 5,
			},
			
			{
				classes = {"leaf", "create"},
				opacity = 0,
				transitionTime = 1,
				
			},
			
			{
				classes = {"leaf"},
				y = -30,
				x = 120,
			},

			{
				classes = {"death-bg", "create"},
				opacity = 0,
				transitionTime = 0.5,
			},

			{
				classes = {"~death-bg", "create"},
				opacity = 0,
				transitionTime = 0.5,
				uiscale = 0.9,
			},
		}
	------------------------------------------------------------------------------------------------------------------------------
	------------------------------------------------------------------------------------------------------------------------------

	local diamondPositions = { { x = -185, y = -30 }, { x = -92.5, y = 80 }, { x = 0, y = -30 }, { x = 92.5, y = 80 }, { x = 185, y = -30 }, }

	local CreateDiamond = function(index)
		return gui.Panel{
			classes = {"life"},
			bgimage = mod.images.salmiakki,
			bgcolor = "white",
			x = diamondPositions[index].x,
			y = diamondPositions[index].y,
			width = 137,
			height = 207,

			gui.Panel{
				width = 64,
				height = 64,
				halign = "center",
				valign = "center",
				styles = {
					{
						blend = "add",
						bgcolor = "white",
					},
					{
						selectors = {"success"},
						bgimage = mod.images.deathSuccess,
					},
					{
						selectors = {"~success"},
						bgimage = mod.images.deathFailure,
					},
					{
						selectors = {"pending"},
						brightness = 0.5,
					},
					{
						selectors = {"finish"},
						uiscale = 3,
						brightness = 8,
						transitionTime = 0.5,
					},
					{
						selectors = {"thinking"},
						bgcolor = "clear",
					},
				},
				init = function(element)
					local status = token.properties:GetDeathSavingThrowStatus(index)
					if status == nil then
						element:SetClass("hidden", true)
					else
						element:SetClass("hidden", false)
						element:SetClass("success", status == "success")
					end
				end,

				data = {
					rollGuid = nil,
					beginThink = nil,
					scheduleFinish = false,
				},

				think = function(element)
					if dmhub.Time() > element.data.beginThink + 2.0 then
						--roll didn't come through, stop listening.
						element.data.rollGuid = nil
						element.data.beginThink = nil
						element.thinkTime = nil
						element:SetClass("thinking", false)
						element:SetClass("hidden", true)
						return
					end

					if element.data.rollGuid ~= nil then
						for i,message in ipairs(chat.messages) do
							dmhub.Debug(string.format("DEATH:: INSPECT %s vs %s", message.key, element.data.rollGuid))
							if message.key == element.data.rollGuid then
								dmhub.Debug("DEATH:: FOUND")
								--rollGuid is the key of the death-save roll, so this message is a dice roll.
								local info = (message --[[@as ChatMessageDiceRollInfoLua]]).resultInfo
								for catid,catInfo in pairs(info) do
									for j,roll in ipairs(catInfo.rolls) do
										local diceEvents = chat.DiceEvents(roll.guid)
										if diceEvents ~= nil then
											diceEvents:Listen(element)
										end
									end
								end

								element:FireEventTree("rollMessage", message)
								element.thinkTime = nil
							end
						end
					end
				end,

				finishdice = function(element)
					local status = token.properties:GetDeathSavingThrowStatus(index)
					if status == nil then
						element:ScheduleEvent("finishdice", 0.05)
					else
						element:SetClass("success", status == "success")
						element:SetClass("pending", false)
						element:PulseClass("finish")
						deathpanel:FireEventTree("finish")
					end
				end,

				diceface = function(element, diceguid, num, t)
					local numSlots = 1
					if element.data.scheduleFinish == false then
						element:ScheduleEvent("finishdice", t)
					end
					element:SetClassImmediate("pending", true)

					if num == 20 then
						numSlots = 5
					elseif num == 1 then
						numSlots = 2
					end


					element:SetClass("thinking", false)

					if token.properties:GetNumDeathSavingThrowFailures() + token.properties:GetNumDeathSavingThrowSuccesses() + numSlots < index then
						element:SetClass("hidden", true)
					else
						element:SetClass("hidden", false)
						local status = token.properties:GetDeathSavingThrowStatus(index)
						if status == nil then
							element:SetClass("success", num >= 10)
						end
					end
				end,

				beginRoll = function(element, guid)
					if element:HasClass("hidden") == false then
						return
					end

					element.thinkTime = 0.05
					element.data.beginThink = dmhub.Time()
					element.data.rollGuid = guid
					element:SetClass("hidden", false)
					element:SetClass("thinking", true)

				end,
			},

		}
	end
		
	local diamonds = {}
	for i=1,5 do
		diamonds[#diamonds+1] = CreateDiamond(i)
	end

	for _,diamond in ipairs(diamonds) do
		diamond:FireEventTree("init")
	end

	local bursting = false 
	local burstsize = 0

	local finished = false --whether we've finished doing a roll on here.

	deathpanel = gui.Panel{

		styles = styles,
		
		id = "death-bg",
		bgimage = "panels/square.png",
		bgcolor = "#000000fa",
		width = 1920,
		height = 1080,
		halign = "center",
		valign = "center",
		flow = "none",

		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		captureEscape = true,
		escape = function(element)
			self:CloseModal()
		end,

		gui.Panel{
			halign = 'center',
			valign = 'center',
			width = 1920,
			height = 1080,
			y = 0,
			x = 28,
			bgimage = mod.images.deathscreenBackground,
			bgcolor = "white",
		},
		
		
		gui.Panel{
			
			halign = "center",
			valign = "top",
			flow = "none",
			width = "100%",
			height = "100%",

			gui.Panel{
		
				bgimage = "panels/deathscreen/skull2.png", --skull2 not used.
				halign = "center",
				floating = true,
				
				bgcolor = "white",
				width = 1300,
				height = 600,
				valign = "top",
				
				create = function(thispanel)
					thispanel:ScheduleEvent("leaf",0.5)
				end,
				
				leaf = function(thispanel)
					local images = {mod.images.lehti, mod.images.lehti2}
					
					local uusileaf = gui.Panel{
					
						bgimage = images[math.random(#images)],
						width = 50,
						height = 50,
						bgcolor = "white",
						classes = "leaf",
						halign = "left",
						valign = "bottom",
						brightness = 0 + math.random()*2,
						
						styles = {
						
							{
								classes = {"leaf", "right"},
								x = math.random(20, 60),
								transitionTime = 0.5,
								easing = "easeinoutsine",
					
							},
							
							{
								classes = {"leaf", "~create"},
								y = 800,
								transitionTime = math.random(5, 8)*cond(bursting,0.2,1),
								easing = "EaseInSine",
							},
						
						
						},
						
						die = function(self)
						
							self:DestroySelf()
						
						end,
						
						swingleft = function(self)
						
							self:RemoveClass("right")
							self:ScheduleEvent("swingright", 0.5)
						
						end,
						
						swingright = function(self)
						
							self:AddClass("right")
							self:ScheduleEvent("swingleft", 0.5)
						
						end,
					}
					
					uusileaf:ScheduleEvent("die", 10)
					
					uusileaf:ScheduleEvent("swingright", 0)
					
					uusileaf.x = math.random(200)
					
					if math.random()>0.5 then
					
						uusileaf.x = uusileaf.x + 700
					
					end
					
					thispanel:AddChild(uusileaf)
					
					local petalspersecond = 2 + life + death
					local startburst = life == 3 or death == 3
					if startburst and not bursting then
						
						burstsize = 500
						
					end
					
					bursting = startburst
					if bursting then

						petalspersecond = petalspersecond + burstsize
						burstsize = burstsize - 0.5
						if burstsize < 0 then 
							burstsize = 0
						end
					
					end
					
					
					petalspersecond = petalspersecond*(0.5 + math.random())
					thispanel:ScheduleEvent("leaf",1/petalspersecond)
				
				
				end,
				
				thinkTime = 0.1,
				think = function(thispanel)
					if token == nil or token.properties == nil then
						return
					end

					death = token.properties:GetNumDeathSavingThrowFailures()
					life = token.properties:GetNumDeathSavingThrowSuccesses()

					local score = life-death
					if death >= 3 then
						score = -3
					elseif life >= 3 then
						score = 3
					end

					if token.properties:IsDead() then
						score = -3
					elseif not token.properties:IsDeadOrDying() then
						score = 3
					end

					thispanel.y = -20
					if score == -3 then 
						thispanel.bgimage = mod.images.skull4valmis --get animation for actual death?
						thispanel.y = 55
					elseif score == -2 then
						thispanel.bgimage = mod.images.skull4valmis
						thispanel.y = 55
					elseif score == -1 then
						thispanel.bgimage = mod.images.skull3valmis
						thispanel.y = 55
					elseif score == 0 then
						thispanel.bgimage = mod.images.skull2valmis
					elseif score == 1 then
						thispanel.bgimage = mod.images.skull1valmis
					elseif score == 2 then
						thispanel.bgimage = mod.images.skull0valmis
					elseif score == 3 then
						thispanel.bgimage = mod.images.skullvalmisvideo
					end
					
				end,
			},
			

		
		},
		
		--salmiakki äiti paneli
		gui.Panel{
			id = "diamondsPanel",
		
			halign = "center",
			valign = "center",
			width = 1000,
			height = 400,
			y = 50,

			children = diamonds,
		},
		
		-- dice panel
		gui.Panel{
			id = "dicePanel",
		
			halign = "center",
			valign = "bottom",
			width = 1000,
			height = 200,
			flow = "none",
			y = -120,
			
			gui.Panel{
				id = "ribbon",
			
				bgimage = mod.images.ribbon,
				bgcolor = "white",
				width = 790,
				height = 183,
			
			
			},
		
			gui.Panel{
			
				bgimage = mod.images.sinetti,
				bgcolor = "white",
				width = 178,
				height = 168,
			
			
			},
		
			gui.Panel{
			
				bgimage = mod.images.diceicon,
				draggable = true,

				finish = function(element)
					finished = true
					element.bgimage = "icons/icon_common/icon_common_29.png"
					element:SetClass("hidden", false)
				end,

				click = function(element)
					if finished then
						self:CloseModal()
					else
						local guid = token.properties:RollDeathSavingThrow()
						deathpanel:FireEventTree("beginRoll", guid)
						element:SetClass("hidden", true)
					end
				end,
				
				styles = {
					{
						bgcolor = "white",
						width = 120,
						height = 120,
						borderWidth = 0,
						cornerRadius = 0,
						valign = "center",
					},
					
					{
						selectors = {"hover"},
						bgcolor = "white",
						brightness = 3.5,
						transitionTime = 0.1,
						scale = 1.1,
						rotate = 0,
					},
					
					{
						selectors = {"press"},
						bgcolor = "#4d4d4d",
				
					},
					
				},
				
			},
			
		},
	}
	deathpanel:FireEventTree("roll")
	return deathpanel
end

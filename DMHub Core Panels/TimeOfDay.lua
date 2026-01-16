local mod = dmhub.GetModLoading()

local CreateTimeOfDayPanel

DockablePanel.Register {
	name = "Time of Day/Lighting",
	icon = "icons/standard/Icon_App_TimeofDay.png",
	notitle = true,
	vscroll = false,
	dmonly = true,
	minHeight = 100,
	maxHeight = 100,
	content = function()
		return CreateTimeOfDayPanel()
	end,
}

local ShowTimeOfDaySettingsDialog
local UploadTimeBasis = nil

function UploadDayNightInfo()
	UploadTimeBasis()
end

local g_solarLatitude = setting {
	id = "solarlatitude",
	description = "Solar Latitude",
	storage = "game",
	editor = "slider",
	default = 0.5,
	min = -1,
	max = 1,
}

setting {
	id = "sunbrightness",
	description = "Sunlight/Moonlight",
	storage = "game",
	editor = "slider",
	percent = true,
	default = 1,
	min = 0,
	max = 1,
}

setting {
	id = "ambientlight",
	description = "Ambient Light",
	storage = "game",
	editor = "slider",
	percent = true,
	default = 0.5,
	min = 0,
	max = 1,
}

local advancetimeSetting = setting {
	id = "advancetime",
	description = "Advance Time",
	storage = "game",
	editor = "dropdown",
	hidelabel = true,
	default = "manual",

	onchange = function() UploadTimeBasis() end,

	enum = {
		{
			value = "manual",
			text = "Manual Time",
		},
		{
			value = "realtime",
			text = "Real Time",
		},
	},
}

setting {
	id = "timepauseduringinitiative",
	description = "Pause Time During Combat",
	storage = "game",
	editor = "check",
	default = true,

	onchange = function() UploadTimeBasis() end,

}

setting {
	id = "timemultiplier",
	description = "Time Multiplier",
	storage = "game",
	editor = "sliderexponential",
	percent = false,
	default = 1,
	min = 0,
	max = math.log(3600) / math.log(2),
	monitorVisible = { 'advancetime' },
	onchange = function()
		UploadTimeBasis()
	end,
	visible = function()
		return dmhub.GetSettingValue('advancetime') == 'realtime'
	end,
	enum = {
		{
			value = "manual",
			text = "Manual Time",
		},
		{
			value = "realtime",
			text = "Real Time",
		},
	},
}

setting {
	id = "undergroundillumination",
	description = "Illumination",
	onchange = function() end,

	storage = "map",
	editor = "slider",
	default = 1.0,
}

local GetDayTypeKey = function(floorid)
	if game.FloorIsAboveGround(floorid) then
		return 'daynight'
	else
		return 'underground'
	end
end

--calculate the game time, which is gametime + (server_time - gametimebasis)*timemultiplier
function CalculateGameDateAndTime()
	local gametime = dmhub.GetSettingValue("gametime")

	local initiativeQueue = dmhub.initiativeQueue
	if initiativeQueue ~= nil and (not initiativeQueue.hidden) and dmhub.GetSettingValue("timepauseduringinitiative") then
		return gametime
	end

	local timeType = dmhub.GetSettingValue("advancetime")
	if timeType == "manual" then
		return gametime
	end

	local realtime = (dmhub.serverTime - dmhub.GetSettingValue("gametimebasis")) / (24 * 60 * 60)
	local t = gametime + realtime * (2 ^ dmhub.GetSettingValue("timemultiplier"))
	return t
end

local CalculateGameDate = function()
	return math.floor(CalculateGameDateAndTime())
end

local CalculateGameTime = function()
	local t = CalculateGameDateAndTime()
	return t - math.floor(t)
end

local g_dateAndTimeSet = nil
local g_dateAndTime = nil
local g_dateAndTimeSeeking = false

local g_seekSpeed = setting {
	id = "timeofdayseekspeed",
	description = "Time of Day Seek Speed",
	storage = "game",
	default = 0.2,
}

local g_maximumSeekTime = setting {
	id = "timeofdayseekmax",
	description = "Time of Day Maximum Seek Duration",
	storage = "game",
	default = 4,
}
local g_seekSpeedOverride = nil --a seek speed override to make sure max seek time is respected.

local CalculateGameDateAndTimeSeek = function()
	local res = CalculateGameDateAndTime()
	if g_dateAndTime == nil then
		g_dateAndTimeSet = dmhub.Time()
		g_dateAndTime = res
		g_dateAndTimeSeeking = false
		return g_dateAndTime, g_dateAndTimeSeeking
	end

	local delta = (dmhub.Time() - g_dateAndTimeSet)
	if delta <= 0 then
		g_dateAndTimeSet = dmhub.Time()
		return g_dateAndTime, g_dateAndTimeSeeking
	end

	g_dateAndTimeSeeking = false

	local seek = delta * (g_seekSpeedOverride or g_seekSpeed:Get())
	g_dateAndTimeSet = dmhub.Time()
	if math.abs(g_dateAndTime - res) <= seek then
		g_dateAndTime = res
		g_seekSpeedOverride = nil
	else
		if g_seekSpeedOverride == nil and math.abs(g_dateAndTime - res) / g_seekSpeed:Get() > g_maximumSeekTime:Get() then
			g_seekSpeedOverride = min(2, math.abs(g_dateAndTime - res) / g_maximumSeekTime:Get())
			seek = delta * g_seekSpeedOverride
		end

		if g_dateAndTime < res then
			g_dateAndTime = g_dateAndTime + seek
		else
			g_dateAndTime = g_dateAndTime - seek
		end

		g_dateAndTimeSeeking = true
	end

	return g_dateAndTime, g_dateAndTimeSeeking
end

local CalculateGameTimeSeek = function()
	local t, isSeeking = CalculateGameDateAndTimeSeek()
	return t - math.floor(t), isSeeking
end

local g_dayNightGradient = core.Gradient {
			point_a = { x = 0, y = 0 },
			point_b = { x = 1, y = 0 },
			stops = {
				{
					position = 0, --midnight.
					color = '#312c5a',
				},
				{
					position = 5 / 24, --5am / sun starts to rise..
					color = '#4253a1',
				},
				{
					position = 6 / 24, --6am / dawn.
					color = '#ffc869',
				},
				{
					position = 7 / 24, --7am / sun above horizon.
					color = '#faec70',
				},
				{
					position = 12 / 24, --midday. Sun high in sky
					color = '#ffffff',
				},
				{
					position = 17 / 24, --5pm. Sun starting to go down
					color = '#ffb861',
				},
				{
					position = 18 / 24, --6pm. Sun setting.
					color = '#ff9c8c',
				},
				{
					position = 19 / 24, --7pm. Sun below horizon..
					color = '#4253a1',
				},
				{
					position = 1, --midnight.
					color = '#312c5a',
				},
			},
		}

local g_undergroundGradient = core.Gradient {
			point_a = { x = 0, y = 0 },
			point_b = { x = 1, y = 0 },
			stops = {
				{
					position = 0,
					color = '#000000',
				},
				{
					position = 1,
					color = '#ffffff',
				},
			},
		}



local g_colorGray = core.Color { r = 0.5, g = 0.5, b = 0.5 }
local g_shadowVec = core.Vector2(0,0)
local DayTypes = {
	daynight = {
		description = "Above Ground",
		timeLabel = 'Time of Day',
		outside = true,
		illumination = 1.0,
		GetShadows = function(t)
			local lengthMultiplier = 1

			--normalized position of sun during the day.
			local r = (t - 5 / 24) / (19 / 24 - 5 / 24)

			if t < 5 / 24 or t > 19 / 24 then
				--at night normalize between dusk and dawn instead.
				if t > 19 / 24 then
					r = (t - 19 / 24) / (10 / 24)
				else
					r = (t + 5 / 24) / (10 / 24)
				end
				r = 1 - r
				lengthMultiplier = 0.4
			end


			--controls how long shadows should be north. The larger this value the further
			--north of the equator the players are (and/or the closer to winter it is).
			--Values negative for Southern Hemisphere.
			local shadowNorth = g_solarLatitude:Get()

			--controls how long shadows should be east/west.
			local shadowConstant = 3

			local shadowLength = lengthMultiplier * shadowConstant * math.tan((r - 0.5) * math.pi / 2)

            g_shadowVec.x = shadowLength
            g_shadowVec.y = shadowNorth

			return {
				dir = g_shadowVec,
				color = g_colorGray,
			}
		end,

		gradient = g_dayNightGradient,
	},
	underground = {
		var = "undergroundillumination",
		description = "Underground",
		timeLabel = 'Illumination',
		outside = false,
		illumination = 0.5,

		GetShadows = function(t)
			return nil
		end,

        gradient = g_undergroundGradient,
	},
}

local GetDayType = function(floorid)
	return DayTypes[GetDayTypeKey(floorid)]
end


local daytimeInfo = DayTypes.daynight

PreviewLightingTypes = { "Day", "Evening", "Night" }

local previewLighting = {
	["Day"] = {
		indoors = daytimeInfo.gradient:Sample(0.4),
		outdoors = daytimeInfo.gradient:Sample(0.4),
		shadow = daytimeInfo.GetShadows(0.4),
	},
	["Evening"] = {
		indoors = daytimeInfo.gradient:Sample(0.7),
		outdoors = daytimeInfo.gradient:Sample(0.7),
		shadow = daytimeInfo.GetShadows(0.7),
	},
	["Night"] = {
		indoors = daytimeInfo.gradient:Sample(0.9),
		outdoors = daytimeInfo.gradient:Sample(0.9),
		shadow = daytimeInfo.GetShadows(0.9),
	},
}

function GetLightingPreviewInfo(id)
	return previewLighting[id] or previewLighting["Day"]
end

--gametime last time we sampled
local currentGameDateAndTime = nil
local currentGameTimeQueryTime = nil
local initiativeBarState = nil
local timeChangeEmbargo = nil

--this will recalculate and upload the new 'time basis' from which time is calculated.
UploadTimeBasis = function()
	if currentGameDateAndTime ~= nil then
		dmhub.SetSettingValue("gametime", currentGameDateAndTime)
		dmhub.SetSettingValue("gametimebasis", dmhub.serverTime)
	end
end

function MoveGameTime(days)
	currentGameDateAndTime = currentGameDateAndTime + days
	UploadTimeBasis()
end

local g_lightingColor = core.Color { r = 1, g = 1, b = 1 }
local g_shadowColor = core.Color { r = 1, g = 1, b = 1 }
dmhub.GetLightingInfo = function(floorid)
	local dayInfo = GetDayType(floorid)

	--if the initiative bar state changes put a short embargo on recalculating lighting info
	local haveInitiativeBar = dmhub.initiativeQueue ~= nil and (not dmhub.initiativeQueue.hidden) and
	dmhub.GetSettingValue("timepauseduringinitiative")
	if initiativeBarState ~= nil and initiativeBarState ~= haveInitiativeBar then
		timeChangeEmbargo = dmhub.Time() + 0.25
	end
	initiativeBarState = haveInitiativeBar

	local isSeeking = false

	if timeChangeEmbargo == nil or dmhub.Time() > timeChangeEmbargo then
		timeChangeEmbargo = nil
		currentGameDateAndTime, isSeeking = CalculateGameDateAndTimeSeek()
		currentGameTimeQueryTime = dmhub.Time()
	end


	local t = currentGameDateAndTime - math.floor(currentGameDateAndTime)

	if dayInfo.var then
		t = dmhub.GetSettingValue(dayInfo.var)
	end

	local color = dayInfo.gradient:Sample(t)
	local shadows = dayInfo.GetShadows(t)
	if dayInfo.outside then
		local sunlight = dmhub.GetSettingValue("sunbrightness")
		color = g_lightingColor
		color.r = color.r * sunlight
		color.g = color.g * sunlight
		color.b = color.b * sunlight

		if shadows ~= nil then
			local ambient = dmhub.GetSettingValue("ambientlight")
			g_shadowColor.r = ambient
			g_shadowColor.g = ambient
			g_shadowColor.b = ambient
			shadows.color = g_shadowColor
		end
	end

	return {
		indoors = color,
		outdoors = color,
		shadow = shadows,
		illumination = dayInfo.illumination,
		cacheable = (not isSeeking) and advancetimeSetting:Get() == "manual",
	}
end

CreateTimeOfDayPanel = function()
	if not dmhub.isDM then
		return nil
	end

	local sunPanel = gui.Panel {
		width = 80,
		height = 80,
		y = -14,
		bgimage = mod.images.Sun,
		bgcolor = "white",
		saturation = 0,
		floating = true,
		halign = "center",
		valign = "center",

		outside = function(element, val)
			element:SetClass("hidden", not val)
		end,

		tick = function(element, val)
			local angle = -math.rad((val - 0.25) * 360)
			local y = math.sin(angle)
			local x = math.cos(angle)


			element.x = x * 100
			element.y = 36 + y * 50
		end,

	}

	local moonPanel = gui.Panel {
		width = 80,
		height = 80,
		y = -14,
		bgimage = mod.images.Moon,
		bgcolor = "white",
		floating = true,
		halign = "center",
		valign = "center",
		saturation = 0,

		outside = function(element, val)
			element:SetClass("hidden", not val)
		end,

		tick = function(element, val)
			local angle = -math.rad((val + 0.25) * 360)
			local y = math.sin(angle)
			local x = math.cos(angle)

			element.x = x * 100
			element.y = 36 + y * 50
		end,
	}

	local dayTextLabel = gui.Label {
		fontSize = 18,
		text = "1",
		hmargin = 4,
		characterLimit = 3,
		editable = dmhub.isDM,
		change = function(element)
			local number = round(tonumber(element.text))
			if type(number) == "number" then
				local time = CalculateGameTime()

				currentGameDateAndTime = (number - 1) + time
				UploadTimeBasis()
			end
		end,
	}
	local dayLabel = gui.Panel {
		floating = true,
		flow = "horizontal",
		halign = "left",
		valign = "top",
		lmargin = 7,
		vmargin = 2,
		gui.Label {
			fontSize = 18,
			text = "Day",
		},
		dayTextLabel,
		create = function(element)
			element:FireEvent("think")
		end,
		thinkTime = 0.5,
		think = function(element)
			if dayTextLabel.editing then
				return
			end
			dayTextLabel.text = string.format("%d", CalculateGameDate() + 1)
		end,
	}


	return gui.Panel {
		selfStyle = {
			vmargin = 0,
			halign = 'center',
			valign = 'top',
			width = "100%",
			height = 80,
			flow = 'vertical',
		},

		styles = {
			{
				bgcolor = 'white',
			},
		},

		children = {

			gui.Panel {
				id = 'timeofdaypanel',
				bgimage = "panels/square.png",
				clip = true,
				clipHidden = true,
				interactable = false,
				selfStyle = { vpad = 0 },
				style = {
					halign = 'center',
					valign = 'center',
					width = 'auto',
					height = 'auto',
					flow = 'vertical',
				},
				children = {
					dayLabel,
					sunPanel,
					moonPanel,

					gui.Panel {
						width = '100%',
						height = '100%',
						flow = 'none',
						halign = "center",
						valign = 'top',

						--gui.Label{
						--	text = '',
						--
						--	thinkTime = 0.25,
						--
						--	style = {
						--		vpad = 2,
						--		fontSize = 12,
						--		width = 'auto',
						--		height = 'auto',
						--		halign = 'center',
						--	},
						--	events = {
						--		create = 'think',
						--		think = function(element)
						--			local dayInfo = GetDayType()
						--			if dayInfo.timeLabel then
						--				element.text = dayInfo.description
						--			end
						--		end,
						--	},
						--	
						--},

						gui.Panel {
							bgimage = 'ui-icons/skills/98.png',
							blend = "add",
							halign = 'right',
							valign = 'top',
							width = 16,
							height = 16,
							rmargin = 4,
							vmargin = 3,
							styles = {
								{
									selectors = { 'hover' },
									brightness = 2,
								},
								{
									selectors = { 'press' },
									brightness = 1.5,
								},
							},

							click = function(element)
								ShowTimeOfDaySettingsDialog()
							end,
						},
					},

					gui.Slider {
						bgimage = 'panels/square.png',
						halign = "center",
						valign = "bottom",
						handleSize = "130%",
						labelWidth = 0,
						sliderWidth = 340,
						wrap = true,
						notchAlign = "top",
						notchColor = Styles.textColor,
						notchHeight = 3,
						fillColor = Styles.textColor,
						labelFormat = '',
						selfStyle = {
						},
						data = {
							currentDayType = nil,
							previewing = false,
							lastval = nil,
						},
						events = {
							create = function(element)
								element:FireEvent("monitor")
								element:FireEvent("tick")
							end,

							tick = function(element)
								if mod.unloaded then
									return
								end

								if element.data.previewing then
									element:ScheduleEvent("tick", 0.1)
									return
								end

								local nextTick = 0.1

								local dayInfo = GetDayType()
								local val
								local seekval
								if dayInfo.var then
									val = dmhub.GetSettingValue(dayInfo.var)
									seekval = val
								else
									val = CalculateGameTime()
									seekval = CalculateGameTimeSeek()
								end

								if element.data.lastval ~= seekval then
									--when we change value tick frequently for a high frame rate.
									nextTick = 0.01
								end

								element:ScheduleEvent("tick", nextTick)

								element.data.lastval = seekval
								element.data.setValueNoEvent(val)

								sunPanel:FireEvent("tick", seekval)
								moonPanel:FireEvent("tick", seekval)

								local dayInfo = GetDayType()
								if element.data.currentDayType ~= dayInfo then
									sunPanel:FireEvent("outside", dayInfo.outside)
									moonPanel:FireEvent("outside", dayInfo.outside)
									element.selfStyle.gradient = dayInfo.gradient
									element.data.currentDayType = dayInfo
									element:FireEventTree("setwrap", dayInfo.outside)
								end
							end,

							preview = function(element)
								local dayInfo = GetDayType()
								if dayInfo.var then
									dmhub.PreviewSettingValue(dayInfo.var, element.value)
								else
									local time = CalculateGameTime()
									local date = CalculateGameDate()
									local elementval = element.value

									--detect wrapping and creating a new date.
									if elementval < time - 0.7 then
										date = date + 1
									elseif elementval > time + 0.7 then
										date = date - 1
									end

									dmhub.PreviewSettingValue("gametime", date + element.value)
									dmhub.PreviewSettingValue("gametimebasis", dmhub.serverTime)

									element.data.previewing = false

									local val = CalculateGameTime()
									sunPanel:FireEvent("tick", val)
									moonPanel:FireEvent("tick", val)
									dayLabel:FireEvent("think")

									element.data.previewing = true
								end
							end,

							confirm = function(element)
								if element.data.previewing then
									--make sure seeking is turned off and we can jump straight there after a drag.
									g_dateAndTimeSet = nil
									g_dateAndTime = nil
									g_dateAndTimeSeeking = nil
								end

								element.data.previewing = false

								local dayInfo = GetDayType()
								if dayInfo.var then
									dmhub.SetSettingValue(dayInfo.var, element.value)
								else
									local time = CalculateGameTime()
									local date = CalculateGameDate()
									local elementval = element.value

									--detect wrapping and creating a new date.
									if elementval < time - 0.7 then
										date = date + 1
									elseif elementval > time + 0.7 then
										date = date - 1
									end

									currentGameDateAndTime = date + element.value
									UploadTimeBasis()
									dayLabel:FireEvent("think")
								end
							end,
						},
						styles = {
							{
								width = 340,
								height = 20,
								halign = 'center',
								valign = 'top',
							},
						},
					},

					gui.Panel {

						thinkTime = 0.25,
						events = {
							create = 'think',
							think = function(element)
								local dayInfo = GetDayType()
								element:SetClass('collapsed', dayInfo.timeLabel ~= nil)
							end,
						},

						styles = {
							{
								halign = 'center',
								flow = 'horizontal',
								width = 160,
								height = 16,
							},
							{
								selectors = { 'icon' },
								halign = 'center',
								height = '100%',
								width = '100% height',
							},
						},
						children = {

							gui.Panel {
								bgimage = 'icons/icon_weather/icon_weather_18.png',
								classes = { 'icon' },
							},

							gui.Panel {
								bgimage = 'icons/icon_weather/icon_weather_3.png',
								classes = { 'icon' },
							},
							gui.Panel {
								bgimage = 'icons/icon_weather/icon_weather_1.png',
								classes = { 'icon' },
							},
							gui.Panel {
								bgimage = 'icons/icon_weather/icon_weather_4.png',
								classes = { 'icon' },
							},
							gui.Panel {
								bgimage = 'icons/icon_weather/icon_weather_18.png',
								classes = { 'icon' },
							},

						}
					},
				},
			},


		},
	}
end

local m_dayNightSettingsDialog = nil

ShowTimeOfDaySettingsDialog = function()
	if not m_dayNightSettingsDialog then
		local UpdateTime = nil

		local hoursLabel = gui.Label {
			editable = true,
			characterLimit = 2,
			change = function() UpdateTime() end,
		}
		local minutesLabel = gui.Label {
			editable = true,
			characterLimit = 2,
			change = function() UpdateTime() end,
		}
		local secondsLabel = gui.Label {
			editable = true,
			characterLimit = 2,
			change = function() UpdateTime() end,
		}

		UpdateTime = function()
			local hours = tonumber(hoursLabel.text)
			local minutes = tonumber(minutesLabel.text)
			local seconds = tonumber(secondsLabel.text)

			if hours == nil or minutes == nil or seconds == nil or hours < 0 or minutes < 0 or seconds < 0 or hours > 23 or hours > 59 or seconds > 59 then
				return
			end

			currentGameDateAndTime = CalculateGameDate() + hours / 24 + minutes / (24 * 60) + seconds / (24 * 60 * 60)
			UploadTimeBasis()
		end

		m_dayNightSettingsDialog = gui.Panel {
			classes = { 'framedPanel', 'hidden' },

			halign = 'center',
			valign = 'center',

			width = 400,
			height = 400,

			flow = 'vertical',

			styles = {
				Styles.Panel,
			},

			draggable = true,
			drag = function(element)
				element.x = element.xdrag
				element.y = element.ydrag
			end,

			gui.CloseButton {
				click = function(element)
					m_dayNightSettingsDialog:SetClass('hidden', true)
				end,
			},

			CreateSettingsEditor("sunbrightness", {
				width = '65%',
			}),

			CreateSettingsEditor("solarlatitude", {
				width = '65%',
			}),

			CreateSettingsEditor("ambientlight", {
				width = '65%',
			}),

			--display the time in conventional format.
			gui.Panel {
				flow = 'horizontal',
				halign = 'center',
				valign = 'top',
				width = 'auto',
				height = 'auto',

				events = {
					create = function(element)
						element:FireEvent('monitor')
						element:FireEvent('tick')
					end,

					tick = function(element)
						element:ScheduleEvent('tick', 0.1)

						local t = CalculateGameTime()

						local hour = math.floor(t * 24)
						local minute = math.floor(t * 24 * 60) % 60
						local second = math.floor(t * 24 * 60 * 60) % 60

						if not hoursLabel.editing then
							hoursLabel.text = string.format("%02d", hour)
						end
						if not minutesLabel.editing then
							minutesLabel.text = string.format("%02d", minute)
						end
						if not secondsLabel.editing then
							secondsLabel.text = string.format("%02d", second)
						end
						--show the time even if underground.
						--element:SetClass('collapsed', GetDayTypeKey() ~= 'daynight')
					end,
				},

				styles = {
					selectors = { 'label' },
					priority = 10,
					color = 'white',
					fontSize = 20,
					width = 24,
					height = 24,
					textAlignment = 'right',
				},

				hoursLabel,
				gui.Label {
					width = 10,
					text = ":",
				},
				minutesLabel,
				gui.Label {
					width = 10,
					text = ":",
				},
				secondsLabel,
			},

			CreateSettingsEditor("advancetime", {
				panelStyle = {
					priority = 10,
					valign = 'top',
					height = 24,
				},
				valign = 'top',
				style = {
					fontSize = '80%',
					width = 200,
					height = 24,
					valign = 'top',
					halign = 'center',
					margin = 0,
				},
			}),


			CreateSettingsEditor("timepauseduringinitiative", {
				width = '65%',
			}),

			CreateSettingsEditor("timemultiplier", {
				style = {
					fontSize = '80%',
					width = 200,
					height = 24,
					valign = 'center',
					halign = 'center',
					margin = 0,
				},
			}),

		}

		gui.DialogPanel():AddChild(m_dayNightSettingsDialog)
	end

	m_dayNightSettingsDialog:SetClass('hidden', not m_dayNightSettingsDialog:HasClass('hidden'))
	if not m_dayNightSettingsDialog:HasClass("hidden") then
		m_dayNightSettingsDialog:PulseClass("fadein")
	end
end

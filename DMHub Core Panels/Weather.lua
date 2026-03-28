local mod = dmhub.GetModLoading()

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local CreateWeatherSettings

DockablePanel.Register{
	name = "Weather",
	icon = mod.images.weatherIcon,
	vscroll = true,
	minHeight = 100,
    dmonly = true,
	content = function()
		track("panel_open", {
			panel = "Weather",
			dailyLimit = 30,
		})
		return CreateWeatherSettings()
	end,
}

local function CreateWeatherEffectAsset()
	dmhub.OpenFileDialog{
		id = 'WeatherEffect',
		extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
		prompt = "Choose image or video to use for the weather effect",
		open = function(path)
			dmhub.Debug(string.format("CREATE WEATHER: %s", path))
			local confirmUpload = false
			local assetid = assets:CreateWeatherEffectFromFile{
				path = path,
				error = function(text)
					gui.ModalMessage{
						title = 'Error creating weather effect',
						message = text,
					}
				end,
				upload = function(tileid)
					printf("WEATHER:: Upload confirmed")
					confirmUpload = true
					gui.CloseModal()
				end,
			}


			if assetid ~= nil then
				gui.ShowModal(
					gui.Label{
						bgimage = 'panels/square.png',
						text = 'Uploading Asset...',
						style = {
							valign = 'center',
							height = 'center',
							width = 'auto',
							height = 'auto',
							pad = 100,
							cornerRadius = 16,
							borderWidth = 2,
							borderColor = 'black',
							bgcolor = '#777777ff',
							color = 'white',
							fontSize = '80%',
							textAlignment = 'center',
						},
						events = {
							refreshAssets = function(element)
								if confirmUpload then
									gui.CloseModal()
									dmhub.SetSettingValue('weather', assetid)
									dmhub.Debug('WEATHER:: FINISH UPLOADING')
								end
							end
						}
					}
				)
			end
		end,
	}
end



CreateWeatherSettings = function()

	local GetWeatherEffectName = function()
		local key = dmhub.GetSettingValue('weather')
		if key == 'none' then
			return 'None'
		else
			local asset = assets.weatherEffects[key]
			if asset ~= nil then
				return asset.description
			else
				return 'None'
			end
		end
	end

	local GetAsset = function()
		local key = dmhub.GetSettingValue('weather')
		return assets.weatherEffects[key]
	end

	local contentPanel = nil
	contentPanel = gui.Panel{
		id = "weatherContentPanel",
		style = {
			pivot = { x = 0, y = 1 },
			width = '100%',
			height = 'auto',
			flow = 'vertical',
		},
		children = {
			CreateSettingsEditor('weather'),

			gui.AddButton{
				tooltip = 'Add new weather effect from an image or video',
				height = 48,
				width = '100% height',
				halign = 'right',
				hmargin = 8,
				events = {
					click = function(element)
						CreateWeatherEffectAsset()
					end,
				}
			},

			gui.Panel{
				style = {
					width = '100%',
					height = 'auto',
					flow = 'vertical',
					fontSize = '60%',
				},

				monitor = 'weather',

				events = {
					create = 'monitor',
					monitor = function(element)
						local hidden = dmhub.GetSettingValue('weather') == 'none'
						element:SetClass('collapsed', hidden)
						dmhub.Debug('MONITOR WEATHER SET COLLAPSED: ' .. tostring(hidden))
					end,
				},

				children = {

					gui.Panel{
						style = {
							width = '100%',
							height = 48,
							flow = 'horizontal',
						},

						children = {

							gui.Label{
								text = "Effect Name:",
								style = {
									width = '40%',
									height = '100%',
								},
							},

							gui.Input{
								text = GetWeatherEffectName(),
								monitor = 'weather',
								style = {
									width = '50%',
									height = '100%',
									margin = 4,
									valign = 'center',
								},
								events = {
									monitor = function(element)
										element.text = GetWeatherEffectName()
									end,

									change = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											asset.description = element.text
											asset:Upload()
										end
									end,
								},
							}
					
						}
					},

					gui.Check{
						value = (function()
							local asset = GetAsset()
							if asset == nil then
								return false
							end
							return asset.fullscreen
						end)(),
						text = "Fullscreen",
						style = {
							width = '100%',
							height = 48,
						},

						monitor = 'weather',

						events = {
							monitor = function(element)
								local asset = GetAsset()
								if asset ~= nil then
									element.value = asset.fullscreen
								end
							end,
							change = function(element)
								local asset = GetAsset()
								if asset ~= nil then
									asset.fullscreen = element.value
									asset:Upload()
									contentPanel:FireEventTree('monitor') --make other panels collapse or uncollapse as appropriate.
								end
							end,
						}
					},

					gui.Panel{
						style = {
							width = '100%',
							height = 48,
							flow = 'horizontal',
						},

						monitor = 'weather',
						events = {
							create = 'monitor',
							monitor = function(element)
								local asset = GetAsset()
								if asset ~= nil then
									element:SetClass('collapsed', asset.fullscreen)
								end
							end,
						},

						children = {

							gui.Label{
								text = "Scale:",
								style = {
									width = 120,
									height = '100%',
								},
							},

							gui.Slider{
								minValue = -4,
								maxValue = 4,
								value = 0,
								monitor = 'weather',
								sliderWidth = 150,
								labelWidth = 60,

								formatFunction = function(num) return
									string.format('%d%%', round((2^num)*100))
								end,
								deformatFunction = function(num)
									local n = num*0.01
									return math.log(n)/math.log(2)
								end,

								style = {
									height = '60%',
									width = 220,
									valign = 'center',
								},
								events = {
									create = 'monitor',
									monitor = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											element.value = -asset.scale
										end
									end,

									change = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											asset.scale = -element.value
											asset:Upload()
										end
									end,
								},
							}
					
						}
					},

					gui.Panel{
						style = {
							width = '100%',
							height = 48,
							flow = 'horizontal',
						},

						children = {

							gui.Label{
								text = "Opacity:",
								style = {
									width = 120,
									height = '100%',
								},
							},

							gui.Slider{
								minValue = 0,
								maxValue = 1,
								value = 0,
								monitor = 'weather',
								sliderWidth = 150,
								labelWidth = 60,

								formatFunction = function(num) return
									string.format('%d%%', round(num*100))
								end,

								style = {
									height = '60%',
									width = 220,
									valign = 'center',
								},
								events = {
									create = 'monitor',
									monitor = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											element.value = asset.alpha
										end
									end,

									change = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											asset.alpha = element.value
											asset:Upload()
										end
									end,
								},
							}
					
						}
					},

					gui.Panel{
						style = {
							width = '100%',
							height = 48,
							flow = 'horizontal',
						},

						monitor = 'weather',
						events = {
							create = 'monitor',
							monitor = function(element)
								local asset = GetAsset()
								if asset ~= nil then
									element:SetClass('collapsed', asset.fullscreen)
								end
							end,
						},

						children = {

							gui.Label{
								text = "Parallax:",
								style = {
									width = 120,
									height = '100%',
								},
							},

							gui.Slider{
								minValue = 0,
								maxValue = 1,
								value = 1,
								monitor = 'weather',
								sliderWidth = 150,
								labelWidth = 60,
								style = {
									height = '60%',
									width = 220,
									valign = 'center',
								},
								events = {
									create = function(element)
										element:FireEvent('monitor')
									end,
									monitor = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											element.value = asset.parallax
											element:SetClass('collapsed', asset.fullscreen)
										end
									end,

									change = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											asset.parallax = element.value
											asset:Upload()
										end
									end,
								},
							}
					
						}
					},

					gui.Panel{
						style = {
							width = '100%',
							height = 48,
							flow = 'horizontal',
						},

						monitor = 'weather',
						events = {
							create = 'monitor',
							monitor = function(element)
								local asset = GetAsset()
								if asset ~= nil then
									element:SetClass('collapsed', asset.fullscreen)
								end
							end,
						},

						children = {

							gui.Label{
								text = "Movement:",
								style = {
									width = 120,
									height = '100%',
								},
							},

							gui.Slider{
								minValue = 0,
								maxValue = 100,
								value = 0,
								monitor = 'weather',
								sliderWidth = 150,
								labelWidth = 60,
								style = {
									height = '60%',
									width = 220,
									valign = 'center',
								},
								events = {
									create = function(element)
										element:FireEvent('monitor')
									end,
									monitor = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											element.value = asset.xmove
											element:SetClass('collapsed', asset.fullscreen)
										end
									end,

									change = function(element)
										local asset = GetAsset()
										if asset ~= nil then
											asset.xmove = element.value
											asset:Upload()
										end
									end,
								},
							}
					
						}
					},

				},
			},

		},
	}

	return contentPanel

end

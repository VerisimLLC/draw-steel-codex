local mod = dmhub.GetModLoading()

function creature:GetVictories()
    return self:try_get("victories", 0)
end

function creature:GetVictoriesWithBonus()
	return self:try_get("victories", 0) + self:CalculateNamedCustomAttribute("Victory Bonus")
end

function creature:SetVictories(n)
    local old = self:try_get("victories", 0)
    self.victories = n
    if n > old then
        self:DispatchEvent("earnvictory", { quantity = n - old })
    end
end

function CharSheet.InspirationPanel()
	local resultPanel

	resultPanel = gui.Panel{
		classes = {"attributePanel", "inspiration"},
		refreshToken = function(element, info)
			element:SetClass("collapsed", info.token.properties.typeName ~= "character")
		end,

		gui.Panel{
			gui.Panel{
				floating = true,
				halign = "center",
				valign = "center",
				width = 60,
				height = 60,
				borderWidth = 2,
				borderColor = Styles.textColor,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				rotate = 45,
			},

			gui.Panel{
				floating = true,
				halign = "center",
				valign = "center",
				width = 62,
				height = 62,
				cornerRadius = 31,
				borderWidth = 1.4,
				borderColor = Styles.textColor,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				rotate = 45,
			},



			classes = {"attributeModifierPanel", "inspiration"},

			gui.Label{
				id = "victoriesLabel",
                classes = {"statsLabel", "valueLabel"},
                editable = true,

                data = {
                    text = "",
                    creature = nil,
                },

                bold = true,
                fontSize = 34,
                width = "auto",
                height = "auto",
                halign = "center",
                characterLimit = 2,

                change = function(element)
                    local n = tonumber(element.text)
                    if n ~= nil and n >= 0 and round(n) == n then
                        element.data.creature:SetVictories(n)
						CharacterSheet.instance:FireEvent('refreshAll')
                    else
                        element.text = element.data.text
                    end
                end,

				refreshToken = function(element, info)
                    element.data.text = tostring(info.token.properties:GetVictories())
                    element.text = element.data.text
                    element.data.creature = info.token.properties
				end,
			},

		},
		gui.Label{
			classes = {"statsLabel","inspiration"},
			text = "VICTORIES",
		},
	}

	return resultPanel
end

function CharSheet.BuilderKitPanel()

	local banner

	local raceChoicePanel = CharSheet.KitChoicePanel{
		alert = function(element)
			banner:FireEvent("showAlert")
		end,
	}

	local content = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		halign = "center",
		valign = "center",

		raceChoicePanel,
	}

	banner = CharSheet.BuilderBanner{
		text = "Kit",
		content = content,
		calculateText = function(element)
			local creature = CharacterSheet.instance.data.info.token.properties
			if creature:has_key("kitid") then
				element.text = string.format("%s", creature:Kit().name)
			else
				element.text = tr("Kit")
			end
		end,
	}

	return banner

end

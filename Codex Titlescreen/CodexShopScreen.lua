local mod = dmhub.GetModLoading()

local fontWeights = {"thin", "extralight", "light", "regular", "medium", "semibold", "bold", "heavy", "black"}

local heightStretch = 175

local shopStyles = {
	{
		selectors = {"collapsedWhenCheckingOut", "checkingOut"},
		collapsed = 1,
	},
	{
		selectors = {"collapsedUnlessCheckingOut", "~checkingOut"},
		collapsed = 1,
	},

	{
		selectors = {"collapseOnGift", "gift"},
		collapsed = 1,
	},

	{
		selectors = {"collapseOnCart", "showingCart"},
		collapsed = 1,
	},
	{
		selectors = {"collapseUnlessCart", "~showingCart"},
		collapsed = 1,
	},
	{
		selectors = {"collapseUnlessCartWithItems", "~showingCartWithItems"},
		collapsed = 1,
	},
	{
		selectors = {"collapseUnlessCartWithoutItems", "~showingCart"},
		collapsed = 1,
	},
	{
		selectors = {"collapseUnlessCartWithoutItems", "showingCartWithItems"},
		collapsed = 1,
	},
	{
		selectors = {"collapsedWhenInventory", "inventory"},
		collapsed = 1,
	},
	{
		selectors = {"collapsedUnlessInventory", "~inventory"},
		collapsed = 1,
	},

	{
		selectors = {"collapsedWhenArtistFocus", "artistFocus"},
		collapsed = 1,
	},

	{
		selectors = {"label"},
		fontFace = "Inter",
		fontWeight = "regular",
		color = Styles.textColor,
		width = "auto",
		height = "auto",
	},

	{
		selectors = {"input"},
		borderFade = false,
		borderWidth = 0,
		fontFace = "Inter",
		width = 220,
		height = 24,
		fontSize = 18,
		bgimage = "panels/square.png",
		bgcolor = "#555555ff",
		cornerRadius = 12,
		halign = "center",
		hpad = 28,
	},

	{
		selectors = {"shopTitle"},
		color = Styles.textColor,
		uppercase = true,
		fontSize = 30,
		fontWeight = "light",
		valign = "top",
		halign = "center",
	},

	{
		selectors = {"shopDescription"},
		fontWeight = "light",
		color = "#aaaaaaff",
		fontSize = 16,
	},

	{
		selectors = {"label"},
		fontFace = "Inter",
		fontWeight = "regular",
		color = Styles.textColor,
		width = "auto",
		height = "auto",
	},

	{
		selectors = {"input"},
		borderFade = false,
		borderWidth = 0,
		fontFace = "Inter",
		width = 220,
		height = 24,
		fontSize = 18,
		bgimage = "panels/square.png",
		bgcolor = "#555555ff",
		cornerRadius = 12,
		halign = "center",
		hpad = 28,
	},

	{
		selectors = {"shopTitle"},
		color = Styles.textColor,
		uppercase = true,
		fontSize = 30,
		fontWeight = "light",
		valign = "top",
		halign = "center",
	},

	{
		selectors = {"shopDescription"},
		fontWeight = "light",
		color = "#aaaaaaff",
		fontSize = 16,
		vmargin = 16,
		valign = "top",
		halign = "center",
	},

	{
		selectors = {"pagingLabel"},
		bgimage = "panels/square.png",
		bgcolor = "clear",
		width = 28,
		height = 28,
		hmargin = 2,
		textAlignment = "center",
		halign = "center",
		fontSize = 16,
		color = "#ffffff55",
	},

	{
		selectors = {"pagingLabel", "selected"},
		bgcolor = "#ffffff11",
		color = Styles.textColor,
	},

	{
		selectors = {"pagingLabel", "hover"},
		color = "white",
	},

	{
		selectors = {"pagingFooter"},
		width = 1080,
		height = 20,
		flow = "horizontal",
		halign = "center",
	},

	{
		selectors = {"pagingFooterArrow"},
		width = 20,
		height = 20,
		textAlignment = "center",
		fontSize = 18,
		fontWeight = "bold",
		color = "#ccccccff",
	},

	{
		selectors = {"pagingFooterArrow", "hover"},
		color = "white",
	},

	{
		selectors = {"divider"},
		bgimage = "panels/square.png",
		width = 1080,
		height = 1,
		bgcolor = "#000000aa",
		vmargin = 20,
		halign = "center",
	},

	{
		selectors = {"centerPanel"},
		flow = "vertical",
		width = "auto",
		height = "auto",
		halign = "center",
	},

	{
		selectors = {"noresultsLabel"},
		halign = "center",
		fontSize = 18,
		vmargin = 8,
	},

	{
		selectors = {"shopGrid"},
		flow = "vertical",
		width = "auto",
		height = "auto",
		halign = "center",
	},

	{
		selectors = {"cartGrid"},
		flow = "vertical",
		width = "auto",
		height = "auto",
		halign = "center",
	},

	{
		selectors = {"shopGridRow"},
		width = "auto",
		height = "auto",
		flow = "horizontal",
		vmargin = 30,
	},

	{
		selectors = {"couponInventory"},
		width = "65%",
		height = "auto",
		halign = "center",
		flow = "vertical",
	},

	{
		selectors = {"couponInventoryRow"},
		width = "100%",
		height = 30,
		flow = "horizontal",
		bgimage = "panels/square.png",
		bgcolor = "#00000077",
		vmargin = 4,
	},

	{
		selectors = {"couponInventoryLabel"},
		fontSize = 14,
		minFontSize = 10,
		color = Styles.textColor,
		hmargin = 8,
		valign = "center",
	},

	{
		selectors = {"redeemCoupon"},
		width = "60%",
		height = "auto",
		halign = "center",
		flow = "vertical",
	},


	{
		selectors = {"titleLabel"},

		uppercase = true,

		color = Styles.textColor,

		tmargin = 8,
		bmargin = 4,
		fontWeight = "bold",
		fontSize = 18,

		width = "100%",
	},
	{
		selectors = {"authorLabel"},

		color = '#c0eddf',
		tmargin = 0,
		bmargin = 4,
		fontWeight = "bold",
		fontSize = 14,
		halign = "left",
		width = "auto",
	},
	{
		selectors = {"authorLabel", "hover"},
		color = '#c0ffdf',
	},
	{
		selectors = {"authorLabel", "hover", "press"},
		color = '#d0ffef',
	},
	{
		selectors = {"priceLabel"},

		color = "white",

		vmargin = 0,
		fontSize = 14,
	},
	{
		selectors = {"noteLabel"},

		italics = true,
		color = "white",
		vmargin = 0,
		fontSize = 14,
	},
	{
		selectors = {"itemDetails"},

		color = "#aaaaaaff",

		width = "100%",
		height = "auto",
		maxHeight = 70,
		textOverflow = "ellipsis",
		fontSize = 12,
		vmargin = 10,
	},

	{
		selectors = {"itemButton"},

		color = Styles.textColor,
		vmargin = 6,
		fontSize = 14,
		uppercase = true,
		width = 140,
		height = 40,
		bgimage = "panels/square.png",
		textAlignment = "center",
		borderColor = "#f6ddb6",
		borderWidth = 2,
		cornerRadius = 20,
	},
	{
		selectors = {"itemButton", "hover"},
		color = "#000000cc",
		transitionTime = 0.1,
		bgcolor = "srgb:#f6ddb6",
	},

	{
		selectors = {"itemButton", "checkoutButton"},
		color = "#000000cc",
		transitionTime = 0.1,
		bgcolor = "srgb:#f6ddb6",
	},
	{
		selectors = {"itemButton", "checkoutButton", "hover"},
		brightness = 1.4,
	},

	{
		selectors = {"itemButtonIcon"},
		halign = "left",
		valign = "center",
		height = 20,
		width = 20,
		hmargin = 16,
		bgcolor = Styles.textColor,
	},

	{
		selectors = {"itemButtonIcon", "check", "~parent:checkoutButton"},
		opacity = 0.02,
	},

	{
		selectors = {"itemButtonIcon", "parent:hover"},
		bgcolor = "#000000cc",
		opacity = 1,
	},

	{
		selectors = {"itemButtonIcon", "parent:checkoutButton"},
		bgcolor = "#000000ff",
	},


	{
		selectors = {"shopSummaryDisplay"},

		halign = "center",
		valign = "center",

		flow = "vertical",
		width = 320,
		height = 420 + heightStretch,
		hmargin = 30,
	},

	{
		selectors = {"shopSummaryDisplay", "newItem"},

		scale = 1.5,
		transitionTime = 1,
	},

	{
		selectors = {"newItem"},
		brightness = 5,
		transitionTime = 1,
	},

	{
		selectors = {"shopTextDisplay"},

		flow = "vertical",
		width = 320,
		height = 220,
		halign = "left",
	},

	{
		selectors = {"shopImage"},

		bgimage = "panels/square.png",
		bgcolor = "clear",


		halign = "center",
		valign = "top",
	},
	{
		selectors = {"shopImage", "selected"},
		borderColor = Styles.textColor,
		borderWidth = 2,
	},
	{
		selectors = {"shopImageBackground"},
		--bgimage = "panels/shopbg.png",
		bgcolor = "white",
		halign = "center",
		valign = "center",
		width = 473,
		height = 431 + heightStretch,
	},

	{
		selectors = {"shopItemBackground"},
		bgimage = "panels/shopbg.png",
		bgcolor = "white",
		halign = "center",
		valign = "center",
		width = "100%",
		height = "100%",
		opacity = 0.92,
	},

	{
		selectors = {"shopItemBackground", "parent:hover"},
		--transitionTime = 0.2,
		--opacity = 1,
	},



	{
		selectors = {"shopIcon"},

		autosizeimage = true,
		bgcolor = "white",
		halign = "center",
		valign = "center",
		width = 325,
		height = 180 + heightStretch,
	},

	{
		selectors = {"friendLabel"},
		bgimage = "panels/square.png",
		bgcolor = "#00000000",
		fontSize = 22,
		width = "100%",
		hpad = 8,
	},
	{
		selectors = {"friendLabel", "hover"},
		bgcolor = Styles.textColor,
		color = "black",
	},
	{
		selectors = {"friendLabel", "selected"},
		bgcolor = Styles.textColor,
		color = "black",
	},

	{
		selectors = {"collapseOnNoCommerce", "noCommerce"},
		collapsed = 1,
	},

}

local MakeShopImageDisplay = function(options)
	options = options or {}
	local uiscale = options.uiscale or 1
	options.uiscale = nil

	local footer = options.footer
	options.footer = nil

	local bg = gui.Panel{
		classes = {"shopImageBackground"},
		floating = true,
		interactable = false,
		uiscale = uiscale,
		x = 3*uiscale,
		y = -4*uiscale,
	}


	local m_item = nil

	local args = {
		classes = {"shopImage"},

		width = 325*uiscale,
		height = (180 + heightStretch)*uiscale,

		bgimage = "panels/square.png",
		bgcolor = "clear",

		bg,
		press = function(element)
			if m_item ~= nil then
				element:FireEventOnParents("showItemDetails", m_item)
			end
		end,

		refreshItem = function(element, item)
			if not footer then
				m_item = item
				element:FireEvent("refreshImage", item.images[1])

			end
		end,

		refreshImage = function(element, imageid)
			element.children = {
				bg,
				gui.Panel{
					classes = {"shopIcon"},
					uiscale = uiscale,
					bgimage = imageid,
				},
			}
		end
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

local MakeShopItemText = function(options)
	local m_itemId = ""
	local m_item = nil

	options = options or {}

	local removeButtonOnRight = options.removeButtonOnRight
	options.removeButtonOnRight = nil

	local args = {
		classes = {"shopTextDisplay"},

		gui.Label{
			classes = {"titleLabel"},
			refreshItem = function(element, item)
				element.text = item.name
			end,
		},

		gui.Label{
			classes = {"authorLabel"},
			data = {
				artistid = nil,
			},
			refreshItem = function(element, item)
				local artist = nil
				if item.artistid ~= nil then
					artist = assets.artists[item.artistid]
				end

				if artist == nil then
					element:SetClass("collapsed", true)
				else
					element:SetClass("collapsed", false)
					element.text = artist.name
					element.data.artistid = item.artistid
				end
			end,

			click = function(element)
				element:FireEventOnParents("focusArtist", element.data.artistid)
			end,
		},

		gui.Label{
			classes = {"priceLabel", "collapsedWhenInventory", "collapseOnGift", "collapseOnNoCommerce"},
			refreshItem = function(element, item)
				m_itemId = item.id
				m_item = item

				if item.price <= 0 then
					element.text = "FREE"
				else
					local dollars = math.tointeger(math.floor(item.price/100))
					local cents = math.tointeger(item.price%100)
					element.text = string.format("$%d.%02d", dollars, cents)
				end
			end,

		},

		gui.Label{
			classes = {"itemDetails"},
			markdown = true,
			links = true,
			hoverLink = function(element, link)
				printf("HOVER:: %s", link)
			end,
			refreshItem = function(element, item)
				local text = item.details
				if text == nil then
					text = ""
				end

				if item.hasBundle then
					if text ~= "" then
						text = text .. "\n\n"
					end

					local allItems = assets.shopItems

					local listText = ""
					local count = 0
					local price = 0
					for itemid,_ in pairs(item.bundle) do
						local item = allItems[itemid]
						if item ~= nil then
							listText = string.format("%s\n* [%s](shop/%s)", listText, item.name, itemid)
							count = count+1
							price = price + item.price
						end
					end

					local dollars = math.tointeger(math.floor(price/100))
					local cents = math.tointeger(price%100)
					text = string.format("%sBy purchasing this bundle you unlock %d products:\n%s\n\n<b>Total value: $%d.%02d.</b>", text, count, listText, dollars, cents)


				end

				element.text = text
			end,
		},

		gui.Label{
			classes = {"itemButton", "collapseOnGift"},
			text = "Remove",
			x = cond(removeButtonOnRight, 40, 0),
			floating = true,
			halign = cond(removeButtonOnRight, "right", "left"),
			valign = "bottom",


			refreshCart = function(element, shoppingCart)
				if shoppingCart[m_itemId] then
					element:SetClass("collapsed", false)
				else
					element:SetClass("collapsed", true)
				end
			end,

			press = function(element)
				element:FireEventOnParents("removeFromCart", m_item)
			end,
		},

		gui.Label{
			classes = {"noteLabel", "collapseOnCart", "collapseOnGift", "collapsedWhenInventory" },
			text = "This item is in your cart",
			valign = "bottom",
			x = 160,
			y = -20,

			refreshCart = function(element, shoppingCart)
				if shoppingCart[m_itemId] then
					element.text = "This item is in your cart"
					element:SetClass("collapsed", false)
				else
					if shop:ItemInInventory(m_itemId) then
						element.text = "You own this item"
						element:SetClass("collapsed", false)
					else
						element:SetClass("collapsed", true)
					end
				end
			end,
		},




		gui.Label{
			classes = {"itemButton", "collapsedWhenInventory", "collapseOnCart", "collapseOnGift", "collapseOnNoCommerce"},
			text = "Add to Cart",
			floating = true,
			valign = "bottom",

			refreshCart = function(element, shoppingCart)
				if shoppingCart[m_itemId] then
					element:SetClass("collapsed", true)
				else
					element.text = cond(shop:ItemInInventory(m_itemId), "Add as Gift", "Add to Cart")
					element:SetClass("collapsed", false)
				end
			end,

			press = function(element)
				element:FireEventOnParents("addToCart", m_item)

				analytics.Event{
					type = "shopAddCart",
				}

			end,
		},

	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

local MakeShopItem = function()
	return gui.Panel{
		classes = {"shopSummaryDisplay"},

		gui.Panel{
			classes = "shopItemBackground",
			interactable = false,
			floating = true,
			hpad = 100,
			vpad = 250,
		},

		MakeShopImageDisplay(),

		MakeShopItemText(),

	}
end

local ShopEntryPanel = function(item)
	local resultPanel

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",

		MakeShopImageDisplay{
			uiscale = 0.62
		},

		gui.Panel{
			width = 8,
			height = 1,
		},
		MakeShopItemText{
			removeButtonOnRight = true
		},
	}

	resultPanel:FireEventTree("refreshItem", item)

	return resultPanel
end

local ShowItemDetailsInternal = function(args)

	local m_shopItemText = MakeShopItemText{
		halign = "left",
		height = cond(args.gift, 140, 530),
	}



	local m_footerItems = {}

	local m_imageDisplay = MakeShopImageDisplay{
		halign = "left",
		uiscale = cond(args.gift, 0.75, 1.5),
	}

	return gui.Panel{
		classes = {"shopDetailsMainPanel"},

		styles = {
			--when showing details, we allow the itemDetails text to be much longer.
			{
				selectors = {"itemDetails"},
				maxHeight = 340,
			},

			{
				selectors = {"shopDetailsMainPanel"},
				flow = cond(args.gift, "vertical", "horizontal"),
				width = "auto",
				height = "auto",
			},
		},

		--text shows up top for gift display.
		cond(args.gift, m_shopItemText),

		gui.Panel{
			width = cond(args.gift, 300, 600),
			height = cond(args.gift, 300, 600),
			halign = "left",
			bgimage = "#DicePreview",
			bgcolor = "white",
			edgeFade = 0.4,
			draggable = true,
			dragMove = false,
			dragxwrap = true,
			dragywrap = true,

			beginDrag = function(element)
				element.data.scene.dragging = true
			end,

			drag = function(element)
				element.data.scene.dragging = false
			end,

			gui.Label{
				text = "Equip",
				classes = {"itemButton", "collapsedUnlessInventory"},
				valign = "bottom",
				halign = "center",
				y = 8,

				data = {
					item = nil
				},

				click = function(element)
					dmhub.SetSettingValue("diceequipped", element.data.item.assetid)
					element.parent:FireEventTree("showProductDetails", element.data.item)
				end,

				showProductDetails = function(element, item)
					element.data.item = item
					element:SetClass("collapsed", item.itemType == "Dice" and item.assetid == dmhub.GetSettingValue("diceequipped"))
				end,
			},

			gui.Label{
				text = "Equipped",
				classes = {"titleLabel", "collapsedUnlessInventory"},
				valign = "bottom",
				halign = "center",
				width = "auto",
				y = 8,

				showProductDetails = function(element, item)
					element:SetClass("collapsed", item.itemType == "Dice" and item.assetid ~= dmhub.GetSettingValue("diceequipped"))
				end,
			},

			data = {
				item = nil,
				scene = nil,
				--Default selection on the d10 pair (index 1, paired with 2)
				--so the preview opens centered with d3 left and d6 right.
				diceIndex = 1,
			},

			chooseDice = function(element, index)
				element.data.diceIndex = index
			end,

			think = function(element)
				element.data.scene.assetid = element.data.item.assetid
				element.data.scene.selectedIndex = element.data.diceIndex

			end,

			showProductDetails = function(element, item)
				if item.itemType == "Dice" then
					element.data.item = item
					element.data.scene = dice.GetPreviewScene()
					element.data.scene.assetid = item.assetid
					element.thinkTime = 0.01
					element:SetClass("collapsed", false)
				else
					element.data.item = nil
					element.thinkTime = nil
					element.data.scene = nil
					element:SetClass("collapsed", true)
				end
			end,
		},

		gui.Panel{
			flow = "vertical",
			width = cond(args.gift, 300, 600),
			height = "auto",
			halign = "left",
			m_imageDisplay,

			showProductDetails = function(element, item)
				element:SetClass("collapsed", item.itemType == "Dice")
			end,

			gui.Panel{
				classes = {"collapsedWhenGift"},
				height = "auto",
				width = "auto",
				flow = "horizontal",
				halign  = "left",
				vmargin = 6,
				showProductDetails = function(element, item)
					for i=1,#item.images do
						m_footerItems[i] = m_footerItems[i] or gui.Panel{
							classes = {"footerItem"},
							bgimage = "panels/square.png",
							x = 8,
							bgcolor = "clear",
							width = "auto",
							height = "auto",
							data = {
								item = item,
							},
							press = function(element)
								for j,item in ipairs(element.parent.children) do
									item:SetClassTree("selected", j == i)
								end

								m_imageDisplay:FireEventTree("refreshImage", element.data.item.images[i])
							end,
							MakeShopImageDisplay{
								uiscale = 0.3,
								footer = true,
								hmargin = 8,
								x = -12,
							}
						}

						m_footerItems[i].data.item = item
					end

					for i=1,#m_footerItems do
						m_footerItems[i]:SetClass("collapsed", item.images[i] == nil)
						if item.images[i] ~= nil then
							m_footerItems[i]:FireEventTree("refreshImage", item.images[i])
							m_footerItems[i]:SetClassTree("selected", i == 1)
						end

					end

					element.children = m_footerItems
				end,
			},
		},


		--text shows up top for gift display.
		cond(args.gift, nil, m_shopItemText),
	}


end

local ShowItemDetailsPanel = function(args)
	args = args or {}

	local resultPanel

	resultPanel = gui.Panel{

		classes = {"collapsed"},
		flow = "vertical",

		width = "auto",
		height = "auto",
		halign = "center",

		gui.Panel{
			classes = "shopItemBackground",
			floating = true,
			hpad = -220,
			vpad = 160,
		},

		showProductDetails = function(element, item)
			element:FireEventTree("refreshItem", item)
			element:SetClass("collapsed", false)
		end,

		hideProductDetails = function(element)
			element:SetClass("collapsed", true)
		end,

		ShowItemDetailsInternal(args),

		gui.Label{
			text = "Auto Install",
			classes = {"itemButton", "collapsedUnlessInventory"},
			valign = "bottom",
			halign = "right",
			width = 200,
			vmargin = 30,
			floating = true,

			data = {
				item = nil
			},

			linger = function(element)
				gui.Tooltip{
					text = "Whether this asset will automatically be added to all of your games.",
					halign = "center",
					valign = "top",
				}(element)
			end,

			click = function(element)
				element:SetClass("checkoutButton", not element:HasClass("checkoutButton"))
				element.data.item.autoInstall = element:HasClass("checkoutButton")
				element.parent:FireEventTree("showProductDetails", element.data.item)
			end,

			showProductDetails = function(element, item)
				element.data.item = item

				if item.itemType ~= "Module" then
					element:SetClass("collapsed", true)
					return
				end

				element:SetClass("collapsed", false)
				element:SetClass("checkoutButton", item.autoInstall)
			end,

			gui.Panel{
				classes = {"itemButtonIcon", "check"},
				bgimage = "icons/icon_common/icon_common_29.png",
			},
		},


		gui.Label{
			classes = {"itemButton"},
			vmargin = 16,
			text = "Go Back",

			press = function(element)
				element:FireEventOnParents("showProductsPage")
			end,
		},
	}

	return resultPanel
end

function ShowShopItemDetails(args)
	args = args or {}
	local params = {
		width = "auto",
		height = "auto",
		styles = shopStyles,

		ShowItemDetailsInternal(args)
	}

	for k,v in pairs(args) do
		params[k] = v
	end

	params.gift = nil

	return gui.Panel(params)
end

local function CreateShopScreenInternal(arguments)
	analytics.Event{
		type = "showShop",
	}

	arguments = arguments or {}

	local initialArtistid = arguments.artistid
	arguments.artistid = nil

	local styles ={
			Styles.Default,

			{
				selectors = {'main-panel'},
				width = 1920,
				height = 1080,
				bgcolor = 'grey',
				halign = 'center',
				valign = 'center',
			},
	}

	local dividerGradient = core.Gradient{
		point_a = {x=0,y=0},
		point_b = {x=1,y=0},
		stops = {
			{
				position = 0,
				color = core.Color{r = 1, g = 1, b = 1, a = 0},
			},
			{
				position = 0.1,
				color = core.Color{r = 1, g = 1, b = 1, a = 1},
			},
			{
				position = 0.9,
				color = core.Color{r = 1, g = 1, b = 1, a = 1},
			},
			{
				position = 1,
				color = core.Color{r = 1, g = 1, b = 1, a = 0},
			},
		},
	}

	local m_focusedArtist = nil

	local fullProductDatabase = {}
	local productDatabase = {}

	local shopItems = assets.shopItems

	for k,shopItem in pairs(shopItems) do
		if shopItem.onsale then
			productDatabase[#productDatabase+1] = shopItem
		end

		fullProductDatabase[#fullProductDatabase+1] = shopItem
	end

	table.sort(productDatabase, function(a,b) return a.name < b.name end)

	local DisplayShop = function(productDatabase)

		local m_assetToItemInstance = {}
		local m_allProducts = productDatabase

		local m_newInventoryItems = {}

		local m_shoppingCart = {}

		local m_category = "all"

		local products = m_allProducts

		local resultPanel

		local pageSelected = 1

		local rowSize = 3
		local numRows = 4

		local rows = {}

		local pageSize = rowSize*numRows

		local shopItems = {}
		for i=1,pageSize do
			shopItems[#shopItems+1] = MakeShopItem()
		end

		local NumPages = function()
			return math.ceil(#products/pageSize)
		end

		local ShowPage = function(npage, newItemIndexes)
			for _,row in ipairs(rows) do
				row:SetClass("collapsed", true)
			end

			local baseIndex = (npage-1)*pageSize
			local highestIndex = 0
			for i=1,pageSize do
				if products[baseIndex+i] == nil then
					shopItems[i]:SetClass("hidden", true)

				else
					shopItems[i]:SetClass("hidden", false)
					shopItems[i]:FireEventTree("refreshItem", products[baseIndex+i])

					local rowIndex = math.ceil(i/rowSize)
					rows[rowIndex]:SetClass("collapsed", false)

					if newItemIndexes ~= nil and newItemIndexes[baseIndex+i] then
						shopItems[i]:PulseClassTree("newItem")
					end
				end
			end

			resultPanel:FireEventTree("refreshCart", m_shoppingCart)

		end

		local ExecuteSearch = function(str)
			local words = {}

			if str ~= nil then
				words = string.split(string.lower(str), " ")
			end

			local cat = m_category
			if m_focusedArtist ~= nil then
				cat = "all"
			end

			products = {}

			local newItemIndexes = {}

			for index,product in ipairs(m_allProducts) do

				local artistName = ""
				if product.artistid ~= nil then
					local artist = assets.artists[product.artistid]
					if artist ~= nil then
						artistName = string.lower(artist.name)
					end
				end

				local mismatch = false
				for _,word in ipairs(words) do
					if string.find(string.lower(product.name), word) == nil and (product.details == nil or string.find(string.lower(product.details), word) == nil) and string.find(artistName, word) == nil then
						mismatch = true
					end
				end

				if m_focusedArtist ~= nil and product.artistid ~= m_focusedArtist then
					mismatch = true
				end

				if cat ~= "all" and product.keywords ~= cat then
					mismatch = true
				end

				if mismatch == false then
					products[#products+1] = product
				end

				if m_newInventoryItems[index] then
					newItemIndexes[index] = true
				end
			end

			m_newInventoryItems = {}

			resultPanel:FireEventTree("refreshSearch")
			ShowPage(1, newItemIndexes)
		end

		local shopItemIndex = 0
		for i=1,numRows do
			rows[#rows+1] = gui.Panel{
				classes = {"shopGridRow"},
				shopItems[shopItemIndex+1],
				shopItems[shopItemIndex+2],
				shopItems[shopItemIndex+3],
			}

			shopItemIndex = shopItemIndex+3
		end

		local footerPanels = {}
		local footerPageLeft = gui.Label{
					classes = {"pagingFooterArrow", "collapseOnCart"},
					text = "<",
					halign = "left",
					press = function(element)
						if footerPanels[pageSelected-1] ~= nil then
							footerPanels[pageSelected-1]:FireEvent("press")
						end
					end,
				}

		local footerPageRight = gui.Label{
					classes = {"pagingFooterArrow", "collapseOnCart"},
					text = ">",
					halign = "right",
					press = function(element)
						if footerPanels[pageSelected+1] ~= nil then
							footerPanels[pageSelected+1]:FireEvent("press")
						end
					end,
				}

		for i=1,6 do
			footerPanels[#footerPanels+1] = gui.Label{
				classes = {"pagingLabel", cond(i == pageSelected, "selected")},
				text = string.format("%d", i),
				press = function(element)
					for j=1,#footerPanels do
						footerPanels[j]:SetClass("selected", j == i)
					end

					ShowPage(i)
					resultPanel.vscrollPosition = 1
					pageSelected = i
				end,

				refreshSearch = function(element)
					element:SetClass("collapsed", i > NumPages())
				end,
			}
		end

		local m_linkEventHandlerId = nil

		resultPanel = gui.Panel{
			id = "shopResultPanel",
			width = "100%",
			height = "100%",
			halign = "center",
			valign = "top",
			classes = {"framedPanel"},
			styles = {
				Styles.Panel,
				shopStyles,
			},

			create = function(element)
				if initialArtistid ~= nil then
					element:FireEvent("focusArtist", initialArtistid)
				end

				m_linkEventHandlerId = dmhub.RegisterEventHandler("link", function(link)
					printf("LINK:: %s", link)
					local prefix = "shop/"
					if string.sub(link, 1, #prefix) == prefix then
						local itemid = string.sub(link, #prefix+1)
						local item = assets.shopItems[itemid]

						if item ~= nil then
							element:FireEvent("showItemDetails", item)
							return true
						end
					end

				end)
			end,

			destroy = function(element)
				if m_linkEventHandlerId ~= nil then
					dmhub.DeregisterEventHandler(m_linkEventHandlerId)
					m_linkEventHandlerId = nil
				end
			end,

			showItemDetails = function(element, item)
				element:FireEventTree("hideProducts")
				element:FireEventTree("showProductDetails", item)
				element:FireEventTree("refreshCart", m_shoppingCart)
			end,

			showProductsPage = function(element)
				element:FireEventTree("showProducts")
				element:FireEventTree("hideProductDetails")
			end,

			addToCart = function(element, item)
				m_shoppingCart[item.id] = true
				resultPanel:FireEventTree("refreshCart", m_shoppingCart, true)
			end,

			removeFromCart = function(element, item)
				m_shoppingCart[item.id] = nil
				resultPanel:FireEventTree("refreshCart", m_shoppingCart)
				if element:HasClass("showingCart") then
					element:FireEvent("showCart")
				end
			end,

			showCart = function(element)

				element:FireEventTree("showProducts")
				element:FireEventTree("hideProductDetails")
				element:FireEventTree("showShoppingCart")
				element:SetClassTree("showingCart", true)
				element:SetClassTree("showingCartWithItems", false)
				for _,_ in pairs(m_shoppingCart) do
					element:SetClassTree("showingCartWithItems", true)
					break
				end
			end,

			hideCart = function(element)
				products = m_allProducts
				resultPanel:FireEventTree("refreshSearch")
				ShowPage(1)
				element:SetClassTree("showingCart", false)
				element:SetClassTree("showingCartWithItems", false)
			end,

			showInventory = function(element)
				if element:HasClass("artistFocus") then
					element:FireEvent("focusArtist", nil)
				end

				if element:HasClass("redeemingCoupon") then
					resultPanel:FireEventTree("clearredeem")
				end

				local productIndex = {}
				for _,item in ipairs(fullProductDatabase) do
					productIndex[item.id] = item
				end
				m_assetToItemInstance = {}
				m_allProducts = {}

				local itemsAck = "itemsAcknowledged"

				local itemsAcknowledged = dmhub.GetSettingValue(itemsAck)

				local newItems = false
				m_newInventoryItems = {}

				local sortedProducts = {}

				for key,productInfo in pairs(shop.inventoryItems) do
					sortedProducts[#sortedProducts+1] = {
						key = key,
						productInfo = productInfo,
					}

					if itemsAcknowledged[productInfo.itemid] == nil then
						sortedProducts[#sortedProducts].newItem = true
						itemsAcknowledged[productInfo.itemid] = true
						newItems = true
					end
				end

				--sort so the most recent items are first.
				table.sort(sortedProducts, function(a,b) return a.productInfo.ctime > b.productInfo.ctime end)

				for _,entry in ipairs(sortedProducts) do
					local key = entry.key
					local productInfo = entry.productInfo
					m_allProducts[#m_allProducts+1] = productIndex[productInfo.itemid]
					m_assetToItemInstance[productInfo.itemid] = m_assetToItemInstance

					if entry.newItem then
						m_newInventoryItems[#m_allProducts] = true
					end
				end

				if newItems then
					dmhub.SetSettingValue(itemsAck, itemsAcknowledged)
				end

				element:SetClassTree("inventory", true)

				ExecuteSearch("")
			end,

			hideInventory = function(element)
				if element:HasClass("showingCouponInventory") then
					resultPanel:FireEventTree("clearCouponDisplay")
				end

				if element:HasClass("redeemingCoupon") then
					resultPanel:FireEventTree("clearredeem")
				end


				m_allProducts = productDatabase
				m_assetToItemInstance = {}
				element:SetClassTree("inventory", false)

				ExecuteSearch("")
			end,

			focusArtist = function(element, artistid)
				m_focusedArtist = artistid

				element:SetClassTree("artistFocus", artistid ~= nil)
				element:FireEventTree("setArtist", artistid)
				if element:HasClass("inventory") then
					element:FireEvent("hideInventory")
				else
					element:FireEvent("showProductsPage")
					ExecuteSearch("")
				end

			end,

			gui.Panel{
				floating = true,
				halign = "center",
				valign = "top",
				width = "100%",
				height = "100%",
				bgimage = "media/shopbg.webm",
				bgcolor = "#bbbbbbff",
			},


			gui.Panel{


				halign = "right",
				valign = "top",
				width = "1920-16",
				height = "100%",
				vscroll = true,
				flow = "vertical",

				gui.Panel{
					flow = "vertical",
					width = "100%",
					height = 300,

					gui.Panel{
						--padding
						height = 40
					},

					gui.Panel{
						width = 128,
						height = 64,
						bgimage = "panels/logo/DMHubLogoBare.png",
						bgcolor = "white",
						halign = "center",
						valign = "top",
						vmargin = 16,
					},


					gui.Panel{
						classes = {"collapsedUnlessInventory"},
						halign = "center",
						flow = "vertical",
						width = "auto",
						height = "auto",
						gui.Label{
							classes = {"shopTitle"},
							text = "Your Inventory",
						},

						gui.Label{
							classes = {"shopDescription"},
							text = "All the items you own!",
						},
					},

					gui.Panel{
						id = "artistBanner",
						classes = {"collapseOnCart","collapsedWhenInventory", "collapsed"},
						width = 500,
						height = 128,
						halign = "center",
						bgcolor = "white",
						bgimage = "panels/square.png",

						setArtist = function(element, artistid)
							local artist = nil
							if artistid ~= nil then
								artist = assets.artists[artistid]
							end

							element:SetClass("collapsed", artist == nil)
							if artist ~= nil then
								element.bgimage = artist.bannerImage
							end
						end,
					},

					gui.Panel{
						classes = {"collapseOnCart","collapsedWhenInventory", "collapsedWhenArtistFocus"},
						halign = "center",
						flow = "vertical",
						width = "auto",
						height = "auto",
						gui.Label{
							classes = {"shopTitle"},
							text = "Official Shop",
						},

						gui.Label{
							classes = {"shopDescription"},
							text = "Come in and stay a while! Find the perfect item to enhance your adventures.",
						},
					},

					gui.Panel{
						classes = {"collapseUnlessCart"},
						halign = "center",
						flow = "vertical",
						width = "auto",
						height = "auto",
						gui.Label{
							classes = {"shopTitle"},
							text = "Shopping Cart",
						},

						gui.Label{
							classes = {"shopDescription"},
							text = "Review the items in your cart. Check out when you're ready!",
						},
					},

					--remove artist displayed panel.
					gui.Label{
						classes = {"authorLabel", "collapsed"},
						text = "All Creators",
						height = 30,
						width = "auto",
						halign = "center",
						setArtist = function(element, artistid)
							element:SetClass("collapsed", artistid == nil)
						end,
						click = function(element)
							element:FireEventOnParents("focusArtist", nil)
						end,
					},

					--categories.
					gui.Panel{
						classes = {"collapsedWhenArtistFocus", "collapseOnCart"},
						halign = "center",
						valign = "bottom",
						height = 30,
						width = "auto",
						flow = "horizontal",

						showProductDetails = function(element)
							element:SetClass("collapsed", true)
						end,

						hideProductDetails = function(element)
							element:SetClass("collapsed", false)
						end,

						styles = {
							{
								selectors = {"redeemingCoupon"},
								collapsed = 1,
							},
							{
								selectors = {"categoryLabel"},
								bgimage = "panels/square.png",
								minWidth = 120,
								width = "auto",
								height = 24,
								fontSize = 18,
								textAlignment = "center",
								color = Styles.textColor,
								bgcolor = "#22222222"
							},
							{
								selectors = {"categoryLabel", "hover"},
								transitionTime = 0.2,
								bgcolor = "#88888888"
							},
							{
								selectors = {"categoryLabel", "selected"},
								transitionTime = 0.2,
								bgcolor = "#ff6666bb"
							},
						},

						data = {
							panels = {
							},
							storeCategories = {
								{
									id = "all",
									text = "All",
								},
								{
									id = "assets",
									text = "Map Making",
								},
								{
									id = "dice",
									text = "Dice",
								},
								{
									id = "codes",
									text = "Gift Codes",
									class = "collapsedUnlessInventory",
									exec = function(element)
										resultPanel:SetClassTree("redeemingCoupon", false)
										resultPanel:SetClassTree("showingCouponInventory", true)
										resultPanel:FireEventTree("showcoupons")
									end,
								},
							},

							CreatePanel = function(cat)
								return gui.Label{
									classes = {"categoryLabel", cond(m_category == cat.id, "selected"), cat.class},
									text = cat.text,
									press = function(element)
										for _,child in ipairs(element.parent.children) do
											child:SetClass("selected", element == child)
										end

										if cat.exec ~= nil then
											cat.exec()
										else
											if element:HasClass("showingCouponInventory") then
												resultPanel:SetClassTree("showingCouponInventory", false)
											end
											m_category = cat.id
											ExecuteSearch("")
										end
									end,
								}
							end,
						},

						refreshCart = function(element)

							local newPanels = {}
							local children = {}
							for _,cat in ipairs(element.data.storeCategories) do
								children[#children+1] = element.data.panels[cat.id] or element.data.CreatePanel(cat)
								newPanels[cat.id] = children[#children]
							end

							element.children = children
							element.data.panels = newPanels
						end,

						clearCouponDisplay = function(element)
							if element:HasClass("showingCouponInventory") and #element.children > 0 then
								element.children[1]:FireEvent("press")
							end
						end,

						clearredeem = function(element)
							resultPanel:SetClassTree("redeemingCoupon", false)
						end,

					},
				},

				--redeem coupon.
				gui.Panel{
					id = "redeemCoupon",
					classes = {"redeemCoupon"},
					flow = "vertical",

					styles = {
						{
							selectors = {"redeemCoupon", "~redeemingCoupon"},
							collapsed = 1,
						}
					},

					redeemcoupons = function(element)
						element.children = {
							gui.Label{
								text = "Enter gift code",
								fontWeight = "bold",
								halign = "center",
								fontSize = 24,
								width = "auto",
								vmargin = 30,

							},

							gui.Input{
								placeholderText = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
								characterLimit = 36,
								width = 400,
								textAlignment = "left",
								edit = function(element)
									element.parent:FireEventTree("cleargift")
									if #element.text ~= 0 and #element.text ~= 36 then
										element.parent:FireEventTree("message", "Incorrect number of characters")
									elseif #element.text == 36 then
										element.parent:FireEventTree("message", "Searching...")
										shop:QueryGiftCode(element.text, function(coupon)
											if coupon == nil then
												element.parent:FireEventTree("message", "Invalid gift code")
												return
											end

											if element == nil or (not element.valid) or coupon.code ~= element.text then
												--user edited the input since the request was sent.
												return
											end

											if coupon.redeemed then
												element.parent:FireEventTree("message", "This code has already been redeemed.")
												return
											end

											local item = assets.shopItems[coupon.itemid]
											if item == nil then
												element.parent:FireEventTree("message", "Error: Unknown item")
												return
											end

											element.parent:FireEventTree("message", "Your gift code is ready to be redeemed!")
											element.parent:FireEventTree("showgift", item, element.text)
										end,
										function(error)
											element.parent:FireEventTree("message", string.format("Error: %s", error))
										end)
									else
										element.parent:FireEventTree("message", "")
									end
								end,
							},

							gui.Label{
								text = "",
								fontSize = 18,
								minFontSize = 10,
								width = "60%",
								halign = "center",
								textAlignment = "center",
								height = 24,
								vmargin = 4,
								message = function(element, message)
									element.text = message
								end,
							},

							gui.Label{
								classes = {"collapsed"},
								text = "",
								fontSize = 18,
								uppercase = true,
								fontWeight = "bold",
								width = "60%",
								halign = "center",
								textAlignment = "center",
								height = 24,
								halign = "center",
								vmargin = 4,

								showgift = function(element, item)
									element.text = item.name
									element:SetClass("collapsed", false)
								end,

								cleargift = function(element)
									element:SetClass("collapsed", true)
								end,
							},

							gui.Panel{
								height = "auto",
								width = "auto",
								flow = "horizontal",
								halign = "center",

								gui.Button{
									classes = {"collapsed"},
									hmargin = 16,
									halign = "center",
									vmargin = 30,
									text = "Redeem Gift",
									data = {
										code = nil
									},
									showgift = function(element, item, code)
										element.data.code = code
										element:SetClass("collapsed", false)
									end,
									cleargift = function(element)
										element:SetClass("collapsed", true)
									end,
									click = function(element)
										element.parent.parent:FireEventTree("message", "Redeeming code...")
										element:SetClass("collapsed", true)
										printf("Posting redeem...")
										net.Post{
											url = dmhub.cloudFunctionsBaseUrl .. "/redeem",
											data = {
												code = element.data.code,
											},

											success = function(data)
												printf("Posting redeem: success")
												if type(data) ~= "table" then
													element.parent.parent:FireEventTree("message", "Error: Invalid response")
													return
												end

												if data.error then
													element.parent.parent:FireEventTree("message", "Error: " .. data.error)
													return
												end

												element.parent.parent:FireEventTree("message", "Your item has been redeemed!")
												element.parent.parent:FireEventTree("redeemed")
											end,

											error = function(msg)
												printf("Posting redeem: error")
												element.parent.parent:FireEventTree("message", "Error: " .. msg)
											end,
										}
										--resultPanel:SetClassTree("redeemingCoupon", false)
									end,
								},

								gui.Button{
									hmargin = 16,
									halign = "center",
									vmargin = 30,
									text = "Cancel",
									showgift = function(element, item, code)
										element:SetClass("collapsed", false)
									end,
									cleargift = function(element)
										element:SetClass("collapsed", false)
									end,
									redeemed = function(element)
										element:SetClass("collapsed", true)
									end,
									click = function(element)
										resultPanel:SetClassTree("redeemingCoupon", false)
									end,
								},

								gui.Button{
									classes = {"collapsed"},
									hmargin = 16,
									halign = "center",
									vmargin = 30,
									text = "Go to Inventory",
									showgift = function(element, item, code)
										element.data.code = code
										element:SetClass("collapsed", true)
									end,
									cleargift = function(element)
										element:SetClass("collapsed", true)
									end,
									redeemed = function(element)
										element:SetClass("collapsed", false)
									end,
									click = function(element)
										resultPanel:FireEvent("showInventory")
									end,
								},
							}
						}
					end,
				},

				--coupon inventory.
				gui.Panel{
					classes = {"couponInventory"},
					id = "couponInventory",

					styles = {
						{
							selectors = {"couponInventory", "~showingCouponInventory"},
							collapsed = 1,
						}
					},

					showcoupons = function(element)
						element.children = {}

						local ncodes = 0
						ncodes = shop:RetrieveGiftCodes(function(coupon)
							local item = assets.shopItems[coupon.itemid]
							local itemName = "(Unknown item)"
							if item ~= nil then
								itemName = item.name
							end
							element:AddChild(gui.Panel{
								data = {
									ord = coupon.ctime,
								},
								classes = {"couponInventoryRow"},
								gui.Label{
									classes = {"couponInventoryLabel"},
									width = "25%",
									text = itemName,
								},

								gui.Label{
									classes = {"couponInventoryLabel"},
									width = "7%",
									text = dmhub.FormatTimestamp(coupon.ctime, "yyyy-MM-dd"),
								},

								gui.Label{
									classes = {"couponInventoryLabel"},
									width = "30%",
									text = cond(coupon.redeemed, string.format(tr("Redeemed by %s on %s"), tostring(coupon.redeemUserFullName), dmhub.FormatTimestamp(coupon.mtime, "yyyy-MM-dd")), "Available for redemption"),
								},

								gui.Label{
									classes = {"couponInventoryLabel"},
									bgimage = "panels/square.png",
									bgcolor = "#00000000",
									width = "27%",
									text = coupon.code,

									press = function(element)
										local tooltip = gui.Tooltip{text = tr("Copied to Clipboard"), valign = "top", borderWidth = 0}(element)
										dmhub.CopyToClipboard(coupon.code)
									end,

									gui.Panel{
										bgimage = "icons/icon_app/icon_app_108.png",
										bgcolor = Styles.textColor,
										width = 16,
										height = 16,
										valign = "center",
										halign = "right",
										styles = {
											{
												selectors = {"parent:hover"},
												brightness = 1.5,
											}
										},
									},
								},
							})

							local children = element.children
							table.sort(children, function(a,b) return b.data.ord < a.data.ord end)
							element.children = children
						end,
						function(error)
							element:AddChild(gui.Panel{
								data = {
									ord = 9999999999999,
								},
								classes = {"couponInventoryRow"},
								gui.Label{
									classes = {"couponInventoryLabel"},
									width = "100%",
									color = "red",
									text = string.format("Error: %s", error),
								},
							})
						end,
						function(allCoupons)
						end)

						if ncodes == 0 then
							element.children = {
								gui.Label{
									classes = {"noresultsLabel"},
									data = { ord = 0 },
									maxWidth = 800,
									text = "You have no gift codes in your inventory. You can purchase gift codes by adding items to your cart and selecting to gift at checkout."
								}
							}
						end
					end,
				},

				--main lower panel.
				gui.Panel{
					width = "100%",
					height = "auto",

					styles = {
						{
							selectors = {"showingCouponInventory"},
							collapsed = 1,
						},
						{
							selectors = {"redeemingCoupon"},
							collapsed = 1,
						},
					},

					gui.Panel{
						floating = true,
						halign = "left",
						valign = "top",
						flow = "vertical",
						width = 400,
						height = 200,
						floating = true,
						vmargin = 20,
						hmargin = 20,



						styles = {
							{
								selectors = {"showingCart"},
								hidden = 1,
							}
						},

						gui.Input{
							placeholderText = "Search",
							editlag = 0.2,
							edit = function(element)
								element:FireEvent("change")
							end,
							change = function(element)
								element:FireEventOnParents("showProductsPage")
								ExecuteSearch(element.text)

								analytics.Event{
									type = "shopSearch",
								}

							end,

							gui.Panel{
								halign = "left",
								x = -22,
								y = 4,
								width = 16,
								height = 16,
								bgcolor = "white",
								bgimage = "icons/icon_tool/icon_tool_42.png",
							},
						},
					},

					ShowItemDetailsPanel(),

					gui.Panel{
						classes = {"centerPanel"},

						showProducts = function(element)
							element:SetClass("collapsed", false)
						end,

						hideProducts = function(element)
							element:SetClass("collapsed", true)
						end,

						gui.Panel{
							classes = {"collapsedUnlessCheckingOut"},
							flow = "vertical",
							width = "100%",
							height = "auto",
							create = function(element)
								shop.events:Listen(element)
							end,

							refreshInventory = function(element)
								if element:HasClass("checkingOut") then
									m_shoppingCart = {}
									resultPanel:SetClassTree("checkingOut", false)
									element:FireEventOnParents("hideCart")

								end

							end,

							gui.Label{
								width = "auto",
								height = "auto",
								fontSize = 16,
								halign = "center",
								text = "Use your web browser to pay for your items...",
							},

							gui.Label{
								classes = {"itemButton"},
								vmargin = 30,
								halign = "center",
								text = "Go Back",

								press = function(element)
									resultPanel:SetClassTree("checkingOut", false)
									element:FireEventOnParents("hideCart")
								end,
							},
						},

						gui.Panel{
							classes = {"cartGrid", "collapseUnlessCart", "collapsedWhenCheckingOut"},
							showShoppingCart = function(element)

								local products = {}

								for _,product in ipairs(m_allProducts) do
									if m_shoppingCart[product.id] then
										products[#products+1] = product
									end
								end

								local children = {}

								for i,product in ipairs(products) do
									if i > 1 then
										children[#children+1] = gui.Panel{
											width = 600,
											height = 1,
											bgimage = "panels/square.png",
											halign = "center",
											valign = "center",
											vmargin = 8,
											bgcolor = Styles.textColor,

											gradient = dividerGradient,

										}
									end

									local panel = ShopEntryPanel(product)

									children[#children+1] = panel

								end

								element.children = children

								element:FireEventTree("refreshCart", m_shoppingCart)

							end,
						},

						gui.Panel{
							classes = {"shopGrid", "collapseOnCart", "collapsedWhenCheckingOut"},
							children = rows,
						},

						gui.Label{
							classes = {"noresultsLabel", "collapsed", "collapseOnCart", "collapsedWhenCheckingOut"},
							text = "We couldn't find any items matching your search!",

							refreshSearch = function(element)
								element:SetClass("collapsed", #products ~= 0)
							end,
						},

						gui.Label{
							classes = {"noresultsLabel", "collapseUnlessCartWithoutItems", "collapsedWhenCheckingOut"},
							text = "There's nothing in your cart yet.",
						},

						--gifting panel.
						gui.Panel{
							id = "giftPanel",
							classes = {"collapseUnlessCartWithItems", "collapsedWhenCheckingOut"},
							flow = "vertical",
							width = "auto",
							height = "auto",
							halign = "center",
							vmargin = 8,

							gui.Panel{
								width = 600,
								height = 1,
								bgimage = "panels/square.png",
								halign = "center",
								valign = "center",
								vmargin = 8,
								bgcolor = Styles.textColor,

								gradient = dividerGradient,
							},

							gui.Label{
								id = "giftButton",
								classes = {"itemButton", "collapseUnlessCart"},
								halign = "center",
								hmargin = 16,
								vmargin = 4,

								text = "Gift",

								press = function(element)
									element:SetClass("checkoutButton", not element:HasClass("checkoutButton"))
									element.parent:FireEventTree("refreshGift", element:HasClass("checkoutButton"))
								end,

								gui.Panel{
									classes = {"itemButtonIcon"},
									bgimage = "ui-icons/gift-icon.png",
								},
							},

							gui.Panel{
								flow = "vertical",
								width = "auto",
								height = "auto",
								halign = "center",
								refreshGift = function(element, val)
									element:SetClass("collapsed", not val)

									if not val then
										return
									end

									element.children = {
										gui.Label{
											classes = {"shopDescription"},
											text = "Who will receive this gift?",
										},

										gui.Panel{
											vscroll = true,
											height = "auto",
											maxHeight = 200,
											flow = "vertical",
											width = 800,
											vmargin = 12,
											halign = "center",

											create = function(element)
												local friends = dmhub.GetFriendsList()

												local children = {}

												children[#children+1] = gui.Label{
													classes = {"friendLabel", "selected"},
													data = {
														friendid = "code",
													},
													text = "Get a redeemable coupon code\n<i>A non-expiring code that can be redeemed anytime</i>",
													press = function(element)
														for i,child in ipairs(element.parent.children) do
															child:SetClass("selected", child == element)
														end

														element:Get("giftNoteInput"):SetClass("collapsed", true)
													end,
												}

												for friendid,friend in pairs(friends) do
													children[#children+1] = gui.Label{
														classes = {"friendLabel"},
														data = {
															friendid = friendid,
														},
														text = string.format("%s\n<i>%s</i>", friend.aliases[1], friend.games[1]),
														press = function(element)
															for i,child in ipairs(element.parent.children) do
																child:SetClass("selected", child == element)
															end

															element:Get("giftNoteInput"):SetClass("collapsed", false)
														end,
													}
												end

												element.children = children
											end,
										},

										gui.Input{
											classes = {"collapsed"},
											id = "giftNoteInput",
											vmargin = 8,
											width = 800,
											height = 140,
											characterLimit = 256,
											placeholderText = "Enter a note...",
											text = "",
										},
									}
								end,
							},
						},

						gui.Label{
							classes = {"priceLabel", "collapseUnlessCartWithItems", "collapsedWhenCheckingOut"},
							fontSize = 20,
							fontWeight = "bold",
							text = "",
							vmargin = 14,


							showShoppingCart = function(element)
								local total_price = 0
								for _,product in ipairs(m_allProducts) do
									if m_shoppingCart[product.id] then
										total_price = total_price + product.price
									end
								end

								if total_price <= 0 then
									element.text = "Total Price: FREE"
								else
									local dollars = math.tointeger(math.floor(total_price/100))
									local cents = math.tointeger(total_price%100)
									element.text = string.format("Total Price: $%d.%02dUS", dollars, cents)
								end
							end,

						},

						gui.Panel{
							classes = {"collapsedWhenCheckingOut"},
							flow = "horizontal",
							width = "auto",
							height = "auto",
							halign = "center",
							vmargin = 60,


							gui.Label{
								classes = {"itemButton", "checkoutButton", "collapseUnlessCartWithItems"},
								halign = "center",
								hmargin = 16,
								text = "Checkout",

								press = function(element)
									analytics.Event{
										type = "shopCheckout",
									}


									local giftInfo = nil

									local giftPanel = element:Get("giftPanel")
									local giftButton = element:Get("giftButton")
									if giftButton:HasClass("checkoutButton") then
										--this is a gift, let's find out who to.
										local friendPanel = giftPanel:FindChildRecursive(function(panel) return panel:HasClass("friendLabel") and panel:HasClass("selected") end)
										if friendPanel ~= nil then
											local friendid = friendPanel.data.friendid

											if friendid == "code" then
												giftInfo = {
													coupon = true,
												}
											else
												giftInfo = {
													friendid = friendid,
													note = element:Get("giftNoteInput").text,
												}
											end
										end
									end

									shop:Checkout(m_shoppingCart, {
										gift = giftInfo,
									})
									resultPanel:FireEventTree("checkingOut")
									resultPanel:SetClassTree("checkingOut", true)
								end,
							},

							gui.Label{
								classes = {"itemButton", "collapseUnlessCart"},
								halign = "center",
								hmargin = 16,
								text = "Keep Shopping",

								press = function(element)
									element:FireEventOnParents("hideCart")
								end,
							},

						},

						gui.Panel{
							classes = {"divider", "collapseOnCart"},
						},

						gui.Panel{
							classes = {"pagingFooter", "collapseOnCart"},

							children = {
								footerPageLeft,
								gui.Panel{
									flow = "horizontal",
									width = "auto",
									height = "auto",
									halign = "center",
									children = footerPanels,
								},
								footerPageRight,
							},
						},


						gui.Panel{
							height = 100,
						},
					},
				},

			},

			--shopping cart etc.
			gui.Panel{
				classes = {"collapseOnNoCommerce"},
				floating = true,
				halign = "right",
				valign = "top",
				hmargin = 32,
				vmargin = 16,
				width = "auto",
				height = "auto",
				flow = "horizontal",

				gui.Panel{
					flow = "horizontal",
					width = "auto",
					height = "auto",
					refreshCart = function(element, shoppingCart, addingItem)
						if addingItem then
							element:PulseClassTree("add")
						end
					end,

					gui.Panel{
						bgimage = "icons/icon_shopping/shopping-cart.png",
						bgcolor = "white",
						width = 32,
						height = 32,
						styles = {
							{
								selectors = {"add"},
								transitionTime = 0.3,
								brightness = 1.4,
							},
							{
								selectors = {"hover"},
								brightness = 1.4,
							},
						},

						press = function(element)
							if element:HasClass("showingCouponInventory") then
								resultPanel:FireEventTree("clearCouponDisplay")
							end

							if element:HasClass("redeemingCoupon") then
								resultPanel:FireEventTree("clearredeem")
							end

							element:FireEventOnParents("showCart")

							analytics.Event{
								type = "showCart",
							}

						end,
					},

					gui.Label{
						fontFace = "Inter",
						fontSize = 22,
						bold = true,
						text = "1",
						width = "auto",
						height = "auto",
						valign = "center",
						minWidth = 20,

						styles = {
							{
								selectors = {"add"},
								transitionTime = 0.3,
								scale = 2,
							},
						},
						refreshCart = function(element, shoppingCart, addingItem)
							local count = 0
							for k,v in pairs(shoppingCart) do
								count = count+1
							end

							if count == 0 then
								element.text = ""
							else
								element.text = string.format("%d", count)
							end

						end,
					},
				},

				gui.Panel{
					--padding
					width = 16,
					height = 1,
				},
			},

			--close button in top left.
			gui.CloseButton{
				halign = "left",
				valign = "top",

				click = function(element)
					element:FireEventOnParents("closeShop")
				end,
			},


			--inventory in top left
			gui.Panel{
				floating = true,
				halign = "left",
				valign = "top",
				hmargin = 96,
				vmargin = 24,
				width = "auto",
				height = "auto",
				flow = "vertical",

				gui.Label{
					classes = {"collapsedWhenInventory"},
					bgcolor = "clear",
					width = "auto",
					height = "auto",
					fontSize = 18,
					text = "My Inventory",
					fontWeight = "bold",

					styles = {
						{
							selectors = {"hover"},
							color = "#ffffff",
						},
					},

					press = function(element)
						resultPanel:FireEvent("showInventory")

					end,

					refreshInventory = function(element)
						element.text = string.format("My Inventory (%d)", table.size(shop.inventoryItems))
					end,

					create = function(element)
						shop.events:Listen(element)
						element:FireEvent("refreshInventory")
					end,

				},

				gui.Label{
					classes = {"collapsedUnlessInventory"},
					bgcolor = "clear",
					width = "auto",
					height = "auto",
					fontSize = 18,
					text = "Back to Shopping",
					fontWeight = "bold",

					styles = {
						{
							selectors = {"hover"},
							color = "#ffffff",
						},
					},

					press = function(element)
						resultPanel:FireEvent("hideInventory")
					end,
				},

				--redeem code.
				gui.Label{
					bgcolor = "clear",
					width = "auto",
					height = "auto",
					fontSize = 18,
					vmargin = 12,
					text = "Redeem a Gift Code",
					fontWeight = "bold",

					styles = {
						{
							selectors = {"hover"},
							color = "#ffffff",
						},
					},

					press = function(element)
						if element:HasClass("redeemingCoupon") then
							resultPanel:SetClassTree("redeemingCoupon", false)
						else
							resultPanel:SetClassTree("showingCouponInventory", false)
							resultPanel:SetClassTree("redeemingCoupon", true)
							resultPanel:FireEventTree("redeemcoupons")
						end
					end,
				},

			},

		}


		if dmhub.whiteLabel == "mcdm" then
			resultPanel:SetClassTree("noCommerce", true)
		end

		if arguments.inventory then
			resultPanel:FireEvent("showInventory")
		else
			resultPanel:FireEventTree("refreshSearch")
			ShowPage(1)
		end

		return resultPanel

	end

	return DisplayShop(productDatabase)
end

function CreateShopScreen(arguments)

	local dialog = arguments.titlescreen.data.dialog

	--scale everything so we have a width of 1920, and a varying height.
	local uiscale = dialog.width/1920
	local dialogPanelHeight = 1920*(dialog.height/dialog.width)


	local dialogPanel
	printf("DIMENSIONS: %s / %s; dialog = %sx%s / scale: %s, %s", json(dmhub.screenDimensions.x), json(dmhub.screenDimensions.y), json(dialog.width), json(dialog.height), json(dmhub.uiscale), json(dmhub.uiVerticalScale))

	dialogPanel = gui.Panel{
		classes = {"framedPanel"},
		floating = true,
		width = 1920, --/dmhub.uiVerticalScale,
		height = dialogPanelHeight,
		uiscale = uiscale,
		halign = "center",
		valign = "center",
		styles = {
			Styles.Panel,
		},

		create = function(element)
			element:FireEvent("showshop", true)
		end,

		showshop = function(element, firstTime)
			if assets.coreAssetsDownloaded then
				element.children = {CreateShopScreenInternal(arguments)}
			else
				if firstTime then
					--show a loading screen until assets are loaded.
					element.children = {
						gui.Panel{
							floating = true,
							halign = "center",
							valign = "top",
							width = "100%",
							height = "100%",
							bgimage = "media/shopbg.webm",
							bgcolor = "#bbbbbbff",
							gui.LoadingIndicator{},

							gui.CloseButton{
								halign = "left",
								valign = "top",
								floating = true,

								click = function(element)
									element:FireEventOnParents("closeShop")
								end,
							},

						},
					}
				end

				element:ScheduleEvent("showshop", 0.1)
			end
		end,

		closeShop = function(element)
			element:DestroySelf()
		end,

		gui.Panel{
			floating = true,
			halign = "center",
			valign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear", --"red"
			width = 1,
			height = "100%",
		},

		gui.Panel{
			floating = true,
			halign = "center",
			valign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear", --"red"
			width = 1,
			height = "100%",
			x = 100,
			opacity = 0.7,
			thinkTime = 0.1,
			think = function(element)
				element.x = dmhub.debugPixelValue
			end,
		},

		gui.Panel{
			floating = true,
			halign = "center",
			valign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear", -- "red"
			width = 1,
			height = "100%",
			x = -100,
			opacity = 0.7,
						thinkTime = 0.1,
			think = function(element)
				element.x = -dmhub.debugPixelValue
			end,

		},


	}

	dialogPanel:PulseClass("fadein")

	return dialogPanel
end

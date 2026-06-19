local mod = dmhub.GetModLoading()

--Mirror of CodexTitleBar.lua's "dev:storepreview" setting. Settings are
--keyed by id, so re-declaring here gives this file read access to the same
--persisted preference without exporting the local from the title bar.
local g_devStorePreviewSetting = setting{
    id = "dev:storepreview",
    default = false,
    storage = "preference",
}

--When true, the "Buy with Steam" button skips the actual Steam call and
--triggers the success path locally after a 0.5s delay. Lets us iterate on
--the post-purchase UI without doing a real Steam transaction (or any redeploy).
--Read directly via dmhub.GetPref rather than via setting{} -- setting{}'s
--cache and dmhub's preference store turn out to use different namespaces, so
--`dmhub.SetPref(id, value)` doesn't reach a setting{} object with the same id.
--Toggle with: dmhub.SetPref("dev:simulateSteamPurchase", true)
local function DevSimulateSteamPurchase()
    return dmhub.GetPref("dev:simulateSteamPurchase") == true
end

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

	--The DMHub logo is replaced by the dice banner on the main shop page;
	--it still shows on the cart and inventory views, which keep their
	--plain text headers.
	{
		selectors = {"shopLogo"},
		collapsed = 1,
	},
	{
		selectors = {"shopLogo", "showingCart"},
		collapsed = 0,
	},
	{
		selectors = {"shopLogo", "inventory"},
		collapsed = 0,
	},

}

--The banner at the top of the shop: a skeleton clutching a (real, rendered)
--die. Three layers: the painted background, the live dice preview render
--sandwiched in the middle, and the skeleton's torso/arms painted on top so
--the die reads as held in its hands.
--Default featured-dice banner config. An empty image field means that layer
--is transparent (not drawn); the dice render over whatever is behind it.
local g_diceBannerDefaults = {
	backgroundImage = "",
	foregroundImage = "",
	diceScale = 3.4,
	dieX = 0.38,
	dieY = 0.385,
	dieSize = 0,
	textPlacement = "right",
	textOffsetX = 0,
	textOffsetY = 0,
}

--Recommended/native source dimensions for custom banner art, shared with the
--admin editor so it can document the target size.
ShopDiceBannerArtWidth = 1232
ShopDiceBannerArtHeight = 706

--On-screen banner size, in solid pixels. Width matches a row of 3 shop items
--(320*3 + 60*2 gaps); height preserves the art's native aspect so the full
--image is shown uncropped.
local g_bannerDisplayWidth = 1080
local g_bannerDisplayHeight = math.floor(g_bannerDisplayWidth * ShopDiceBannerArtHeight / ShopDiceBannerArtWidth)

--Returns a full config table: defaults overlaid with any fields present in cfg
--(a Dice item's diceBanner table, which may be nil or partial).
local function NormalizeBannerConfig(cfg)
	local result = {}
	for k,v in pairs(g_diceBannerDefaults) do
		result[k] = v
	end
	if type(cfg) == "table" then
		for k,_ in pairs(g_diceBannerDefaults) do
			if cfg[k] ~= nil then
				result[k] = cfg[k]
			end
		end
	end
	return result
end

--Reads item.diceBanner defensively and returns a normalized config. The field
--is a C# bridge property shipped alongside this code; the pcall keeps the shop
--banner working if Lua is hot-reloaded against an older engine binary that
--does not have it yet (falls back to defaults / transparent layers).
local function ReadItemBannerConfig(item)
	if item == nil then
		return NormalizeBannerConfig(nil)
	end
	local ok, cfg = pcall(function() return item.diceBanner end)
	if ok then
		return NormalizeBannerConfig(cfg)
	end
	return NormalizeBannerConfig(nil)
end

--Maps a placement preset + pixel offset onto a floating text panel. The panel
--is anchored to an edge/corner (halign/valign) and pushed inward by a base
--inset, then nudged by the user's offset.
local function ApplyTextPlacement(textPanel, placement, offsetX, offsetY)
	local inset = 36
	local h, v = "right", "center"
	if placement == "left" then
		h, v = "left", "center"
	elseif placement == "topleft" then
		h, v = "left", "top"
	elseif placement == "topright" then
		h, v = "right", "top"
	elseif placement == "bottomleft" then
		h, v = "left", "bottom"
	elseif placement == "bottomright" then
		h, v = "right", "bottom"
	end

	textPanel.selfStyle.halign = h
	textPanel.selfStyle.valign = v

	local baseX = cond(h == "left", inset, -inset)
	local baseY = 0
	if v == "top" then
		baseY = inset
	elseif v == "bottom" then
		baseY = -inset
	end

	textPanel.x = baseX + (offsetX or 0)
	textPanel.y = baseY + (offsetY or 0)
end

--Builds the featured-dice banner. opts.adminPreview = true makes it a passive
--preview driven entirely by the admin editor's applyBannerConfig event (it
--skips the auto-feature scan and renders defaults until told otherwise).
--Exposed globally (ShopDiceBanner, below) so the Shop admin module can reuse
--the real component for a live preview.
local MakeDiceBanner = function(opts)
	opts = opts or {}
	--Solid pixel dimensions; height preserves the 1232x706 art aspect so the
	--full image is shown uncropped. (See g_bannerDisplayWidth/Height.)
	local bannerWidth = g_bannerDisplayWidth
	local imageHeight = g_bannerDisplayHeight

	local m_item = nil
	local m_suspended = false

	--Live banner config (see g_diceBannerDefaults). Starts at defaults; the
	--shop overwrites it from the featured item's diceBanner, and the admin
	--editor drives it live via the applyBannerConfig event.
	local m_cfg = NormalizeBannerConfig(nil)
	local m_diceScale = m_cfg.diceScale
	local m_dieSize = math.floor(imageHeight)

	--The die, rendered between the banner background and the foreground layer.
	--Positioned in full-image coordinates. The preview RT is transparent
	--outside the die, so the panel harmlessly overflows the banner bounds.
	--
	--The die is interactive in two modes:
	--  * adminPreview: drag it on the banner to set its POSITION. dragMove lets
	--    the engine move it live; 'drag' (on release) bakes the final spot (via
	--    dragDelta), clamps it, and reports dieX/dieY up via 'dieDragged'.
	--  * detailsMode (shop showcase): grab it to SPIN it. beginDrag flips the
	--    shared preview scene into drag mode (the cursor motion drives the spin
	--    velocity and direction); on release it decays back to the gentle idle
	--    spin (handled C#-side in DicePreviewScene). The panel itself stays put
	--    (dragMove off).
	--Other banners leave the die non-interactive.
	local diePanel = gui.Panel{
		floating = true,
		interactable = opts.adminPreview == true or opts.detailsMode == true,
		draggable = opts.adminPreview == true or opts.detailsMode == true,
		dragMove = opts.adminPreview == true,
		bgimage = "#DicePreview",
		bgcolor = "white",
		width = m_dieSize,
		height = m_dieSize,
		halign = "left",
		valign = "top",

		beginDrag = function(element)
			if opts.detailsMode then
				dice.GetPreviewScene().dragging = true
			end
		end,

		drag = function(element)
			if opts.detailsMode then
				--Release: stop feeding cursor input; the spin coasts and decays.
				dice.GetPreviewScene().dragging = false
				return
			end

			--Admin: reposition the die and report the new dieX/dieY.
			element.x = element.x + element.dragDelta.x
			element.y = element.y + element.dragDelta.y
			local dieX = clamp((element.x + m_dieSize / 2) / bannerWidth, 0, 1)
			local dieY = clamp((element.y + m_dieSize / 2) / imageHeight, 0, 1)
			m_cfg.dieX = dieX
			m_cfg.dieY = dieY
			element.x = math.floor(bannerWidth * dieX - m_dieSize / 2)
			element.y = math.floor(imageHeight * dieY - m_dieSize / 2)
			element:FireEventOnParents("dieDragged", { dieX = dieX, dieY = dieY })
		end,
	}

	--The foreground overlay in front of the die (e.g. hands holding it).
	--Solid pixels matching the banner; transparent until a custom image is set.
	local frontPanel = gui.Panel{
		floating = true,
		interactable = false,
		bgimage = "panels/square.png",
		bgcolor = "clear",
		halign = "left",
		valign = "top",
		width = bannerWidth,
		height = imageHeight,
	}

	local resultPanel

	--Applies the banner config: the two (uncropped, full-size) layer images,
	--die size/position, and (via a tree event) the text overlay placement.
	--Safe to call repeatedly as the admin editor tweaks values. dieX/dieY are
	--fractions of the full image.
	local function ApplyConfig(cfg)
		m_cfg = cfg
		m_diceScale = cfg.diceScale

		local dieSize = cfg.dieSize
		if dieSize == nil or dieSize <= 0 then
			dieSize = math.floor(imageHeight)
		end
		m_dieSize = dieSize
		diePanel.width = dieSize
		diePanel.height = dieSize

		--Each layer shows its custom image, or is transparent when the field is
		--empty (cleared). A transparent (alpha 0) bgcolor hides the layer while
		--keeping the panel solidly sized.
		if cfg.backgroundImage ~= nil and cfg.backgroundImage ~= "" then
			resultPanel.bgimage = cfg.backgroundImage
			resultPanel.selfStyle.bgcolor = "white"
		else
			resultPanel.selfStyle.bgcolor = "clear"
		end

		if cfg.foregroundImage ~= nil and cfg.foregroundImage ~= "" then
			frontPanel.bgimage = cfg.foregroundImage
			frontPanel.selfStyle.bgcolor = "white"
		else
			frontPanel.selfStyle.bgcolor = "clear"
		end

		diePanel.x = math.floor(bannerWidth * cfg.dieX - dieSize / 2)
		diePanel.y = math.floor(imageHeight * cfg.dieY - dieSize / 2)

		resultPanel:FireEventTree("placeBannerText", cfg)
	end

	resultPanel = gui.Panel{
		--Only the top featured banner auto-hides on the cart/inventory/artist
		--views. The passive admin-preview and details-showcase banners manage
		--their own visibility, so they skip these classes (otherwise the details
		--banner would vanish when viewing a dice item from the inventory).
		classes = cond(opts.adminPreview or opts.detailsMode, {}, {"collapseOnCart", "collapsedWhenInventory", "collapsedWhenArtistFocus"}),
		width = bannerWidth,
		--Solid pixel height matching the 1232x706 art aspect, so the full image
		--shows uncropped. ApplyConfig sets the background image / transparency.
		height = imageHeight,
		halign = "center",
		valign = "top",
		bgimage = "panels/square.png",
		bgcolor = "clear",

		--Self-contained copies of the shop's text styles so the banner renders
		--correctly even when reused outside the shop screen (the admin editor's
		--live preview, which lacks the shop root's cascading shopStyles).
		styles = {
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
		},

		create = function(element)
			if opts.adminPreview or opts.detailsMode then
				--Passive: render defaults and wait to be driven -- the admin
				--editor pushes config via applyBannerConfig; the product
				--details view drives it via showProductDetails. Details mode
				--starts collapsed until a dice item is shown.
				element.thinkTime = 0.01
				ApplyConfig(m_cfg)
				if opts.detailsMode then
					element:SetClass("collapsed", true)
				end
				return
			end

			--Feature the first dice product we can find; prefer one that
			--is on sale.
			local fallback = nil
			for _,item in pairs(assets.shopItems) do
				if item.itemType == "Dice" then
					if item.onsale then
						m_item = item
						break
					end
					fallback = fallback or item
				end
			end

			m_item = m_item or fallback

			if m_item ~= nil then
				element.thinkTime = 0.01
				ApplyConfig(ReadItemBannerConfig(m_item))
				element:FireEventTree("refreshBannerItem", m_item)
			end
		end,

		--Admin editor live preview: apply an explicit config + featured item.
		--payload = { cfg = <normalized config table>, item = <ShopItemLua> }.
		applyBannerConfig = function(element, payload)
			m_suspended = false
			m_item = payload.item
			element.thinkTime = 0.01
			ApplyConfig(payload.cfg)
			if payload.item ~= nil then
				element:FireEventTree("refreshBannerItem", payload.item)
			end
		end,

		--Top featured banner: while the product details page is up it drives the
		--(shared) dice preview scene itself, so stop feeding it our settings.
		--The details-mode banner ignores these (it IS the details page) and uses
		--showProductDetails/hideProductDetails instead.
		hideProducts = function(element)
			if opts.detailsMode then return end
			m_suspended = true
			element:SetClass("collapsed", true)
		end,

		showProducts = function(element)
			if opts.detailsMode then return end
			m_suspended = false
			element:SetClass("collapsed", false)
		end,

		--Details showcase: configure the banner for the dice item being viewed
		--(or collapse for non-dice). Only active in detailsMode.
		showProductDetails = function(element, item)
			if not opts.detailsMode then return end
			if item ~= nil and item.itemType == "Dice" then
				m_item = item
				m_suspended = false
				element.thinkTime = 0.01
				ApplyConfig(ReadItemBannerConfig(item))
				element:FireEventTree("refreshBannerItem", item)
				element:SetClass("collapsed", false)
			else
				m_item = nil
				m_suspended = true
				element:SetClass("collapsed", true)
			end
		end,

		hideProductDetails = function(element)
			if not opts.detailsMode then return end
			m_suspended = true
			element:SetClass("collapsed", true)
		end,

		think = function(element)
			if m_suspended or m_item == nil then
				return
			end

			--Cart/inventory views hide the top featured banner; the details
			--showcase still drives the scene in those views.
			if not opts.detailsMode and (element:HasClass("showingCart") or element:HasClass("inventory")) then
				return
			end

			local assetid = m_item.assetid
			if assetid == nil or assetid == "" then
				return
			end

			local scene = dice.GetPreviewScene()
			scene.assetid = assetid
			scene.selectedIndex = 0
			scene.solo = true
			scene.transparent = true
			scene.diceScale = m_diceScale
			scene.fixedTime = false

			--The details showcase gently turns the die so buyers see all its
			--faces; the featured top banner keeps it static (it reads as held in
			--the skeleton's hands), as does the admin positioning preview.
			scene.initialRotation = cond(opts.detailsMode, 30, 0)
		end,

		--Dev hook for tuning the banner live, e.g.:
		--CodexTitlescreenRoot:FireEventTree("configureBanner",
		--  {dieX = 0.38, dieY = 0.555, size = 618, scale = 3.4})
		configureBanner = function(element, opts)
			opts = opts or {}
			if opts.scale ~= nil then
				m_cfg.diceScale = opts.scale
			end
			if opts.size ~= nil then
				m_cfg.dieSize = opts.size
			end
			if opts.dieX ~= nil then
				m_cfg.dieX = opts.dieX
			end
			if opts.dieY ~= nil then
				m_cfg.dieY = opts.dieY
			end
			ApplyConfig(m_cfg)
		end,

		--Dev hook: dump the actual layer geometry for debugging.
		debugBanner = function(element)
			printf("BANNER:: banner rendered=%sx%s", json(element.renderedWidth), json(element.renderedHeight))
			printf("BANNER:: front rendered=%sx%s", json(frontPanel.renderedWidth), json(frontPanel.renderedHeight))
			printf("BANNER:: die pos=(%s,%s) size=%sx%s scale=%s", json(diePanel.x), json(diePanel.y), json(diePanel.renderedWidth), json(diePanel.renderedHeight), json(m_diceScale))
		end,

		diePanel,

		frontPanel,

		--Advertising copy for the featured dice. By default it sits on the
		--empty rock to the right of the skeleton; per-item config can move it
		--to any edge/corner. A dark scrim sits behind the text so it stays
		--readable over the art. ApplyTextPlacement sets halign/valign/x/y.
		gui.Panel{
			floating = true,
			flow = "vertical",
			halign = "right",
			valign = "center",
			width = 420,
			height = "auto",
			borderBox = true,
			hpad = 24,
			vpad = 20,
			bgimage = "panels/square.png",
			bgcolor = "#000000a0",
			cornerRadius = 12,

			placeBannerText = function(element, cfg)
				ApplyTextPlacement(element, cfg.textPlacement, cfg.textOffsetX, cfg.textOffsetY)
			end,

			gui.Label{
				classes = {"shopTitle"},
				width = "100%",
				height = "auto",
				halign = "left",
				textAlignment = "left",
				fontWeight = "bold",
				fontSize = 34,
				text = "",

				refreshBannerItem = function(element, item)
					element.text = item.name
				end,
			},

			gui.Label{
				classes = {"shopDescription"},
				width = "100%",
				height = "auto",
				halign = "left",
				textAlignment = "left",
				vmargin = 10,
				maxHeight = 110,
				textOverflow = "ellipsis",
				text = "",

				refreshBannerItem = function(element, item)
					local text = item.details
					if text == nil or text == "" then
						text = "Roll in style with this exclusive dice set."
					end
					element.text = text
				end,
			},

			gui.Label{
				classes = {"itemButton"},
				halign = "left",
				vmargin = 12,
				text = "View Dice",

				--In the details showcase we're already viewing the item, so this
				--button is hidden there.
				create = function(element)
					element:SetClass("collapsed", opts.detailsMode == true)
				end,

				press = function(element)
					if m_item ~= nil then
						element:FireEventOnParents("showItemDetails", m_item)
					end
				end,
			},
		},
	}

	return resultPanel
end

--Expose the real banner component so the Shop admin editor (a separate module)
--can render an exact live preview while editing a Dice item's banner config.
--ShopDiceBanner.Create{ adminPreview = true } returns a passive banner panel;
--push edits to it with panel:FireEventTree("applyBannerConfig", {cfg=..., item=...}).
ShopDiceBanner = {
	Create = MakeDiceBanner,
	NormalizeConfig = NormalizeBannerConfig,
	ReadItemConfig = ReadItemBannerConfig,
	defaults = g_diceBannerDefaults,
	artWidth = ShopDiceBannerArtWidth,
	artHeight = ShopDiceBannerArtHeight,
	displayWidth = g_bannerDisplayWidth,
	displayHeight = g_bannerDisplayHeight,
}

--Monotonic id handed to each shop-image display so dice tiles can request their
--own live preview die ("#DicePreview:<assetid>:<seq>"). The seq is stable for the
--life of a tile (assigned once below), so reusing a tile for a different dice set
--swaps to a fresh pooled preview and the old one is evicted engine-side.
local g_dicePreviewSeq = 0

local MakeShopImageDisplay = function(options)
	options = options or {}
	local uiscale = options.uiscale or 1
	options.uiscale = nil

	local footer = options.footer
	options.footer = nil

	g_dicePreviewSeq = g_dicePreviewSeq + 1
	local mySeq = g_dicePreviewSeq

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
				--Dice items show a live, up-close die on their chosen banner
				--background (cropped to the die) instead of a flat product shot.
				if item.itemType == "Dice" then
					element:FireEvent("refreshDicePreview", item)
				else
					element:FireEvent("refreshImage", item.images[1])
				end
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
		end,

		--Builds a cropped view of the dice banner for this item: the chosen
		--background art zoomed in and centered on the configured die position,
		--with the item's own live 3D die ("#DicePreview:<assetid>:<seq>")
		--composited on top. Mirrors how the details banner composites
		--background + die, but tightly framed on the die for the tile.
		refreshDicePreview = function(element, item)
			local cfg = ReadItemBannerConfig(item)

			local tileW = 325*uiscale
			local tileH = (180 + heightStretch)*uiscale

			--Banner-space dimensions the die position (dieX/dieY) is relative to.
			local bannerW = g_bannerDisplayWidth
			local bannerH = g_bannerDisplayHeight

			--Show roughly this fraction of the banner height inside the tile
			--(the rest is cropped away), zooming in on the die. Kept ~= 1/dieZoom
			--below so the die sits on its background at banner-faithful proportions.
			local cropFrac = 0.667
			local zoom = tileH / (bannerH * cropFrac)
			local scaledW = bannerW * zoom
			local scaledH = bannerH * zoom

			local clipChildren = {}

			--The background and foreground art share the banner's full-image
			--coordinate space: each is oversized and offset by the same amount so the
			--die point (dieX,dieY) lands at the tile center; the clip window crops the
			--rest. (The banner draws background behind the die and foreground -- e.g.
			--hands holding the die -- in front of it.)
			local layerX = math.floor(tileW*0.5 - cfg.dieX*scaledW)
			local layerY = math.floor(tileH*0.5 - cfg.dieY*scaledH)
			local function MakeBannerLayer(image)
				return gui.Panel{
					interactable = false,
					floating = true,
					bgimage = image,
					bgcolor = "white",
					width = scaledW,
					height = scaledH,
					halign = "left",
					valign = "top",
					x = layerX,
					y = layerY,
				}
			end

			--Chosen background art (behind the die).
			if cfg.backgroundImage ~= nil and cfg.backgroundImage ~= "" then
				clipChildren[#clipChildren+1] = MakeBannerLayer(cfg.backgroundImage)
			end

			--The live die. The preview RT is transparent outside the die, so the
			--panel is oversized (dieZoom) to bring the die up close; the empty
			--margin simply overflows and is clipped. Lower = more space around the die.
			local dieZoom = 1.5
			local dieSize = math.floor(tileH * dieZoom)
			clipChildren[#clipChildren+1] = gui.Panel{
				interactable = false,
				floating = true,
				bgimage = "#DicePreview:" .. tostring(item.assetid) .. ":" .. tostring(mySeq),
				bgcolor = "white",
				width = dieSize,
				height = dieSize,
				halign = "center",
				valign = "center",
			}

			--Chosen foreground art (in front of the die), added last so it draws on
			--top -- matching the details banner's frontPanel.
			if cfg.foregroundImage ~= nil and cfg.foregroundImage ~= "" then
				clipChildren[#clipChildren+1] = MakeBannerLayer(cfg.foregroundImage)
			end

			element.children = {
				bg,
				gui.Panel{
					interactable = false,
					clip = true,
					clipHidden = true,
					bgimage = "panels/square.png",
					bgcolor = "clear",
					halign = "center",
					valign = "center",
					width = tileW,
					height = tileH,
					children = clipChildren,
				},
			}
		end,
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

--Opens a "try rolling" tray for a dice item: temporarily equips that item's
--dice set, then shows a modal containing a dice cage (the real DiceHarness
--preview panel). Press Roll to throw a Power Roll into the cage; once the dice
--settle you can grab and re-throw them (the dice.* API drives the embedded
--preview dice). The previously-equipped set is restored when the modal closes.
--
--Lua-only -- reuses existing engine pieces (SheetPanel:SetAsDicePreviewPanel,
--dmhub.Roll, dice.MouseEnter/Click/DragThink/DragEnd). Requires a roll-capable
--context (i.e. opened from inside a game); the equipped-set swap is restored on
--close so the player's real selection is untouched.
local function ShowDiceTryRoll(item)
	if item == nil or item.assetid == nil or item.assetid == "" then
		return
	end

	gui.ShowModal(gui.Panel{
		width = 820,
		height = 360,
		halign = "center",
		valign = "bottom",
		vmargin = 60,
		flow = "vertical",
		bgimage = "panels/square.png",
		bgcolor = "#0a0a0af2",
		cornerRadius = 16,
		borderWidth = 2,
		borderColor = "#f6ddb6",

		--Override the roll dice with this item's set so we can roll dice the
		--player doesn't own yet (the equipped-dice setting silently reverts
		--unowned sets). Cleared when the modal closes. pcall-guarded: the C#
		--method ships with this change, so a Lua-only reload against an older
		--binary just rolls the equipped set instead of erroring.
		create = function(element)
			pcall(function() dice.SetRollPreviewModel(item.assetid) end)
		end,

		destroy = function(element)
			pcall(function() dice.SetRollPreviewModel(nil) end)
		end,

		gui.Label{
			classes = {"shopTitle"},
			fontSize = 20,
			halign = "center",
			vmargin = 10,
			text = string.format("Try %s", item.name),
		},

		--The dice cage: rolled dice tumble inside this panel, and dragging
		--inside it grabs + throws them (mirrors the embedded roll dialog).
		gui.Panel{
			width = "92%",
			height = 210,
			halign = "center",
			bgimage = "panels/square.png",
			bgcolor = "#00000055",
			cornerRadius = 8,
			draggable = true,
			dragMove = false,
			thinkTime = 0.01,

			create = function(element)
				element:SetAsDicePreviewPanel(true)
			end,
			destroy = function(element)
				element:SetAsDicePreviewPanel(false)
			end,
			hover = function(element) dice.MouseEnter() end,
			dehover = function(element) dice.MouseLeave() end,
			click = function(element) dice.Click() end,
			dragging = function(element) dice.DragThink() end,
			drag = function(element) dice.DragEnd() end,

			gui.Label{
				halign = "center",
				valign = "center",
				width = "auto",
				height = "auto",
				fontSize = 15,
				color = "#888888ff",
				interactable = false,
				text = "Press Roll, then grab the dice to throw them again",
			},
		},

		gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = "auto",
			halign = "center",
			vmargin = 10,

			gui.Label{
				classes = {"itemButton"},
				hmargin = 8,
				text = "Roll Power Roll",
				press = function(element)
					dmhub.Roll{ roll = "2d10", description = string.format("Trying %s", item.name) }
				end,
			},

			gui.Label{
				classes = {"itemButton"},
				hmargin = 8,
				text = "Close",
				press = function(element)
					gui.CloseModal()
				end,
			},
		},
	})
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

	--Dice items are shown with the real banner component (background +
	--foreground + die + name/details overlay) instead of the spinnable
	--carousel. Details mode drives itself from the viewed item.
	local m_diceBanner = ShopDiceBanner.Create{ detailsMode = true }

	--Soft dark gradient backing for the details panel. Applied directly to the
	--shopDetailsMainPanel below as its own bgimage, NOT as a floating child:
	--a floating child sized at 100% resolves its percentage against the
	--containing dialog (1920x1048), not this auto-sized panel, so it ballooned
	--to cover the whole screen in front of the content. A panel's own bgimage
	--always fills exactly the panel and draws behind its children. Built from a
	--plain square.png so it reads edge-to-edge instead of the old shopbg.png
	--texture (whose dark fill only covered the central ~67%, leaving an inset,
	--shadowed look). The gradient holds solid through the body and softly fades
	--out at the very bottom so the band dissolves rather than ending on a hard
	--line. bgcolor sets the hue; the gradient supplies the alpha.
	local detailsBackingGradient = core.Gradient{
		point_a = {x = 0.5, y = 0},
		point_b = {x = 0.5, y = 1},
		stops = {
			{position = 0,    color = core.Color{r = 1, g = 1, b = 1, a = 0.93}},
			{position = 0.92, color = core.Color{r = 1, g = 1, b = 1, a = 0.93}},
			{position = 1,    color = core.Color{r = 1, g = 1, b = 1, a = 0}},
		},
	}

	return gui.Panel{
		classes = {"shopDetailsMainPanel"},

		bgimage = "panels/square.png",
		bgcolor = "#13131cff",
		gradient = detailsBackingGradient,

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

		--Dice showcase: the configured banner, centered, with Add to Cart /
		--Equip below it. Shown for Dice items; collapsed for everything else
		--(which uses the image gallery + text column below).
		gui.Panel{
			flow = "vertical",
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "top",

			--While a dice item's details are shown, override the roll model so
			--the inline roll-the-dice button (and the dice it spawns) uses this
			--set even if the player doesn't own it yet. Cleared when leaving the
			--dice view, returning to the grid, or closing the shop.
			showProductDetails = function(element, item)
				local isDice = item ~= nil and item.itemType == "Dice"
				element:SetClass("collapsed", not isDice)
				pcall(function() dice.SetRollPreviewModel(isDice and item.assetid or nil) end)
			end,

			showProducts = function(element)
				pcall(function() dice.SetRollPreviewModel(nil) end)
			end,

			destroy = function(element)
				pcall(function() dice.SetRollPreviewModel(nil) end)
			end,

			m_diceBanner,

			--Action row under the banner: a roll-the-dice control on the left,
			--Add to Cart pinned to the right. Sized to the banner width so the
			--two ends line up with the banner's edges. Both children float so
			--they sit at opposite ends regardless of flow.
			gui.Panel{
				width = g_bannerDisplayWidth,
				height = 96,
				halign = "center",
				vmargin = 12,

				styles = {
					{ selectors = {"shopTryDie"}, transitionTime = 0.1 },
					{ selectors = {"shopTryDie", "hover"}, scale = 1.15, brightness = 1.25 },
				},

				--Roll the dice you're previewing: a dsdice icon you can click to
				--roll, or drag off to throw, mirroring the action-bar Dice panel.
				--Rolls use the previewed set (see showProductDetails above).
				gui.Panel{
					classes = {"collapseOnGift"},
					floating = true,
					halign = "left",
					valign = "center",
					x = 24,
					width = 140,
					height = 96,
					flow = "vertical",

					gui.Panel{
						classes = {"shopTryDie"},
						bgimage = "ui-icons/dsdice/djordice-d10-filled.png",
						bgcolor = "white",
						width = 56,
						height = 56,
						halign = "center",
						valign = "top",
						data = { item = nil },

						refreshItem = function(element, item)
							element.data.item = item
							local ok, styling = pcall(function() return dmhub.GetDiceStyling(item.assetid, dmhub.GetSettingValue("playercolor")) end)
							if ok and styling ~= nil then
								element.selfStyle.bgcolor = styling.bgcolor
								element:FireEventTree("refreshTrim", styling.trimcolor)
							end
						end,

						dragMove = false,
						draggable = true,
						beginDrag = function(element)
							if element.data.item == nil then
								return
							end
							pcall(function() dice.SetRollPreviewModel(element.data.item.assetid) end)
							dmhub.Roll{ drag = true, numDice = 1, numFaces = 10, numKeep = 0, description = "Try Dice" }
						end,
						click = function(element)
							if element.data.item == nil then
								return
							end
							pcall(function() dice.SetRollPreviewModel(element.data.item.assetid) end)
							dmhub.Roll{ numDice = 1, numFaces = 10, numKeep = 0, description = "Try Dice" }
						end,

						--Trim outline drawn over the filled die in the set's trim color.
						gui.Panel{
							interactable = false,
							width = "100%",
							height = "100%",
							bgimage = "ui-icons/dsdice/djordice-d10.png",
							bgcolor = "white",
							refreshTrim = function(element, trimcolor)
								element.selfStyle.bgcolor = trimcolor
							end,
						},
					},

					gui.Label{
						text = "Drag to roll dice",
						halign = "center",
						valign = "bottom",
						width = "auto",
						height = "auto",
						fontSize = 12,
						color = "#cfcfcf",
						vmargin = 4,
					},
				},

				--Add to Cart, with the price baked into the label. Hidden in the
				--inventory / gift views. Pinned to the right edge of the row.
				gui.Label{
					classes = {"itemButton", "collapsedWhenInventory", "collapseOnGift", "collapseOnNoCommerce"},
					floating = true,
					halign = "right",
					valign = "center",
					x = -24,
					width = 320,
					data = { item = nil, inCart = false },

					refreshItem = function(element, item)
						element.data.item = item
					end,

					refreshCart = function(element, shoppingCart)
						local item = element.data.item
						if item == nil then
							return
						end
						local inCart = shoppingCart[item.id] == true
						element.data.inCart = inCart
						if inCart then
							element.text = "Remove from Cart"
						else
							local priceText
							if item.price <= 0 then
								priceText = "FREE"
							else
								priceText = string.format("$%d.%02d", math.tointeger(math.floor(item.price/100)), math.tointeger(item.price%100))
							end
							element.text = string.format("%s - %s", cond(shop:ItemInInventory(item.id), "Add as Gift", "Add to Cart"), priceText)
						end
					end,

					press = function(element)
						local item = element.data.item
						if item == nil then
							return
						end
						if element.data.inCart then
							element:FireEventOnParents("removeFromCart", item)
						else
							element:FireEventOnParents("addToCart", item)
							analytics.Event{ type = "shopAddCart" }
						end
					end,
				},
			},

			--Equip / Equipped (inventory only).
			gui.Label{
				text = "Equip",
				classes = {"itemButton", "collapsedUnlessInventory"},
				halign = "center",
				vmargin = 8,
				data = { item = nil },
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
				halign = "center",
				width = "auto",
				vmargin = 8,
				showProductDetails = function(element, item)
					element:SetClass("collapsed", item.itemType == "Dice" and item.assetid ~= dmhub.GetSettingValue("diceequipped"))
				end,
			},

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


		--Non-gift info/cart column. Collapses for dice -- the showcase above
		--already shows the banner (name/details overlay) and its own Add to Cart.
		cond(args.gift, nil, gui.Panel{
			width = "auto",
			height = "auto",
			halign = "left",
			showProductDetails = function(element, item)
				element:SetClass("collapsed", item ~= nil and item.itemType == "Dice")
			end,
			m_shopItemText,
		}),
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
		--Floated + vertically centered so the details showcase sits in the middle
		--of the screen rather than hugging the top. Anchors to the (full-height)
		--main lower panel that hosts it.
		floating = true,
		halign = "center",
		valign = "center",

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
					height = "auto",

					gui.Panel{
						--padding
						height = 40
					},

					gui.Panel{
						classes = {"shopLogo"},
						width = 128,
						height = 64,
						bgimage = "panels/logo/DMHubLogoBare.png",
						bgcolor = "white",
						halign = "center",
						valign = "top",
						vmargin = 16,
					},

					MakeDiceBanner(),


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

					--The text header for the main shop page is replaced by the
					--dice banner above; keep the panel around (collapsed) in
					--case we want to bring the tagline back.
					gui.Panel{
						classes = {"collapsed"},
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

				--main lower panel. Height is auto while browsing the grid (so the
				--product rows scroll normally), but fills the screen while viewing a
				--single product's details, so the floated details panel can center
				--vertically instead of hugging the top. Toggled by the
				--showProductDetails/showProducts handlers below.
				gui.Panel{
					classes = {"lowerShopPanel"},
					width = "100%",

					styles = {
						{
							selectors = {"lowerShopPanel"},
							height = "auto",
						},
						{
							selectors = {"lowerShopPanel", "viewingDetails"},
							height = "100%",
						},
						{
							selectors = {"showingCouponInventory"},
							collapsed = 1,
						},
						{
							selectors = {"redeemingCoupon"},
							collapsed = 1,
						},
					},

					showProductDetails = function(element)
						element:SetClass("viewingDetails", true)
					end,

					showProducts = function(element)
						element:SetClass("viewingDetails", false)
					end,

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


							--Steam Microtransactions checkout. Only visible on Steam builds.
							--The Steam overlay confirms the cart total in one popup; on Yes,
							--the server (steamPurchaseFinalize) writes ShopItemInstance rows
							--directly into the user's inventory and we enter the same
							--checkingOut state the browser-checkout uses.
							gui.Label{
								classes = {"itemButton", "checkoutButton", "collapseUnlessCartWithItems"},
								halign = "center",
								hmargin = 16,
								text = "Buy with Steam",
								data = { purchasing = false, originalText = "Buy with Steam" },

								create = function(element)
									--Hide unless Steam is initialized OR we're in the
									--dev simulate mode (so the post-purchase UI is
									--testable without launching through Steam).
									if not (shop.steamAvailable or DevSimulateSteamPurchase()) then
										element:SetClass("collapsed", true)
									end
								end,

								press = function(element)
									if element.data.purchasing then return end

									--The Steam Microtransaction confirmation is shown
									--through the Steam overlay. If the overlay isn't
									--running (launched outside Steam, or the overlay is
									--disabled in Steam's settings) the confirmation can
									--never appear, so block the purchase up front and
									--tell the user why. Skipped in dev simulate mode,
									--which bypasses Steam entirely.
									if not DevSimulateSteamPurchase() and not dmhub.IsSteamOverlayRunning() then
										gui.Tooltip{
											text = tr("The Steam overlay must be enabled to purchase. Turn it on in Steam under Settings -> In Game, then restart Draw Steel."),
											valign = "top",
											borderWidth = 0,
										}(element)
										return
									end

									--m_shoppingCart is keyed by itemid -> true (entries are
									--removed by setting to nil), so the keys are the items in
									--the cart.
									local itemids = {}
									for itemid in pairs(m_shoppingCart) do
										itemids[#itemids+1] = itemid
									end
									if #itemids == 0 then return end

									analytics.Event{
										type = "shopCheckoutSteam",
									}

									element.data.purchasing = true
									element.text = "Confirm in Steam..."

									local function onSuccess(instanceids)
										if not element.valid then return end
										element.data.purchasing = false
										element.text = element.data.originalText
										element:FireEventOnParents("steamPurchaseError", "")
										element:FireEventOnParents("steamPurchaseSuccess", instanceids)

										--Granted items are now in the user's inventory;
										--remove them from the cart so the cart UI doesn't
										--still show them as purchasable.
										for k in pairs(m_shoppingCart) do
											m_shoppingCart[k] = nil
										end

										--Close the cart panel first (showInventory only
										--switches the title/content mode; it doesn't
										--collapse the cart on its own), then transition
										--to Inventory so the user sees their newly-
										--granted item.
										element:FireEventOnParents("hideCart")
										resultPanel:FireEvent("showInventory")
									end

									local function onFailure(err)
										if not element.valid then return end
										element.data.purchasing = false
										element.text = element.data.originalText
										element:FireEventOnParents("steamPurchaseError", err)
									end

									if DevSimulateSteamPurchase() then
										--Dev shortcut: skip Steam entirely. Pretend
										--the auth + finalize succeeded so we can
										--iterate on the post-purchase UI without
										--redeploying or going through the overlay.
										dmhub.Schedule(0.5, function()
											if mod.unloaded then return end
											onSuccess(itemids)
										end)
										return
									end

									shop:BuyItemsWithSteam(itemids, onSuccess, onFailure)
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

						--Transient error display for "Buy with Steam". Cleared on success
						--by firing steamPurchaseError with an empty string.
						gui.Label{
							classes = {"collapsed"},
							text = "",
							fontSize = 18,
							color = "#ff8888",
							halign = "center",
							width = "80%",
							height = "auto",
							textAlignment = "center",
							vmargin = 4,
							steamPurchaseError = function(element, message)
								element.text = message or ""
								element:SetClass("collapsed", message == nil or message == "")
							end,
						},

						--Transient success display for "Buy with Steam". Auto-hides
						--after 3s; the cart-close handler in the press handler
						--still runs immediately on success so the user gets fast
						--visual feedback.
						gui.Label{
							classes = {"collapsed"},
							text = "Purchase complete!",
							fontSize = 18,
							color = "#88ff88",
							halign = "center",
							width = "80%",
							height = "auto",
							textAlignment = "center",
							vmargin = 4,
							steamPurchaseSuccess = function(element)
								element:SetClass("collapsed", false)
								dmhub.Schedule(3.0, function()
									if mod.unloaded then return end
									if not element.valid then return end
									element:SetClass("collapsed", true)
								end)
							end,
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


		--MCDM/Codex builds normally hide the commerce UI (price labels,
		--checkout buttons, gifting, etc.) since the live shop isn't open to
		--the public yet. The dev:storepreview preference (toggled by the same
		--setting that exposes the Shop/Inventory menu items in the title bar)
		--bypasses this so we can browse + buy test items via Steam MTX
		--sandbox.
		if dmhub.whiteLabel == "mcdm" and not g_devStorePreviewSetting:Get() then
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

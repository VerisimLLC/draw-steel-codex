local mod = dmhub.GetModLoading()

--Mirror of CodexTitleBar.lua's "dev:storepreview" setting. Settings are
--keyed by id, so re-declaring here gives this file read access to the same
--persisted preference without exporting the local from the title bar.
local g_devStorePreviewSetting = setting{
    id = "dev:storepreview",
    default = false,
    storage = "preference",
}

--Shop items in the "Preview in store" state (item.preview; set from the shop
--admin panel) are shown in the shop only to users with this preference on.
--No editor field, so it never appears in settings menus; flip on with
--/set dev:storeitempreview true.
local g_storeItemPreviewSetting = setting{
    id = "dev:storeitempreview",
    description = "Show preview-state items in the shop.",
    default = false,
    storage = "preference",
}

--True if this item is in the "Preview in store" state. Read defensively (the
--C# field may predate this build, like featured/hidden); on older builds
--nothing is ever a preview item. Mutually exclusive with onsale.
local function ItemIsStorePreview(item)
    local ok, val = pcall(function() return item.preview end)
    return ok and val == true
end

--True if the local user should see this item in the shop: live (onsale) items
--for everyone, preview items only for users with dev:storeitempreview on.
local function ItemVisibleInShop(item)
    if item.onsale then
        return true
    end
    if not g_storeItemPreviewSetting:Get() then
        return false
    end
    return ItemIsStorePreview(item)
end

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

--The store background defaults to a looping video (media/shopbg.webm). The MCDM
--white label instead shows a static branded still (panels/storebg2.png). These
--helpers keep the choice in one place -- it is used by both the shop screen and
--its "assets still downloading" loading splash. The video is drawn under a grey
--multiply tint; the finished still is shown at full brightness (bgcolor white).
local function StoreBackgroundImage()
    if dmhub.whiteLabel == "mcdm" then
        return "panels/storebg2.png"
    end
    return "media/shopbg.webm"
end

local function StoreBackgroundColor()
    if dmhub.whiteLabel == "mcdm" then
        return "white"
    end
    return "#bbbbbbff"
end

--First-open loading cover ----------------------------------------------------
--The shop's art (featured banner images, tile art, product shots) is streamed
--from the cloud. A panel whose image is still downloading either renders
--nothing or -- if the panel previously showed the white square.png
--placeholder -- a flat white rectangle, so the first open of the shop looked
--broken for a moment while everything popped in. To fix that, the shop keeps
--a cover (the store background + a loading indicator) on top of the content
--until the initial page's images have actually arrived, then fades it out.
--
--Any image panel wrapped with TrackCoverImage participates: it reports
--shopImagePending up the tree when created and shopImageReady once its image
--is loaded (the engine fires imageLoaded on a freshly created panel both for
--instant cache hits and async downloads). The cover -- built in DisplayShop --
--counts the reports and reveals when they balance, or after
--g_shopCoverMaxTime as a backstop so a failed download can't hold the shop
--hostage. Reports arriving after the reveal (page flips, details view,
--carousel switches) are ignored.

--How long the cover will wait for tracked images before revealing anyway.
local g_shopCoverMaxTime = 4

--Fade-out time of the cover once the content is ready.
local g_shopCoverFadeTime = 0.25

--Wraps a gui.Panel args table (which must carry a bgimage) with the
--pending/ready reporting above. When fadeIn is set the panel also gets the
--"shopArtFadeIn" class (see shopStyles): it starts transparent and eases in
--over 0.2s when its image arrives, so art that lands after the reveal fades
--in instead of popping.
local function TrackCoverImage(args, fadeIn)
	if fadeIn then
		local classes = args.classes or {}
		classes[#classes+1] = "shopArtFadeIn"
		args.classes = classes
	end

	local oldCreate = args.create
	args.create = function(element)
		element:FireEventOnParents("shopImagePending")
		if oldCreate ~= nil then
			oldCreate(element)
		end
	end

	local m_reported = false
	local oldImageLoaded = args.imageLoaded
	args.imageLoaded = function(element)
		if fadeIn then
			element:SetClass("loaded", true)
		end
		if not m_reported then
			m_reported = true
			element:FireEventOnParents("shopImageReady")
		end
		if oldImageLoaded ~= nil then
			oldImageLoaded(element)
		end
	end

	return args
end

local fontWeights = {"thin", "extralight", "light", "regular", "medium", "semibold", "bold", "heavy", "black"}

local heightStretch = 175

local shopStyles = {
	--Streamed art eases in when its texture arrives (see TrackCoverImage).
	--The unqualified rule keeps the panel transparent until the "loaded"
	--class lands; only the loaded rule carries a transitionTime so becoming
	--visible animates but the initial hidden state is instant.
	{
		selectors = {"shopArtFadeIn"},
		opacity = 0,
	},
	{
		selectors = {"shopArtFadeIn", "loaded"},
		opacity = 1,
		transitionTime = 0.2,
	},

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
		selectors = {"collapsedWhenRedeeming", "redeemingCoupon"},
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
		--Half the old vmargin=16 above (the title->subtitle gap the header
		--pair asked to tighten); keep the original 16 below so the header's
		--spacing to the banner/grid underneath is unchanged.
		tmargin = 8,
		bmargin = 16,
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
		maxHeight = 30,
		textOverflow = "ellipsis",
		fontSize = 12,
		vmargin = 10,
	},

	{
		selectors = {"itemButton"},

		color = "white",
		vmargin = 6,
		fontSize = 14,
		uppercase = true,
		width = 152,
		height = 40,
		bgimage = "panels/square.png",
		textAlignment = "center",
		borderColor = "white",
		borderWidth = 2,
		cornerRadius = 20,
	},
	{
		selectors = {"itemButton", "hover"},
		color = "black",
		transitionTime = 0.1,
		bgcolor = "white",
	},

	{
		selectors = {"itemButton", "checkoutButton"},
		color = "#000000cc",
		transitionTime = 0.1,
		bgcolor = "srgb:#f6ddb6",
		borderColor = "srgb:#f6ddb6",
	},
	{
		selectors = {"itemButton", "checkoutButton", "hover"},
		brightness = 1.4,
	},

	--A dice equip-panel button whose role/slot currently has THIS dice set
	--equipped (see the equip panel in ShowItemDetailsInternal). Gold like the
	--checkout button so "equipped" reads as the affirmative state.
	{
		selectors = {"itemButton", "equipped"},
		color = "#000000cc",
		transitionTime = 0.1,
		bgcolor = "srgb:#f6ddb6",
		borderColor = "srgb:#f6ddb6",
	},
	{
		selectors = {"itemButton", "equipped", "hover"},
		color = "#000000cc",
		bgcolor = "srgb:#f6ddb6",
		brightness = 1.4,
	},

	{
		selectors = {"itemButtonIcon"},
		halign = "left",
		valign = "center",
		height = 20,
		width = 20,
		hmargin = 16,
		bgcolor = "white",
	},

	{
		selectors = {"itemButtonIcon", "check", "~parent:checkoutButton"},
		opacity = 0.02,
	},

	{
		selectors = {"itemButtonIcon", "parent:hover"},
		bgcolor = "black",
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
		--Exactly image area (180 + heightStretch) + 21 text tmargin + 160 text.
		width = 320,
		height = 361 + heightStretch,
		hmargin = 30,
	},

	{
		selectors = {"shopSummaryDisplay", "newItem"},

		scale = 1.5,
		transitionTime = 1,
	},

	--Corner badge on a grid card whose item is only on the store in the
	--"Preview in store" state -- i.e. one that is on the page purely because
	--the local user has dev:storeitempreview on, and which the public cannot
	--see. See MakeShopItem.
	{
		selectors = {"shopPreviewBadge"},

		bgimage = "panels/square.png",
		bgcolor = "#000000cc",
		cornerRadius = 4,
		borderWidth = 1,
		borderFade = false,
		borderColor = "#ffc44dff",

		color = "#ffc44dff",
		fontFace = "Inter",
		fontSize = 12,
		fontWeight = "bold",
		uppercase = true,
		textAlignment = "center",

		width = 76,
		height = 20,
		halign = "left",
		valign = "top",
		hmargin = 10,
		vmargin = 6,
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
		height = 160,
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
	--Degrees the previewed die's idle spin AXIS is rotated about the screen-normal
	--(Z) axis. The spin speed stays constant (g_bannerBaseSpinSpeed); this only
	--changes which way it turns. 0 = original vertical spin; 180 = reversed; 90 = tumbling.
	spinDirection = 0,
	textPlacement = "right",
	textOffsetX = 0,
	textOffsetY = 0,
}

--Constant idle spin speed (degrees/sec) for the previewed die. The per-item
--spinDirection only rotates the spin AXIS (about the screen-normal Z axis), so
--changing direction never changes how fast the die turns.
local g_bannerBaseSpinSpeed = 30

--Number of live shop screens (titlescreen-hosted or in-game). Maintained by
--CreateShopScreen's dialog create/destroy and exposed through
--ShopDiceBanner.ShopScreenOpen so surfaces reusing shop components outside
--the shop (the titlescreen store banner's mini carousel) can yield the
--shared "#DicePreview" scene while a real shop screen is up.
local g_openShopScreens = 0

--One-time capability flag: scene.spinAxisAngle is a new C# bridge property
--shipped alongside this code. It is set false the first time the engine binary
--predates it (Lua hot-reloaded against an older build) so the per-frame think
--handler stops trying instead of erroring every frame. Resets fresh on reload.
local g_supportsSpinAxis = true

--Recommended/native source dimensions for custom banner art, shared with the
--admin editor so it can document the target size.
ShopDiceBannerArtWidth = 1232
ShopDiceBannerArtHeight = 706

--On-screen banner size, in solid pixels. Width matches the VISIBLE outer
--edges of a row of 3 shop items: the item slots span 1080 (320*3 + 60*2 gaps),
--but each card's shopbg.png frame art bleeds past its slot (the 520-wide
--padded shopItemBackground stretches the 473px-wide art, whose solid region
--runs from x=73 to x=392), so the perceived row edges sit ~16px outside the
--slots on each side. Height preserves the art's native aspect so the full
--image is shown uncropped.
local g_bannerDisplayWidth = 1112
local g_bannerDisplayHeight = math.floor(g_bannerDisplayWidth * ShopDiceBannerArtHeight / ShopDiceBannerArtWidth)

--The banner die is rendered into the shared "#DicePreview" RT at 1/g_bannerDieRtZoom
--scale and shown in a die panel g_bannerDieRtZoom times larger, so the on-screen die is
--the SAME size but its attached particle FX (appearance burst, embers, shockwaves) get
--that many times more room inside the preview camera frame before being clipped at the
--RT edges. The die's stage FX are attachToDie Hierarchy-scaled children
--(DiceController.ApplyHierarchyScaling), so they shrink with the die and ride the same
--zoom. This is a pure framing change on the shared singleton scene: diceScale is divided
--here and the panel multiplied, with no change to the 1024x1024 RT (it has resolution to
--spare for the on-screen size). Only the bare-"#DicePreview" banner uses this; the pooled
--"#DicePreview:<assetid>:<seq>" tile previews are a separate scene and are unaffected.
local g_bannerDieRtZoom = 2

--Featured-dice carousel cross-fade timings (seconds). When switching featured
--sets via the dots, the background/foreground images dissolve over the full
--time while the text fades out then in around a midpoint, and the (single,
--shared) preview die hard-cuts at that same midpoint. The text-fade and
--die-cut times are half the full time so the midpoint stays centered.
local g_bannerCrossfadeTime = 1.5
local g_bannerTextFadeTime = 0.75
local g_bannerDieCutTime = 0.75

--The featured-dice carousel auto-advances to the next set this many seconds
--after the last switch (manual click or auto). Resets on every switch.
local g_bannerAutoCycleTime = 12

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

--Default per-item shop-tile preview config (item.dicePreview). A Dice item
--with no config renders its tile the automatic way -- a crop of its banner
--config zoomed in on the die (see BuildDiceTileLayers); when the admin
--customizes the preview display the item carries one of these instead and the
--tile becomes a mini banner of its own. The stored C# shape is shared with the
--banner config; tiles draw no text overlay, so the text fields are unused
--here. dieX/dieY are fractions of the TILE (die at its center by default);
--dieSize is in base tile pixels (0 = auto); diceScale matches the pooled tile
--scenes' engine default (DiceSetPreviewManager.TileDiceScale) so an untouched
--slider changes nothing.
local g_dicePreviewDefaults = {
	backgroundImage = "",
	foregroundImage = "",
	diceScale = 3.0,
	dieX = 0.5,
	dieY = 0.5,
	dieSize = 0,
	spinDirection = 0,
}

--Returns a full preview config: defaults overlaid with any fields present in
--cfg (may be nil or partial).
local function NormalizePreviewConfig(cfg)
	local result = {}
	for k,v in pairs(g_dicePreviewDefaults) do
		result[k] = v
	end
	if type(cfg) == "table" then
		for k,_ in pairs(g_dicePreviewDefaults) do
			if cfg[k] ~= nil then
				result[k] = cfg[k]
			end
		end
	end
	return result
end

--Reads item.dicePreview defensively. Returns a normalized config, or nil when
--the item has no custom preview config (or the engine binary predates the
--dicePreview bridge property) -- nil means "automatic": the tile derives its
--look from the banner config, as it always has.
local function ReadItemPreviewConfig(item)
	if item == nil then
		return nil
	end
	local ok, cfg = pcall(function() return item.dicePreview end)
	if ok and type(cfg) == "table" then
		return NormalizePreviewConfig(cfg)
	end
	return nil
end

--Maps a placement preset + pixel offset onto a floating text panel. The panel
--is anchored to an edge/corner (halign/valign) and pushed inward by a base
--inset, then nudged by the user's offset.
local function ApplyTextPlacement(textPanel, placement, offsetX, offsetY)
	--Edge margin for the standard placement presets (was 36; now 60% of that).
	local inset = 21.6
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

	--opts.pause: optional predicate(bannerPanel). While it returns true the
	--banner leaves the shared "#DicePreview" scene completely alone: the
	--per-frame think driver early-outs and the auto-cycle timer reschedules
	--without advancing (a cross-fade would PlayExit the shared scene's die
	--out from under whoever else is driving it). Used by the titlescreen
	--store banner's mini carousel so it yields the scene to a real shop
	--screen while one is open and sleeps while it is offscreen.
	--Solid pixel dimensions; height preserves the 1232x706 art aspect so the
	--full image is shown uncropped. (See g_bannerDisplayWidth/Height.)
	local bannerWidth = g_bannerDisplayWidth
	local imageHeight = g_bannerDisplayHeight

	local m_item = nil
	local m_suspended = false

	--The top featured banner carousels up to three random "featured" dice
	--products; the dots in the bottom-right corner switch between them.
	--m_featuredIndex is the 1-based index of the one currently shown.
	local m_featuredItems = {}
	local m_featuredIndex = 1

	--Cross-fade transition state. The shown die is driven from m_dieAssetid
	--(not m_item) so the carousel can hard-cut the die at the midpoint while
	--the images dissolve across the full second. m_transitionGen guards the
	--scheduled midpoint against a newer switch superseding it; m_destroyed
	--guards against the banner being torn down mid-transition.
	local m_dieAssetid = nil
	local m_transitionGen = 0
	local m_destroyed = false

	--Guards the pending auto-advance timer so a manual switch (or a newer
	--auto-advance) supersedes an older scheduled one.
	local m_autoCycleGen = 0

	--Live banner config (see g_diceBannerDefaults). Starts at defaults; the
	--shop overwrites it from the featured item's diceBanner, and the admin
	--editor drives it live via the applyBannerConfig event.
	local m_cfg = NormalizeBannerConfig(nil)
	local m_diceScale = m_cfg.diceScale
	local m_spinDirection = m_cfg.spinDirection
	--m_dieSize is the RENDER size of the die panel (2x, for FX headroom, see
	--g_bannerDieRtZoom). m_hitSize is the on-screen size of the VISIBLE die (1x),
	--which is the only part that is interactive (see the diePanel/dieHit split).
	local m_dieSize = math.floor(imageHeight * g_bannerDieRtZoom)
	local m_hitSize = math.floor(imageHeight)

	--The die render + interaction are split into two panels so the transparent
	--FX margin around the die does not block the editor controls behind it:
	--
	--  * diePanel renders the "#DicePreview" RT (die + attached FX). It is 2x the
	--    visible die (g_bannerDieRtZoom) so FX clear the frame edges, and the RT
	--    is transparent outside the die. It is NON-interactive, so its oversized
	--    bounding box never eats clicks (a panel is hit-tested by its box, not by
	--    which pixels are opaque). It is a centered child of dieHit.
	--
	--  * dieHit is a small, invisible hit box sized to the VISIBLE die (1x). It is
	--    the only interactive part, so grabbing works on the die itself and the
	--    surrounding FX margin passes clicks through. Because it is the dragged
	--    element, the render child rides along with it during a live drag.
	--
	--dieHit is interactive in two modes:
	--  * adminPreview: drag it on the banner to set the die POSITION. dragMove lets
	--    the engine move it (and its render child) live; 'drag' (on release) bakes
	--    the final spot (via dragDelta), clamps it, reports dieX/dieY via 'dieDragged'.
	--  * spin (shop showcase detailsMode, and the top featured banner via
	--    opts.spinnable): grab it to SPIN the die. beginDrag flips the shared preview
	--    scene into drag mode (cursor motion drives the spin velocity and direction);
	--    on release it decays back to the gentle idle spin (handled C#-side in
	--    DicePreviewScene). The box itself stays put (dragMove off).
	--Other banners leave the die non-interactive.
	local spinDrag = opts.detailsMode == true or opts.spinnable == true
	local diePanel = gui.Panel{
		floating = true,
		interactable = false,
		bgimage = "#DicePreview",
		bgcolor = "white",
		--The transparent preview RT is premultiplied (rendered over an alpha-0 clear) with an
		--engine-reconstructed alpha channel (DicePreviewScene's alpha fix). Premultiplied
		--compositing keeps additive dice FX (appearance/exit bursts, embers) from knocking
		--the banner art behind them out to black, and stops alpha-blended smoke being
		--double-darkened.
		blend = "premultiplied",
		width = m_dieSize,
		height = m_dieSize,
		halign = "center",
		valign = "center",
	}

	local dieHit = gui.Panel{
		floating = true,
		interactable = opts.adminPreview == true or spinDrag,
		draggable = opts.adminPreview == true or spinDrag,
		dragMove = opts.adminPreview == true,
		--Keep the normal (default) cursor while the die is interactive. Because
		--dieHit is the dragged panel, this also becomes the cursor for the whole
		--drag (see SheetPanel.GetHoveredMouseCursor), which suppresses the default
		--"forbidden" drag cursor a draggable panel shows when it has no drop target.
		hoverCursor = cond(opts.adminPreview == true or spinDrag, "default", nil),
		--Transparent, but a bgimage keeps a solid (bounding-box) hit surface.
		bgimage = "panels/square.png",
		bgcolor = "clear",
		width = m_hitSize,
		height = m_hitSize,
		halign = "left",
		valign = "top",

		beginDrag = function(element)
			if spinDrag then
				dice.GetPreviewScene().dragging = true
			end
		end,

		drag = function(element)
			if spinDrag then
				--Release: stop feeding cursor input; the spin coasts and decays.
				dice.GetPreviewScene().dragging = false
				return
			end

			--Admin: reposition the die and report the new dieX/dieY.
			element.x = element.x + element.dragDelta.x
			element.y = element.y + element.dragDelta.y
			local dieX = clamp((element.x + m_hitSize / 2) / bannerWidth, 0, 1)
			local dieY = clamp((element.y + m_hitSize / 2) / imageHeight, 0, 1)
			m_cfg.dieX = dieX
			m_cfg.dieY = dieY
			element.x = math.floor(bannerWidth * dieX - m_hitSize / 2)
			element.y = math.floor(imageHeight * dieY - m_hitSize / 2)
			element:FireEventOnParents("dieDragged", { dieX = dieX, dieY = dieY })
		end,

		diePanel,
	}

	--A cross-fade image layer sized to the full banner. setImage swaps the
	--shown image instantly (admin/details/first show); crossfadeImage
	--dissolves from the current image to a new one over g_bannerCrossfadeTime
	--seconds (carousel switch). Each image gets a FRESHLY CREATED panel rather
	--than recycling a shared pair: the engine keeps a brand-new panel
	--invisible until its texture has actually loaded (and fires imageLoaded on
	--it, feeding the first-open cover via TrackCoverImage), whereas re-setting
	--bgimage on a live panel leaves its previous sprite -- the flat white
	--square.png placeholder -- on screen for the whole download. That white
	--flash is what made the shop's first open look broken.
	local function MakeCrossfadeImageLayer()
		--The panel currently showing (or fading in), and the previous one
		--still dissolving out; the latter is destroyed on the next swap.
		local m_active = nil
		local m_fadingOut = nil

		--The image currently applied. Repeated applies of the same image are
		--no-ops (the old bgimage-setter short-circuit): the admin editor
		--re-applies the whole config on every slider tick, which must not
		--churn out a fresh panel each time.
		local m_image = nil

		local function MakeLayerPanel(image)
			if image == nil or image == "" then
				return nil
			end
			return gui.Panel(TrackCoverImage{
				classes = {"xfadeLayer", "fade"},
				floating = true,
				interactable = false,
				bgimage = image,
				bgcolor = "white",
				halign = "left",
				valign = "top",
				width = bannerWidth,
				height = imageHeight,
			})
		end

		return gui.Panel{
			floating = true,
			interactable = false,
			halign = "left",
			valign = "top",
			width = bannerWidth,
			height = imageHeight,

			--Only the fade class carries a transitionTime (both directions),
			--so the instant setImage path stays instant while crossfadeImage
			--dissolves over g_bannerCrossfadeTime. Matches MCDMClassCarousel.
			styles = {
				{
					selectors = {"xfadeLayer", "fade"},
					opacity = 0,
					transitionTime = g_bannerCrossfadeTime,
				},
			},

			--Instant swap (no dissolve): replace everything with a fresh panel
			--showing the image (or nothing, when the field is empty/cleared).
			setImage = function(element, image)
				if image == m_image then
					return
				end
				m_image = image
				m_active = MakeLayerPanel(image)
				m_fadingOut = nil
				element.children = {m_active}
				if m_active ~= nil then
					m_active:SetClassImmediate("fade", false)
				end
			end,

			--Dissolve from the current image to a new one: fade a fresh panel
			--in over the old one fading out.
			crossfadeImage = function(element, image)
				if image == m_image then
					return
				end
				m_image = image
				if m_fadingOut ~= nil then
					m_fadingOut:DestroySelf()
				end
				m_fadingOut = m_active
				m_active = MakeLayerPanel(image)
				if m_active ~= nil then
					element:AddChild(m_active)
					m_active:SetClass("fade", false)
				end
				if m_fadingOut ~= nil then
					m_fadingOut:SetClass("fade", true)
				end
			end,
		}
	end

	--The background art (behind the die) and the foreground overlay in front of
	--the die (e.g. hands holding it). Both are full-banner cross-fade layers.
	local backLayer = MakeCrossfadeImageLayer()
	local frontLayer = MakeCrossfadeImageLayer()

	local resultPanel

	--Applies the die-only part of a config: size, position, scale, spin axis,
	--and which dice set the (shared) preview scene shows. Pulled out of
	--ApplyConfig so the carousel can hard-cut the die at the transition midpoint
	--independently of the image cross-fade. assetid drives the preview die via
	--m_dieAssetid (read by think); pass nil for "no die yet".
	local function ApplyDieState(cfg, assetid)
		m_diceScale = cfg.diceScale
		m_spinDirection = cfg.spinDirection

		local hitSize = cfg.dieSize
		if hitSize == nil or hitSize <= 0 then
			hitSize = math.floor(imageHeight)
		end
		m_hitSize = hitSize
		--Render the die small in the RT and show it in a proportionally larger panel so its
		--FX clear the frame edges; the on-screen die size is unchanged (see g_bannerDieRtZoom).
		m_dieSize = math.floor(hitSize * g_bannerDieRtZoom)

		--The hit box tracks the VISIBLE die (1x), positioned in banner coords.
		--The render panel is a centered child, so it overflows the hit box
		--symmetrically with its (non-interactive) 2x FX margin.
		dieHit.width = hitSize
		dieHit.height = hitSize
		dieHit.x = math.floor(bannerWidth * cfg.dieX - hitSize / 2)
		dieHit.y = math.floor(imageHeight * cfg.dieY - hitSize / 2)
		diePanel.width = m_dieSize
		diePanel.height = m_dieSize

		m_dieAssetid = assetid
	end

	--Applies a banner config instantly (no cross-fade): the two (uncropped,
	--full-size) layer images, the die state, and (via a tree event) the text
	--overlay placement. Used by the admin live preview, the details showcase,
	--and the carousel's first show. Safe to call repeatedly as the admin editor
	--tweaks values. dieX/dieY are fractions of the full image.
	local function ApplyConfig(cfg)
		m_cfg = cfg
		backLayer:FireEvent("setImage", cfg.backgroundImage)
		frontLayer:FireEvent("setImage", cfg.foregroundImage)
		ApplyDieState(cfg, (m_item ~= nil and m_item.assetid) or nil)
		resultPanel:FireEventTree("placeBannerText", cfg)
	end

	--True for a dice product currently flagged featured. featured is read
	--defensively (the C# field may predate this build, like spinAxisAngle).
	--Only live (onsale) dice can be featured.
	local function IsFeaturedDice(item)
		if item.itemType ~= "Dice" or not item.onsale then
			return false
		end
		local ok, val = pcall(function() return item.featured end)
		return ok and val == true
	end

	--Pick up to three featured dice at random (Fisher-Yates shuffle, take 3).
	local function SelectFeaturedDice()
		local pool = {}
		for _,item in pairs(assets.shopItems) do
			if IsFeaturedDice(item) then
				pool[#pool+1] = item
			end
		end

		for i=#pool,2,-1 do
			local j = math.random(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end

		local result = {}
		for i=1,math.min(3, #pool) do
			result[i] = pool[i]
		end
		return result
	end

	--Cross-fade from the current featured item to newItem. The images dissolve
	--over the full second; the text fades out then, at the midpoint, swaps and
	--fades back in; the (single, shared) preview die hard-cuts at that same
	--midpoint. m_item / die / text stay on the OLD set until the midpoint so
	--everything visible flips together.
	local function CrossfadeToItem(newItem)
		local newCfg = ReadItemBannerConfig(newItem)
		m_suspended = false

		--Kick off the current die's exit animation (Exit FX + fade-out) as the
		--cross-fade begins. The fade-out runs over the midpoint time so the die
		--mesh reaches full transparency exactly at the hard-cut, just as the new
		--dice set takes over and plays its own appearance. pcall-guarded so a
		--pre-build engine binary (no PlayExit) simply skips it.
		pcall(function() dice.GetPreviewScene():PlayExit(g_bannerDieCutTime) end)

		backLayer:FireEvent("crossfadeImage", newCfg.backgroundImage)
		frontLayer:FireEvent("crossfadeImage", newCfg.foregroundImage)
		resultPanel:FireEventTree("fadeBannerText", true)

		m_transitionGen = m_transitionGen + 1
		local gen = m_transitionGen
		dmhub.Schedule(g_bannerDieCutTime, function()
			--Skip if the banner is gone, the mod reloaded, or a newer switch
			--has superseded this one.
			if mod.unloaded or m_destroyed or gen ~= m_transitionGen then
				return
			end

			m_item = newItem
			m_cfg = newCfg
			ApplyDieState(newCfg, newItem.assetid)
			resultPanel:FireEventTree("refreshBannerItem", newItem)
			resultPanel:FireEventTree("placeBannerText", newCfg)
			resultPanel:FireEventTree("fadeBannerText", false)
		end)
	end

	--Forward-declared because ScheduleAutoCycle (below) advances via it, while
	--ShowFeatured (re)arms the auto-cycle timer through ScheduleAutoCycle.
	local ShowFeatured

	--(Re)arm the auto-advance timer: g_bannerAutoCycleTime after the most recent
	--switch, cross-fade to the next featured set, wrapping around. Only runs when
	--there is more than one featured set; resets on every switch via the gen
	--guard. While the banner is suspended (cart/inventory view) it just reschedules
	--instead of advancing, so it resumes cleanly when the banner is shown again.
	local function ScheduleAutoCycle()
		if #m_featuredItems <= 1 then
			return
		end

		m_autoCycleGen = m_autoCycleGen + 1
		local gen = m_autoCycleGen
		dmhub.Schedule(g_bannerAutoCycleTime, function()
			if mod.unloaded or m_destroyed or gen ~= m_autoCycleGen then
				return
			end

			if m_suspended or (opts.pause ~= nil and opts.pause(resultPanel)) then
				ScheduleAutoCycle()
				return
			end

			local nextIndex = m_featuredIndex + 1
			if nextIndex > #m_featuredItems then
				nextIndex = 1
			end
			ShowFeatured(nextIndex, true)
		end)
	end

	--Show the featured dice at the given carousel index and light its dot. When
	--animate is set (a dot click or auto-advance) and there is a previous item,
	--cross-fade to it; otherwise (the first show) apply it instantly. Either way
	--the auto-cycle countdown restarts.
	ShowFeatured = function(index, animate)
		if #m_featuredItems == 0 then
			return
		end
		index = clamp(index, 1, #m_featuredItems)
		local newItem = m_featuredItems[index]
		m_featuredIndex = index
		resultPanel:FireEventTree("setFeaturedDot", index)

		if animate and m_item ~= nil and newItem ~= m_item then
			CrossfadeToItem(newItem)
		else
			m_item = newItem
			m_suspended = false
			ApplyConfig(ReadItemBannerConfig(newItem))
			resultPanel:FireEventTree("refreshBannerItem", newItem)
		end

		ScheduleAutoCycle()
	end

	resultPanel = gui.Panel{
		--Only the top featured banner auto-hides on the cart/inventory/artist
		--views. The passive admin-preview and details-showcase banners manage
		--their own visibility, so they skip these classes (otherwise the details
		--banner would vanish when viewing a dice item from the inventory).
		classes = cond(opts.adminPreview or opts.detailsMode, {}, {"collapseOnCart", "collapsedWhenInventory", "collapsedWhenArtistFocus", "collapsedWhenRedeeming"}),
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
				color = "white",
				vmargin = 6,
				fontSize = 14,
				uppercase = true,
				width = 140,
				height = 40,
				bgimage = "panels/square.png",
				textAlignment = "center",
				borderColor = "white",
				borderWidth = 2,
				cornerRadius = 20,
			},
			{
				selectors = {"itemButton", "hover"},
				color = "black",
				transitionTime = 0.1,
				bgcolor = "white",
			},

			--Carousel text-box fade: toggling "faded" dissolves the whole text
			--box. Used to fade the old copy out and the new copy in across a
			--featured switch. transitionTime lives on the faded rule (both
			--directions), matching the image cross-fade pattern.
			{
				selectors = {"bannerTextBox", "faded"},
				opacity = 0,
				transitionTime = g_bannerTextFadeTime,
			},
		},

		--Marks the banner torn down so an in-flight cross-fade midpoint callback
		--(dmhub.Schedule) bails instead of touching dead panels.
		destroy = function(element)
			m_destroyed = true
		end,

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

			--Carousel up to three random featured dice; the dots below the
			--banner's bottom-left corner switch between them.
			m_featuredItems = SelectFeaturedDice()

			--Fallback when nothing is flagged featured: show the first dice
			--product (prefer one on sale), as before -- no dots in that case.
			if #m_featuredItems == 0 then
				local fallback = nil
				for _,item in pairs(assets.shopItems) do
					if item.itemType == "Dice" then
						if item.onsale then
							m_featuredItems = { item }
							break
						end
						fallback = fallback or item
					end
				end

				if #m_featuredItems == 0 and fallback ~= nil then
					m_featuredItems = { fallback }
				end
			end

			if #m_featuredItems > 0 then
				element.thinkTime = 0.01
				element:FireEventTree("buildFeaturedDots", #m_featuredItems)
				ShowFeatured(1)

				--Warm the OTHER featured sets' banner art right away (setting a
				--bgimage starts the download even on an invisible 1px panel), so
				--the first carousel cross-fades dissolve onto already-loaded
				--images instead of onto art that pops in mid-fade.
				local warm = {}
				for i = 2, #m_featuredItems do
					local cfg = ReadItemBannerConfig(m_featuredItems[i])
					for _,img in ipairs({cfg.backgroundImage, cfg.foregroundImage}) do
						if img ~= nil and img ~= "" then
							warm[#warm+1] = gui.Panel{
								interactable = false,
								width = 1,
								height = 1,
								bgcolor = "clear",
								bgimage = img,
							}
						end
					end
				end
				if #warm > 0 then
					element:AddChild(gui.Panel{
						interactable = false,
						floating = true,
						halign = "left",
						valign = "top",
						width = 1,
						height = 1,
						children = warm,
					})
				end
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

				--A carousel cross-fade may have just started the shared preview
				--die's exit fade (PlayExit in CrossfadeToItem). If this item is
				--the same dice set the scene is already showing, nothing rebuilds
				--the dice (the scene only replays the appearance on an assetid
				--CHANGE), so the exit would run to full transparency and the die
				--would stay invisible here. Recover it; no-op when no exit is in
				--flight. pcall-guarded so a pre-build engine binary (no
				--CancelExit) simply skips it.
				pcall(function() dice.GetPreviewScene():CancelExit() end)

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

			--Externally paused (opts.pause): someone else owns the shared
			--preview scene right now, or we are offscreen. Leave it alone.
			if opts.pause ~= nil and opts.pause(element) then
				return
			end

			--Cart/inventory/redeem views hide the top featured banner; the details
			--showcase still drives the scene in those views.
			if not opts.detailsMode and (element:HasClass("showingCart") or element:HasClass("inventory") or element:HasClass("redeemingCoupon")) then
				return
			end

			--Driven from m_dieAssetid (not m_item.assetid) so a carousel switch
			--can hold the old die until its 0.5s hard-cut while m_item/text/images
			--transition.
			local assetid = m_dieAssetid
			if assetid == nil or assetid == "" then
				return
			end

			local scene = dice.GetPreviewScene()
			scene.assetid = assetid
			scene.selectedIndex = 0
			scene.solo = true
			scene.transparent = true
			--Divide by the zoom so the die renders small in the RT (leaving FX headroom); the
			--die panel is multiplied by the same factor, keeping the on-screen size constant.
			scene.diceScale = m_diceScale / g_bannerDieRtZoom
			scene.fixedTime = false

			--Gently turn the die so buyers see all its faces -- on the featured top
			--banner / carousel, the details showcase, AND the admin preview (so the
			--admin sees the exact rotation shoppers will). The speed is constant; the
			--per-item spinDirection only re-aims the spin axis (rotating it about the
			--screen-normal Z axis), so the admin slider changes direction, not speed.
			scene.initialRotation = g_bannerBaseSpinSpeed
			if g_supportsSpinAxis then
				--pcall-guarded: tolerate a pre-build engine binary (see g_supportsSpinAxis).
				g_supportsSpinAxis = pcall(function() scene.spinAxisAngle = m_spinDirection end)
			end
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
			printf("BANNER:: front rendered=%sx%s", json(frontLayer.renderedWidth), json(frontLayer.renderedHeight))
			printf("BANNER:: die pos=(%s,%s) hit=%sx%s render=%sx%s scale=%s", json(dieHit.x), json(dieHit.y), json(dieHit.renderedWidth), json(dieHit.renderedHeight), json(diePanel.renderedWidth), json(diePanel.renderedHeight), json(m_diceScale))
		end,

		--Order matters: backLayer (background art) behind the die, frontLayer
		--(foreground overlay) in front of it. Both are cross-fade layers.
		--dieHit carries the die render panel (diePanel) as its child.
		backLayer,

		dieHit,

		frontLayer,

		--Advertising copy for the featured dice. By default it sits on the
		--empty rock to the right of the skeleton; per-item config can move it
		--to any edge/corner. A dark scrim sits behind the text so it stays
		--readable over the art. ApplyTextPlacement sets halign/valign/x/y.
		gui.Panel{
			classes = {"bannerTextBox"},
			floating = true,
			flow = "vertical",
			halign = "right",
			valign = "center",
			width = 420,
			height = "auto",
			borderBox = true,
			--Padding cut 30% (hpad 24 -> 16.8, vpad 20 -> 14).
			hpad = 16.8,
			vpad = 14,
			bgimage = "panels/square.png",
			bgcolor = "#000000c0",
			cornerRadius = 12,

			placeBannerText = function(element, cfg)
				ApplyTextPlacement(element, cfg.textPlacement, cfg.textOffsetX, cfg.textOffsetY)
			end,

			--Cross-fade the whole text box out (true) / in (false) during a
			--featured carousel switch.
			fadeBannerText = function(element, faded)
				element:SetClass("faded", faded)
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
				maxHeight = 160,
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
						element:FireEventOnParents("showItemDetails", m_item, "featuredBanner")
					end
				end,
			},
		},

		--Carousel dots: one per featured dice set, with the currently shown one
		--lit. Clicking a dot cross-fades to that set. Floated below the banner
		--image at its left edge, vertically centered on the search-bar row that
		--occupies the gap under the banner (11px gap + 24px input, so y = 23 + 8
		--half-height of the 16px dots). Built by buildFeaturedDots (fired once
		--the featured set is chosen); stays empty in the admin preview / details
		--showcase.
		gui.Panel{
			floating = true,
			flow = "horizontal",
			halign = "left",
			valign = "bottom",
			width = "auto",
			height = "auto",
			hmargin = 0,
			vmargin = 0,
			y = 31,

			styles = {
				{
					selectors = {"featuredDot"},
					bgimage = "panels/square.png",
					width = 12,
					height = 12,
					cornerRadius = 6,
					hmargin = 5,
					valign = "center",
					bgcolor = "#ffffff66",
					transitionTime = 0.1,
				},
				{
					selectors = {"featuredDot", "hover"},
					bgcolor = "#ffffffbb",
				},
				{
					selectors = {"featuredDot", "selected"},
					bgcolor = "#ffffffff",
				},
			},

			data = {
				dots = {},
			},

			--Build one dot per featured set. A single set (or the no-featured
			--fallback) needs no carousel, so dots only appear when count > 1.
			buildFeaturedDots = function(element, count)
				local dots = {}
				local children = {}
				if count > 1 then
					for i=1,count do
						local idx = i
						local dot = gui.Panel{
							classes = {"featuredDot"},
							press = function()
								ShowFeatured(idx, true)
							end,
						}
						dots[i] = dot
						children[i] = dot
					end
				end
				element.data.dots = dots
				element.children = children
			end,

			--Light the dot for the currently shown featured set.
			setFeaturedDot = function(element, index)
				for i,dot in ipairs(element.data.dots) do
					dot:SetClass("selected", i == index)
				end
			end,
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

	--True while any real shop screen is open (see g_openShopScreens); used
	--as an opts.pause input by banners living outside the shop.
	ShopScreenOpen = function()
		return g_openShopScreens > 0
	end,
}

--Monotonic id handed to each shop-image display so dice tiles can request their
--own live preview die ("#DicePreview:<assetid>:<seq>"). The seq is stable for the
--life of a tile (assigned once below), so reusing a tile for a different dice set
--swaps to a fresh pooled preview and the old one is evicted engine-side.
local g_dicePreviewSeq = 0

--Base (unscaled) dimensions of a shop tile's image area (see the shopImage
--style / MakeShopImageDisplay, which multiply these by a per-instance
--uiscale). A per-item preview-display config positions its art and die in
--this space; instances at other scales (grid fullBleed, cart rows, details
--page) scale the whole composition proportionally.
local g_tileBaseWidth = 325
local g_tileBaseHeight = 180 + heightStretch

--Builds the composited layer panels for a Dice item's shop tile, shared by
--the real shop tiles (MakeShopImageDisplay.refreshDicePreview) and the
--ShopAdmin live preview (MakeDicePreviewTile). Returns (children, dieRect):
--children go inside a clip panel of args.tileW x args.tileH; dieRect
--{x, y, size} is the die box in tile coords (custom mode only, for the admin
--drag hit box), nil otherwise.
--
--args = { tileW, tileH, assetid, seq, previewCfg, bannerCfg }
--
--previewCfg == nil (automatic): the tile is a cropped view of the item's
--BANNER config -- the chosen background art zoomed in and centered on the
--configured die position, with the item's own live 3D die composited on top.
--Mirrors how the details banner composites background + die, but tightly
--framed on the die for the tile.
--
--previewCfg ~= nil (customized): the tile is a mini banner of its own -- the
--preview config's art fills the tile, and the die is positioned (dieX/dieY,
--fractions of the tile), sized (dieSize, base tile pixels, 0 = auto), scaled
--and spun (diceScale/spinDirection, carried in the preview key) by the config.
local function BuildDiceTileLayers(args)
	local tileW = args.tileW
	local tileH = args.tileH
	local children = {}

	--IMPORTANT: layers must NOT be built as oversized panels that get visually
	--clipped: a panel's bounding box takes mouse hits even where it is clipped,
	--so oversized layers made each tile steal presses from a huge area of the
	--screen (e.g. the search box and the gaps between cards, opening the wrong
	--item's details). Instead each layer panel is exactly the visible
	--intersection with the tile, with the crop done in UV space via imageRect.
	--Returns nil if the layer is entirely cropped.
	--
	--blendMode is optional; the live-die layer passes "premultiplied" because
	--the dice preview RT is premultiplied with a reconstructed alpha (see the
	--banner's diePanel comment). Art layers use the default straight-alpha blend.
	local function MakeCroppedLayer(image, w, h, offsetX, offsetY, blendMode)
		local x1 = math.max(0, offsetX)
		local y1 = math.max(0, offsetY)
		local x2 = math.min(tileW, offsetX + w)
		local y2 = math.min(tileH, offsetY + h)
		if x2 <= x1 or y2 <= y1 then
			return nil
		end

		local layerArgs = {
			interactable = false,
			floating = true,
			bgimage = image,
			bgcolor = "white",
			blend = blendMode,
			width = x2 - x1,
			height = y2 - y1,
			halign = "left",
			valign = "top",
			x = x1,
			y = y1,
			imageRect = {
				x1 = (x1 - offsetX)/w,
				y1 = (y1 - offsetY)/h,
				x2 = (x2 - offsetX)/w,
				y2 = (y2 - offsetY)/h,
			},
		}

		--Streamed art layers report to the first-open cover and fade in when
		--their texture arrives. The live-die "#DicePreview" layers are lazy
		--RenderTextures with their own lifecycle: the engine already keeps
		--them hidden until their first rendered frame, and the cover must not
		--wait on them -- a die's dice ASSET can take several seconds to stream
		--in cold, and holding the whole shop for that reads as a hang.
		if string.sub(image, 1, 1) ~= "#" then
			layerArgs = TrackCoverImage(layerArgs, true)
		end

		return gui.Panel(layerArgs)
	end

	local assetid = args.assetid
	if assetid == nil or assetid == "" then
		return children, nil
	end

	if args.previewCfg ~= nil then
		--Customized preview display: a mini banner in tile space.
		local cfg = args.previewCfg

		--Art layers fill the tile exactly (author art at the tile's aspect;
		--see ShopDicePreview.artWidth/artHeight for the recommended size).
		--Tracked + fade-in like MakeCroppedLayer's art layers.
		local function FullTileLayer(image)
			return gui.Panel(TrackCoverImage({
				interactable = false,
				floating = true,
				bgimage = image,
				bgcolor = "white",
				width = tileW,
				height = tileH,
				halign = "left",
				valign = "top",
				x = 0,
				y = 0,
			}, true))
		end

		if cfg.backgroundImage ~= nil and cfg.backgroundImage ~= "" then
			children[#children+1] = FullTileLayer(cfg.backgroundImage)
		end

		--The die box, in base tile pixels scaled to this instance's tile size.
		--The preview RT is transparent outside the die; any part of the box
		--hanging past the tile is cropped away like the art layers.
		local scale = tileW / g_tileBaseWidth
		local dieSize = cfg.dieSize
		if dieSize == nil or dieSize <= 0 then
			dieSize = math.floor(g_tileBaseHeight * 1.5)
		end
		dieSize = math.floor(dieSize * scale)
		local dieX = math.floor(tileW * cfg.dieX - dieSize/2)
		local dieY = math.floor(tileH * cfg.dieY - dieSize/2)

		--Die scale + spin direction ride in the preview key, parsed engine-side
		--by DiceSetPreviewManager (older engine builds just ignore the extra
		--segments). %.2f quantizes slider edits so a drag doesn't mint a new
		--pooled scene every tick.
		local dieKey = string.format("#DicePreview:%s:%s:%.2f:%.2f",
			tostring(assetid), tostring(args.seq),
			cfg.diceScale or g_dicePreviewDefaults.diceScale,
			cfg.spinDirection or 0)
		children[#children+1] = MakeCroppedLayer(
			dieKey,
			dieSize, dieSize,
			dieX, dieY,
			"premultiplied")

		--Foreground art (in front of the die), added last so it draws on top.
		if cfg.foregroundImage ~= nil and cfg.foregroundImage ~= "" then
			children[#children+1] = FullTileLayer(cfg.foregroundImage)
		end

		return children, { x = dieX, y = dieY, size = dieSize }
	end

	--Automatic: derive from the banner config.
	local cfg = args.bannerCfg or NormalizeBannerConfig(nil)

	--Banner-space dimensions the die position (dieX/dieY) is relative to.
	local bannerW = g_bannerDisplayWidth
	local bannerH = g_bannerDisplayHeight

	--Show roughly this fraction of the banner height inside the tile (the rest
	--is cropped away), zooming in on the die. Kept ~= 1/dieZoom below so the
	--die sits on its background at banner-faithful proportions.
	local cropFrac = 0.667
	local zoom = tileH / (bannerH * cropFrac)
	local scaledW = bannerW * zoom
	local scaledH = bannerH * zoom

	--The background and foreground art share the banner's full-image coordinate
	--space: each is conceptually scaled to scaledW x scaledH and offset by the
	--same amount so the die point (dieX,dieY) lands at the tile center. (The
	--banner draws background behind the die and foreground -- e.g. hands
	--holding the die -- in front of it.)
	local layerX = math.floor(tileW*0.5 - cfg.dieX*scaledW)
	local layerY = math.floor(tileH*0.5 - cfg.dieY*scaledH)
	local function MakeBannerLayer(image)
		return MakeCroppedLayer(image, scaledW, scaledH, layerX, layerY)
	end

	--Chosen background art (behind the die).
	if cfg.backgroundImage ~= nil and cfg.backgroundImage ~= "" then
		children[#children+1] = MakeBannerLayer(cfg.backgroundImage)
	end

	--The live die. The preview RT is transparent outside the die, so the panel
	--is oversized (dieZoom) to bring the die up close; the empty margin is
	--cropped away by MakeCroppedLayer just like the art layers. Lower = more
	--space around the die.
	local dieZoom = 1.5
	local dieSize = math.floor(tileH * dieZoom)
	children[#children+1] = MakeCroppedLayer(
		"#DicePreview:" .. tostring(assetid) .. ":" .. tostring(args.seq),
		dieSize, dieSize,
		math.floor((tileW - dieSize)/2), math.floor((tileH - dieSize)/2),
		"premultiplied")

	--Chosen foreground art (in front of the die), added last so it draws on
	--top -- matching the details banner's frontPanel.
	if cfg.foregroundImage ~= nil and cfg.foregroundImage ~= "" then
		children[#children+1] = MakeBannerLayer(cfg.foregroundImage)
	end

	return children, nil
end

--A passive live preview of a Dice item's shop tile for the admin editor,
--mirroring ShopDiceBanner.Create{adminPreview = true}. Drive it with
--panel:FireEventTree("applyPreviewConfig", payload) where payload = {
--  cfg = <normalized preview config, or nil for automatic mode>,
--  bannerCfg = <normalized banner config (automatic mode derives from it)>,
--  item = <ShopItemLua>,
--}. In customized mode the die can be dragged to reposition it; the release
--fires "previewDieDragged" { dieX = ..., dieY = ... } up the parents (like
--the banner's dieDragged).
local MakeDicePreviewTile = function(opts)
	opts = opts or {}
	--Editing scale: the composition is authored in base tile space and shown
	--scale-times larger (1.5 matches the details-page tile exactly).
	local scale = opts.scale or 1
	local tileW = math.floor(g_tileBaseWidth * scale)
	local tileH = math.floor(g_tileBaseHeight * scale)

	g_dicePreviewSeq = g_dicePreviewSeq + 1
	local mySeq = g_dicePreviewSeq

	--True die-box center in tile pixels. Tracked separately from the hit box
	--because the hit box is CLAMPED to the tile (see applyPreviewConfig): the
	--auto die box is larger than the tile, and a panel's bounding box takes
	--mouse hits even where it hangs outside the tile, so an unclamped hit box
	--would cover -- and steal clicks from -- the editor controls around the
	--preview (section headers, checkboxes).
	local m_dieCenter = { x = tileW/2, y = tileH/2 }

	local clipPanel = gui.Panel{
		interactable = false,
		clip = true,
		clipHidden = true,
		bgimage = "panels/square.png",
		bgcolor = "clear",
		halign = "left",
		valign = "top",
		width = tileW,
		height = tileH,
	}

	--Invisible drag box tracking the die position (customized mode only;
	--collapsed in automatic mode). Mirrors the banner's dieHit.
	local dieHit = gui.Panel{
		classes = {"collapsed"},
		floating = true,
		draggable = true,
		dragMove = true,
		--Transparent, but a bgimage keeps a solid (bounding-box) hit surface.
		bgimage = "panels/square.png",
		bgcolor = "clear",
		width = 100,
		height = 100,
		halign = "left",
		valign = "top",

		drag = function(element)
			--Report the dragged die center; the resulting config edit re-fires
			--applyPreviewConfig, which re-renders the tile and re-lays-out this
			--hit box, so nothing needs baking here.
			local dieX = clamp((m_dieCenter.x + element.dragDelta.x) / tileW, 0, 1)
			local dieY = clamp((m_dieCenter.y + element.dragDelta.y) / tileH, 0, 1)
			element:FireEventOnParents("previewDieDragged", { dieX = dieX, dieY = dieY })
		end,
	}

	return gui.Panel{
		width = tileW,
		height = tileH,
		halign = "left",
		--Dark backdrop + border so transparent layers and the tile bounds read
		--clearly inside the editor.
		bgimage = "panels/square.png",
		bgcolor = "#111111ff",
		borderWidth = 1,
		borderColor = "#666666ff",

		applyPreviewConfig = function(element, payload)
			local children, dieRect = BuildDiceTileLayers{
				tileW = tileW,
				tileH = tileH,
				assetid = (payload.item ~= nil and payload.item.assetid) or nil,
				seq = mySeq,
				previewCfg = payload.cfg,
				bannerCfg = payload.bannerCfg,
			}
			clipPanel.children = children

			if dieRect ~= nil then
				--Clamp the hit box to the visible intersection of the die box
				--with the tile (see m_dieCenter above for why).
				local x1 = math.max(0, dieRect.x)
				local y1 = math.max(0, dieRect.y)
				local x2 = math.min(tileW, dieRect.x + dieRect.size)
				local y2 = math.min(tileH, dieRect.y + dieRect.size)
				m_dieCenter = { x = dieRect.x + dieRect.size/2, y = dieRect.y + dieRect.size/2 }
				dieHit.width = math.max(1, x2 - x1)
				dieHit.height = math.max(1, y2 - y1)
				dieHit.x = x1
				dieHit.y = y1
			end
			dieHit:SetClass("collapsed", dieRect == nil)
		end,

		clipPanel,
		dieHit,
	}
end

--Expose the tile-preview machinery so the Shop admin editor (a separate
--module) can render an exact live preview of a Dice item's shop tile while
--editing its preview-display config. Mirrors ShopDiceBanner above.
ShopDicePreview = {
	Create = MakeDicePreviewTile,
	NormalizeConfig = NormalizePreviewConfig,
	ReadItemConfig = ReadItemPreviewConfig,
	defaults = g_dicePreviewDefaults,
	tileWidth = g_tileBaseWidth,
	tileHeight = g_tileBaseHeight,
	--Recommended source art size: 2x the base tile, matching its aspect.
	artWidth = g_tileBaseWidth * 2,
	artHeight = g_tileBaseHeight * 2,
}

local MakeShopImageDisplay = function(options)
	options = options or {}
	local uiscale = options.uiscale or 1
	options.uiscale = nil

	local footer = options.footer
	options.footer = nil

	--Grid cards bleed the dice preview out to the visible edges of the card
	--frame art so there is no grey border beside or above the image.
	local fullBleed = options.fullBleed
	options.fullBleed = nil

	--Which surface this display lives on, for shopViewItem attribution
	--("productTile" grid cards, "cartRow" cart rows). The instances inside the
	--already-open details view (main gallery, footer thumbnails) leave it nil
	--so their presses refresh the page without being counted as a navigation.
	local analyticsSource = options.analyticsSource
	options.analyticsSource = nil

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
				element:FireEventOnParents("showItemDetails", m_item, analyticsSource)
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
			local iconArgs = {
				classes = {"shopIcon"},
				uiscale = uiscale,
				bgimage = imageid,
			}
			--Track/fade only when there is a real image; a nil bgimage never
			--fires imageLoaded and would hold the first-open cover until its
			--timeout.
			if imageid ~= nil and imageid ~= "" then
				iconArgs = TrackCoverImage(iconArgs, true)
			end
			element.children = {
				bg,
				gui.Panel(iconArgs),
			}
		end,

		--Builds this item's dice tile via BuildDiceTileLayers: either the
		--automatic banner-derived crop, or -- when the item carries a custom
		--dicePreview config -- its own mini-banner composition. Either way the
		--item's own live 3D die ("#DicePreview:<assetid>:<seq>[:params]") is
		--composited between the art layers.
		refreshDicePreview = function(element, item)
			local tileW = 325*uiscale
			local tileH = (180 + heightStretch)*uiscale

			--Full bleed: cover the visible card frame flush to its side and top
			--edges instead of sitting inside it. The solid region of shopbg.png
			--is 352px wide as drawn by the padded shopItemBackground (320px of
			--the 473px art, stretched by 520/473) and starts 8px above the item
			--panel's top (see the vpad tuning there), so scale the tile up
			--proportionally (keeping its aspect) and nudge it up to meet the
			--frame's top edge.
			local tileY = 0
			if fullBleed then
				local bleedScale = 352/325
				tileW = tileW * bleedScale
				tileH = tileH * bleedScale
				tileY = -8*uiscale
			end

			local clipChildren = BuildDiceTileLayers{
				tileW = tileW,
				tileH = tileH,
				assetid = item.assetid,
				seq = mySeq,
				previewCfg = ReadItemPreviewConfig(item),
				bannerCfg = ReadItemBannerConfig(item),
			}

			element.children = {
				bg,
				gui.Panel{
					interactable = false,
					clip = true,
					clipHidden = true,
					bgimage = "panels/square.png",
					bgcolor = "clear",
					halign = "center",
					valign = cond(fullBleed, "top", "center"),
					y = tileY,
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
					element.text = string.format("$%d.%02dUS", dollars, cents)
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
					local isGift = shop:ItemInInventory(m_itemId)
					--The cart icon (below) only makes sense for "Add to Cart";
					--a gift needs no cart, so hide the icon and drop the leading
					--spaces in that case. The leading spaces nudge the centered
					--"Add to Cart" label right so it clears the icon anchored at
					--the button's left edge (the button keeps its default width).
					element.text = cond(isGift, "Add as Gift", "   Add to Cart")
					element:SetClass("collapsed", false)
					for _,child in ipairs(element.children or {}) do
						if child:HasClass("itemButtonIcon") then
							child:SetClass("collapsed", isGift)
						end
					end
				end
			end,

			press = function(element)
				element:FireEventOnParents("addToCart", m_item)

				analytics.Event{
					type = "shopAddCart",
					itemid = m_item.id,
				}

			end,

			--Cart icon anchored at the button's left edge (shown for "Add to
			--Cart" only -- see refreshCart). Uses the shared itemButtonIcon class
			--so it recolors in tandem with the button (white -> black on
			--parent:hover, same as the "Auto Install" check icon).
			gui.Panel{
				classes = {"itemButtonIcon"},
				bgimage = "icons/icon_shopping/shopping-cart.png",
				hmargin = 12,
			},
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
			--vpad stretches shopbg.png's solid card region (y=93..337 of the
			--431-tall art) so its top edge lands 8px above the item panel
			--(where the fullBleed dice tile is anchored) and its bottom edge
			--~6px below it. Change the item height and this needs retuning.
			vpad = 218,
			--shopbg.png's solid card region sits 4px left of its canvas center
			--(solid x=73..392 in the 473-wide art); nudge right so the visible
			--frame is centered on the item slot and the row's outer edges line
			--up with the featured banner (see g_bannerDisplayWidth).
			x = 4,
		},

		MakeShopImageDisplay{ fullBleed = true, analyticsSource = "productTile" },

		--The fullBleed tile above draws ~21px below its 355px layout slot
		--(scaled to 384px, anchored 8px up), so push the text block down to
		--restore the original ~8px gap between the image and the title.
		MakeShopItemText{ tmargin = 21 },

		--"Preview" badge for items visible only because dev:storeitempreview
		--is on. Lives on the card rather than inside the image display -- that
		--rebuilds its whole child list on every refresh -- and is last in the
		--list so it draws over the card art (z-order = sibling order).
		gui.Label{
			classes = {"shopPreviewBadge", "collapsed"},
			floating = true,
			interactable = false,
			text = "Preview",

			refreshItem = function(element, item)
				element:SetClass("collapsed", not ItemIsStorePreview(item))
			end,
		},

	}
end

local ShopEntryPanel = function(item)
	local resultPanel

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",

		MakeShopImageDisplay{
			uiscale = 0.62,
			analyticsSource = "cartRow",
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
					dmhub.Roll{ roll = "2d10", ["local"] = true, silent = true, description = string.format("Trying %s", item.name) }
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

--------------------------------------------------------------------------------
--Dice slot ("uses") helpers, shared by the equip panel's slot-activation column
--and the "Add Uses..." custom-uses dialog. A slot is a record shaped like the
--Dice Studio's authored slots (see dicestudio.slots):
--  { slotType = "damage", damageType = "fire" }
--  { slotType = "class", classid = "<classes id>", subclassid = "<absent = any>" }
--  { slotType = "monster", groupid = "<MonsterGroup table id>" }
--------------------------------------------------------------------------------

--The diceslotsequipped key a slot record activates under. Must mirror the
--roll dialog's candidate keys (see EmbeddedRollDialog's slot-dice resolution).
local function SlotKey(slot)
	if slot.slotType == "damage" then
		return "damage:" .. (slot.damageType or "")
	end
	if slot.slotType == "monster" then
		return "monster:" .. (slot.groupid or "")
	end
	local key = "class:" .. (slot.classid or "")
	if slot.subclassid ~= nil and slot.subclassid ~= "" then
		key = key .. ":" .. slot.subclassid
	end
	return key
end

--Whether a slot record has its criteria chosen. Incomplete records (fresh rows
--in the Add Uses dialog) neither display in the equip panel nor auto-activate.
local function SlotIsComplete(slot)
	if slot.slotType == "damage" then
		return (slot.damageType or "") ~= ""
	end
	if slot.slotType == "monster" then
		return (slot.groupid or "") ~= ""
	end
	return (slot.classid or "") ~= ""
end

--Player-facing slot description, e.g. "Fire Damage",
--"Shadow: College of Black Ash", or "Undead Monsters".
--Class/subclass/monster-type names resolve from the lobby game's
--compendium tables.
local function SlotLabel(slot)
	if slot.slotType == "damage" then
		local damageType = slot.damageType or ""
		if damageType == "" then
			return "Any Damage"
		end
		return damageType:gsub("^%l", string.upper) .. " Damage"
	end

	if slot.slotType == "monster" then
		local group = (dmhub.GetTable("MonsterGroup") or {})[slot.groupid or ""]
		local groupName = "Unknown Monster Type"
		if group ~= nil then
			groupName = group:try_get("name", groupName)
		end
		return groupName .. " Monsters"
	end

	local classInfo = (dmhub.GetTable("classes") or {})[slot.classid or ""]
	local className = "Unknown Class"
	if classInfo ~= nil then
		className = classInfo:try_get("name", className)
	end
	if slot.subclassid ~= nil and slot.subclassid ~= "" then
		local sub = (dmhub.GetTable("subclasses") or {})[slot.subclassid]
		if sub ~= nil then
			return string.format("%s: %s", className, sub:try_get("name", "Subclass"))
		end
	end
	return className
end

--Player-facing explanation of when an activated slot's dice will roll -- the
--tooltip on the slot toggle buttons.
local function SlotDescription(slot, label)
	if slot.slotType == "damage" then
		return string.format("Roll these dice whenever your power roll deals %s.", label:lower())
	end
	if slot.slotType == "monster" then
		return string.format("Roll these dice when controlling %s.", label:lower())
	end
	return string.format("Roll these dice when playing a %s.", label)
end

--Copy-modify-set the slot-activation table; a slot key holds at most one dice
--set, so activating here replaces any other set previously activated for the
--same slot.
local function SetSlotActivation(key, assetid)
	local result = {}
	for k,v in pairs(dmhub.GetSettingValue("diceslotsequipped") or {}) do
		result[k] = v
	end
	result[key] = assetid
	dmhub.SetSettingValue("diceslotsequipped", result)
end

--The player's own custom slots for a dice set (the dicecustomslots setting;
--see ShowCustomUsesDialog). Returns a mutable deep copy; write back with
--SetCustomSlots.
local function GetCustomSlots(assetid)
	local all = dmhub.GetSettingValue("dicecustomslots") or {}
	local slots = all[assetid]
	if slots == nil then
		return {}
	end
	return DeepCopy(slots)
end

local function SetCustomSlots(assetid, slots)
	local result = {}
	for k,v in pairs(dmhub.GetSettingValue("dicecustomslots") or {}) do
		result[k] = v
	end
	if slots == nil or #slots == 0 then
		result[assetid] = nil
	else
		result[assetid] = DeepCopy(slots)
	end
	dmhub.SetSettingValue("dicecustomslots", result)
end

--Criteria option lists for the Add Uses dialog's dropdowns -- the same
--criteria the Dice Studio's Slots section offers (see DiceStudio.lua).
local function SlotDamageTypeOptions()
	local rulesGlobal = rawget(_G, "rules")
	local damageTypes = (rulesGlobal ~= nil and rulesGlobal.damageTypesAvailable) or {}
	local result = {}
	for _,damageType in ipairs(damageTypes) do
		result[#result+1] = { id = damageType, text = damageType }
	end
	return result
end

local function SlotClassOptions()
	local result = {}
	for k,classInfo in pairs(dmhub.GetTable("classes") or {}) do
		if (not classInfo:try_get("hidden", false)) and (not classInfo:try_get("isSubclass", false)) then
			result[#result+1] = { id = k, text = classInfo:try_get("name", "Unknown Class") }
		end
	end
	table.sort(result, function(a,b) return a.text < b.text end)
	return result
end

local function SlotSubclassOptions(classid)
	local result = {}
	for k,sub in pairs(dmhub.GetTable("subclasses") or {}) do
		if (not sub:try_get("hidden", false)) and sub:try_get("primaryClassId", "") == classid then
			result[#result+1] = { id = k, text = sub:try_get("name", "Unknown Subclass") }
		end
	end
	table.sort(result, function(a,b) return a.text < b.text end)
	table.insert(result, 1, { id = "", text = "(Any Subclass)" })
	return result
end

local function SlotMonsterGroupOptions()
	local result = {}
	for k,group in pairs(dmhub.GetTable("MonsterGroup") or {}) do
		if not group:try_get("hidden", false) then
			result[#result+1] = { id = k, text = group:try_get("name", "Unknown Monster Type") }
		end
	end
	table.sort(result, function(a,b) return a.text < b.text end)
	return result
end

local g_slotTypeOptions = {
	{ id = "damage", text = "Dealing Damage" },
	{ id = "class", text = "Playing Class" },
	{ id = "monster", text = "Playing Monster Type" },
}

--Cap on the custom slots a player can attach to one dice set.
local g_maxCustomSlots = 5

--The one open custom-uses dialog; opening another closes it first.
local g_customUsesDialog = nil

--The "Add Uses..." dialog: lets the player attach up to g_maxCustomSlots slot
--records of their own to a dice set they own, using the same criteria the Dice
--Studio's Slots section authors. Edits save immediately (dicecustomslots);
--closing the dialog auto-activates any complete uses that were added during
--this session, so they light up in the equip panel right away. Hosted as a
--self-contained floating overlay on the UI root (the titlescreen has no
--gamehud modal stack), styled after the shop's gold-bordered dialogs.
--args:
--  item     -- the shop item (dice) being configured
--  host     -- a live panel used to reach the UI root
--  changed  -- called when the dialog closes (rebuild the equip panel)
local function ShowCustomUsesDialog(args)
	local item = args.item

	if g_customUsesDialog ~= nil and g_customUsesDialog.valid then
		g_customUsesDialog:DestroySelf()
	end
	g_customUsesDialog = nil

	local m_slots = GetCustomSlots(item.assetid)

	--Keys already complete when the dialog opened; anything complete beyond
	--these at close time was added here and gets auto-activated.
	local m_openKeys = {}
	for _,slot in ipairs(m_slots) do
		if SlotIsComplete(slot) then
			m_openKeys[SlotKey(slot)] = true
		end
	end

	local resultPanel
	local rowsPanel
	local addRowPanel

	local function Save()
		SetCustomSlots(item.assetid, m_slots)
	end

	local function RefreshAll()
		rowsPanel:FireEvent("refreshUses")
		addRowPanel:FireEventTree("refreshUses")
	end

	local function Close()
		--Auto-activate the complete uses added during this dialog session.
		for _,slot in ipairs(m_slots) do
			if SlotIsComplete(slot) then
				local key = SlotKey(slot)
				if not m_openKeys[key] then
					SetSlotActivation(key, item.assetid)
				end
			end
		end
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel:DestroySelf()
		end
		g_customUsesDialog = nil
		if args.changed ~= nil then
			args.changed()
		end
	end

	--One editable use: slot-type dropdown + the type's criteria dropdown, with
	--a class's subclass picker on a second line (mirrors the Dice Studio rows),
	--and a delete button on the right.
	local function CreateRow(index, slot)
		local rowChildren = {}
		local subclassLine = nil

		--Slot type. Changing it resets the record to that type's blank shape.
		rowChildren[#rowChildren+1] = gui.Dropdown{
			width = 170,
			height = 30,
			fontSize = 14,
			options = g_slotTypeOptions,
			idChosen = slot.slotType,
			change = function(element)
				local cur = m_slots[index]
				if cur == nil or cur.slotType == element.idChosen then
					return
				end
				if element.idChosen == "damage" then
					m_slots[index] = { slotType = "damage", damageType = "" }
				elseif element.idChosen == "monster" then
					m_slots[index] = { slotType = "monster", groupid = "" }
				else
					m_slots[index] = { slotType = "class", classid = "" }
				end
				Save()
				RefreshAll()
			end,
		}

		if slot.slotType == "damage" then
			rowChildren[#rowChildren+1] = gui.Dropdown{
				width = 200,
				height = 30,
				fontSize = 14,
				hmargin = 8,
				textDefault = "Choose Damage Type...",
				options = SlotDamageTypeOptions(),
				idChosen = slot.damageType or "",
				change = function(element)
					local cur = m_slots[index]
					if cur == nil then
						return
					end
					cur.damageType = element.idChosen
					Save()
				end,
			}
		elseif slot.slotType == "monster" then
			rowChildren[#rowChildren+1] = gui.Dropdown{
				width = 200,
				height = 30,
				fontSize = 14,
				hmargin = 8,
				textDefault = "Choose Monster Type...",
				options = SlotMonsterGroupOptions(),
				idChosen = slot.groupid or "",
				change = function(element)
					local cur = m_slots[index]
					if cur == nil then
						return
					end
					cur.groupid = element.idChosen
					Save()
				end,
			}
		else
			rowChildren[#rowChildren+1] = gui.Dropdown{
				width = 200,
				height = 30,
				fontSize = 14,
				hmargin = 8,
				textDefault = "Choose Class...",
				options = SlotClassOptions(),
				idChosen = slot.classid or "",
				change = function(element)
					local cur = m_slots[index]
					if cur == nil then
						return
					end
					cur.classid = element.idChosen
					cur.subclassid = nil
					Save()
					--Rebuild so the subclass dropdown appears/refreshes.
					RefreshAll()
				end,
			}

			if slot.classid ~= nil and slot.classid ~= "" then
				local subclassOptions = SlotSubclassOptions(slot.classid)
				--Only offer a subclass picker when the class actually has
				--subclasses (the list always contains "(Any Subclass)").
				if #subclassOptions > 1 then
					subclassLine = gui.Panel{
						width = "100%",
						height = "auto",
						flow = "horizontal",
						vmargin = 2,
						--Align under the class dropdown (type dropdown width).
						lmargin = 178,

						gui.Dropdown{
							width = 200,
							height = 30,
							fontSize = 14,
							options = subclassOptions,
							idChosen = slot.subclassid or "",
							change = function(element)
								local cur = m_slots[index]
								if cur == nil then
									return
								end
								if element.idChosen == "" then
									cur.subclassid = nil
								else
									cur.subclassid = element.idChosen
								end
								Save()
							end,
						},
					}
				end
			end
		end

		--Delete: removes the use, deactivating it first if it was activated
		--for this set (an orphaned activation would keep skinning rolls).
		rowChildren[#rowChildren+1] = gui.Button{
			classes = {"deleteButton", "sizeS"},
			halign = "right",
			valign = "center",
			click = function(element)
				local cur = m_slots[index]
				if cur ~= nil and SlotIsComplete(cur) then
					local key = SlotKey(cur)
					local slotsEquipped = dmhub.GetSettingValue("diceslotsequipped") or {}
					if slotsEquipped[key] == item.assetid then
						SetSlotActivation(key, nil)
					end
					--Forget the open-time snapshot of this key so re-adding
					--the same use in this session counts as newly added.
					m_openKeys[key] = nil
				end
				table.remove(m_slots, index)
				Save()
				RefreshAll()
			end,
		}

		local firstLine = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			children = rowChildren,
		}

		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			vmargin = 4,
			children = { firstLine, subclassLine },
		}
	end

	--The uses list. Scoped ThemeEngine cascade so the dropdowns and delete
	--buttons pick up the theme's widget styling (the shop cascade has no
	--dropdown rules -- matches the Dropdown pattern in CodexTitlescreen.lua).
	rowsPanel = gui.Panel{
		styles = ThemeEngine.GetStyles(),
		width = "94%",
		height = "auto",
		maxHeight = 250,
		halign = "center",
		flow = "vertical",
		vscroll = true,
		vmargin = 8,

		create = function(element)
			element:FireEvent("refreshUses")
		end,
		refreshUses = function(element)
			local children = {}
			for i,slot in ipairs(m_slots) do
				children[#children+1] = CreateRow(i, slot)
			end
			if #children == 0 then
				children[#children+1] = gui.Label{
					width = "100%",
					height = "auto",
					halign = "center",
					textAlignment = "center",
					fontSize = 13,
					color = "#999999ff",
					vmargin = 12,
					text = "No custom uses yet. Press Add Use to create one.",
				}
			end
			element.children = children
		end,
	}

	--Add Use + count. The button collapses at the cap.
	addRowPanel = gui.Panel{
		width = "94%",
		height = "auto",
		halign = "center",
		flow = "horizontal",
		vmargin = 4,

		gui.Label{
			classes = {"itemButton"},
			width = 140,
			fontSize = 12,
			halign = "left",
			text = "Add Use",
			refreshUses = function(element)
				element:SetClass("collapsed", #m_slots >= g_maxCustomSlots)
			end,
			press = function(element)
				if #m_slots >= g_maxCustomSlots then
					return
				end
				m_slots[#m_slots+1] = { slotType = "damage", damageType = "" }
				Save()
				RefreshAll()
			end,
		},

		gui.Label{
			width = "auto",
			height = "auto",
			halign = "right",
			valign = "center",
			fontSize = 13,
			color = "#999999ff",
			refreshUses = function(element)
				element.text = string.format("%d/%d uses", #m_slots, g_maxCustomSlots)
			end,
		},

		create = function(element)
			element:FireEventTree("refreshUses")
		end,
	}

	resultPanel = gui.Panel{
		--Fullscreen dim backdrop; clicking it (or Escape, or Done) closes the
		--dialog and applies the auto-activations.
		floating = true,
		width = "100%",
		height = "100%",
		halign = "center",
		valign = "center",
		bgimage = "panels/square.png",
		bgcolor = "#000000aa",
		styles = shopStyles,
		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			Close()
		end,
		click = function(element)
			Close()
		end,

		--The dialog card, styled after the shop's gold-bordered dialogs. Its
		--empty click handler swallows clicks so only the backdrop closes.
		gui.Panel{
			width = 600,
			height = "auto",
			halign = "center",
			valign = "center",
			flow = "vertical",
			bgimage = "panels/square.png",
			bgcolor = "#0a0a0af2",
			cornerRadius = 16,
			borderWidth = 2,
			borderColor = "#f6ddb6",
			vpad = 16,
			borderBox = true,
			click = function(element)
			end,

			gui.Label{
				classes = {"shopTitle"},
				fontSize = 20,
				halign = "center",
				vmargin = 4,
				text = "Custom Uses",
			},

			gui.Label{
				width = "94%",
				height = "auto",
				halign = "center",
				textAlignment = "center",
				fontSize = 13,
				color = "#bbbbbbff",
				vmargin = 4,
				text = string.format("Add your own uses to %s. Activate a use and these dice roll for it automatically -- when dealing a damage type, playing a class, or controlling a monster type.", item.name),
			},

			rowsPanel,

			addRowPanel,

			gui.Label{
				classes = {"itemButton"},
				width = 152,
				halign = "center",
				vmargin = 8,
				text = "Done",
				press = function(element)
					Close()
				end,
			},
		},
	}

	local root = args.host.root
	if root == nil then
		return
	end
	root:AddChild(resultPanel)
	g_customUsesDialog = resultPanel
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
			{position = 0,    color = core.Color{r = 1, g = 1, b = 1, a = 0.92}},
			{position = 0.92, color = core.Color{r = 1, g = 1, b = 1, a = 0.92}},
			{position = 1,    color = core.Color{r = 1, g = 1, b = 1, a = 0}},
		},
	}

	--A "try dice" cage: an invisible, clickable/draggable panel that real 3D
	--preview dice rest on, plus an optional caption. Used twice below -- the
	--Draw Steel 2d10 power-roll pair and a single d6 -- as two INDEPENDENT
	--cages: each registers itself as a dice-preview panel and seeds its own
	--preview roll scoped to itself (previewPanel in dmhub.Roll; the engine's
	--multi-cage preview support), so rolling one leaves the other's resting
	--dice in place. All the engine calls are pcall-guarded so a Lua-only
	--reload against an older binary degrades gracefully rather than erroring.
	--cageArgs: x/width (wrapper placement in the action row), cageWidth (the
	--invisible hitbox), numDice/numFaces (the seeded roll), restScale
	--(optional resting-size multiplier for this cage's dice; hover/roll
	--sizes unaffected), label (optional caption under the dice).
	local MakeTryDiceCage = function(cageArgs)
		local captionLabel = nil
		if cageArgs.label ~= nil then
			captionLabel = gui.Label{
				text = cageArgs.label,
				floating = true,
				halign = "center",
				valign = "bottom",
				width = "auto",
				height = "auto",
				fontSize = 12,
				color = "#cfcfcf",
				vmargin = 4,
			}
		end

		--gui.DicePreview is a dedicated dice-preview cage panel type: the engine moved
		--SetAsDicePreviewPanel / the DicePreview* input methods / previewPanel roll-scoping
		--off the generic panel onto it, so the cage MUST be a DicePreview or none of the
		--dice-preview calls below take effect (the resting dice would fall to the default
		--bottom-of-screen preview spot and be uninteractable). Fall back to a plain gui.Panel
		--on an older binary (Lua-only reload) that predates it; the field/method calls below
		--are already pcall-guarded so they no-op on the fallback. (gui is engine userdata, so
		--index via pcall rather than rawget.)
		local diceCageCtor = gui.Panel
		pcall(function() diceCageCtor = gui.DicePreview or gui.Panel end)

		return gui.Panel{
			classes = {"collapseOnGift"},
			floating = true,
			halign = "left",
			valign = "center",
			x = cageArgs.x,
			width = cageArgs.width,
			height = 96,
			flow = "vertical",

			diceCageCtor{
				classes = {"shopTryDie"},
				bgimage = true,
				bgcolor = "white",
				--Oversized invisible cage: the dice render over it and anchor to its
				--world centre, so a bigger panel just widens the click/drag hitbox
				--(easier to grab the spread-out dice) without moving the dice.
				width = cageArgs.cageWidth,
				height = 108,
				halign = "center",
				--The resting dice anchor to this panel's world centre, so centre the
				--panel in the column and lift it slightly (negative y = up) so the dice
				--sit above the caption label instead of covering it.
				valign = "center",
				y = -16,
				floating = true,
				draggable = true,
				dragMove = false,
				data = { item = nil, reseedPending = false, visible = false },

				--Invisible-but-interactable cage, like the Timeline roll dialog's
				--dice panel (EmbeddedRollDialog): a real 3D die renders over it.
				--Hover wobble + click/drag-to-roll are routed through the panel-scoped
				--DicePreview* methods so they only touch THIS cage's dice.
				styles = {
					gui.Style{ opacity = 0 },
				},

				--Register as a dice-preview cage so resting dice anchor here and
				--chat typing can't clear them. SetPreviewRollScreenBounds(true) lets the
				--thrown dice roll out to the real screen edges instead of a tight box
				--(the C# SimUpdate opts out of the panel cage while this is set), so a
				--click or drag both produce a normal full-screen roll. The screen-bounds
				--flag, dice spacing and preview model are globals shared by both cages;
				--setting/clearing them twice is harmless. All of it is torn down on
				--destroy so nothing leaks into in-game rolls once the shop closes.
				create = function(element)
					pcall(function() dice.SetPreviewRollScreenBounds(true) end)
					pcall(function() element:SetAsDicePreviewPanel(true) end)
					--Pull a pair of try-dice a little closer together than the default
					--embedded spacing. Tunable: lower = closer, 1 = default.
					pcall(function() dice.SetPreviewDiceSpacing(0.78) end)
					--Pick up + drag lifts the die a little; a gentle release (no hurl) then
					--drops it from that altitude so it falls and lands with an impact instead
					--of just snapping back to rest. A quick flick still tosses a full roll.
					pcall(function() element.dicePreviewLiftDrop = true end)
					--Per-cage resting-size tuning; hover/roll sizes are unaffected,
					--so a shrunk cage still pops to the normal size on mouseover.
					if cageArgs.restScale ~= nil then
						pcall(function() element.dicePreviewRestScale = cageArgs.restScale end)
					end
				end,
				destroy = function(element)
					pcall(function() element:CancelDicePreviewRoll() end)
					pcall(function() element:SetAsDicePreviewPanel(false) end)
					pcall(function() dice.SetPreviewRollScreenBounds(false) end)
					pcall(function() dice.SetPreviewDiceSpacing(1.0) end)
					pcall(function() dice.SetRollPreviewModel("") end)
				end,

				--The reused details panel toggles visibility via show/hideProductDetails
				--(it is not destroyed between items), so track visibility ourselves and
				--seed/clear the resting dice as it is shown/hidden -- otherwise a hidden
				--panel leaves a die floating on screen, and a scheduled re-seed that lands
				--after the panel hides would spawn one onto nothing.
				--Non-Dice items get refreshItem too: the showcase panel above only
				--sets "collapsed" on itself, and refreshItem is fired down the whole
				--tree (collapsed or not) before that even runs. Collapsing hides the
				--cage's UI but NOT the resting preview dice -- those are real 3D
				--objects anchored to the cage, so seeding here would leave dice
				--sitting on a non-dice item's page. Treat a non-Dice item exactly
				--like the panel being hidden.
				refreshItem = function(element, item)
					if item == nil or item.itemType ~= "Dice" then
						element:FireEvent("hideProductDetails")
						return
					end
					element.data.item = item
					element.data.visible = true
					element:FireEvent("seedTryDie")
				end,

				hideProductDetails = function(element)
					element.data.visible = false
					element.data.reseedPending = false
					pcall(function() element:CancelDicePreviewRoll() end)
				end,

				--Spawn this cage's resting dice in the previewed set. preview = true
				--(handled in dmhub.Roll) seeds the dice at rest on this panel
				--(previewPanel scopes the seed and the armed roll to this cage) so a
				--click or drag executes this same local/silent roll. When it finishes --
				--or a too-weak drag cancels it -- we re-seed shortly after so fresh dice
				--are always sitting here.
				seedTryDie = function(element)
					if not element.valid or not element.data.visible then
						return
					end
					element.data.reseedPending = false
					local item = element.data.item
					if item == nil then
						return
					end
					--Clear any existing resting dice first so the freshly seeded dice always
					--pick up the current item's set/material: UpdatePreview retains a
					--same-size die and would otherwise keep the previous item's look.
					pcall(function() element:CancelDicePreviewRoll() end)
					pcall(function() dice.SetRollPreviewModel(item.assetid) end)
					dmhub.Roll{
						preview = true, ["local"] = true, silent = true,
						previewPanel = element,
						numDice = cageArgs.numDice, numFaces = cageArgs.numFaces, numKeep = 0, description = "Try Dice",
						complete = function()
							--The seeded preview roll only executes when the user clicks
							--or drags the cage, so a completion here is a real try-roll
							--(cancel covers the too-weak-drag and teardown paths).
							analytics.Event{
								type = "shopTryDiceRoll",
								itemid = item.id,
								dice = string.format("%dd%d", cageArgs.numDice, cageArgs.numFaces),
							}
							if element.valid then element:FireEvent("requestReseed") end
						end,
						cancel = function()
							if element.valid then element:FireEvent("requestReseed") end
						end,
					}
				end,

				requestReseed = function(element)
					if not element.valid or element.data.reseedPending then
						return
					end
					element.data.reseedPending = true
					element:ScheduleEvent("seedTryDie", 0.6)
				end,

				--Hover wobble + click/drag-to-roll on this cage's resting dice.
				hover = function(element)
					pcall(function() element:DicePreviewMouseEnter() end)
				end,
				dehover = function(element)
					pcall(function() element:DicePreviewMouseLeave() end)
				end,
				click = function(element)
					pcall(function() element:DicePreviewClick() end)
				end,
				dragging = function(element)
					pcall(function() element:DicePreviewDragThink() end)
				end,
				drag = function(element)
					pcall(function() element:DicePreviewDragEnd() end)
				end,
			},

			captionLabel,
		}
	end

	return gui.Panel{
		classes = {"shopDetailsMainPanel"},

		bgimage = "panels/square.png",
		--Match the shop item cards' grey (shopbg.png fill is #252525) at ~0.92
		--opacity (supplied by detailsBackingGradient's alpha), so the details
		--panel reads as the same semi-transparent grey as the item grid.
		bgcolor = "#252525ff",
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

			--Action row under the banner: a roll-the-dice control on the left;
			--on the right, Add to Cart (store view) or the dice equip panel
			--(inventory view). Sized to the banner width so the two ends line up
			--with the banner's edges. The cages and Add to Cart float; the equip
			--panel is the row's one flowed child, so the row grows to fit it in
			--the inventory view and falls back to the cages' height otherwise.
			gui.Panel{
				width = g_bannerDisplayWidth,
				height = "auto",
				minHeight = 96,
				halign = "center",
				--Top margin only: the row keeps its gap to the banner above but
				--sits flush against the bottom of the showcase column.
				tmargin = 12,

				styles = {
					{ selectors = {"shopTryDie"}, transitionTime = 0.1 },
					{ selectors = {"shopTryDie", "hover"}, scale = 1.15, brightness = 1.25 },
				},

				--Roll the dice you're previewing: click to roll, or drag off to
				--throw, mirroring the action-bar Dice panel. Rolls use the
				--previewed set (see showProductDetails above). Two independent
				--cages built by MakeTryDiceCage above: the Draw Steel 2d10
				--power-roll pair, and a single d6 to its right.
				MakeTryDiceCage{
					x = 24,
					width = 140,
					cageWidth = 170,
					numDice = 2,
					numFaces = 10,
					--The d10 pair reads slightly large next to the d6 at the shared
					--rest size; sit them 5% smaller (hover still pops to full size).
					restScale = 0.95,
					label = "Drag to roll dice",
				},

				MakeTryDiceCage{
					x = 240,
					width = 100,
					cageWidth = 110,
					numDice = 1,
					numFaces = 6,
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
							analytics.Event{ type = "shopAddCart", itemid = item.id }
						end
					end,
				},

				--Equip panel (inventory only), filling the right side of the action
				--row beside the try-dice cages rather than adding a row of vertical
				--space below them. Dice equip into a multi-part loadout rather than
				--one monolithic choice. Three columns, each a LIVE spinning
				--render of the real 3D die currently equipped in that slot (a pooled
				--"#DicePreview:<set>:<seq>:<scale>:<spin>:<faces>" scene -- see
				--DiceSetPreviewManager; the faces segment picks the d10/d6 geometry)
				--above a button that equips the viewed set there:
				--  1st Power Die -- the diceequipped setting: the default set, used for
				--                   everything another slot doesn't override, including
				--                   the first d10 of a power roll (today's behavior).
				--  2nd Power Die -- diceequipped2: rolls with multiple d10s alternate
				--                   between the two power-die slots.
				--  D3/D6         -- diceequippedd6: d6- and d3-shaped dice.
				--Pressing a button puts the viewed set in that slot (pressing again
				--clears the slot back to the default); the icon above swaps to the new
				--die. Beneath the columns a central "Equip for All Dice" button equips
				--the viewed set as the default and clears the other slots so every die
				--uses it.
				--To the right of the equip columns, one toggle button per slot authored
				--on the dice set (Dice Studio Slots section): activating a slot binds
				--this set to that purpose (e.g. dealing fire damage, playing a Shadow,
				--controlling an Undead monster) instead of equipping it always.
				--Activations are stored in the diceslotsequipped setting keyed by slot
				--(so a slot holds one dice set); the roll dialog consumes them, picking
				--the most specific activated slot matching the roll (see
				--EmbeddedRollDialog's slot-dice resolution).
				--Layout: the panel flows horizontally -- the equip block sits on the
				--left and the slot column (when the set has slots) on its right, so
				--the whole panel stays pinned to the action row's right edge.
				gui.Panel{
					classes = {"collapsedUnlessInventory"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					halign = "right",
					valign = "top",
					rmargin = 24,
					vmargin = 8,
					data = { item = nil },

					showProductDetails = function(element, item)
						element.data.item = item
						element:SetClass("collapsed", item.itemType ~= "Dice")
						element:FireEvent("rebuildEquip")
					end,

					rebuildEquip = function(element)
						local item = element.data.item
						if item == nil or item.itemType ~= "Dice" then
							element.children = {}
							return
						end

						local function Rebuild()
							element:FireEvent("rebuildEquip")
						end

						local function MakeEquipButton(args)
							local classes = {"itemButton"}
							if args.equipped then
								classes[#classes+1] = "equipped"
							end
							return gui.Label{
								classes = classes,
								text = args.text,
								width = args.width,
								fontSize = args.fontSize,
								halign = "center",
								hmargin = 8,
								linger = function(el)
									gui.Tooltip{
										text = args.tooltip,
										halign = "center",
										valign = "top",
									}(el)
								end,
								press = function(el)
									args.click()
									Rebuild()
								end,
							}
						end

						--SlotKey/SlotLabel/SlotDescription/SetSlotActivation and the
						--custom-uses accessors are file-scope helpers shared with the
						--Add Uses... dialog (see ShowCustomUsesDialog above).

						local children = {}

						local equippedDefault = dmhub.GetSettingValue("diceequipped")
						local equipped2 = dmhub.GetSettingValue("diceequipped2")
						local equippedD6 = dmhub.GetSettingValue("diceequippedd6")

						--One column per die slot: a live spinning render of the die
						--currently equipped there, above the button that equips the
						--viewed set. args = { faces = 10|6, seq, text, slotSet, tooltip,
						--click }. seq is a stable per-slot tag so rebuilds after an equip
						--click re-attach to the same pooled scene (same key) instead of
						--spinning up a fresh one; changing the slot's set changes the key,
						--which naturally builds the new die and evicts the old.
						--Sized slightly down (80px dice, 140px buttons) so the slot
						--column beside the equip block still fits the action row.
						local function MakeSlotColumn(args)
							--The die previewed for this slot: the slot's own set, falling
							--back to the default set for empty slots (that is what rolls).
							local previewSet = args.slotSet
							if previewSet == nil or previewSet == "" then
								previewSet = equippedDefault
								if previewSet == nil or previewSet == "" then
									previewSet = "Default"
								end
							end

							return gui.Panel{
								flow = "vertical",
								width = "auto",
								height = "auto",
								halign = "center",
								hmargin = 8,

								--Live 3D die of the equipped set (pooled preview scene; the
								--same mechanism as the shop tiles' spinning dice). The RT is
								--premultiplied with reconstructed alpha, like the tile die
								--layers. The trailing segments are dice scale, spin-axis
								--angle, and the die geometry; an engine build that predates
								--the faces segment ignores it and shows a d10.
								gui.Panel{
									interactable = false,
									bgimage = string.format("#DicePreview:%s:%s:%.2f:%.2f:%d",
										tostring(previewSet), args.seq, 3.0, 0, args.faces),
									bgcolor = "white",
									blend = "premultiplied",
									width = 80,
									height = 80,
									halign = "center",
								},

								MakeEquipButton{
									text = args.text,
									width = 140,
									equipped = item.assetid == args.slotSet,
									tooltip = args.tooltip,
									click = args.click,
								},
							}
						end

						--The equip block: the three die columns with the equip-for-all
						--button beneath them. Fills the panel's left side; the slot
						--column (below) sits to its right.
						local equipBlockChildren = {}

						equipBlockChildren[#equipBlockChildren+1] = gui.Panel{
							flow = "horizontal",
							width = "auto",
							height = "auto",
							halign = "center",

							MakeSlotColumn{
								faces = 10,
								seq = "equipslot1",
								text = "1st Power Die",
								slotSet = equippedDefault,
								tooltip = cond(item.assetid == equippedDefault,
									"Your default dice: the first d10 of your power rolls, and every die another slot does not override. Click to revert to the standard dice.",
									"Use this set as your default dice: the first d10 of your power rolls, and every die another slot does not override."),
								click = function()
									dmhub.SetSettingValue("diceequipped", cond(item.assetid == equippedDefault, "Default", item.assetid))
								end,
							},

							MakeSlotColumn{
								faces = 10,
								seq = "equipslot2",
								text = "2nd Power Die",
								slotSet = equipped2,
								tooltip = cond(item.assetid == equipped2,
									"Your second d10: rolls with multiple d10s alternate between your 1st and 2nd power dice. Click to use your default set for every d10.",
									"Rolls with multiple d10s -- like your power rolls -- will alternate between your default set and this one."),
								click = function()
									dmhub.SetSettingValue("diceequipped2", cond(item.assetid == equipped2, "", item.assetid))
								end,
							},

							MakeSlotColumn{
								faces = 6,
								seq = "equipslotd6",
								text = "D3/D6",
								slotSet = equippedD6,
								tooltip = cond(item.assetid == equippedD6,
									"Your d3/d6 dice. Click to use your default set for these rolls.",
									"Use this set whenever you roll a d3 or a d6."),
								click = function()
									dmhub.SetSettingValue("diceequippedd6", cond(item.assetid == equippedD6, "", item.assetid))
								end,
							},
						}

						--Central equip-for-all: the viewed set becomes the default and the
						--other slots clear, so every die uses it.
						equipBlockChildren[#equipBlockChildren+1] = MakeEquipButton{
							text = "Equip for All Dice",
							width = 240,
							equipped = item.assetid == equippedDefault and (equipped2 == nil or equipped2 == "") and (equippedD6 == nil or equippedD6 == ""),
							tooltip = "Equip this set for all of your dice.",
							click = function()
								dmhub.SetSettingValue("diceequipped", item.assetid)
								dmhub.SetSettingValue("diceequipped2", "")
								dmhub.SetSettingValue("diceequippedd6", "")
							end,
						}

						children[#children+1] = gui.Panel{
							flow = "vertical",
							width = "auto",
							height = "auto",
							halign = "left",
							valign = "top",
							children = equipBlockChildren,
						}

						--Slot activations: the set's authored slots plus the player's own
						--custom "uses" (added via the Add Uses... dialog), deduped by
						--key, as a column of toggle buttons to the right of the equip
						--block. A gold (equipped-style) button means the slot is active
						--for this set; clicking toggles it. The column always shows for
						--owned dice -- the Add Uses... entry point lives at its foot even
						--when the set has no slots yet. pcall: dice.GetDiceSlots needs an
						--engine build that has it.
						local authoredSlots = nil
						pcall(function() authoredSlots = dice.GetDiceSlots(item.assetid) end)

						local displaySlots = {}
						local seenKeys = {}
						for _,slot in ipairs(authoredSlots or {}) do
							local key = SlotKey(slot)
							if SlotIsComplete(slot) and not seenKeys[key] then
								seenKeys[key] = true
								displaySlots[#displaySlots+1] = { slot = slot, custom = false }
							end
						end
						for _,slot in ipairs(GetCustomSlots(item.assetid)) do
							local key = SlotKey(slot)
							if SlotIsComplete(slot) and not seenKeys[key] then
								seenKeys[key] = true
								displaySlots[#displaySlots+1] = { slot = slot, custom = true }
							end
						end

						local slotsEquipped = dmhub.GetSettingValue("diceslotsequipped") or {}

						local slotChildren = {}

						if #displaySlots > 0 then
							slotChildren[#slotChildren+1] = gui.Label{
								text = "Or activate this set for...",
								width = "auto",
								height = "auto",
								halign = "center",
								fontSize = 12,
								color = "#cfcfcf",
								vmargin = 4,
							}

							local slotButtons = {}
							for _,entry in ipairs(displaySlots) do
								local slot = entry.slot
								local key = SlotKey(slot)
								local label = SlotLabel(slot)
								local active = slotsEquipped[key] == item.assetid
								local description = SlotDescription(slot, label)
								if entry.custom then
									description = description .. "\n\nA custom use you added (manage in Add Uses...)."
								end
								slotButtons[#slotButtons+1] = MakeEquipButton{
									text = label,
									width = 210,
									fontSize = 12,
									equipped = active,
									tooltip = cond(active,
										description .. "\n\nThis set is activated. Click to deactivate.",
										description .. "\n\nClick to activate this set for this purpose."),
									click = function()
										SetSlotActivation(key, cond(active, nil, item.assetid))
									end,
								}
							end

							--Scroll region: dice with many slots scroll here rather
							--than stretching the action row (width leaves room for
							--the scrollbar beside the 210px buttons).
							slotChildren[#slotChildren+1] = gui.Panel{
								flow = "vertical",
								width = 234,
								height = "auto",
								maxHeight = 168,
								halign = "center",
								vscroll = true,
								children = slotButtons,
							}
						end

						--Add Uses...: opens the custom-uses dialog for this set.
						slotChildren[#slotChildren+1] = MakeEquipButton{
							text = "Add Uses...",
							width = 210,
							fontSize = 12,
							tooltip = "Add your own uses to this set -- damage types, classes, or monster types these dice should roll for.",
							click = function()
								ShowCustomUsesDialog{
									item = item,
									host = element,
									changed = function()
										if element.valid then
											element:FireEvent("rebuildEquip")
										end
									end,
								}
							end,
						}

						children[#children+1] = gui.Panel{
							flow = "vertical",
							width = "auto",
							height = "auto",
							halign = "left",
							valign = "top",
							lmargin = 16,
							children = slotChildren,
						}

						element.children = children
					end,
				},

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
		--Floated at the top of the (full-height) main lower panel that hosts it.
		--The lower panel starts right under the "Store" header (the featured
		--banner and the inventory/artist headers above it all collapse in the
		--details view), so top-aligning here puts the showcase banner the same
		--distance below the header as the products page's featured banner --
		--rather than centering it in the screen and leaving a large gap.
		floating = true,
		halign = "center",
		valign = "top",

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

--Builds one row displaying a gift code the user owns: item name, purchase
--date, redemption status, and the code itself (press to copy). Used by both
--the Gift Codes inventory tab and the Redeem a Gift Code screen.
local MakeCouponRow = function(coupon)
	local item = assets.shopItems[coupon.itemid]
	local itemName = "(Unknown item)"
	if item ~= nil then
		itemName = item.name
	end

	return gui.Panel{
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
	}
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
		if ItemVisibleInShop(shopItem) then
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
						if pageSelected < NumPages() and footerPanels[pageSelected+1] ~= nil then
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

					--searches always reset to showing page 1, so keep the
					--selection state in sync with that.
					element:SetClass("selected", i == 1)
					pageSelected = 1
				end,
			}
		end

		local m_linkEventHandlerId = nil

		--First-open loading cover (see TrackCoverImage at the top of the
		--file). The full shop UI is built immediately underneath -- which is
		--what kicks off all the image downloads and warms the dice preview
		--scenes -- while the cover shows the plain store background + loading
		--indicator on top. Once every tracked image from the initial page has
		--reported in (or after g_shopCoverMaxTime), the cover fades away,
		--revealing a fully-formed page instead of a wall of loading panels.
		local m_coverPending = 0
		local m_coverArmed = false
		local m_coverRevealed = false

		local coverPanel
		coverPanel = gui.Panel{
			id = "shopLoadingCover",
			floating = true,
			width = "100%",
			height = "100%",
			halign = "center",
			valign = "top",
			bgimage = StoreBackgroundImage(),
			bgcolor = StoreBackgroundColor(),

			styles = {
				{
					selectors = {"fadeout"},
					opacity = 0,
					transitionTime = g_shopCoverFadeTime,
				},
			},

			gui.CloseButton{
				floating = true,
				halign = "left",
				valign = "top",

				click = function(element)
					element:FireEventOnParents("closeShop")
				end,
			},

			create = function(element)
				--Tracked panels register themselves during their own create
				--events; arm the balance check just after that settles. If
				--everything was already cached the cover clears here, only a
				--couple tenths of a second after opening.
				element:ScheduleEvent("armReveal", 0.15)
				element:ScheduleEvent("revealShop", g_shopCoverMaxTime)
			end,

			armReveal = function(element)
				m_coverArmed = true
				if m_coverPending <= 0 then
					element:FireEvent("revealShop")
				end
			end,

			revealShop = function(element)
				if m_coverRevealed then
					return
				end
				m_coverRevealed = true
				--opacity does not cascade to children, so drop the loading
				--indicator/close button outright and fade just the backdrop.
				element.children = {}
				element:SetClass("fadeout", true)
				element:ScheduleEvent("dieCover", g_shopCoverFadeTime + 0.1)
			end,

			dieCover = function(element)
				element:DestroySelf()
			end,
		}

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
							element:FireEvent("showItemDetails", item, "bundleLink")
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

			--First-open cover bookkeeping: tracked image panels (TrackCoverImage)
			--report in as they are created and as their images load. After the
			--reveal these events keep arriving from page flips, the details
			--view and carousel switches, and are simply ignored.
			shopImagePending = function(element)
				if not m_coverRevealed then
					m_coverPending = m_coverPending + 1
				end
			end,

			shopImageReady = function(element)
				if m_coverRevealed then
					return
				end
				m_coverPending = m_coverPending - 1
				if m_coverArmed and m_coverPending <= 0 then
					coverPanel:FireEvent("revealShop")
				end
			end,

			showItemDetails = function(element, item, source)
				element:FireEventTree("hideProducts")
				element:FireEventTree("showProductDetails", item)
				element:FireEventTree("refreshCart", m_shoppingCart)

				--Funnel attribution: which surface brought the user to this
				--product page -- "featuredBanner" (top banner's View Dice),
				--"productTile" (grid cards below), "cartRow", or "bundleLink".
				--nil = a re-fire from inside the already-open details view
				--(gallery presses), which is not a navigation, so not counted.
				if source ~= nil then
					analytics.Event{
						type = "shopViewItem",
						source = source,
						itemid = item.id,
						itemType = item.itemType,
					}
				end
			end,

			showProductsPage = function(element)
				element:FireEventTree("showProducts")
				element:FireEventTree("hideProductDetails")

				--Returning to the main store grid (Go Back from details, leaving
				--the cart, artist focus, searching). The deduplicate window
				--collapses programmatic bursts -- e.g. the search box re-fires
				--this on every text change -- into a single event.
				analytics.Event{
					type = "shopShowProducts",
					deduplicate = 2,
				}
			end,

			addToCart = function(element, item)
				m_shoppingCart[item.id] = true

				--Adding an item the user already owns is only meaningful as a
				--gift (the buttons read "Add as Gift" in that case), so force
				--gift mode on rather than letting checkout buy a duplicate.
				if shop:ItemInInventory(item.id) then
					local giftButton = element:Get("giftButton")
					if giftButton ~= nil and not giftButton:HasClass("checkoutButton") then
						giftButton:SetClass("checkoutButton", true)
						giftButton.parent:FireEventTree("refreshGift", true)
					end
				end

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
				bgimage = StoreBackgroundImage(),
				bgcolor = StoreBackgroundColor(),
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

					--Main shop page header, above the featured dice banner. Same
					--shopTitle/shopDescription styling as the inventory header
					--below; carries the dice banner's collapse classes so it
					--shows in lockstep with it (main shop page only -- hidden on
					--cart, inventory, artist focus, and coupon redemption).
					gui.Panel{
						classes = {"collapseOnCart", "collapsedWhenInventory", "collapsedWhenArtistFocus", "collapsedWhenRedeeming"},
						halign = "center",
						flow = "vertical",
						width = "auto",
						height = "auto",
						gui.Label{
							classes = {"shopTitle"},
							text = "Store",
						},

						gui.Label{
							classes = {"shopDescription"},
							text = "Find the perfect item for you.",
						},
					},

					MakeDiceBanner{ spinnable = true },


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

						setArtist = function(element, artistid)
							local artist = nil
							if artistid ~= nil then
								artist = assets.artists[artistid]
							end

							element:SetClass("collapsed", artist == nil)
							if artist ~= nil then
								--A fresh child per image: re-setting bgimage on a
								--live panel shows the old sprite (the white square
								--placeholder) while the banner downloads; a new
								--panel stays invisible until the art is ready and
								--then fades in.
								element.children = {
									gui.Panel(TrackCoverImage({
										interactable = false,
										bgimage = artist.bannerImage,
										bgcolor = "white",
										width = "100%",
										height = "100%",
									}, true)),
								}
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
                            {
                                --REMOVED FOR NOW, COLLAPSED UNTIL WE NEED CATEGORIES
                                collapsed = 1,
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

						--Programmatically select the Gift Codes tab -- used after a
						--gift purchase so the user lands on their new codes.
						showGiftCodes = function(element)
							local codesPanel = element.data.panels["codes"]
							if codesPanel ~= nil then
								codesPanel:FireEvent("press")
							end
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
							},

							--The user's own purchased gift codes, listed here so codes
							--remain findable (and their redemption status checkable)
							--after the one-time post-purchase display.
							gui.Panel{
								width = "100%",
								height = "auto",
								flow = "vertical",
								halign = "center",

								create = function(element)
									local header = gui.Label{
										classes = {"collapsed"},
										text = "Your Gift Codes",
										fontWeight = "bold",
										halign = "center",
										fontSize = 24,
										width = "auto",
										vmargin = 30,
									}

									local rowsPanel = gui.Panel{
										width = "100%",
										height = "auto",
										flow = "vertical",
										halign = "center",
									}

									element.children = {header, rowsPanel}

									--The header stays collapsed until a code actually
									--arrives, so users with no codes see nothing extra.
									shop:RetrieveGiftCodes(function(coupon)
										header:SetClass("collapsed", false)
										rowsPanel:AddChild(MakeCouponRow(coupon))

										local children = rowsPanel.children
										table.sort(children, function(a,b) return b.data.ord < a.data.ord end)
										rowsPanel.children = children
									end,
									function(error)
										header:SetClass("collapsed", false)
										rowsPanel:AddChild(gui.Label{
											classes = {"couponInventoryLabel"},
											data = { ord = 0 },
											width = "100%",
											height = "auto",
											color = "red",
											text = string.format("Error: %s", error),
										})
									end,
									function(allCoupons)
									end)
								end,

								--After redeeming a code in this screen, rebuild the list
								--so the redeemed code's status updates.
								redeemed = function(element)
									element:FireEvent("create")
								end,
							},
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
							element:AddChild(MakeCouponRow(coupon))

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

				--Search bar row: occupies the gap between the featured banner and
				--the product grid, right-aligned so the search box's right edge
				--lines up with the banner's right edge. Hidden (keeping the gap)
				--while viewing the cart; fully collapsed while viewing a single
				--product's details, so the lower panel really does start right
				--under the "Store" header and the details showcase banner sits
				--the same distance below it as the featured banner does.
				--The gap below the box is provided by the grid row's own 30px
				--vmargin minus the 8px the card frame art rises above the items
				--(22px effective); the -11 bmargin pulls the grid up to make it
				--~11px, matching the 11px tmargin so spacing is even on both
				--sides. The featured-carousel dots float into this row's band at
				--the banner's left edge (see the dots panel in MakeDiceBanner).
				gui.Panel{
					width = g_bannerDisplayWidth,
					height = "auto",
					halign = "center",
					tmargin = 11,
					bmargin = -11,

					styles = {
						{
							selectors = {"showingCart"},
							hidden = 1,
						},
						{
							selectors = {"viewingItem"},
							collapsed = 1,
						},
						{
							selectors = {"redeemingCoupon"},
							hidden = 1,
						},
					},

					showProductDetails = function(element)
						element:SetClass("viewingItem", true)
					end,

					showProducts = function(element)
						element:SetClass("viewingItem", false)
					end,

					gui.Input{
						placeholderText = "Search",
						halign = "right",
						editlag = 0.2,
						--Wipe the typed text without re-running the search; the
						--caller resets the results itself (see the redeem toggle).
						clearSearch = function(element)
							element.text = ""
						end,
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

							--Gift purchases always mint a redeemable gift code per item
							--at checkout (see the gift branch of the Buy with Steam
							--handler); there is no recipient to pick here.
							gui.Panel{
								classes = {"collapsed"},
								flow = "vertical",
								width = "auto",
								height = "auto",
								halign = "center",
								refreshGift = function(element, val)
									element:SetClass("collapsed", not val)
								end,

								gui.Label{
									classes = {"shopDescription"},
									text = "You will get a gift code to send",

									--One code is minted per item in the cart, so the
									--message pluralizes with the cart contents.
									refreshCart = function(element, shoppingCart)
										local nitems = 0
										for _ in pairs(shoppingCart) do
											nitems = nitems + 1
										end

										if nitems > 1 then
											element.text = string.format("You will get %d gift codes to send, one for each item", nitems)
										else
											element.text = "You will get a gift code to send"
										end
									end,
								},
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
							vmargin = 30,


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

									--Gift mode is the giftButton toggle above the cart. A
									--gift purchase mints one redeemable gift code per item
									--instead of granting the items to this account.
									local giftButton = element:Get("giftButton")
									local giftPurchase = giftButton ~= nil and giftButton:HasClass("checkoutButton")

									analytics.Event{
										type = "shopCheckoutSteam",
										gift = giftPurchase,
									}

									element.data.purchasing = true
									element.text = "Confirm in Steam..."

									local function onSuccess(instanceids, giftcodes)
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

										--Gift mode is spent; clear the toggle so the next
										--cart doesn't silently stay in gift mode.
										if giftButton ~= nil and giftButton.valid then
											giftButton:SetClass("checkoutButton", false)
											giftButton.parent:FireEventTree("refreshGift", false)
										end

										--Close the cart panel first (showInventory only
										--switches the title/content mode; it doesn't
										--collapse the cart on its own), then transition
										--to Inventory so the user sees their newly-
										--granted item. Gift purchases land on the Gift
										--Codes view instead, where the new codes are.
										element:FireEventOnParents("hideCart")
										resultPanel:FireEvent("showInventory")

										if giftPurchase then
											resultPanel:FireEventTree("showGiftCodes")

											--The codes list reads accountInventory.coupons,
											--which arrives over the /Patrons monitor and can
											--lag the purchase by a moment; refresh the list
											--again once the write has had time to propagate.
											dmhub.Schedule(2, function()
												if mod.unloaded then return end
												if resultPanel == nil or not resultPanel.valid then return end
												if resultPanel:HasClass("showingCouponInventory") then
													resultPanel:FireEventTree("showcoupons")
												end
											end)
										end
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
											if giftPurchase then
												local fakeCodes = {}
												for _ in ipairs(itemids) do
													fakeCodes[#fakeCodes+1] = dmhub.GenerateGuid()
												end
												onSuccess({}, fakeCodes)
											else
												onSuccess(itemids)
											end
										end)
										return
									end

									--Fail safe: if the engine build predates gift support,
									--the options argument would be silently dropped and the
									--purchase granted to this account -- the exact self-grant
									--bug gift mode exists to fix. Older builds error on the
									--property read, hence the pcall.
									if giftPurchase then
										local supportsGifts = false
										pcall(function() supportsGifts = shop.supportsGiftPurchases == true end)
										if not supportsGifts then
											onFailure(tr("Gift purchases require an updated version of the app."))
											return
										end
									end

									shop:BuyItemsWithSteam(itemids, onSuccess, onFailure, {gift = giftPurchase})
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

						gui.Divider{
							classes = {"collapseOnCart"},
							height = 3,
							opacity = 0.4,
							tmargin = 2,
							bmargin = 20,
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

			--shopping cart etc. "Redeem a Gift Code" rides in the same top-right
			--cluster, to the left of the cart icon. collapseOnNoCommerce lives on
			--the cart group only (not the whole cluster) so redeeming codes stays
			--available when the commerce UI is hidden.
			--vmargin centers the 32px row on the close button's line (the X is
			--24px at margin 6, center y 18, so 18 - 32/2 = 2).
			gui.Panel{
				floating = true,
				halign = "right",
				valign = "top",
				hmargin = 10,
				vmargin = 2,
				width = "auto",
				height = "auto",
				flow = "horizontal",

				--redeem code.
				gui.Label{
					bgcolor = "clear",
					width = "auto",
					height = "auto",
					fontSize = 18,
					valign = "center",
					rmargin = 16,
					text = "Redeem a Gift Code",
					fontWeight = "regular",

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

							--Entering redeem mode resets any in-progress search so
							--the full grid is back when the user returns to it.
							resultPanel:FireEventTree("clearSearch")
							ExecuteSearch("")
						end
					end,
				},

				--Divider between the redeem link and the cart group. It only
				--separates the two when the cart group is shown, so it collapses
				--along with it.
				gui.Panel{
					classes = {"collapseOnNoCommerce"},
					bgimage = "panels/square.png",
					bgcolor = "white",
					opacity = 0.4,
					width = 2,
					height = 24,
					valign = "center",
					rmargin = 16,
				},

				--"View Cart" + cart icon + item count: one clickable unit. The
				--press handler lives here on the group (an invisible backing makes
				--the whole row, including the gaps, the hit area) and the hover
				--feedback on the children keys off parent:hover so text and icon
				--light up together.
				gui.Panel{
					classes = {"collapseOnNoCommerce"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					bgimage = "panels/square.png",
					bgcolor = "clear",
					refreshCart = function(element, shoppingCart, addingItem)
						if addingItem then
							element:PulseClassTree("add")
						end
					end,

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

					gui.Label{
						bgcolor = "clear",
						width = "auto",
						height = "auto",
						fontSize = 18,
						valign = "center",
						rmargin = 8,
						text = "View Cart",
						fontWeight = "bold",

						styles = {
							{
								selectors = {"parent:hover"},
								color = "#ffffff",
							},
						},
					},

					gui.Panel{
						bgimage = "icons/icon_shopping/shopping-cart.png",
						bgcolor = "white",
						width = 32,
						height = 32,
						--The cart icon art is pure white, so hover/add feedback
						--tints it gold (brightness can't lift white any further).
						--parent:hover so hovering anywhere on the View Cart group
						--tints it, not just the icon itself.
						styles = {
							{
								selectors = {"add"},
								transitionTime = 0.3,
								bgcolor = "#f6ddb6",
							},
							{
								selectors = {"parent:hover"},
								bgcolor = "#f6ddb6",
							},
						},
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
			},

			--close button in top left.
			gui.CloseButton{
				halign = "left",
				valign = "top",

				click = function(element)
					element:FireEventOnParents("closeShop")
				end,
			},


			--inventory in top left. vmargin picked so the 18px labels (~24px
			--tall) center on the close button's line (the X is 24px at margin 6,
			--center y 18), which the top-right cart/redeem row also aligns to.
			gui.Panel{
				floating = true,
				halign = "left",
				valign = "top",
				hmargin = 96,
				vmargin = 6,
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

			},

			--Last child so it draws above the whole screen: the first-open
			--loading cover. Destroys itself once the initial images are in.
			coverPanel,

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
			g_openShopScreens = g_openShopScreens + 1
			element:FireEvent("showshop", true)
		end,

		destroy = function(element)
			g_openShopScreens = math.max(0, g_openShopScreens - 1)
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
							bgimage = StoreBackgroundImage(),
							bgcolor = StoreBackgroundColor(),

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

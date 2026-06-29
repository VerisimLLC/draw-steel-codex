local mod = dmhub.GetModLoading()

local ShowShopPanel

Compendium.Register{
    section = "Assets",
    text = "Shop",
    click = function(contentPanel)
        ShowShopPanel(contentPanel)

    end,
}

ShowShopPanel = function(parentPanel)
    local m_couponMonitor = nil
    local m_item = nil

    --Left-list view state, shared between the editing panel's Hidden checkbox
    --and the list's filter / show-hidden controls.
    local m_filterText = ""
    local m_showHidden = false

    --Forward-declared so the editing panel's change handlers (defined below but
    --invoked later) can refresh the side list when an item is hidden/unhidden.
    local itemsListPanel

    --Read/write item.hidden defensively: the C# field (ShopItem.hidden) only
    --exists once the matching engine build is present. Pre-build the read
    --reports "not hidden" and the write no-ops, mirroring the diceBanner setter
    --guard above, so the panel keeps working against an older binary.
    local function ItemHidden(item)
        local ok, val = pcall(function() return item.hidden end)
        return ok and val == true
    end

    local function SetItemHidden(item, val)
        pcall(function() item.hidden = val end)
    end

    --Same defensive guard for item.featured (only live items may be featured).
    local function ItemFeatured(item)
        local ok, val = pcall(function() return item.featured end)
        return ok and val == true
    end

    local function SetItemFeatured(item, val)
        pcall(function() item.featured = val end)
    end

    --------------------------------------------------------------------------
    -- Featured-dice shop banner editor (Type == "Dice").
    --
    -- m_diceBanner is the working config for the currently selected Dice item
    -- (a table matching ShopDiceBanner.defaults). bannerPreview is a live
    -- instance of the REAL shop banner component (CodexShopScreen's
    -- ShopDiceBanner), so the admin sees exactly what shoppers will see. Edits
    -- write straight back to m_item.diceBanner, upload, and push to the preview.
    --------------------------------------------------------------------------
    local m_diceBanner = ShopDiceBanner.NormalizeConfig(nil)
    local bannerPreview = ShopDiceBanner.Create{ adminPreview = true }

    --Push the working config to the live preview. Cheap + local, so this runs
    --on every slider tick.
    local function PreviewBanner()
        if bannerPreview ~= nil then
            bannerPreview:FireEventTree("applyBannerConfig", { cfg = m_diceBanner, item = m_item })
        end
    end

    --Persist the working config to the item in the cloud. Debounced (coalesced
    --to one write ~0.4s after the last edit) so dragging a slider does not spam
    --the catalog with uploads.
    local m_uploadScheduled = false
    local function CommitBanner()
        if m_uploadScheduled then
            return
        end
        m_uploadScheduled = true
        dmhub.Schedule(0.4, function()
            m_uploadScheduled = false
            if mod.unloaded or m_item == nil then
                return
            end
            --pcall guards the brand-new diceBanner C# setter: if the editor is
            --opened against an engine binary that predates this build, the write
            --no-ops instead of erroring (the live preview still works locally).
            local ok = pcall(function()
                m_item.diceBanner = m_diceBanner
                m_item:Upload()
            end)
            if not ok then
                printf("ShopAdmin: diceBanner not supported by this build; banner config not saved (rebuild + restart required).")
            end
        end)
    end

    --Update the preview now and schedule a coalesced cloud upload.
    local function SaveAndPreviewBanner()
        PreviewBanner()
        CommitBanner()
    end

    --A labeled slider row bound to a numeric field of m_diceBanner. Listens to
    --"refreshBanner" so it reloads when a different item is selected.
    local function BannerSlider(label, field, minValue, maxValue)
        return gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                halign = "left",
                text = label,
            },
            gui.Slider{
                style = { height = 26, width = 340, fontSize = 14 },
                sliderWidth = 250,
                labelWidth = 70,
                minValue = minValue,
                maxValue = maxValue,
                value = ShopDiceBanner.defaults[field] or 0,
                refreshBanner = function(element, cfg)
                    element.value = cfg[field]
                end,
                change = function(element)
                    m_diceBanner[field] = element.value
                    SaveAndPreviewBanner()
                end,
            },
        }
    end

    --An upload slot for one banner layer image (background or foreground),
    --with a thumbnail preview, an Upload button, and a Clear button.
    local function BannerImageSlot(label, field)
        local thumb
        thumb = gui.Panel{
            width = 220,
            height = 126,
            valign = "center",
            halign = "left",
            borderWidth = 1,
            borderColor = "#666666ff",
            bgimage = "panels/square.png",
            bgcolor = "#222222ff",
            refreshBanner = function(element, cfg)
                local img = cfg[field]
                if img ~= nil and img ~= "" then
                    element.bgimage = img
                    element.selfStyle.bgcolor = "white"
                else
                    element.bgimage = "panels/square.png"
                    element.selfStyle.bgcolor = "#222222ff"
                end
            end,
        }

        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            hmargin = 12,
            vmargin = 6,

            gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 16,
                halign = "left",
                text = string.format("%s layer (%dx%d):", label, ShopDiceBanner.artWidth, ShopDiceBanner.artHeight),
            },

            thumb,

            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 4,

                gui.Button{
                    classes = {"sizeS"},
                    width = 120,
                    text = "Upload...",
                    click = function(element)
                        if m_item == nil then
                            return
                        end
                        dmhub.OpenFileDialog{
                            id = "ShopBanner",
                            extensions = {"jpeg", "jpg", "png", "webp"},
                            multiFiles = false,
                            prompt = string.format("Choose %s layer image", label),
                            open = function(path)
                                assets:UploadImageAsset{
                                    --Banner art is referenced by the global
                                    --shop catalog, so it must live in the Core
                                    --asset store (see Upload Images above).
                                    core = true,
                                    error = function(msg)
                                    end,
                                    upload = function(guid)
                                        m_diceBanner[field] = guid
                                        SaveAndPreviewBanner()
                                        thumb:FireEvent("refreshBanner", m_diceBanner)
                                    end,
                                    description = string.format("ShopBanner: %s", m_item.id),
                                    path = path,
                                }
                            end,
                        }
                    end,
                },

                gui.Button{
                    classes = {"sizeS"},
                    width = 90,
                    hmargin = 8,
                    text = "Clear",
                    click = function(element)
                        m_diceBanner[field] = ""
                        SaveAndPreviewBanner()
                        thumb:FireEvent("refreshBanner", m_diceBanner)
                    end,
                },
            },
        }
    end

    --Row of text-overlay placement presets. The selected preset is highlighted;
    --clicking one re-anchors the banner's advertising copy.
    local function BannerTextPresets()
        local presets = {
            { id = "topleft", text = "Top Left" },
            { id = "topright", text = "Top Right" },
            { id = "left", text = "Left" },
            { id = "right", text = "Right" },
            { id = "bottomleft", text = "Bottom Left" },
            { id = "bottomright", text = "Bottom Right" },
        }

        local row
        local children = {}
        for _,p in ipairs(presets) do
            local placement = p.id
            children[#children+1] = gui.Button{
                classes = {"sizeS"},
                width = 130,
                hmargin = 4,
                vmargin = 4,
                text = p.text,
                styles = {
                    {
                        selectors = {"selected"},
                        borderWidth = 2,
                        borderColor = "white",
                        brightness = 1.3,
                    },
                },
                refreshBanner = function(element, cfg)
                    element:SetClass("selected", cfg.textPlacement == placement)
                end,
                click = function(element)
                    m_diceBanner.textPlacement = placement
                    SaveAndPreviewBanner()
                    row:FireEventTree("refreshBanner", m_diceBanner)
                end,
            }
        end

        row = gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = 820,
            height = "auto",
            halign = "left",
            children = children,
        }

        return row
    end

    local editingPanel
    editingPanel = gui.Panel{
        classes = {"hidden"},
        styles = {
            Styles.Form,
            {
                selectors = {"formLabel"},
                halign = "left",
            },
            {
                selectors = {"formInput"},
                halign = "left",
            },
        },
        width = 1400,
        height = 960,
        vscroll = true,
        flow = "vertical",

        code = function(element, codes)
            element:FireEventTree("couponCodes", codes)
        end,

        destroy = function(element)
            if m_couponMonitor ~= nil then
                m_couponMonitor.events:Unlisten(element)
                m_couponMonitor:Destroy()
                m_couponMonitor = nil
            end
        end,

        item = function(element, item)
            element:SetClass("hidden", false)
            m_item = item


            if m_couponMonitor ~= nil then
                m_couponMonitor.events:Unlisten(element)
                m_couponMonitor:Destroy()
                m_couponMonitor = nil
            end

            element:FireEventTree("couponCodes", {})

            m_couponMonitor = shop:MonitorItemGiftCodes(m_item.id)
            m_couponMonitor.events:Listen(element)
        end,

        gui.Check{
            text = "Live on store",
            item = function(element, item)
                element.value = item.onsale
            end,
            change = function(element)
                m_item.onsale = element.value
                if element.value then
                    --An item that is live on the store cannot also be hidden.
                    SetItemHidden(m_item, false)
                else
                    --An item that is not live on the store cannot be featured.
                    SetItemFeatured(m_item, false)
                end
                m_item:Upload()
                --Refresh the Hidden/Featured checkboxes (they enable/disable on
                --this) and the side list (highlighting + hidden depend on it).
                editingPanel:FireEventTree("item", m_item)
                itemsListPanel:FireEvent("refreshAssets")
            end,
        },

        gui.Check{
            text = "Featured",
            tooltip = "Feature this item in the shop. Only items that are live on the store can be featured.",
            styles = {
                {
                    selectors = {"disabled"},
                    opacity = 0.4,
                },
            },
            item = function(element, item)
                element.value = ItemFeatured(item)
                --Only live items can be featured, so lock the control otherwise.
                element:SetClass("disabled", not item.onsale)
            end,
            change = function(element)
                SetItemFeatured(m_item, element.value)
                m_item:Upload()
                itemsListPanel:FireEvent("refreshAssets")
            end,
        },

        gui.Check{
            text = "Hidden",
            tooltip = "Hide this item from the shop list. Items that are live on the store cannot be hidden.",
            styles = {
                {
                    selectors = {"disabled"},
                    opacity = 0.4,
                },
            },
            item = function(element, item)
                element.value = ItemHidden(item)
                --Live items cannot be hidden, so lock the control when onsale.
                element:SetClass("disabled", item.onsale)
            end,
            change = function(element)
                SetItemHidden(m_item, element.value)
                m_item:Upload()
                itemsListPanel:FireEvent("refreshAssets")
            end,
        },

        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Name:",
            },

            gui.Input{
                classes = {"formInput"},
                item = function(element, item)
                    element.text = item.name
                end,
                change = function(element)
                    m_item.name = element.text
                    m_item:Upload()
                end,
            }
        },

        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Keywords:",
            },

            gui.Input{
                classes = {"formInput"},
                item = function(element, item)
                    element.text = item.keywords
                end,
                change = function(element)
                    m_item.keywords = element.text
                    m_item:Upload()
                end,
            }
        },



        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Artist:",
            },

            gui.Dropdown{

                create = function(element)
                    local options = {}

                    for artistid,artist in pairs(assets.artists) do
                        options[#options+1] = {
                            id = artistid,
                            text = artist.name,
                        }
                    end

                    table.sort(options, function(a,b) return a.text < b.text end)

                    table.insert(options, 1, {
                        id = "none",
                        text = "(None)",
                    })

                    element.options = options
                end,
                item = function(element, item)
                    local artistid = item.artistid
                    if artistid == nil or artistid == "" then
                        artistid = "none"
                    end
                    element.idChosen = artistid
                end,

                change = function(element)
                    if element.idChosen == "none" then
                        m_item.artistid = nil
                    else
                        m_item.artistid = element.idChosen
                    end

                    m_item:Upload()
                end,
            },
        },

        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Price (US cents):",
            },

            gui.Input{
                classes = {"formInput"},
                item = function(element, item)
                    element.text = string.format("%d", item.price)
                end,
                change = function(element)
                    if tonumber(element.text) then
                        m_item.price = math.floor(tonumber(element.text))
                        m_item:Upload()
                    end

                    element.parent:FireEventTree("item", m_item)
                end,
            },

            gui.Label{
                classes = {"formLabel"},
                item = function(element, item)

                    if item.price <= 0 then
                        element.text = "FREE"
                    else
                        local dollars = math.tointeger(math.floor(item.price/100))
                        local cents = math.tointeger(item.price%100)
                        element.text = string.format("$%d.%02d", dollars, cents)
                    end
                end,
            },
        },

        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Type:",
                valign = "top",
            },

            gui.Dropdown{
                options = {
                    {
                        id = "None",
                        text = "None",
                    },
                    {
                        id = "Dice",
                        text = "Dice",
                    },
                    {
                        id = "Module",
                        text = "Module",
                    },
                    {
                        id = "Bundle",
                        text = "Bundle",
                    },
                    {
                        id = "AnimatedTokens",
                        text = "Animated Tokens",
                    },
                },

                item = function(element, item)
                    element.idChosen = item.itemType
                end,
                change = function(element)
                    m_item.itemType = element.idChosen
                    m_item:Upload()
                    editingPanel:FireEventTree("item", m_item)
                end,
            }
        },

        gui.Panel{
            classes = {"formPanel"},
            item = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "Module")
            end,

            gui.Label{
                classes = {"formLabel"},
                text = "Module ID:",
                valign = "top",
            },

            gui.Input{
                classes = {"formInput"},
                width = 300,
                characterLimit = 50,
                item = function(element, item)
                    if item.itemType == "Module" then
                        element.text = item.assetid
                    end
                end,
                change = function(element)
                    m_item.assetid = element.text
                    m_item:Upload()
                end,
            },

            --status label.
            gui.Label{
                data = {
                    checking = "",
                },
                classes = {"formLabel"},
                text = "",
                width = "auto",
                thinkTime = 0.1,
                think = function(element)
                    if m_item == nil or m_item.assetid == element.data.checking then
                        return
                    end

                    element.text = ""
                    element.data.checking = m_item.assetid

                    local moduleid = m_item.assetid
                    module.DownloadModuleInfo{
                        moduleid = moduleid,
                        success = function(info)
                            if m_item.assetid == moduleid then
                                element.selfStyle.color = "green"
                                element.text = string.format("%s", info.name)
                            end
                        end,
                        failure = function(msg)
                            if m_item.assetid == moduleid then
                                element.selfStyle.color = "red"
                                element.text = msg
                            end
                        end,
                    }

                end,

            },
        },

        --Dice editor: choose the dice set, then customize the featured-dice
        --shop banner (custom art, dice transform, text placement) with a live
        --preview of the real banner component.
        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            item = function(element, item)
                local isDice = item.itemType == "Dice"
                element:SetClass("collapsed", not isDice)
                if isDice then
                    m_diceBanner = ShopDiceBanner.ReadItemConfig(item)
                    element:FireEventTree("refreshBanner", m_diceBanner)
                    bannerPreview:FireEventTree("applyBannerConfig", { cfg = m_diceBanner, item = item })
                end
            end,

            --Fired by the banner when the user drags the die on the preview.
            --Sync the working config, persist, and update the X/Y sliders.
            dieDragged = function(element, info)
                m_diceBanner.dieX = info.dieX
                m_diceBanner.dieY = info.dieY
                SaveAndPreviewBanner()
                element:FireEventTree("refreshBanner", m_diceBanner)
            end,

            gui.Panel{
                classes = {"formPanel"},

                gui.Label{
                    classes = {"formLabel"},
                    text = "Dice:",
                    valign = "top",
                },

                gui.Dropdown{
                    textDefault = "(None)",

                    options = dice.GetAllDice(),

                    item = function(element, item)
                        element.idChosen = item.assetid
                    end,
                    change = function(element)
                        m_item.assetid = element.idChosen
                        m_item:Upload()
                        --New dice set: refresh the preview die.
                        bannerPreview:FireEventTree("applyBannerConfig", { cfg = m_diceBanner, item = m_item })
                    end,
                }
            },

            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                vmargin = 8,
                fontSize = 24,
                fontWeight = "bold",
                text = "Shop Banner",
            },

            gui.Label{
                width = 900,
                height = "auto",
                halign = "left",
                fontSize = 13,
                color = "#aaaaaaff",
                text = string.format("Customize the banner shown at the top of the shop when this dice set is featured. Upload two %dx%d images: a BACKGROUND layer (painted behind the dice) and a FOREGROUND layer (painted over the dice, e.g. hands holding them -- use PNG transparency). Click Clear on a layer to leave it transparent (the dice render directly over whatever is behind it). Use the controls below to position/scale the live dice and place the text overlay.", ShopDiceBanner.artWidth, ShopDiceBanner.artHeight),
            },

            --Live preview of the real banner component. The wrapper is sized in
            --solid pixels to exactly the banner's display dimensions.
            gui.Panel{
                width = ShopDiceBanner.displayWidth,
                height = ShopDiceBanner.displayHeight,
                halign = "left",
                vmargin = 12,
                bannerPreview,
            },

            --Two image upload slots side by side.
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                wrap = true,

                BannerImageSlot("Background", "backgroundImage"),
                BannerImageSlot("Foreground", "foregroundImage"),
            },

            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                vmargin = 6,
                fontSize = 18,
                fontWeight = "bold",
                text = "Dice Placement & Scale",
            },

            gui.Label{
                width = 900,
                height = "auto",
                halign = "left",
                fontSize = 13,
                color = "#aaaaaaff",
                text = "Tip: drag the dice directly on the preview above to position them. The X/Y sliders below give the same control.",
            },

            BannerSlider("Dice Scale:", "diceScale", 0.5, 8),
            --Spin direction for the previewed die, in degrees: the slider rotates
            --the spin AXIS about the screen-normal (Z) axis at a constant speed.
            --0 = the original vertical spin; +/-180 = reversed; +/-90 = tumbling.
            --Saved per dice set and applied live in the preview above (and in the
            --live shop banner).
            BannerSlider("Spin Direction:", "spinDirection", -180, 180),
            BannerSlider("Dice X (0-1):", "dieX", 0, 1),
            BannerSlider("Dice Y (0-1):", "dieY", 0, 1),
            BannerSlider("Dice Box Size (0=auto):", "dieSize", 0, 1200),

            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                vmargin = 6,
                fontSize = 18,
                fontWeight = "bold",
                text = "Text Overlay Placement",
            },

            BannerTextPresets(),

            BannerSlider("Text Offset X:", "textOffsetX", -500, 500),
            BannerSlider("Text Offset Y:", "textOffsetY", -350, 350),
        },

        --bundle editor
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            item = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "Bundle")
            end,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                item = function(element, item)
                    if item.itemType ~= "Bundle" then
                        return
                    end

                    local shopItems = assets.shopItems
                    local children = {}

                    for k,_ in pairs(item.bundle) do
                        local itemInfo = shopItems[k]
                        local itemName = nil
                        if itemInfo ~= nil then
                            itemName = itemInfo.name
                        else
                            itemName = string.format("INVALID ITEM: %s", k)
                        end

                        children[#children+1] = gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",

                            gui.Label{
                                text = itemName,
                                width = 400,
                                height = "auto",
                                hmargin = 16,
                                fontSize = 14,
                            },

                            gui.DeleteItemButton{
                                width = 16,
                                height = 16,
                                click = function(element)
                                    local bundle = m_item.bundle
                                    bundle[k] = nil
                                    m_item.bundle = bundle
                                    m_item:Upload()
                                    editingPanel:FireEventTree("item", m_item)
                                end,
                            }
                        }
                    end

                    element.children = children
                end,
            },

            gui.Dropdown{
                textOverride = "Add to Bundle...",
                idChosen = "none",
                hasSearch = true,
                lmargin = 10,
                width = 320,
                create = function(element)
                    local options = {}
                    local shopItems = assets.shopItems
                    for k,v in pairs(shopItems) do
                        options[#options+1] = {
                            id = k,
                            text = v.name,
                        }
                    end

                    table.sort(options, function(a,b) return a.text < b.text end)

                    element.options = options
                end,

                change = function(element)
                    if element.idChosen == "none" then
                        return
                    end


                    local bundle = m_item.bundle
                    bundle[element.idChosen] = true
                    m_item.bundle = bundle
                    m_item:Upload()
                    editingPanel:FireEventTree("item", m_item)

                    element.idChosen = "none"
                end,
            },

            gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 14,
                text = "",
                item = function(element, item)
                    if item.itemType ~= "Bundle" then
                        return
                    end

                    local shopItems = assets.shopItems
                    local total = 0
                    local count = 0
                    for k,_ in pairs(item.bundle) do
                        local itemInfo = shopItems[k]
                        if itemInfo ~= nil then
                            total = total + itemInfo.price
                            count = count+1
                        end
                    end

                    local dollars = math.tointeger(math.floor(total/100))
                    local cents = math.tointeger(total%100)
                    element.text = string.format("Bundle Value: $%d.%02d in %d items", dollars, cents, count)
                end,
            }
        },

        --animated tokens editor. Like the bundle editor, an AnimatedTokens item grants a
        --SET of animated tokens (by spine registry name, e.g. "lightbender"), so this is a
        --multi-select list (add via dropdown, remove via delete button) rather than the
        --single-asset dropdown the Dice type uses.
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            item = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "AnimatedTokens")
            end,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                item = function(element, item)
                    if item.itemType ~= "AnimatedTokens" then
                        return
                    end

                    local children = {}

                    for k,_ in pairs(item.animatedTokens) do
                        children[#children+1] = gui.Panel{
                            width = "auto",
                            height = "auto",
                            flow = "horizontal",

                            gui.Label{
                                text = k,
                                width = 400,
                                height = "auto",
                                hmargin = 16,
                                fontSize = 14,
                            },

                            gui.DeleteItemButton{
                                width = 16,
                                height = 16,
                                click = function(element)
                                    local tokens = m_item.animatedTokens
                                    tokens[k] = nil
                                    m_item.animatedTokens = tokens
                                    m_item:Upload()
                                    editingPanel:FireEventTree("item", m_item)
                                end,
                            }
                        }
                    end

                    element.children = children
                end,
            },

            gui.Dropdown{
                textOverride = "Add Animated Token...",
                idChosen = "none",
                hasSearch = true,
                lmargin = 10,
                width = 320,
                create = function(element)
                    local options = {}
                    for _,entry in ipairs(spine.listEntries()) do
                        options[#options+1] = {
                            id = entry.id,
                            text = entry.text,
                        }
                    end

                    table.sort(options, function(a,b) return a.text < b.text end)

                    element.options = options
                end,

                change = function(element)
                    if element.idChosen == "none" then
                        return
                    end

                    local tokens = m_item.animatedTokens
                    tokens[element.idChosen] = true
                    m_item.animatedTokens = tokens
                    m_item:Upload()
                    editingPanel:FireEventTree("item", m_item)

                    element.idChosen = "none"
                end,
            },
        },


        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                text = "Details:",
                valign = "top",
            },

            gui.Input{
                classes = {"formInput"},
                height = "auto",
                minHeight = 60,
                multiline = true,
                width = 400,
                item = function(element, item)
                    element.text = item.details
                end,
                change = function(element)
                    m_item.details = element.text
                    m_item:Upload()
                end,
            }
        },

        gui.Panel{
            classes = {"formPanel"},

            gui.Label{
                classes = {"formLabel"},
                valign = "top",
                text = "Images:",
            },
            gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                gui.Panel{
                    flow = "horizontal",
                    wrap = true,
                    width = 900,
                    height = "auto",

                    item = function(element, item)
                        local children = {}

                        for i,imageid in ipairs(item.images) do
                            children[#children+1] = gui.Panel{
                                width = 280,
                                height = 280,
                                gui.Panel{
                                    classes = {"itemImage"},
                                    bgimage = imageid,
                                    bgcolor = "white",
                                    halign = "center",
                                    valign = "center",
                                    autosizeimage = true,
                                    maxWidth = 256,
                                    maxHeight = 256,
                                    width = "auto",
                                    height = "auto",
                                    styles = {
                                        {
                                            selectors = {"drag-target"},
                                            brightness = 1.2,
                                            borderWidth = 1,
                                            borderColor = "grey",
                                        },
                                        {
                                            selectors = {"drag-target-hover"},
                                            brightness = 2.0,
                                            borderWidth = 1,
                                            borderColor = "white",
                                        },
                                    },
                                    draggable = true,
                                    dragTarget = true,
                                    data = {
                                        index = i,
                                    },
                                    canDragOnto = function(element, target)
                                        return target ~= nil and target ~= element and target:HasClass("itemImage")
                                    end,
                                    drag = function(element, target)
                                        if target ~= nil then
                                            local images = m_item.images
                                            local a = images[element.data.index]
                                            local b = images[target.data.index]
                                            images[element.data.index] = b
                                            images[target.data.index] = a
                                            m_item.images = images
                                            m_item:Upload()
                                            editingPanel:FireEventTree("item", m_item)
                                        end
                                    end,
                                },

                                gui.Button{
                                    classes = {"deleteButton", "sizeS"},
                                    halign = "right",
                                    valign = "top",
                                    floating = true,
                                    click = function(element)
                                        local images = m_item.images
                                        local newImages = {}
                                        for _,img in ipairs(images) do
                                            if img ~= imageid then
                                                newImages[#newImages+1] = img
                                            end
                                        end

                                        m_item.images = newImages
                                        m_item:Upload()
                                        editingPanel:FireEventTree("item", m_item)
                                    end,
                                }
                            }
                        end

                        element.children = children
                    end,

                },

                gui.Label{
                    classes = {"hidden"},
                    fontSize = 16,
                    width = "auto",
                    height = "auto",
                    data = {
                        outstanding = 0,
                        highWaterMark = 0,
                    },
                    uploadingStatus = function(element, requests)
                        if requests > element.data.outstanding then
                            element.data.highWaterMark = requests
                        end
                        if requests <= 0 then
                            element:SetClass("hidden", true)
                        else
                            local completed = element.data.highWaterMark - requests
                            element:SetClass("hidden", false)
                            element.text = string.format("Uploading %d/%d", completed+1, element.data.highWaterMark)
                        end

                        element.data.outstanding = requests
                    end,
                },

                gui.Button{
                    classes = {"sizeL"},
                    width = 190,
                    text = "Upload Images",
                    data = {
                        requests = 0,
                    },
                    click = function(element)
                        element.data.requests = 0
                        dmhub.OpenFileDialog{
                            id = "ShopImages",
                            extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
                            multiFiles = true,
                            prompt = "Choose media for shop",
                            open = function(path)
                                element.data.requests = element.data.requests+1
                                editingPanel:FireEventTree("uploadingStatus", element.data.requests)
                                assets:UploadImageAsset{
                                    -- Force the image into the global Core asset store
                                    -- regardless of which game we're in. The shop catalog
                                    -- entry that references this guid is itself global,
                                    -- so the image must be too or other clients won't
                                    -- resolve it. Engine ignores this for non-admins.
                                    core = true,
                                    error = function(msg)
                                    end,
                                    upload = function(guid)
                                        local images = m_item.images
                                        images[#images+1] = guid
                                        m_item.images = images

                                        element.data.requests = element.data.requests-1
                                        editingPanel:FireEventTree("uploadingStatus", element.data.requests)

                                        if element.data.requests == 0 then
                                            printf("Upload: NewItem")
                                            m_item:Upload()
                                            editingPanel:FireEventTree("item", m_item)
                                        end
                                    end,
                                    description = string.format("ShopMedia: %s", m_item.id),
                                    path = path,
                                }

                            end,

                        }
                    end,
                },

                gui.Label{
                    text = "Gift Codes",
                    vmargin = 8,
                    fontSize = 24,
                    fontWeight = "bold",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                },

                gui.Panel{
                    flow = "vertical",
                    width = "auto",
                    height = "auto",

                    data = {
                        rows = {},
                    },

                    couponCodes = function(element, codes)
                        local newRows = {}
                        local children = {}
                        for k,v in pairs(codes) do
                            children[#children+1] = element.data.rows[k] or gui.Panel{
                                width = "auto",
                                height = 26,
                                flow = "horizontal",
                                data = {
                                    ord = v.ctime,
                                },
                                gui.Label{
                                    text = k,
                                    width = 280,
                                    height = "auto",
                                    hmargin = 16,
                                    fontSize = 14,
                                    bgimage = "panels/square.png",
                                    bgcolor = "#00000000",
                                    press = function(element)
                                        local tooltip = gui.Tooltip{text = "Copied to Clipboard", valign = "top", borderWidth = 0}(element)
                                        dmhub.CopyToClipboard(k)
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

                                gui.Label{
                                    width = 200,
                                    height = "auto",
                                    fontSize = 14,
                                    refreshCode = function(element, info)
                                        element.text = string.format("Created %s", dmhub.FormatTimestamp(info.ctime, "yyyy-MM-dd HH:mm"))
                                    end,
                                },
                                gui.Label{
                                    width = 310,
                                    height = "auto",
                                    fontSize = 14,
                                    refreshCode = function(element, info)
                                        if info.redeemed then
                                            element.text = string.format("Redeemed %s %s", info.redeemUserFullName or "(Unknown)", dmhub.FormatTimestamp(info.mtime, "yyyy-MM-dd HH:mm"))
                                        else
                                            element.text = "Available"
                                        end
                                    end,
                                },

                                gui.Input{
                                    height = 22,
                                    width = 200,
                                    valign = "center",
                                    placeholderText = "Enter note...",
                                    fontSize = 14,
                                    characterLimit = 120,
                                    refreshCode = function(element, info)
                                        element.text = info.adminNote or ""
                                    end,
                                    change = function(element)
                                        codes[k].adminNote = element.text
                                        shop:AdminSetGiftCodeNote(k, element.text)
                                    end,
                                }
                            }

                            table.sort(children, function(a,b) return a.data.ord > b.data.ord end)

                            newRows[k] = children[#children]
                            children[#children]:FireEventTree("refreshCode", v)
                        end

                        element.data.rows = newRows
                        element.children = children
                    end,
                },

                gui.Button{
                    classes = {"sizeL"},
                    width = 190,
                    text = "Add Gift Code",
                    click = function(element)
                        shop:AdminCreateGiftCode(dmhub.GenerateGuid(), {
                            itemid = m_item.id,
                            admin = true,
                        })
                    end,
                },
            },
        },
    }

    local addingItemText = gui.Label{
        classes = {"collapsed"},
        fontSize = 14,
        text = "Adding item...",
        width = "auto",
        height = "auto",
    }

    local m_artistPanels = {}
    local m_itemPanels = {}

    itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        width = 360,
        vscroll = true,
        monitorAssets = true,

        --Featured items are called out in bold purple in the list. Cascades to
        --the list-item labels (descendants) that carry the "featured" class.
        --Only color/bold are set, so the normal hover/selected wash still wins
        --on the active row while bold keeps it recognizable.
        styles = {
            {
                selectors = {"featured"},
                color = "#c77dffff",
                bold = true,
            },
        },

        refreshAssets = function(element)
            local shopItems = assets.shopItems
            local artists = assets.artists

            --A lowercased substring filter matched against an item's name or
            --keywords. An empty filter matches everything.
            local filter = string.lower(m_filterText or "")

            --An item appears in the list unless it is soft-hidden (and we are
            --not showing hidden items) or it fails the text filter. An item
            --that is live on the store is never treated as hidden.
            local function ItemVisible(v)
                if (not m_showHidden) and (not v.onsale) and ItemHidden(v) then
                    return false
                end

                if filter ~= "" then
                    local name = string.lower(v.name or "")
                    local keywords = string.lower(v.keywords or "")
                    if string.find(name, filter, 1, true) == nil and string.find(keywords, filter, 1, true) == nil then
                        return false
                    end
                end

                return true
            end

            --Build a panel for every artist that has any item, visible or not.
            --They all stay attached below (empty ones are collapsed), because
            --removing a cached panel from the tree destroys it and a later
            --refresh would then reuse a dead reference.
            local artistPanelChildren = {}
            for k,v in pairs(shopItems) do
                local artistid = v.artistid or "none"

                local artist = artists[artistid]
                local artistName = "No Artist"
                if artist ~= nil then
                    artistName = artist.name
                end


                local artistPanel
                artistPanel = m_artistPanels[artistid] or gui.Panel{
                    data = {
                        ord = artistName,
                        artistid = v.artistid,
                    },
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        gui.Panel{
                            styles = gui.TriangleStyles,
                            bgimage = "panels/triangle.png",
                            classes = {"expanded"},
                            click = function(element)
                                element:SetClass("expanded", not element:HasClass("expanded"))
                                artistPanel:FireEventTree("expanded", element:HasClass("expanded"))
                            end,
                        },
                        gui.Label{
                            width = "100%-16",
                            height = 20,
                            fontSize = 14,
                            text = artistName,
                        },
                    },

                    gui.Panel{
                        flow = "vertical",
                        width = "100%-20",
                        height = "auto",
                        lmargin = 20,
                        expanded = function(element, val)
                            element:SetClass("collapsed", not val)
                        end,
                    }
                }

                m_artistPanels[artistid] = artistPanel
                artistPanelChildren[artistid] = {}
            end


            for k,v in pairs(shopItems) do
              if ItemVisible(v) then
                local list = artistPanelChildren[v.artistid or "none"]
                local text = v.name
                if v.onsale then
                    if v.price <= 0 then
                        text = string.format("%s (FREE)", text)
                    else
                        local dollars = math.tointeger(math.floor(v.price/100))
                        local cents = math.tointeger(v.price%100)
                        text = string.format("%s: $%d.%02d", text, dollars, cents)
                    end
                end
                local listItem = Compendium.CreateListItem{
                    ord = v.ctime,
                    text = text,
                    click = function(element)
                        itemsListPanel:SetClassTree("selected", false)
                        element:SetClass("selected", true)
                        local item = assets.shopItems[k]
                        if item ~= nil then
                            printf("ShowShopItem: %s", k)
                            editingPanel:FireEventTree("item", item)
                        end
                    end,
                }
                --Featured (and still live) items stand out in bold purple.
                if ItemFeatured(v) and v.onsale then
                    listItem:SetClass("featured", true)
                end
                list[#list+1] = listItem
              end
            end

            for k,v in pairs(artistPanelChildren) do
                table.sort(v, function(a,b) return a.data.ord < b.data.ord end)
                m_artistPanels[k].children[2].children = v
                --Hide whole artist groups that have no visible items this refresh
                --(filtered out / all hidden) without detaching them.
                m_artistPanels[k]:SetClass("collapsed", #v == 0)
            end

            local childItems = {}
            for k,v in pairs(m_artistPanels) do
                childItems[#childItems+1] = v
            end

            table.sort(childItems, function(a,b) return a.data.ord < b.data.ord end)

            element.children = childItems

            addingItemText:SetClass("collapsed", true)
        end,

        create = function(element)
            element:FireEvent("refreshAssets")
        end,
    }

    local leftPanel = gui.Panel{
        selfStyle = {
            flow = 'vertical',
            height = '100%',
            width = 'auto',
        },

        --Live text filter over the item list (matches name or keywords).
        gui.Input{
            width = 340,
            height = 24,
            halign = "left",
            vmargin = 4,
            placeholderText = "Filter items...",
            editlag = 0.2,
            edit = function(element)
                m_filterText = element.text
                itemsListPanel:FireEvent("refreshAssets")
            end,
            change = function(element)
                m_filterText = element.text
                itemsListPanel:FireEvent("refreshAssets")
            end,
        },

        itemsListPanel,

        --Reveal soft-hidden items in the list above. This only affects the
        --admin view; hidden items are already excluded from the live shop.
        gui.Check{
            text = "Show Hidden Items",
            value = false,
            fontSize = 14,
            halign = "left",
            vmargin = 4,
            change = function(element)
                m_showHidden = element.value
                itemsListPanel:FireEvent("refreshAssets")
            end,
        },

        gui.Input{
            width = 160,
            height = 24,
            placeholderText = "Add new item...",
            change = function(element)
                if element.text ~= "" then
                    local newItem = assets.CreateLocalShopItem()
                    newItem.name = element.text
                    newItem:Upload()
                    element.text = ""
                    addingItemText:SetClass("collapsed", false)
                end
            end,
        },


        addingItemText,

    }

    parentPanel.children = {leftPanel, editingPanel}
end

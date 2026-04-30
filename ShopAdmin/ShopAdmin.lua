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
                m_item:Upload()
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

        gui.Panel{
            classes = {"formPanel"},
            item = function(element, item)
                element:SetClass("collapsed", item.itemType ~= "Dice")
            end,

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
                end,
            }
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

                                gui.DeleteItemButton{
                                    width = 16,
                                    height = 16,
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

                gui.PrettyButton{
                    width = 190,
                    height = 54,
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

                gui.PrettyButton{
                    width = 190,
                    height = 54,
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

    local itemsListPanel
    itemsListPanel = gui.Panel{
        classes = {"list-panel"},
        width = 360,
        vscroll = true,
        monitorAssets = true,
        refreshAssets = function(element)
            local shopItems = assets.shopItems
            local artists = assets.artists
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
                list[#list+1] = Compendium.CreateListItem{
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
            end

            for k,v in pairs(artistPanelChildren) do
                table.sort(v, function(a,b) return a.data.ord < b.data.ord end)
                m_artistPanels[k].children[2].children = v
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

        itemsListPanel,

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

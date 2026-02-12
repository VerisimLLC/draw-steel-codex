local mod = dmhub.GetModLoading()


dmhub.RegisterEventHandler("link", function(url)

    printf("APILink: %s", url)

    if not string.starts_with(url, "api:") then
        return
    end

    local rawtypename = string.sub(url, 5)
    local docs = dmhub.GetTypeDocumentation(rawtypename)
    if docs == nil then
        return
    end

    for i=1,10 do
        if rawtypename == nil then
            break
        end
        local ok, result = pcall(function()
            local typeInfo = rawget(_G, rawtypename)
            rawtypename = typeInfo.mt.baseTypeName
            if rawtypename ~= nil then
                local baseDocs = dmhub.GetTypeDocumentation(rawtypename)

                --merge into the main docs.
                for _,field in ipairs(baseDocs.fields) do
                    for i=1,#docs.fields do
                        if docs.fields[i].name > field.name then
                            table.insert(docs.fields, i, field)
                            break
                        end
                    end
                end
            end
        end)
    end


    local dialog

    dialog = gui.Panel{
        width = 1000,
        height = 1000,
        halign = "center",
        valign = "center",
        classes = {"framedPanel"},
        styles = {
            Styles.Default,
            Styles.Panel,
        },

        gui.Label{
            classes = {"dialogTitle"},
            text = string.sub(url, 5),
            halign = "center",
            valign = "top",
            tmargin = 8,
        },

        gui.Panel{
            vscroll = true,
            width = "80%",
            height = "90%",
            valign = "center",
            halign = "center",
            flow = "vertical",

            create = function(element)
                local fields = docs.fields
                table.sort(fields, function(a,b)
                    local t1 = cond(a.type == "Method", 2, 1)
                    local t2 = cond(b.type == "Method", 2, 1)
                    if t1 ~= t2 then
                        return t1 < t2
                    end

                    return a.name < b.name
                end)

                local currentTitle = nil
                local children = {}
                for _,field in ipairs(fields) do
                    local title = cond(field.type == "Method", "Methods", "Fields")
                    if title ~= currentTitle then
                        currentTitle = title
                        children[#children+1] = gui.Label{
                            fontSize = 22,
                            bold = true,
                            halign = "left",
                            valign = "top",
                            width = "100%",
                            height = "auto",
                            text = string.format("<b>%s</b>", title),
                        }
                    end
                    local field = gui.Panel{
                        width = "95%",
                        height = "auto",
                        minHeight = 20,
                        halign = "left",
                        lmargin = 8,
                        pad = 8,
                        flow = "vertical",
                        gui.Label{
                            fontSize = 14,
                            bold = true,
                            halign = "left",
                            valign = "top",
                            width = "100%",
                            height = "auto",
                            text = string.format("<b>%s</b>", field.name),
                        },
                        gui.Label{
                            fontSize = 14,
                            halign = "left",
                            width = "auto",
                            height = "auto",
                            text = field.typeSignature or "",
                        },

                        gui.Label{
                            fontSize = 14,
                            halign = "left",
                            width = "auto",
                            height = "auto",
                            text = field.documentation or "",
                        },
                    }

                    children[#children+1] = field

                end

                element.children = children
            end,
        },

        gui.CloseButton{
            halign = "right",
            valign = "top",
            click = function(element)
                dialog:DestroySelf()
            end,
        },
    }

    gamehud.dialogWorldPanel:AddChild(dialog)
end)
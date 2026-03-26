local mod = dmhub.GetModLoading()

gui.KeywordSelector = function(args)

    local keywords = args.keywords
    args.keywords = nil

    local resultPanel

    local children = {}

    local keywordsFound = {}
    for keyword,val in sorted_pairs(keywords) do
        if val == true then
            keywordsFound[keyword] = true
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                data = {ord = keyword},
                width = 200,
                height = 14,
                minHeight = 14,
                gui.Label{
                    text = ActivatedAbility.CanonicalKeyword(keyword),
                    width = "auto",
                    height = 14,
                    fontSize = 14,
                    color = Styles.textColor,
                },
                gui.DeleteItemButton{
                    width = 12,
                    height = 12,
                    halign = "right",
                    click = function(element)
                        keywords[keyword] = nil
                        resultPanel:FireEvent("change")
                    end,
                },
            }
        end
    end

    local dropdownOptions = {}
    for keyword,_ in pairs(GameSystem.abilityKeywords) do
        if not keywordsFound[keyword] then
            dropdownOptions[#dropdownOptions+1] = {
                id = keyword,
                text = keyword,
            }
        end
    end

    children[#children+1] = gui.Dropdown{
        selfStyle = {
            height = 30,
            width = 240,
            fontSize = 16,
            halign = "left",
        },
        valign = "center",
        sort = true,
        hasSearch = true,
        options = dropdownOptions,
        textDefault = "Add Keyword...",
        change = function(element)
            if element.idChosen ~= nil and GameSystem.abilityKeywords[element.idChosen] then
                keywords[element.idChosen] = true
            end
            resultPanel:FireEvent("change")
        end,
    }

    local params = {
        width = "auto",
        height = "auto",
        flow = "vertical",
        children = children,
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)

    return resultPanel
end
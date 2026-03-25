local mod = dmhub.GetModLoading()

--- @class SourceReference
--- @string type
--- @string docid
--- @number page
SourceReference = RegisterGameType("SourceReference")

SourceReference.type = "pdf"
SourceReference.docid = "none"
SourceReference.page = 1

function SourceReference:url()
    return string.format("%s:%s&page=%d", self.type, self.docid, self.page)
end

function SourceReference:Editor(options)
    local m_object = options.object
    options.object = nil

    local sourcesOptions = {
    }

    local docs = assets.pdfDocumentsTable
    for k,doc in pairs(docs) do
        if not doc.hidden then
            sourcesOptions[#sourcesOptions+1] = {
                id = k,
                text = doc.description,
            }
        end
    end

    table.sort(sourcesOptions, function(a,b) return a.text < b.text end)
    table.insert(sourcesOptions, 1, {
        id = "none",
        text = "(None)",
    })



    local resultPanel
    local children = {
        gui.Panel {
            classes = { "formPanel" },
            gui.Label {
                classes = { "formLabel" },
                text = "Source:",
            },
            gui.Dropdown {
                classes = "formDropdown",
                options = sourcesOptions,
                idChosen = self.docid,
                change = function(element)
                    self.docid = element.idChosen
                    if self.docid ~= "none" then
                        local document = assets.pdfDocumentsTable[self.docid]
                        print("CHANGE:: Object = ", m_object)
                        if document ~= nil and m_object ~= nil then
                            local searchResults = document.doc:Search(m_object.name)
                            print("CHANGE:: SEARCH:", m_object.name, "Results:", searchResults)
                            if type(searchResults) == "table" and searchResults[1] ~= nil then
                                print("CHANGE:: SET PAGE", searchResults[1].page)
                                self.page = searchResults[1].page+1
                            end
                        end
                    end
                    resultPanel:FireEventTree("refreshSource")
                    resultPanel:FireEvent("change")
                end,
            }
        },

        gui.Panel {
            classes = { "formPanel", cond(self.docid == "none", "collapsed") },
            refreshSource = function(element)
                element:SetClass("collapsed", self.docid == "none")
            end,
            gui.Label {
                classes = { "formLabel" },
                text = "Page:",
            },
            gui.Input {
                classes = "formInput",
                text = self.page,
                characterLimit = 4,
                refreshSource = function(element)
                    element.text = self.page
                end,
                change = function(element)
                    local num = tonumber(element.text)
                    if num ~= nil then
                        self.page = num
                    else
                        element.text = self.page
                    end
                    resultPanel:FireEvent("change")
                end,
            },
            gui.Button {
                fontSize = 14,
                width = "auto",
                height = "auto",
                text = "Open",
                click = function(element)
                    print("CHANGE:: OPEN:", self:url())
                    dmhub.OpenDocument(self:url())
                end,
            },
        }
    }

    local params = {
        width = "auto",
        height = "auto",
        flow = "vertical",
        children = children,
    }

    for k,v in pairs(options or {}) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)
    return resultPanel
end
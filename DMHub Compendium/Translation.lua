local mod = dmhub.GetModLoading()

Translation = {}

function Translation.CreateEditor()
	local translationid = nil
	local currentTranslation = nil
	local resultPanel
	local dirty = false

	local SetDirty = function()
		dirty = true
	end

	local search = ""

	local allStrings = i18n.GetStrings()
	local strings = allStrings

	local showTranslated = true
	local showUntranslated = true

	local pagenum = 1
	local PageSize = 10
	local GetNumPages = function()
		return math.ceil(#strings/PageSize)
	end
	local stringPanels = {}
	for i=1,PageSize do
		local currentString = nil
		local label = gui.Label{
			width = 400,
			height = "auto",
			fontSize = 14,
			valign = "center",
			notranslation = true,


			click = function(element)
				local popup = CreateTooltipPanel("Copied to clipboard")
				element.popup = popup

				dmhub.Schedule(2, function()
					if element.popup == popup then
						element.popup = nil
					end
					popup = nil
				end)

				dmhub.CopyToClipboard(element.text)
			end,
		}

		local input = gui.Input{
			classes = {"formInput"},
			placeholderText = "Translate...",
			height = "auto",
			multiline = true,
			width = "50%",
			halign = "left",
			valign = "top",
			change = function(element)
				currentTranslation:SetString(currentString, element.text)
				SetDirty()
			end,
		}

		local child = gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			bgimage = "panels/square.png",
			bgcolor = "black",
			pad = 4,
			opacity = cond(i%2 == 1, 0.3, 0.7),
			page = function(element)
				local index = (pagenum-1)*PageSize + i
				local str = strings[index]
				currentString = str
				if str == nil then
					element:SetClass("collapsed", true)
					return
				end

				element:SetClass("collapsed", false)
				label.text = str

				local translated = currentTranslation:GetString(str)
				if translated == nil then
					translated = ""
				end

				input.text = translated
			end,

			label,
			input,
		}
		stringPanels[i] = child
	end

	local SetPage = function(n)
		if n < 1 then
			 n = 1
		end

		if n > GetNumPages() then
			n = GetNumPages()
		end

		pagenum = n
		resultPanel:FireEventTree("page")
	end

	local RecalculateStrings = function()
		if search == "" and showTranslated and showUntranslated then
			strings = allStrings
		else
			search = string.lower(search)
			strings = {}
			for _,s in ipairs(allStrings) do

				local fail = false
				local translated = currentTranslation:GetString(s)
				if translated == nil and (not showUntranslated) then
					fail = true
				end

				if translated ~= nil and (not showTranslated) then
					fail = true
				end

				if fail == false then
					if string.find(string.lower(s), search) then
						strings[#strings+1] = s
					elseif currentTranslation ~= nil then
						if translated ~= nil and string.find(string.lower(translated), search) then
							strings[#strings+1] = s
						end
					end
				end
			end
		end
		SetPage(1)
	end


	local UploadIfDirty = function()
		if dirty and translationid ~= nil and currentTranslation ~= nil then
			i18n.UploadTranslation(translationid, currentTranslation)
		end

		dirty = false
	end

	resultPanel = gui.Panel{
		classes = {"hidden"},
		width = 1024,
		height = "auto",

		flow = "vertical",

		styles = {
			Styles.Form,
		},

		destroy = function(element)
			UploadIfDirty()
		end,

		setid = function(element, id)
			UploadIfDirty()

			translationid = id
			currentTranslation = i18n.GetTranslation(id)
			if currentTranslation == nil then
				element:SetClass("hidden", true)
				return
			end

			element:SetClass("hidden", false)

			element:FireEventTree("translation")
		end,

		destroy = function(element)
			UploadIfDirty()
		end,

		gui.Panel{
			classes = {"translationHeader"},
			width = 500,
			height = "auto",
			flow = "vertical",

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Language Name:",
				},
				gui.Input{
					classes = {"formInput"},
					text = "",
					translation = function(element)
						element.text = currentTranslation.name
					end,
					change = function(element)
						currentTranslation.name = element.text
						SetDirty()
					end,
				},
			},
			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Language ID:",
				},
				gui.Input{
					classes = {"formInput"},
					text = "",
					translation = function(element)
						element.text = currentTranslation.identifier
					end,
					change = function(element)
						currentTranslation.identifier = element.text
						SetDirty()
					end,
				},
			},

			gui.Input{
				classes = {"formInput"},
				placeholderText = "Search Strings...",
				translation = function(element)
					element.text = ""
					search = ""
				end,
				change = function(element)
					search = element.text
					RecalculateStrings()
				end,
			},

			gui.Dropdown{
				classes = {"formDropdown"},
				options = {"Show All Strings", "Show Untranslated Strings", "Show Translated Strings"},
				optionChosen = "Show All Strings",

				translation = function(element)
					element.optionChosen = "Show All Strings"
					showTranslated = true
					showUntranslated = true
				end,

				change = function(element)
					showTranslated = element.optionChosen == "Show All Strings" or element.optionChosen == "Show Translated Strings"
					showUntranslated = element.optionChosen == "Show All Strings" or element.optionChosen == "Show Untranslated Strings"
					RecalculateStrings()
				end,
			},
		},

		gui.Panel{
			width = "auto",
			height = 800,
			flow = "vertical",
			vscroll = true,
			children = stringPanels,
			translation = function(element)
				SetPage(1)
			end,
		},

		--paging footer.
		gui.Panel{
			halign = "right",
			width = "auto",
			height = 32,
			flow = "horizontal",

			gui.PagingArrow{
				facing = -1,
				page = function(element)
					element:SetClass("hidden", pagenum == 1)
				end,
				click = function(element)
					SetPage(pagenum-1)
				end,
			},

			gui.Label{
				fontSize = 14,
				width = 100,
				height = "auto",
				valign = "center",
				textAlignment = "center",
				text = "Page 1/2",
				page = function(element)
					element.text = string.format("Page %d/%d", pagenum, GetNumPages())
				end,
			},

			gui.PagingArrow{
				facing = 1,
				page = function(element)
					element:SetClass("hidden", pagenum == GetNumPages())
				end,
				click = function(element)
					SetPage(pagenum+1)
				end,
			},
		},
	}

	return resultPanel
end

local customStringsTable = "langstring"

RegisterGameType("langstring")

langstring.name = "Translation"

function langstring.Create(str)
	return langstring.new{
		text = str
	}
end

function langstring:TranslationStrings()
	return {
		key = self.text
	}
end

dmhub.AddCustomTranslationString = function(labelTarget, str)


	local lang = dmhub.GetSettingValue("lang")
	if lang == nil or lang == "" then
		return
	end

	lang = i18n.LanguageIDToKey(lang)
	if lang == nil then
		printf("NO LANGUAGE FOUND")
		return
	end

	local translation = i18n.GetTranslation(lang)
	if translation == nil then
		return
	end

	local have = false
	local strings = i18n.GetStrings()
	for _,existing in ipairs(strings) do
		if existing == str then
			have = true
			break
		end
	end

	if not have then
		local entry = langstring.Create(str)
		dmhub.SetAndUploadTableItem(customStringsTable, entry)
	end

	local m_text = nil

	printf("DETECT:: CREATE")

	local dialog
	dialog = gui.Panel{
		width = "100%",
		height = "100%",
		bgimage = "panels/square.png",
		bgcolor = "#000000f2",
		styles = Styles.default,

		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,

		gui.Panel{
			halign = "center",
			valign = "center",
			flow = "vertical",
			width = 600,
			height = 600,

			gui.Panel{
				halign = "center",
				valign = "center",
				width = 620,
				height = 400,
				vscroll = true,
				gui.Label{
					halign = "center",
					valign = "top",
					maxWidth = 600,
					width = "auto",
					height = "auto",
					text = " " .. str,
					color = "white",
					fontSize = 18,
				},
			},

			gui.Input{
				width = 500,
				height = "auto",
				maxHeight = 300,
				multiline = true,
				fontSize = 18,
				text = translation:GetString(str),
				placeholderText = "Enter translated text...",
				edit = function(element)
					m_text = element.text
				end,
				change = function(element)
					m_text = element.text
				end,
			}
		},

		gui.Panel{
			halign = "center",
			valign = "bottom",
			flow = "horizontal",
			width = 800,
			height = 40,
			vmargin = 80,
			gui.Button{
				halign = "center",
				text = "Confirm",
				click = function(element)
					if m_text ~= nil then
						translation:SetString(str, m_text)
						i18n.UploadTranslation(lang, translation)
						if labelTarget ~= nil and labelTarget.valid then
							labelTarget:RefreshText()
						end
					end
					gui.CloseModal()
				end,
			},
			gui.Button{
				halign = "center",
				text = "Cancel",
				click = function(element)
					gui.CloseModal()
				end,
			},
		}

	}

	gui.ShowModal(dialog)
end
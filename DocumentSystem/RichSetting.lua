local mod = dmhub.GetModLoading()

---@class RichSetting: RichTag
RichSetting = RegisterGameType("RichSetting", "RichTag")
RichSetting.tag = "setting"
RichSetting.pattern = "setting:(?<settingid>[a-zA-Z0-9_ -]+)"
RichSetting.hasEdit = false

--CreateSettingsEditor is shared app-wide; re-colour by cascade from here, never edit it.
local function SettingStyles(pal)
    local styles = {}

    if pal ~= nil then
        styles[#styles + 1] = { selectors = {"label", "~button"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"formLabel"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"checkboxLabel"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"checkBackground"}, bgcolor = pal.page, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"checkMark"}, bgcolor = pal.accent }
        styles[#styles + 1] = { selectors = {"dropdown"}, bgcolor = pal.page, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"dropdown-option"}, bgcolor = pal.page, color = pal.ink }
        styles[#styles + 1] = { selectors = {"dropdown-option", "hover"}, bgcolor = pal.wash }
        styles[#styles + 1] = { selectors = {"dropdownLabel"}, color = pal.ink }
        styles[#styles + 1] = { selectors = {"enumSliderOption"}, bgcolor = pal.page, color = pal.ink, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"enumSliderOption", "selected"}, bgcolor = pal.accent, color = pal.page }
        styles[#styles + 1] = { selectors = {"sliderFill"}, bgcolor = pal.accent }
    end

    return ThemeEngine.MergeTokens(styles)
end

function RichSetting.CreateDisplay(self)
    local resultPanel
    local m_palSignature = nil

    resultPanel = gui.Panel{
        width = 500,
        height = "auto",
        halign = "left",
        styles = SettingStyles(nil),

        refreshTag = function(element, tag, match)
            --Reassign only when the palette changes; refreshTag fires every render.
            local pal = MarkdownDocument.PageSkinPalette((tag or self):GetDocument())
            local sig = pal ~= nil and (pal.page .. "/" .. pal.ink .. "/" .. pal.accent) or nil
            if sig ~= m_palSignature then
                m_palSignature = sig
                element.styles = SettingStyles(pal)
            end

            if match ~= nil and match.settingid ~= element.data.settingid then
                local settingid = match.settingid
                if Settings[settingid] == nil then
                    settingid = string.lower(settingid)
                    if Settings[settingid] == nil then
                        for key,settingInfo in pairs(Settings) do
                            if settingInfo.description ~= nil and string.lower(settingInfo.description) == settingid then
                                settingid = key
                                break
                            end
                        end
                    end
                end
                element.data.settingid = match.settingid
                if Settings[settingid] ~= nil then
                    element.children = {
                        CreateSettingsEditor(settingid)
                    }
                else
                    print("SETTING:: Could not find setting:", settingid)
                end
            end
        end,
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichSetting)
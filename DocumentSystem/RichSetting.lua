local mod = dmhub.GetModLoading()

---@class RichSetting: RichTag
RichSetting = RegisterGameType("RichSetting", "RichTag")
RichSetting.tag = "setting"
RichSetting.pattern = "setting:(?<settingid>[a-zA-Z0-9_ -]+)"
RichSetting.hasEdit = false

function RichSetting.CreateDisplay(self)
    local resultPanel

    resultPanel = gui.Panel{
        width = 500,
        height = "auto",
        halign = "left",
        
        refreshTag = function(element, tag, match)
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
local mod = dmhub.GetModLoading()

--- @class DamageFlag: GameType
--- @field tableName string Data table name ("damageFlags").
--- @field name string Flag name (e.g. "magical"). Stored lowercase in DamageFlag.Flags.
--- @field Flags table<string, DamageFlag> Cached map of lowercase flag name to DamageFlag object.
DamageFlag = RegisterGameType("DamageFlag")

function DamageFlag.CreateNew()
    return DamageFlag.new{
        id = dmhub.GenerateGuid(),
    }
end

DamageFlag.tableName = "damageFlags"
DamageFlag.name = "magical"

DamageFlag.Flags = {}

dmhub.RegisterEventHandler("refreshTables", function()
    local t = dmhub.GetTable(DamageFlag.tableName) or {}
    for k,v in pairs(t) do
        if v.name == nil then
            dmhub.Debug(string.format("ERROR:: Found %s", json(v)))
        end
        DamageFlag.Flags[string.lower(v.name)] = v
    end
end)

function DamageFlag.CreateEditor()
    local currentItem = nil

    local resultPanel

    resultPanel = gui.Panel{
        classes = {"collapsed"},
        styles = {Styles.Form},
        flow = "vertical",
        halign = "left",
        vscroll = true,
        width = 340,
        height = 900,

        data = {
            SetDamageFlag = function(tableName, guid)
                local t = dmhub.GetTable(tableName) or {}
                local item = t[guid]
                if item == nil then
                    resultPanel:SetClass("collapsed", true)
                    return
                end

                currentItem = item

                resultPanel:SetClass("collapsed", false)
                resultPanel:FireEventTree("refreshFlag", item)
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
                refreshFlag = function(element, item)
                    element.text = item.name
                end,
                change = function(element)
                    currentItem.name = element.text
                    dmhub.SetAndUploadTableItem(DamageFlag.tableName, currentItem)
                end,
            }
        }
    }

    return resultPanel
end
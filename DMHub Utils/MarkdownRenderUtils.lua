local mod = dmhub.GetModLoading()

local g_registry = {}
local g_tableRegistry = {}

MarkdownRender = {

    Register = function(obj)
        g_registry[obj.typeName] = true
    end,

    RegisterTable = function(options)
        g_tableRegistry[options.tableName] = options
    end,

    FindTableFromPrefix = function(prefix)
        for tableName, tableInfo in pairs(g_tableRegistry) do
            if prefix == tableInfo.prefix then
                return tableInfo.tableName
            end
        end

        return nil
    end,

    -- Returns a list of {prefix, tableName} for all registered markdown tables.
    GetRegisteredPrefixes = function()
        local result = {}
        for tableName, tableInfo in pairs(g_tableRegistry) do
            result[#result+1] = {
                prefix = tableInfo.prefix,
                tableName = tableName,
            }
        end
        return result
    end,

    IsRenderable = function(obj)
        return type(obj) == "table" and g_registry[obj.typeName] == true
    end,

    RenderToMarkdown = function(obj, options)
        if g_registry[obj.typeName] ~= true then
            return nil
        end

        options = options or {}
        local doc = obj:RenderToMarkdown(options)
        doc.readonly = true
        return doc

    end,

    RenderToPanel = function(obj, options)
        local doc = MarkdownRender.RenderToMarkdown(obj, options)
        if doc == nil then
            return nil
        end

        return doc:DisplayPanel{
            width = options.width or "100%",
            height = options.height or "auto",
            vscroll = options.vscroll or false,
            noninteractive = options.noninteractive,
        }
    end,
}
local mod = dmhub.GetModLoading()


RegisterGameType("CompendiumReference")

CompendiumReference.targetTable = ""
CompendiumReference.targetid = ""
CompendiumReference.targetPath = "/"

local knownTables = {
    "classes",
    "races",
    "subraces",
    "subclasses",
}

local function SearchObject(obj, feature, path)
    if feature == obj or (rawget(feature, "id") == rawget(obj, "id") and rawget(feature, "id") ~= nil) then
        return path
    end

    if #path > 15 then
        print("RESOLVE:: RECURSE", path)
        return
    end

    for key,value in pairs(obj) do
        if type(value) == "table" and not string.starts_with(key, "_tmp_") then
            path[#path+1] = key
            local result = SearchObject(value, feature, path)
            if result ~= nil then
                return result
            end
            path[#path] = nil
        end
    end

    return nil
end

function CompendiumReference.CreateFromObject(feature)
    print("RESOLVE::", feature)
    for _,tableName in ipairs(knownTables) do
        local t = GetTableCached(tableName)
        if t ~= nil then
            for key,value in pairs(t) do
                local path = SearchObject(value, feature, {})
                print("RESOLVE:: RESULTS:", tableName, key, path)
                if path ~= nil then
                    return CompendiumReference.new{
                        targetTable = tableName,
                        targetid = key,
                        targetPath = table.concat(path, "/"),
                    }
                end
            end
        end
    end
end

function CompendiumReference:Resolve()
    local t = GetTableCached(self.targetTable)
    if t ~= nil then
        local obj = t[self.targetid]
        local pathParts = string.split(self.targetPath, "/")
        print("REF:: RESOLVING FOR", obj, "PATH:", self.targetPath, pathParts)
        for _,part in ipairs(pathParts) do
            if part ~= "" then
                part = tonumber(part) or part
                if obj == nil then
                    return nil
                end

                obj = obj[part]
                print("REF:: PART", part, "RESOLVE TO", obj)
            end
        end

        return obj
    end
end
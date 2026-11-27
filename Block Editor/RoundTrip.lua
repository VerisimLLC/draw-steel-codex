local mod = dmhub.GetModLoading()

--[[
    BERoundTrip: the Block Editor's round-trip check (/blockroundtrip), the
    gate for build phase 2. It opens every class and subclass ability as
    blocks and saves it back without an edit; each must come back identical
    (dmhub.DeepEqual, so a number saved as a string still counts as changed).

    "/blockroundtrip forced" saves every piece through its writer as if it had
    been edited, to test that writers keep what they do not claim.

    The report also counts how many abilities open with no Advanced block
    (every step read by a real block), which rises as phase 2 adds blocks.
]]

--- @class BERoundTrip
BERoundTrip = {}

--the tables whose abilities the check covers: the core class content.
local TABLES = { "classes", "subclasses" }
--how many differences the report spells out.
local REPORT_DIFFS = 5

--- Every top-level ability in the class tables, with where it was found.
--- An ability inside another (a follow-up) is checked as part of its parent.
--- @return {ability: table, where: string}[]
function BERoundTrip.Abilities()
    local result = {}
    local seen = {}
    local function Walk(obj, where, depth)
        if (type(obj) ~= "table" and type(obj) ~= "userdata") or depth > 16 or seen[obj] then
            return
        end
        seen[obj] = true
        local typeName = nil
        pcall(function() typeName = obj.typeName end)
        if typeName == "ActivatedAbility" then
            if rawget(obj, "categorization") ~= "Hidden" then
                result[#result + 1] = { ability = obj, where = where }
            end
            return
        end
        pcall(function()
            for _, value in pairs(obj) do
                if type(value) == "table" then
                    Walk(value, where, depth + 1)
                end
            end
        end)
    end
    for _, tableName in ipairs(TABLES) do
        for _, row in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
            Walk(row, string.format("%s/%s", tableName, tostring(row.name)), 0)
        end
    end
    return result
end

--- The first class or subclass ability with this name (any case), or nil.
--- @param name string
--- @return table|nil
function BERoundTrip.FindAbility(name)
    local wanted = string.lower(name)
    for _, entry in ipairs(BERoundTrip.Abilities()) do
        local abilityName = rawget(entry.ability, "name")
        if type(abilityName) == "string" and string.lower(abilityName) == wanted then
            return entry.ability
        end
    end
    return nil
end

--- Runs the check.
--- @param forced? boolean save every piece through its writer
--- @return {total: integer, identical: integer, allBlocks: integer, locked: table<string, integer>, failures: {name: string, where: string, diff: string}[]}
function BERoundTrip.Run(forced)
    local host = Block.Get("host", "ability") --[[@as BlockHost|nil]]
    local report = { total = 0, identical = 0, allBlocks = 0, locked = {}, failures = {} }
    if host == nil then
        dmhub.Error("BlockEditor: no ability host is registered.")
        return report
    end
    for _, entry in ipairs(BERoundTrip.Abilities()) do
        local ability = entry.ability
        report.total = report.total + 1
        local ok, model = pcall(BERecordCache.Open, ability, host)
        local same, diff = false, nil
        if ok then
            local saveOk, result, resultDiff = pcall(BERecordCache.SavesUnchanged, model, ability, host, forced)
            if saveOk then
                same, diff = result, resultDiff
            else
                diff = { error = tostring(result) }
            end
            local advanced = false
            for _, instance in ipairs(model.blocks) do
                if instance.block == host.advancedBlock then
                    advanced = true
                end
            end
            if not advanced then
                report.allBlocks = report.allBlocks + 1
            end
            for slotId, _ in pairs(model.locked or {}) do
                report.locked[slotId] = (report.locked[slotId] or 0) + 1
            end
        else
            diff = { error = tostring(model) }
        end
        if same then
            report.identical = report.identical + 1
        else
            report.failures[#report.failures + 1] = {
                name = tostring(rawget(ability, "name")),
                where = entry.where,
                diff = string.sub(json(diff), 1, 400),
            }
        end
    end
    return report
end

--- The report as lines of text.
--- @param report table from BERoundTrip.Run
--- @param forced boolean
--- @return string
function BERoundTrip.Describe(report, forced)
    local lines = {
        string.format("Block Editor round trip%s: %d of %d abilities save back identical; %d open with every step as a block.",
            forced and " (forced through the writers)" or "", report.identical, report.total, report.allBlocks),
    }
    local locked = {}
    for slotId, count in pairs(report.locked) do
        locked[#locked + 1] = string.format("%s %d", slotId, count)
    end
    if #locked > 0 then
        table.sort(locked)
        lines[#lines + 1] = "Header slots shown but not written (their writer could not reproduce the saved form): " .. table.concat(locked, ", ")
    end
    for i, failure in ipairs(report.failures) do
        if i > REPORT_DIFFS then
            lines[#lines + 1] = string.format("... and %d more.", #report.failures - REPORT_DIFFS)
            break
        end
        lines[#lines + 1] = string.format("Changed: %s (%s): %s", failure.name, failure.where, failure.diff)
    end
    return table.concat(lines, "\n")
end

Commands.RegisterMacro{
    name = "blockroundtrip",
    summary = "check every class ability saves back unchanged (developers)",
    doc = "Usage: /blockroundtrip [forced]\nOpens every class and subclass ability as blocks and saves it back without an edit, and reports how many come back identical and how many open with every step as a block. \"forced\" saves every piece through its writer as if edited. Developer mode only.",
    command = function(str)
        if not BlockEditor._isDeveloper() then
            dmhub.Log("The Block Editor is in development: turn on developer mode to run its checks.")
            return
        end
        local forced = trim(str or "") == "forced"
        local text = BERoundTrip.Describe(BERoundTrip.Run(forced), forced)
        print(text)
        dmhub.Log(text)
    end,
}

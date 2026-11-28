local mod = dmhub.GetModLoading()

--[[
    BERoundTrip: the Block Editor's round-trip check (/blockroundtrip), the
    gate for build phase 2. It opens every record a host lists (host.records:
    the ability host lists the class and subclass abilities) as blocks and
    saves it back without an edit; each must come back identical
    (dmhub.DeepEqual, so a number saved as a string still counts as changed).

    "/blockroundtrip forced" saves every piece through its writer as if it had
    been edited, to test that writers keep what they do not claim.

    The report also counts how many abilities open with no Advanced block
    (every step read by a real block), which rises as phase 2 adds blocks.
]]

--- @class BERoundTrip
BERoundTrip = {}

--how many differences the report spells out.
local REPORT_DIFFS = 5

--- The hosts the check covers: those that list their records.
--- @return BlockHost[]
local function _hosts()
    local result = {}
    for _, host in ipairs(Block.All("host")) do
        --- @cast host BlockHost
        if host.records ~= nil and host.fields ~= nil then
            result[#result + 1] = host
        end
    end
    return result
end

--- The first record of any host with this name (any case), and its host.
--- @param name string
--- @return table|nil record, BlockHost|nil host
function BERoundTrip.Find(name)
    local wanted = string.lower(name)
    for _, host in ipairs(_hosts()) do
        local ok, records = pcall(host.records)
        for _, entry in ipairs(ok and records or {}) do
            local recordName = rawget(entry.record, "name")
            if type(recordName) == "string" and string.lower(recordName) == wanted then
                return entry.record, host
            end
        end
    end
    return nil, nil
end

--- Whether a list (or anything inside it) holds an Advanced block, and
--- whether it holds tier words no tier block reads.
--- @param list BlockInstance[]|nil
--- @param advancedBlock string|nil
--- @return boolean advanced, boolean words
local function _scan(list, advancedBlock)
    local advanced, words = false, false
    for _, instance in ipairs(list or {}) do
        local decl = Block.GetBlock(instance.block)
        if instance.block == advancedBlock then
            advanced = true
        elseif decl ~= nil and decl.unread then
            words = true
        end
        for _, body in pairs(instance.bodies or {}) do
            local innerAdvanced, innerWords = _scan(body, advancedBlock)
            advanced = advanced or innerAdvanced
            words = words or innerWords
        end
    end
    return advanced, words
end

--- How many of each block a list holds, inside other blocks too.
--- @param list BlockInstance[]|nil
--- @param counts? table<string, integer>
--- @return table<string, integer>
local function _counts(list, counts)
    counts = counts or {}
    for _, instance in ipairs(list or {}) do
        counts[instance.block] = (counts[instance.block] or 0) + 1
        for _, body in pairs(instance.bodies or {}) do
            _counts(body, counts)
        end
    end
    return counts
end

--- Checks one record and adds it to the report.
--- @param host BlockHost
--- @param entry {record: table, where: string, group?: string}
--- @param forced? boolean
--- @param report table
function BERoundTrip._check(host, entry, forced, report)
    local ability = entry.record
    report.total = report.total + 1
    local groupId = entry.group or string.match(entry.where or "", "^([^/]+)") or "other"
    local group = report.groups[groupId]
    if group == nil then
        group = { total = 0, identical = 0, allBlocks = 0 }
        report.groups[groupId] = group
    end
    group.total = group.total + 1
    local ok, model = pcall(BERecordCache.Open, ability, host)
    local same, diff = false, nil
    if ok then
        local saveOk, result, resultDiff = pcall(BERecordCache.SavesUnchanged, model, ability, host, forced)
        if saveOk then
            same, diff = result, resultDiff
        else
            diff = { error = tostring(result) }
        end
        local advanced, words = _scan(model.blocks, host.advancedBlock)
        if not advanced then
            report.allBlocks = report.allBlocks + 1
            group.allBlocks = group.allBlocks + 1
            if not words then
                report.allRead = report.allRead + 1
            end
        end
        for blockId, count in pairs(_counts(model.blocks)) do
            report.blocks[blockId] = (report.blocks[blockId] or 0) + count
        end
        for slotId, _ in pairs(model.locked or {}) do
            report.locked[slotId] = (report.locked[slotId] or 0) + 1
        end
    else
        diff = { error = tostring(model) }
    end
    if same then
        report.identical = report.identical + 1
        group.identical = group.identical + 1
    else
        report.failures[#report.failures + 1] = {
            name = tostring(rawget(ability, "name")),
            where = entry.where,
            diff = string.sub(json(diff), 1, 400),
        }
    end
end

--- Runs the check over every host that lists its records.
--- @param forced? boolean save every piece through its writer
--- @return {total: integer, identical: integer, allBlocks: integer, allRead: integer, blocks: table<string, integer>, locked: table<string, integer>, failures: {name: string, where: string, diff: string}[], groups: table<string, {total: integer, identical: integer, allBlocks: integer}>}
function BERoundTrip.Run(forced)
    local report = { total = 0, identical = 0, allBlocks = 0, allRead = 0, blocks = {}, locked = {}, failures = {}, groups = {} }
    local hosts = _hosts()
    if #hosts == 0 then
        dmhub.Error("BlockEditor: no host lists its records for the round trip.")
        return report
    end
    for _, host in ipairs(hosts) do
        local listed, records = pcall(host.records)
        for _, entry in ipairs(listed and records or {}) do
            BERoundTrip._check(host, entry, forced, report)
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
        string.format("Block Editor round trip%s: %d of %d abilities save back identical; %d open with every step as a block (%d of them with every tier word read too).",
            forced and " (forced through the writers)" or "", report.identical, report.total, report.allBlocks, report.allRead),
    }
    --one line per group (a table, or monsters), largest first.
    local groups = {}
    for groupId, group in pairs(report.groups or {}) do
        groups[#groups + 1] = { id = groupId, group = group }
    end
    table.sort(groups, function(a, b) return a.group.total > b.group.total end)
    for _, entry in ipairs(groups) do
        local group = entry.group
        lines[#lines + 1] = string.format("  %s: %d of %d identical, %d fully as blocks", entry.id, group.identical, group.total, group.allBlocks)
    end
    local used = {}
    for blockId, count in pairs(report.blocks or {}) do
        used[#used + 1] = { id = blockId, count = count }
    end
    table.sort(used, function(a, b) return a.count > b.count end)
    local usedText = {}
    for i, entry in ipairs(used) do
        usedText[i] = string.format("%s %d", entry.id, entry.count)
    end
    if #usedText > 0 then
        lines[#lines + 1] = "Blocks opened: " .. table.concat(usedText, ", ")
    end
    local locked = {}
    for slotId, count in pairs(report.locked) do
        locked[#locked + 1] = string.format("%s %d", slotId, count)
    end
    if #locked > 0 then
        table.sort(locked)
        lines[#lines + 1] = "Header slots shown but not written (their writer failed, or what it wrote did not read back the same): " .. table.concat(locked, ", ")
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
            dmhub.Log("The Block Editor is in development: turn on developer mode and the Block Editor setting (developer settings) to run its checks.")
            return
        end
        local forced = trim(str or "") == "forced"
        local text = BERoundTrip.Describe(BERoundTrip.Run(forced), forced)
        dmhub.Log(text)
    end,
}

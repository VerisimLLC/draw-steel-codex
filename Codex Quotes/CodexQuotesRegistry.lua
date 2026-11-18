local mod = dmhub.GetModLoading()

CodexQuotes = {
    quotes = {},
    --ids in the order they were registered, so the Developer preview can step
    --through the quotes in file order.
    ordered = {},
}

CodexQuotes.Register = function(entry)
    if CodexQuotes.quotes[entry.id] == nil then
        CodexQuotes.ordered[#CodexQuotes.ordered + 1] = entry.id
    end
    CodexQuotes.quotes[entry.id] = entry
end

CodexQuotes.SelectQuote = function()
    local entries = table.values(CodexQuotes.quotes)
    if #entries == 0 then
        return nil
    end
    local result = entries[math.random(1, #entries)]
    return result
end

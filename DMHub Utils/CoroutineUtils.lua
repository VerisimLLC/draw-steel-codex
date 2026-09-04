local mod = dmhub.GetModLoading()

function coroutine.safe_sleep_while(predicate)
    if not dmhub.inCoroutine then
        print("coroutine.safe_sleep_while() must be called from a coroutine")
        return
    end

    if not dmhub.canSafelyYield then
        print("coroutine.safe_sleep_while() called in a non-yielding context")
        return
    end

    while predicate() do
        coroutine.yield()
    end
end

function sleep(seconds)
    local start = dmhub.Time()
    local target = start + seconds
    while dmhub.Time() < target do
        coroutine.yield()
    end

    return dmhub.Time() - start
end
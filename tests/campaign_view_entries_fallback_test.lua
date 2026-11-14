--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/campaign_view_entries_fallback_test.lua
--The title screen's Campaigns list comes from CampaignRearrange.ViewEntries.
--On an engine build without lobby.accountGameIds it must still list the
--loaded games (as ViewGames does), not come back empty.
local path = 'Codex Titlescreen/CodexCampaignRearrange.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, message)
end

--Engine stubs are set through stub() so LuaLS does not retype the real globals.
local function stub(name, value) rawset(_G, name, value) end
stub('dmhub', {
    GetModLoading = function() return {} end,
    loginUserid = 'me',
})
stub('RegisterGameType', function() return {} end)
stub('setting', function() return { Get = function() return '' end } end)

local games = {
    {gameid = 'g1', owner = 'me', description = 'Mine 1'},
    {gameid = 'g2', owner = 'other', description = 'Theirs'},
    {gameid = 'g3', owner = 'me', description = 'Mine 2'},
}
--An older engine: games are loaded, but there is no accountGameIds and no
--IsGameSummaryPending.
stub('lobby', {games = games})

assert(load(source, '@' .. path))()
local CR = rawget(_G, 'CampaignRearrange')

local director = CR.ViewEntries(true)
check(#director == 2, 'Director view: expected 2 owned games without lobby.accountGameIds, got ' .. #director)
check(director[1] and director[1].gameid == 'g1' and director[2] and director[2].gameid == 'g3',
    'Director view: expected owned games g1, g3 in engine order')

local player = CR.ViewEntries(false)
check(#player == 1, 'Player view: expected 1 joined game without lobby.accountGameIds, got ' .. #player)
check(player[1] and player[1].gameid == 'g2', 'Player view: expected joined game g2')

--A newer engine still uses the account order and placeholders.
stub('lobby', {
    games = {games[1]},
    accountGameIds = {'g9', 'g1'},
    IsGameSummaryPending = function(self, id) return id == 'g9' end,
})
local newer = CR.ViewEntries(true)
check(#newer == 2, 'Newer engine: expected placeholder + loaded game, got ' .. #newer)
check(CR.IsPlaceholder(newer[1]) and newer[1].gameid == 'g9', 'Newer engine: expected g9 placeholder first')
check(newer[2] == games[1], 'Newer engine: expected loaded g1 second')

print('campaign_view_entries_fallback: ' .. checks .. ' checks passed')

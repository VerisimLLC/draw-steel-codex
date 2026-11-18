local mod = dmhub.GetModLoading()

--Michael Ghelfi Studios (MGS) partner audio: connect a user's MGS account, read what
--they may use (their manifest), play previews, and add a track they own to the current
--game so the whole table hears it (MGS allows one owner to share a track within a game).
--
--Credentials: the user's device token ("mgsdt_...") is kept with dmhub.SetLocalSecret,
--on this machine only, and every request that carries it is quiet (kept out of logs).
--
--Browsing: a connected user sees MGS's manifest, which marks what their account may use.
--Anyone else sees the whole library from our partnerAudioCatalogue cloud function (MGS's
--catalogue key stays on our server, never in the app), with nothing usable, and can
--still play previews, which MGS allows without an account.
--
--Storage: a track goes into R2 once. The first owner to add it downloads it from MGS
--and uploads it; the partnerAudioRegistry cloud function then records that blob, and
--anyone else who owns the track reuses it in any game without downloading again.
--
--API doc: codexsteel-api.md from MGS (device code flow, manifest, downloads, previews).

--- @class MGSTrack
--- @field id string MGS track id
--- @field title string
--- @field kind string "music", "effects" or "ambience" (the anthem picker's categories)
--- @field genre string
--- @field composer string
--- @field duration number seconds
--- @field entitled boolean the user may download it
--- @field accessUrl nil|string where to get access (Patreon tier or album purchase)
--- @field tier nil|string the Patreon tier that includes it, e.g. "Guardian"
--- @field album nil|string the album to buy for it, when it is sold as an album
--- @field free boolean any free MGS account includes it
--- @field search string lower-case text a search matches against

--- @class MGSAudio
MGSAudio = {}

local BASE_URL = "https://michaelghelfistudios.com/api/music"
local CLIENT = "codexsteel"
local SECRET_KEY = "mgs-device-token"
--the format added to games: mp3 plays without transcoding (Opus would be re-encoded).
local ADD_FORMAT = "mp3_320"
local ADD_EXTENSION = "mp3"
--MGS's terms: at most this many previews a day for users without a subscription.
local FREE_PREVIEWS_PER_DAY = 100
local PREVIEW_CACHE_LIMIT = 200

--previews already on disk, by track id: {[trackId] = path}.
local g_previewCache = setting{
    id = "mgs:previewfiles",
    description = "Michael Ghelfi Studios previews on this machine",
    storage = "preference",
    default = {},
}

--previews fetched today, for the daily cap: {day = "2026-11-15", count = 3}.
local g_previewCount = setting{
    id = "mgs:previewcount",
    description = "Michael Ghelfi Studios previews fetched today",
    storage = "preference",
    default = {},
}

local KIND_BY_TYPE = {
    music = "music",
    sfx = "effects",
    ambience = "ambience",
}

--- "unknown" before the first load, then "loading", "ready" or "unavailable" (MGS
--- switched the partnership off, or the library could not be reached).
local g_state = "unknown"
--- where g_tracks came from: "manifest" (connected), "catalogue" (not) or nil.
--- @type nil|string
local g_source = nil
--- when the catalogue was loaded (dmhub.Time()), to reload it in a long session.
local g_catalogueAt = 0
--- how long a loaded catalogue is kept before the picker reloads it.
local CATALOGUE_KEEP_SECONDS = 6 * 3600
--- @type nil|string
local g_token = nil
local g_tokenLoaded = false
--- @type nil|{id: number, display_name: string}
local g_user = nil
local g_subscribed = false
--- @type MGSTrack[]
local g_tracks = {}
--- @type table<string, MGSTrack>
local g_byId = {}
--- @type nil|string
local g_stamp = nil
--- @type table<table, fun()>
local g_watchers = {}
--- @type table<string, boolean> tracks being added to the game now
local g_adding = {}

local function Changed()
    for _, fn in pairs(g_watchers) do
        fn()
    end
end

--- Repaint fn whenever the connection or the manifest changes; owner keys it.
--- @param owner table
--- @param fn nil|fun()
function MGSAudio.Watch(owner, fn)
    g_watchers[owner] = fn
end

local function Token()
    if not g_tokenLoaded then
        g_tokenLoaded = true
        g_token = dmhub.GetLocalSecret(SECRET_KEY)
    end
    return g_token
end

--- @param withToken boolean
--- @return table<string, string>
local function Headers(withToken)
    local platform = "Windows"
    if dmhub.platform == "macOS" then
        platform = "macOS"
    elseif dmhub.platform == "linux" then
        platform = "Linux"
    end
    local headers = {
        ["X-MGS-Client"] = CLIENT,
        ["User-Agent"] = string.format("CodexSteel/%s (%s)", tostring(dmhub.version), platform),
    }
    local token = Token()
    if withToken and token ~= nil then
        headers["Authorization"] = "Bearer " .. token
    end
    return headers
end

local function Forget()
    dmhub.SetLocalSecret(SECRET_KEY, nil)
    g_token = nil
    g_user = nil
    g_subscribed = false
    g_tracks = {}
    g_byId = {}
    g_source = nil
    g_stamp = nil
    g_state = "unknown"
    Changed()
    MGSAudio.Refresh()
end

--- A token call failed: 401 means the user revoked this install at MGS; a disabled
--- partnership keeps the token for later.
--- @param status integer
--- @param body nil|table
local function TokenFailed(status, body)
    local code = type(body) == "table" and body.code or nil
    if status == 401 then
        Forget()
    elseif code == "CLIENT_DISABLED" or code == "PARTNER_DISABLED" or code == "client_disabled" then
        g_state = "unavailable"
        Changed()
    end
end

--- The message of an MGS error response, for a message box.
--- @param message string
--- @param body nil|table
--- @return string
local function ErrorText(message, body)
    if type(body) == "table" and type(body.error) == "string" and body.error ~= "" then
        return body.error
    end
    return message or "Michael Ghelfi Studios could not be reached."
end

--- @return string "unknown", "loading", "ready" or "unavailable"
function MGSAudio.State()
    return g_state
end

--- @return boolean
function MGSAudio.IsConnected()
    return Token() ~= nil
end

--- The connected MGS account's name, or nil.
--- @return nil|string
function MGSAudio.AccountName()
    return g_user ~= nil and g_user.display_name or nil
end

--- @return MGSTrack[]
function MGSAudio.Tracks()
    return g_tracks
end

--- @param id string
--- @return nil|MGSTrack
function MGSAudio.Track(id)
    return g_byId[id]
end

--- One manifest catalogue row as an MGSTrack.
--- @param row table
--- @return nil|MGSTrack
local function TrackFromRow(row)
    if type(row) ~= "table" or type(row.id) ~= "string" or type(row.title) ~= "string" then
        return nil
    end
    local kind = KIND_BY_TYPE[row.type or ""]
    if kind == nil then
        return nil
    end
    local words = {row.title, row.genre or "", row.composer_name or "", row.type or ""}
    for _, list in ipairs({row.keywords, row.moods, row.themes}) do
        if type(list) == "table" then
            for _, word in ipairs(list) do
                if type(word) == "string" then
                    words[#words+1] = word
                end
            end
        end
    end
    local accessUrl = nil
    if type(row.subscribe_url) == "string" and row.subscribe_url ~= "" then
        accessUrl = row.subscribe_url
    elseif type(row.buy_url) == "string" and row.buy_url ~= "" then
        accessUrl = row.buy_url
    end
    --album.title names the Patreon tier when source_type is "patreon_tier".
    local albumTitle = nil
    if type(row.album) == "table" and type(row.album.title) == "string" and row.album.title ~= "" then
        albumTitle = row.album.title
    end
    local tier, album = nil, nil
    if row.source_type == "patreon_tier" then
        tier = albumTitle
    elseif type(row.buy_url) == "string" and row.buy_url ~= "" then
        album = albumTitle
    end
    return {
        id = row.id,
        title = row.title,
        kind = kind,
        genre = (type(row.genre) == "string" and row.genre ~= "" and row.genre ~= "Not Applicable") and row.genre or "Other",
        composer = type(row.composer_name) == "string" and row.composer_name or "",
        duration = tonumber(row.duration_seconds) or 0,
        entitled = row.entitled == true,
        accessUrl = accessUrl,
        tier = tier,
        album = album,
        free = row.free == true,
        search =string.lower(table.concat(words, " ")),
    }
end

--- Replace the track list with a manifest's or the catalogue's rows.
--- @param response any
--- @param source string "manifest" or "catalogue"
local function TakeRows(response, source)
    local tracks = {}
    local byId = {}
    local rows = type(response) == "table" and response.catalogue or nil
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local track = TrackFromRow(row)
            if track ~= nil then
                tracks[#tracks+1] = track
                byId[track.id] = track
            end
        end
    end
    g_tracks = tracks
    g_byId = byId
    g_source = source
    g_state = #tracks > 0 and "ready" or "unavailable"
    Changed()
end

--- Where the whole library comes from for users who are not connected. A developer can
--- point it at a local stand-in: MGSAudio.catalogueUrl = "http://127.0.0.1:8789/".
--- @type nil|string
MGSAudio.catalogueUrl = nil

--- The whole MGS library for a user who is not connected (about 300 KB gzipped).
local function LoadCatalogue()
    g_state = "loading"
    Changed()
    net.Post{
        url = MGSAudio.catalogueUrl or (dmhub.cloudFunctionsBaseUrl .. "/partnerAudioCatalogue"),
        data = {partner = "mgs"},
        --keeps the 1.5 MB reply out of the logs.
        quiet = true,
        success = function(response)
            if mod.unloaded or Token() ~= nil then
                return
            end
            g_catalogueAt = dmhub.Time()
            TakeRows(response, "catalogue")
        end,
        error = function(message, status)
            if mod.unloaded or Token() ~= nil then
                return
            end
            print(string.format("MGSAudio: catalogue failed (%s %s)", tostring(status), tostring(message)))
            g_state = "unavailable"
            Changed()
        end,
    }
end

local function LoadManifest()
    g_state = "loading"
    Changed()
    net.Get{
        url = BASE_URL .. "/sync/manifest",
        headers = Headers(true),
        quiet = true,
        success = function(response)
            if mod.unloaded then
                return
            end
            TakeRows(response, "manifest")
        end,
        error = function(message, status, body)
            if mod.unloaded then
                return
            end
            g_state = "unavailable"
            TokenFailed(status, body)
            Changed()
        end,
    }
end

--- Check the connection and bring the manifest up to date: call when the picker
--- opens. It downloads the manifest (a few MB) only when MGS says it changed.
function MGSAudio.Refresh()
    if g_state == "loading" then
        return
    end
    if Token() == nil then
        if g_source ~= "catalogue" or g_state ~= "ready" or dmhub.Time() - g_catalogueAt > CATALOGUE_KEEP_SECONDS then
            LoadCatalogue()
        end
        return
    end
    if g_user == nil then
        net.Get{
            url = BASE_URL .. "/devices/validate",
            headers = Headers(true),
            quiet = true,
            success = function(response)
                if mod.unloaded or type(response) ~= "table" then
                    return
                end
                if type(response.user) == "table" then
                    g_user = {id = response.user.id, display_name = tostring(response.user.display_name or "")}
                end
                g_subscribed = type(response.patreon) == "table" and response.patreon.active == true
                Changed()
            end,
            error = function(message, status, body)
                if not mod.unloaded then
                    TokenFailed(status, body)
                end
            end,
        }
    end
    net.Get{
        url = BASE_URL .. "/sync/manifest/stamp",
        headers = Headers(true),
        quiet = true,
        success = function(response)
            if mod.unloaded then
                return
            end
            local stamp = type(response) == "table" and (response.stamp or response.data) or nil
            if stamp ~= nil and stamp == g_stamp and #g_tracks > 0 and g_source == "manifest" then
                return
            end
            g_stamp = stamp
            LoadManifest()
        end,
        error = function(message, status, body)
            if mod.unloaded then
                return
            end
            TokenFailed(status, body)
            --no stamp: load once anyway if nothing is loaded yet.
            if Token() ~= nil and (#g_tracks == 0 or g_source ~= "manifest") then
                LoadManifest()
            end
        end,
    }
end

--- Start connecting this install to an MGS account (RFC 8628 device flow). The user
--- approves on the MGS website. Returns a handle whose cancel() stops polling.
--- @param callbacks {code: fun(userCode: string, url: string), done: fun(), fail: fun(message: string)}
--- @return {cancel: fun()}
function MGSAudio.StartConnect(callbacks)
    local handle = {cancelled = false}
    handle.cancel = function()
        handle.cancelled = true
    end
    local platform = dmhub.platform == "macOS" and "Mac" or (dmhub.platform == "linux" and "Linux" or "Windows")
    net.Post{
        url = BASE_URL .. "/devices/code",
        headers = Headers(false),
        quiet = true,
        data = {client = CLIENT, label = string.format("Draw Steel Codex (%s)", platform)},
        success = function(response)
            if mod.unloaded or handle.cancelled then
                return
            end
            if type(response) ~= "table" or type(response.device_code) ~= "string" then
                callbacks.fail("Michael Ghelfi Studios did not return a code.")
                return
            end
            local deviceCode = response.device_code
            local interval = tonumber(response.interval) or 5
            local url = response.verification_uri_complete or response.verification_uri or "https://michaelghelfistudios.com/audio/connect"
            callbacks.code(tostring(response.user_code or ""), url)

            local function Poll()
                if mod.unloaded or handle.cancelled then
                    return
                end
                net.Post{
                    url = BASE_URL .. "/devices/code/token",
                    headers = Headers(false),
                    quiet = true,
                    data = {device_code = deviceCode},
                    success = function(result)
                        if mod.unloaded or handle.cancelled then
                            return
                        end
                        local token = type(result) == "table" and result.device_token or nil
                        if type(token) ~= "string" or token == "" then
                            callbacks.fail("Michael Ghelfi Studios did not return a token.")
                            return
                        end
                        dmhub.SetLocalSecret(SECRET_KEY, token)
                        g_token = token
                        g_tokenLoaded = true
                        g_user = nil
                        g_stamp = nil
                        g_state = "unknown"
                        callbacks.done()
                        MGSAudio.Refresh()
                        Changed()
                    end,
                    error = function(message, status, body)
                        if mod.unloaded or handle.cancelled then
                            return
                        end
                        local code = type(body) == "table" and body.code or nil
                        if code == "authorization_pending" then
                            dmhub.Schedule(interval, Poll)
                        elseif code == "slow_down" then
                            interval = interval + 5
                            dmhub.Schedule(interval, Poll)
                        elseif code == "access_denied" then
                            callbacks.fail("The connection was refused on the Michael Ghelfi Studios website.")
                        elseif code == "expired_token" then
                            callbacks.fail("The code expired. Start again to get a new one.")
                        elseif status == 0 then
                            --no response (a network blip): keep trying until the code expires.
                            dmhub.Schedule(interval, Poll)
                        else
                            callbacks.fail(ErrorText(message, body))
                        end
                    end,
                }
            end
            dmhub.Schedule(interval, Poll)
        end,
        error = function(message, status, body)
            if not (mod.unloaded or handle.cancelled) then
                callbacks.fail(ErrorText(message, body))
            end
        end,
    }
    return handle
end

--- Forget this install's MGS connection. The user can also revoke it on the MGS site.
function MGSAudio.Disconnect()
    Forget()
end

local function Today()
    return os.date("!%Y-%m-%d")
end

--- True when a preview may be fetched under the daily cap (subscribers have none).
--- @return boolean
local function PreviewAllowed()
    if g_subscribed then
        return true
    end
    local count = g_previewCount:Get()
    if type(count) ~= "table" or count.day ~= Today() then
        return true
    end
    return (tonumber(count.count) or 0) < FREE_PREVIEWS_PER_DAY
end

local function CountPreview()
    local count = g_previewCount:Get()
    local today = Today()
    if type(count) ~= "table" or count.day ~= today then
        count = {day = today, count = 0}
    end
    g_previewCount:Set({day = today, count = (tonumber(count.count) or 0) + 1})
end

--- Remember a downloaded preview's path, keeping the list short.
--- @param trackId string
--- @param path string
local function RememberPreview(trackId, path)
    local cache = DeepCopy(g_previewCache:Get() or {})
    if type(cache) ~= "table" then
        cache = {}
    end
    local count = 0
    for _ in pairs(cache) do
        count = count + 1
    end
    if count >= PREVIEW_CACHE_LIMIT then
        cache = {}
    end
    cache[trackId] = path
    g_previewCache:Set(cache)
end

--- Play a track's preview (the whole track, 128 kbps). A preview fetched before plays
--- from disk. done gets the playing instance; fail a message.
--- @param trackId string
--- @param done fun(instance: SoundEventInstanceLua)
--- @param fail fun(message: string)
function MGSAudio.PlayPreview(trackId, done, fail)
    local cache = g_previewCache:Get()
    local cached = type(cache) == "table" and cache[trackId] or nil
    if type(cached) == "string" then
        local instance = assets:PlayAudioFile(cached)
        if instance ~= nil then
            done(instance)
            return
        end
    end
    --no account needed: without a token MGS limits previews per IP address instead.
    if not PreviewAllowed() then
        fail(string.format("You have played %d previews today. More are available tomorrow.", FREE_PREVIEWS_PER_DAY))
        return
    end
    net.Post{
        url = BASE_URL .. "/tracks/" .. trackId .. "/preview",
        headers = Headers(true),
        quiet = true,
        data = {},
        success = function(response)
            if mod.unloaded then
                return
            end
            local url = type(response) == "table" and response.url or nil
            if type(url) ~= "string" then
                fail("Michael Ghelfi Studios did not return a preview.")
                return
            end
            CountPreview()
            net.DownloadFile{
                url = url,
                name = "mgs-preview-" .. trackId .. ".mp3",
                success = function(path)
                    if mod.unloaded then
                        return
                    end
                    RememberPreview(trackId, path)
                    local instance = assets:PlayAudioFile(path)
                    if instance == nil then
                        fail("The preview could not be played.")
                    else
                        done(instance)
                    end
                end,
                error = function(message)
                    if not mod.unloaded then
                        fail(message or "The preview could not be downloaded.")
                    end
                end,
            }
        end,
        error = function(message, status, body)
            if mod.unloaded then
                return
            end
            TokenFailed(status, body)
            fail(ErrorText(message, body))
        end,
    }
end

--- The game's audio asset for an MGS track, if this game already has it.
--- @param trackId string
--- @return nil|string
function MGSAudio.GameAssetFor(trackId)
    for id, asset in pairs(assets.audioTable) do
        if not asset.hidden and asset.source == "mgs" and asset.sourceId == trackId then
            return id
        end
    end
    return nil
end

--- True while a track is being added to the game.
--- @param trackId string
--- @return boolean
function MGSAudio.IsAdding(trackId)
    return g_adding[trackId] == true
end

local function RegistryUrl()
    return dmhub.cloudFunctionsBaseUrl .. "/partnerAudioRegistry"
end

--- Record the blob a track was uploaded to, so other games reuse it. Best effort.
--- The upload callback runs when the server acks the asset write, which can be
--- before the record reaches assets.audioTable, so this waits for it (up to ~10s).
--- @param track MGSTrack
--- @param guid string
--- @param attempt nil|integer
local function RegisterBlob(track, guid, attempt)
    if mod.unloaded then
        return
    end
    local asset = assets.audioTable[guid]
    local audioId = asset ~= nil and asset.audioId or nil
    if audioId == nil or audioId == "" then
        attempt = (attempt or 0) + 1
        if attempt <= 20 then
            dmhub.Schedule(0.5, function()
                RegisterBlob(track, guid, attempt)
            end)
        else
            print(string.format("MGSAudio: no stored file to register for %s", track.id))
        end
        return
    end
    local data = {
        action = "put",
        partner = "mgs",
        format = ADD_FORMAT,
        trackId = track.id,
        audioId = audioId,
        extension = asset.extension or ADD_EXTENSION,
        duration = tonumber(asset.duration) or track.duration,
    }
    if asset.loudnessMeasured then
        data.loudnessLufs = asset.loudnessLufs
    end
    net.Post{
        url = RegistryUrl(),
        quiet = true,
        data = data,
        error = function(message, status)
            print(string.format("MGSAudio: registry put failed for %s (%s %s)", track.id, tostring(status), tostring(message)))
        end,
    }
end

--- Options shared by both ways of adding a track: its name, category and credit.
--- @param track MGSTrack
--- @return table
local function AssetFields(track)
    return {
        description = track.title,
        category = track.kind,
        source = "mgs",
        sourceId = track.id,
        sourceCredit = track.composer,
    }
end

--- Download the track from MGS and upload it into this game, then register its blob.
--- @param track MGSTrack
--- @param callbacks {done: fun(guid: string), fail: fun(message: string), progress: nil|fun(fraction: number)}
local function DownloadAndUpload(track, callbacks)
    net.Post{
        url = BASE_URL .. "/tracks/" .. track.id .. "/download",
        headers = Headers(true),
        quiet = true,
        data = {format = ADD_FORMAT},
        success = function(response)
            if mod.unloaded then
                return
            end
            local tokenId = type(response) == "table" and response.token_id or nil
            if type(tokenId) ~= "string" then
                callbacks.fail("Michael Ghelfi Studios did not allow the download.")
                return
            end
            net.DownloadFile{
                url = BASE_URL .. "/download/" .. tokenId,
                name = "mgs-track-" .. track.id .. "." .. ADD_EXTENSION,
                headers = Headers(true),
                progress = function(fraction)
                    if callbacks.progress ~= nil then
                        callbacks.progress(fraction * 0.5)
                    end
                end,
                success = function(path)
                    if mod.unloaded then
                        return
                    end
                    local options = AssetFields(track)
                    options.path = path
                    --the downloaded copy is only needed until it is uploaded.
                    options.deleteAfterUse = true
                    options.error = function(message)
                        callbacks.fail(message)
                    end
                    options.progress = function(percent)
                        if callbacks.progress ~= nil then
                            callbacks.progress(0.5 + (tonumber(percent) or 0) * 0.5)
                        end
                    end
                    options.upload = function(guid)
                        if mod.unloaded then
                            return
                        end
                        RegisterBlob(track, guid)
                        callbacks.done(guid)
                    end
                    local guid = assets:UploadAudioAsset(options)
                    if guid == nil then
                        callbacks.fail("The track could not be uploaded.")
                    end
                end,
                error = function(message, status, body)
                    if mod.unloaded then
                        return
                    end
                    TokenFailed(status, body)
                    callbacks.fail(ErrorText(message, body))
                end,
            }
        end,
        error = function(message, status, body)
            if mod.unloaded then
                return
            end
            TokenFailed(status, body)
            local code = type(body) == "table" and body.code or nil
            if code == "DOWNLOAD_CAP_REACHED" then
                callbacks.fail("Your Michael Ghelfi Studios download limit for this month has been reached.")
            elseif status == 403 then
                callbacks.fail("Your Michael Ghelfi Studios account does not include this track.")
            else
                callbacks.fail(ErrorText(message, body))
            end
        end,
    }
end

--- Add a track the user owns to this game (or find it if the game has it already).
--- Reuses the stored copy when one exists, else downloads and uploads it. done's
--- second argument is false when the game already had the track.
--- @param trackId string
--- @param callbacks {done: fun(guid: string, added: boolean), fail: fun(message: string), progress: nil|fun(fraction: number)}
function MGSAudio.AddToGame(trackId, callbacks)
    local existing = MGSAudio.GameAssetFor(trackId)
    if existing ~= nil then
        callbacks.done(existing, false)
        return
    end
    local track = g_byId[trackId]
    if track == nil or not track.entitled then
        callbacks.fail("Your Michael Ghelfi Studios account does not include this track.")
        return
    end
    if g_adding[trackId] then
        return
    end
    g_adding[trackId] = true
    Changed()
    local wrapped = {
        progress = callbacks.progress,
        done = function(guid)
            g_adding[trackId] = nil
            Changed()
            callbacks.done(guid, true)
        end,
        fail = function(message)
            g_adding[trackId] = nil
            Changed()
            callbacks.fail(message)
        end,
    }
    net.Post{
        url = RegistryUrl(),
        quiet = true,
        data = {action = "get", partner = "mgs", format = ADD_FORMAT, trackIds = {trackId}},
        success = function(response)
            if mod.unloaded then
                return
            end
            local record = type(response) == "table" and type(response.records) == "table" and response.records[trackId] or nil
            if type(record) ~= "table" or type(record.audioId) ~= "string" then
                DownloadAndUpload(track, wrapped)
                return
            end
            local options = AssetFields(track)
            options.audioId = record.audioId
            options.extension = record.extension or ADD_EXTENSION
            options.duration = tonumber(record.duration) or track.duration
            options.loudnessLufs = tonumber(record.loudnessLufs)
            options.upload = function(guid)
                if not mod.unloaded then
                    wrapped.done(guid)
                end
            end
            if assets:CreateAudioAssetFromBlob(options) == nil then
                DownloadAndUpload(track, wrapped)
            end
        end,
        error = function(message, status)
            if mod.unloaded then
                return
            end
            --the registry is only an optimisation: without it, download as usual.
            print(string.format("MGSAudio: registry get failed (%s %s)", tostring(status), tostring(message)))
            DownloadAndUpload(track, wrapped)
        end,
    }
end

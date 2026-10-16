---@meta

--- Client for the developer image repository (internal-dashboards /api/devimages). Admin accounts only; the server enforces it. Request speaks the JSON API; Image, UploadFile, SaveAs and Fetch move the bytes.
--- @class DevImagesLuaInterface
--- @field webUrl string The repository's web page (the Images dashboard). OpenWeb opens a path under it.
DevImagesLuaInterface = {}

--- Open the repository's web page in the browser. `path` is appended to it, e.g. "/entry/<id>" or "/requests"; nil opens the top level.
--- @param path nil|string
function DevImagesLuaInterface:OpenWeb(path) end

--- Call the repository API. `path` is under /api/devimages (e.g. "/index", "/entries/<id>"); `body` is a table sent as JSON. `complete` receives the decoded JSON reply with httpStatus added; on failure it also has `error` (a message) and usually `code` (the API's error code).
--- @param args {method: nil|string, path: string, body: nil|table, complete: nil|fun(result: table)}
function DevImagesLuaInterface:Request(args) end

--- A bgimage id for a repository image (by its SHA-256), or nil while it downloads. When it is not ready yet, the download starts and `onReady(id)` is called with the id once it is. Use it for thumbnails and previews -- not for multi-MB originals.
--- @param hash string
--- @param onReady nil|fun(id: string)
--- @return nil|string
function DevImagesLuaInterface:Image(hash, onReady) end

--- Download a repository file through a Save As dialog. `filename` is the name offered. `complete(path)` gets the saved path, or nil plus a message if it was cancelled or failed. Streams to disk, so multi-GB PSBs are fine.
--- @param args {hash: string, filename: string, complete: nil|fun(path: nil|string, error: nil|string)}
function DevImagesLuaInterface:SaveAs(args) end

--- Download a repository file into the local cache (kept by hash, so a second call is instant) under `filename`, and call `complete(path)` with its local path -- e.g. to hand a popout to assets:UploadImageAsset. On failure `complete(nil, message)`.
--- @param args {hash: string, filename: string, complete: fun(path: nil|string, error: nil|string)}
function DevImagesLuaInterface:Fetch(args) end

--- Upload a local file as a repository blob and get back the file object the attach calls take ({hash, filename, width, height, thumbHash, previewHash}) -- e.g. body for PUT /images/<id>/files/<role>. Pictures (png/jpg) also get PNG thumbnail (512) and, when bigger than 2048, preview renditions. Bytes already in the repository are not sent again. `progress(fraction, phase)` reports 'hashing' / 'uploading'. `complete(file)` or `complete(nil, message)`.
--- @param args {path: string, progress: nil|fun(fraction: number, phase: string), complete: fun(file: nil|table, error: nil|string)}
function DevImagesLuaInterface:UploadFile(args) end

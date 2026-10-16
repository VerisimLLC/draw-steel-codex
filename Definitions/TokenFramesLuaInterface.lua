---@meta

--- Registry of premium token frame materials. Register{...} defines a frame; a token uses it by setting token.portraitFrameMaterial to the id and token.portraitFrame to the entry's albedo asset. `frames` is iterable from Lua (`for id, entry in pairs(dmhub.tokenFrames.frames) do ... end`).
--- @class TokenFramesLuaInterface
--- @field cloudFrames any Map of frame id -> entry table for every frame in the cloud catalogue (/CoreAssetsCurrent/tokenframes) that is not hidden. These are the frames the Token Studio has uploaded; they are registered automatically on asset refresh, so they are also in `frames`.
--- @field frames any Map of registered frame id -> entry table (the table passed to Register). Iterable from Lua.
TokenFramesLuaInterface = {}

--- Register a premium frame material. `albedo` is the frame image asset (an AvatarFrame image with a transparent interior; the token's portraitFrame must be set to it too). `normal` is a tangent-space normal map stored as raw RGB (loaded linear), `roughness` packs roughness in R and metallic in G, `matcap` is an optional sphere-lit environment image. All are cloud image asset guids. `params` tunes the shading: normalStrength, specStrength, fresnelPower, cameraReactivity (how much the view angle changes across the viewport), eyeHeight (virtual eye height in viewport half-heights), roughness / metallic (used when no roughness map), matcapStrength, ambient, lightFollowsTimeOfDay (0..1 blend toward the map's sun), lightDir {x,y,z} (fallback/fixed light, +z toward the camera), sheenColor and lightColor ("#rrggbb" or {r,g,b}), sheenFromAlbedo (0..1: metal reflections take the frame's own colour instead of sheenColor; use 1 for coloured chrome) and albedoSheenBoost (brightens the albedo-derived reflection colour, default 1.6). HDR: the map is bloomed above 1.0, so hdrGlow (extra brightness of matcap texels above glowThreshold, default 0 / 0.7) and specGlow (extra specular peak, default 0) make just the highlights bloom. rimStrength (default 1) scales the Fresnel rim on its own: it depends only on the ring's tilt, so on a smooth dome it draws a circle at the steepest radius; 0 removes it while keeping the specular.
--- @param entry table { id: string, name: string|nil, albedo: string, normal: string|nil, roughness: string|nil, matcap: string|nil, flipNormalY: boolean|nil, params: table|nil }
function TokenFramesLuaInterface:Register(entry) end

--- Returns the registered entry table for a frame id, or nil if no such frame is registered.
--- @param id string
--- @return table|nil
function TokenFramesLuaInterface:Get(id) end

--- ADMIN ONLY. Uploads a frame definition (the same table shape Register takes) to the core asset store at /CoreAssetsCurrent/tokenframes/{id}, so every client registers it on its next asset refresh -- the token-frame analogue of a Dice Studio upload. Mints entry.id when it is empty. The image assets the entry references (albedo, normal, roughness, matcap) are promoted into the core image store so other clients can resolve their guids. Also registers the entry locally at once. Returns the frame id, or nil if the account is not an admin or the entry has no albedo.
--- @param entry table { id: string|nil, name: string|nil, albedo: string, normal: string|nil, roughness: string|nil, matcap: string|nil, flipNormalY: boolean|nil, params: table|nil }
--- @return string|nil
function TokenFramesLuaInterface:Upload(entry) end

--- ADMIN ONLY. Removes an uploaded frame from the cloud catalogue: the /CoreAssetsCurrent/tokenframes/{id} record is kept but marked hidden, so clients stop registering it (tokens that still reference the id fall back to their flat albedo frame). Also unregisters it locally. Returns true if a cloud record with that id existed.
--- @param id string
--- @return boolean
function TokenFramesLuaInterface:Delete(id) end

--- Diagnostic: describes the frame material state on a token's renderer -- keyword, which maps resolved to textures (with their sizes and formats), and the parameter vectors currently on the material. Returns a table, or nil if the token has no renderer.
--- @param token CharacterToken
--- @return table|nil
function TokenFramesLuaInterface:Inspect(token) end

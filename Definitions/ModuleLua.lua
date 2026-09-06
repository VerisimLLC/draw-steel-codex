---@meta

--- @class ModuleLua
--- @field idvalid boolean
--- @field fullid any
--- @field authorid string
--- @field moduleid string
--- @field name string
--- @field details string
--- @field keywords any
--- @field keywordsAsJoinedString any
--- @field coverDocumentId string
--- @field coverart any
--- @field owned boolean True if this account may use this module: it was bought in the store, OR a Patreon membership of the publishing creator organization grants it. Use this to gate installing or offering to buy. It is not a claim that a purchase exists -- see hasAccessThroughPatreon to tell the two apart.
--- @field premium boolean
--- @field hasAccessThroughPatreon boolean True if a Patreon membership grants this account access to this module: it is published under a creator organization we are entitled to, and that organization includes it with membership. A premium module is normally hidden on builds with no store; this is the second route past that, so patrons can see and install what they were granted.
--- @field offeredWithPatreon boolean True if the publishing creator organization includes this module with their Patreon. This is a fact about the module, not a claim about this account -- it is true for everyone, patron or not, which is what lets a premium module show in the browser so someone who has not pledged can find it. Never gate access on it; use owned for that. Pair it with owned to decide whether to offer an install or a 'get this with a membership' prompt.
--- @field offeredWithMCDMPatreon boolean Deprecated alias of offeredWithPatreon, kept so Lua written against the MCDM-only version of this feature keeps working. Despite the name it now answers for ANY creator organization.
--- @field patreonCampaign nil|{name: string, url: string|nil, creator: string} The publishing creator organization's public Patreon campaign identity as {name, url, creator}, or nil if the organization has no linked campaign (or offers nothing with it). `creator` is the organization's display name. Marketing information for a 'Become a patron' offer -- it never gates anything.
--- @field published boolean
--- @field deleted boolean
--- @field deprecated boolean True if an administrator has deprecated this module. A deprecated module is disabled in every game by default, but the user may explicitly enable it again with SetDisabled(false). Read-only: deprecation is set by an offline admin script.
--- @field deprecationOverridden boolean True if this module is deprecated but this game has explicitly enabled it anyway. Only meaningful when deprecated is true.
--- @field deprecationMessage string The message explaining why this module is deprecated. Only meaningful when deprecated is true, in which case it is never nil.
--- @field dmhubCanUse boolean
--- @field moduleType string The kind of module this is, chosen by the author when publishing: "general" for a module holding any mix of content, or "mappack" for a collection of maps. Modules published before module types existed read as "general". The publish dialog owns the list of types and the content rules each enforces.
--- @field publishingProperties any
--- @field contentSummary any
--- @field isdisabled boolean
--- @field ourModule boolean
--- @field org nil|string The organization id this module is published under, or nil for a personal module.
--- @field publishedFromThisGame any
--- @field loadedVersion any
--- @field installedVersion any
--- @field latestVersion any
--- @field installationBandwidthInKBytes any
--- @field versions any
--- @field cachedStats any
--- @field vote number
ModuleLua = {}

--- IsModuleIdValid
--- @param id? string
--- @return boolean
function ModuleLua:IsModuleIdValid(id) end

--- IsAuthorIdValid
--- @param id? string
--- @return boolean
function ModuleLua:IsAuthorIdValid(id) end

--- Upload
--- @param options? any
function ModuleLua:Upload(options) end

--- Soft-deletes this module. Marks the module record deleted (so direct-id lookups and searches no longer find it), removes it from the public index and from the current user's published-module lists. Users who already installed the module keep access to the content they imported. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'success' (function) and 'failure' (function(string)) fields.
function ModuleLua:Delete(options) end

--- ReserveAuthorID
--- @param options? any
function ModuleLua:ReserveAuthorID(options) end

--- CheckAuthorIDAvailable
--- @param callback? any
function ModuleLua:CheckAuthorIDAvailable(callback) end

--- CheckModuleIDAvailable
--- @param options? any
function ModuleLua:CheckModuleIDAvailable(options) end

--- UploadModuleVersion
--- @param options? any
function ModuleLua:UploadModuleVersion(options) end

--- UploadModulePublishProperties
--- @param properties? any
function ModuleLua:UploadModulePublishProperties(properties) end

--- Install
--- @param options? any
function ModuleLua:Install(options) end

--- Uninstall
--- @param options? any
function ModuleLua:Uninstall(options) end

--- SetDisabled
--- @param disabled? boolean
function ModuleLua:SetDisabled(disabled) end

--- QueryStats
--- @param fn? any
function ModuleLua:QueryStats(fn) end

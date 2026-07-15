--- @class DiceStudioLua Provides the Lua interface for the Dice Studio, allowing creation and customization of dice sets. Admin-only.
--- @field canSave boolean True if the current dice set has a file and can be saved.
--- @field uploaded boolean True if the current dice set has been uploaded to the cloud.
--- @field currentVersion number The version number of the version currently open in the studio.
--- @field liveVersion number The version number of the loaded set's LIVE version -- the one users of the dice consume.
--- @field isLiveVersion boolean True when the version currently open in the studio is the set's live version.
--- @field notes string Artist notes about the current version (the Version Notes box). Saved and uploaded with the version.
--- @field hasUnsavedChanges boolean True when the studio state differs from the current version's last save. Used to prompt before switching versions or dice sets. False while no set is loaded (or in the brief window before the post-load baseline snapshot is taken).
--- @field dicePanelStyles table Gets or sets the dice panel style table containing bgcolor, trimcolor, and color fields.
--- @field displayName string Gets or sets the player-facing display name for this dice set. This is the name shown to end users wherever a dice set is presented (e.g. the 'Dice Set' setting dropdown); it is independent of the internal/authoring name (which identifies the local file and cloud document). An empty string means 'no override -- fall back to the internal name'.
--- @field font string Gets or sets the font name used for the dice face numbers.
--- @field fontOptions string[] Gets a list of available font names for dice faces.
--- @field border string Gets or sets the border style name for the dice. Returns 'None' if no border is set.
--- @field borderOptions string[] Gets a list of available border style names, including 'None'.
--- @field customDiceModel string Gets or sets the custom dice 3D model name, or nil if using the default model.
--- @field script string The custom Lua script attached to this dice set, or an empty string if none. The script runs once per die instance as a sandboxed coroutine and may inspect/modify each die (see DiceInstanceLua). Setting it re-binds any live preview dice so the studio shows the effect immediately.
--- @field slots table An array of 'slot' tables describing purposes this dice set is suited for (e.g. dealing fire damage, playing a Shadow, or playing an Undead monster). Each entry has a slotType field: 'damage' entries carry a damageType string; 'class' entries carry a classid string and an optional subclassid string; 'monster' entries carry a groupid string (a MonsterGroup table id). Authored in the Dice Studio Slots section; saves and uploads with the set. Owners activate slots from the shop inventory's equip panel (the diceslotsequipped setting) and the roll dialog then skins matching rolls with the activated set (dice.SetRollSlotDice).
--- @field haloEnabled boolean Whether this dice set draws a glowing outline/halo around each die (see haloColor/haloRadius/haloSoftness/haloIntensity for its look). A dice script can also toggle this per-die via die.halo.
--- @field haloColor Color The color of the dice outline/halo. HDR: values above 1 make it glow brighter.
--- @field haloRadius number The thickness of the dice outline/halo in die-local units. 0 == no halo.
--- @field haloSoftness number Softness of the outline/halo outer edge, 0 (crisp outline) to 1 (soft glow).
--- @field haloIntensity number HDR brightness multiplier of the outline/halo (higher = glows brighter).
--- @field billboardEnabled boolean Whether this dice set renders a glowing billboard inside each die: a camera-facing quad drawn behind the die body, so a semi-transparent die reads as having a glow suspended inside it. See billboardImage/billboardColorInner/billboardColorOuter/billboardSize/billboardFalloff/billboardIntensity for its look. A dice script can also toggle this per-die via die.billboard.
--- @field billboardImage string The image asset id of an artist-supplied billboard glow image, or an empty string to render the procedural radial gradient instead. In image mode the image is tinted by billboardColorInner and its own alpha is its coverage.
--- @field billboardColorInner Color The billboard gradient's center color (HDR: values above 1 glow brighter). In image mode this tints the image.
--- @field billboardColorOuter Color The billboard gradient's outer/edge color (HDR). Only used in gradient mode (no image set).
--- @field billboardSize number The billboard quad's size as a fraction of the die's bounding-box size (1 == die-sized). 0 == effectively off.
--- @field billboardFalloff number The billboard gradient's falloff exponent (higher = tighter, more concentrated core). Only used in gradient mode.
--- @field billboardIntensity number HDR brightness multiplier of the billboard glow (higher = glows brighter).
--- @field specialMovement "none"|"teleport"|"portal" The special movement dice in this set perform during a roll: 'none', 'teleport', or 'portal'. 'teleport' makes a die freeze and jump across the playfield (wrapping at the edges) near the end of its roll. 'portal' spawns a pair of portals on the playfield surfaces when the die is hurled and the die passes through one to emerge from the other. Reconciles with legacy teleporting dice sets.
--- @field teleporting boolean Deprecated: use specialMovement instead. True iff specialMovement == 'teleport'. Kept so existing UI that toggles teleporting keeps working; setting it true selects 'teleport', false selects 'none'.
--- @field physicsEnabled boolean Whether this dice set overrides the global dice physics settings with its own per-set 'feel' (see physicsGravity/physicsVelocity/physicsDrag/physicsAngularDrag/physicsBounciness). When false the set rolls with the global dice:* settings.
--- @field physicsGravity number Per-set gravity multiplier (dice 'heft'); only used when physicsEnabled is true. Higher = the die falls and settles harder. Matches the global dice:gravity default (22) for a plastic feel.
--- @field physicsVelocity number Per-set launch-velocity scale (throw energy); only used when physicsEnabled is true. Matches the global dice:velocity default (5).
--- @field physicsDrag number Per-set linear drag (skitter damping); only used when physicsEnabled is true. Higher = the die stops sooner. Matches the global dice:drag default (1.5).
--- @field physicsAngularDrag number Per-set angular drag (tumble damping); only used when physicsEnabled is true. Higher = the die's spin dies sooner. Matches the global dice:angulardrag default (1).
--- @field physicsBounciness number Per-set bounciness / restitution (0..1); only used when physicsEnabled is true. Higher = bouncier. Matches the global dice:bounciness default (0.8).
--- @field teleportVelocity number For teleporting dice: the linear speed at or below which a die's teleport jump triggers (it is then 'almost at a stop').
--- @field teleportDistance number For teleporting dice: how far the die jumps, as a fraction (0-1) of the playfield width.
--- @field teleportDuration number For teleporting dice: how long the jump slide takes, in seconds (lower = faster).
--- @field portalCreationTime number For portal dice: seconds the die must be airborne before its first wall/floor collision passes it through a portal (the first such collision after this window triggers it, once per throw). Also the lead time the portals are shown before the impact.
--- @field portalFlashPeriod number For portal dice: duration in seconds of the brightness flash a die pulses as it enters a portal. The flash peak is timed to the moment of entry (it begins half this period before impact). 0 disables it.
--- @field portalFlashIntensity number For portal dice: peak brightness multiplier of the portal-entry flash (1 = no flash).
--- @field customDiceModelOptions table[] Gets a list of available custom dice model options, each as a table with id and text fields.
--- @field curves DiceCurveLua[] Gets or sets the list of dice curve modifiers applied to the dice.
--- @field allCurveInputs table[] Gets a list of all available curve input types, each as a table with id and text fields.
--- @field builtinMaterialProperties DiceMaterialStudioProperties Gets the built-in material properties for the dice, initializing from the d20 mesh if needed.
--- @field materialProperties DiceMaterialStudioProperties Gets the surface material properties for the dice.
--- @field textMaterialProperties DiceMaterialStudioProperties Gets the text material properties used for dice face number rendering.
--- @field showText boolean Gets or sets whether dice face text/numbers are displayed in the studio.
--- @field surfaceMaterialName nil|string Gets the name of the current surface material override, or nil if none is set.
--- @field material nil|DiceMaterialLua Gets or sets the surface material override for the dice. Set to nil to clear.
--- @field hideBaseMaterial boolean Whether the base dice material is hidden entirely so that only the custom surface material is shown. When true, the engraved face numbers and the border cage are not rendered. Has no visible effect unless a surface material is set.
--- @field finishVideoEffect DiceVideoEffect Gets the video effect played when dice finish rolling.
--- @field availableMaterials DiceMaterialLua[] Gets a list of all available dice materials.
--- @field previewScale number Gets or sets the scale of the dice shown in the dice studio preview.
DiceStudioLua = {}

--- Activate: Activates the Dice Studio view.
--- @return nil
function DiceStudioLua:Activate()
	-- dummy implementation for documentation purposes only
end

--- Deactivate: Deactivates the Dice Studio view.
--- @return nil
function DiceStudioLua:Deactivate()
	-- dummy implementation for documentation purposes only
end

--- UpdateMaterial: Signals that the dice material has been modified and needs to be re-rendered.
--- @return nil
function DiceStudioLua:UpdateMaterial()
	-- dummy implementation for documentation purposes only
end

--- Save: Saves the current dice set to its existing file. With versioning this writes the current version's snapshot (versions/v{n}/data.json); when the current version is the live one it also refreshes the set root's data.json (the live copy users of the local file see).
--- @return nil
function DiceStudioLua:Save()
	-- dummy implementation for documentation purposes only
end

--- SaveAs: Saves the current dice set to a new file with the given name. The new set starts over at Version 1, which is its live version.
--- @param name string
--- @return nil
function DiceStudioLua:SaveAs(name)
	-- dummy implementation for documentation purposes only
end

--- New: Creates a brand-new dice set from the Dice Studio defaults and saves it to a new local file with the given name. Unlike SaveAs -- which copies the currently-loaded dice -- New discards the current edits and starts from a clean slate.
--- @param name string
--- @return nil
function DiceStudioLua:New(name)
	-- dummy implementation for documentation purposes only
end

--- Load: Loads a dice set from a local file by name. Opens the set's LIVE version; use LoadVersion to open a different version of the loaded set.
--- @param name string
--- @return nil
function DiceStudioLua:Load(name)
	-- dummy implementation for documentation purposes only
end

--- Upload: Uploads the current VERSION of the dice set to the cloud (to /DiceVersions/{id}/v{n}). When the current version is the live one it also updates the players' live doc at /CoreAssetsCurrent/dice/{id}. The set must have been saved first. Throws if the current account is not signed in as an admin.
--- @return nil
function DiceStudioLua:Upload()
	-- dummy implementation for documentation purposes only
end

--- GetLocalFiles: Gets a list of locally saved dice set files, each as a table with id and text fields.
--- @return table
function DiceStudioLua:GetLocalFiles()
	-- dummy implementation for documentation purposes only
end

--- DownloadCloudDice: Downloads an already-uploaded (cloud) dice set by its cloud id and saves it as a local Dice Studio file, so it appears in the local dice list (GetLocalFiles). The local copy keeps the cloud name and id, so editing it and then calling Save/Upload updates the same cloud document. If a local set with the same name already exists it is overwritten. Returns the local name on success, or nil if no uploaded dice has that id.
--- @param id string  The cloud dice id (guid), e.g. an entry's `id` from dice.GetAllDice().
--- @return string|nil
function DiceStudioLua:DownloadCloudDice(id)
	-- dummy implementation for documentation purposes only
end

--- GetVersions: Lists the loaded set's saved versions, sorted ascending, each as a table with version (number), notes (string), and live (boolean) fields. Empty if no set is loaded.
--- @return {version: number, notes: string, live: boolean}[]
function DiceStudioLua:GetVersions()
	-- dummy implementation for documentation purposes only
end

--- NewVersion: Creates a new version of the loaded set -- a clone of the studio's current state (including any unsaved edits; the version you were on keeps its last save) -- saves it, and switches the studio to it. The live version is unchanged. Returns the new version number, or 0 if no set is loaded.
--- @return number
function DiceStudioLua:NewVersion()
	-- dummy implementation for documentation purposes only
end

--- LoadVersion: Loads the given version of the currently-loaded dice set into the studio, discarding any unsaved edits (callers should check hasUnsavedChanges first). No-op with an error log if that version has no saved file.
--- @param version number
function DiceStudioLua:LoadVersion(version)
	-- dummy implementation for documentation purposes only
end

--- SetLive: Makes the version currently open in the studio the set's LIVE version. Saves the version first, updates the local live copy, and -- when the set has been uploaded -- immediately pushes this version to the players' live doc at /CoreAssetsCurrent/dice/{id} (users pick it up on the live-asset push / next app start).
--- @return nil
function DiceStudioLua:SetLive()
	-- dummy implementation for documentation purposes only
end

--- ValidateScript: Compiles the given dice-script source in the sandbox without running it, returning an empty string if it compiles cleanly or the error message otherwise. Used by the Script editor to show inline status. Does not change the current script.
--- @param src string
--- @return string
function DiceStudioLua:ValidateScript(src)
	-- dummy implementation for documentation purposes only
end

--- GetEventEffect: Gets the prefab name currently bound to the given dice lifecycle event. Returns an empty string if nothing is bound.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail, portal.
--- @return string
function DiceStudioLua:GetEventEffect(eventName)
	-- dummy implementation for documentation purposes only
end

--- SetEventEffect: Binds (or clears) a prefab to a dice lifecycle event. Pass nil or an empty string to clear.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail, portal.
--- @param effectName string|nil
function DiceStudioLua:SetEventEffect(eventName, effectName)
	-- dummy implementation for documentation purposes only
end

--- GetEventEffectOptions: Gets the list of effect prefab names registered as available for the given dice lifecycle event.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail, portal.
--- @return string[]
function DiceStudioLua:GetEventEffectOptions(eventName)
	-- dummy implementation for documentation purposes only
end

--- GetEventEffectList: Gets the list of effects bound to the given event, in authored order. An event can have several effects, each with its own tunables; each is returned as a DiceEventEffectBindingLua wrapper. Returns an empty list if nothing is bound.
--- @param eventName string
--- @return DiceEventEffectBindingLua[]
function DiceStudioLua:GetEventEffectList(eventName)
	-- dummy implementation for documentation purposes only
end

--- AddEventEffect: Adds another effect to the given event and returns its DiceEventEffectBindingLua wrapper (so its tunables can be set). Pass the effect prefab name, or nil/empty to add an unbound slot. Returns nil if the event name is invalid.
--- @param eventName string
--- @param effectName string|nil
--- @return DiceEventEffectBindingLua|nil
function DiceStudioLua:AddEventEffect(eventName, effectName)
	-- dummy implementation for documentation purposes only
end

--- RemoveEventEffect: Removes a single effect (previously obtained from GetEventEffectList/AddEventEffect) from its event. No-op if the binding is not part of the current dice set.
--- @param binding DiceEventEffectBindingLua
function DiceStudioLua:RemoveEventEffect(binding)
	-- dummy implementation for documentation purposes only
end

--- ClearEventEffects: Removes ALL effects bound to the given event.
--- @param eventName string
function DiceStudioLua:ClearEventEffects(eventName)
	-- dummy implementation for documentation purposes only
end

--- PlayRawBinding: Plays a single bound effect's prefab raw (at world origin, no parenting/layer/transform changes) for debugging its appearance. Takes a DiceEventEffectBindingLua from GetEventEffectList/AddEventEffect.
--- @param binding DiceEventEffectBindingLua
function DiceStudioLua:PlayRawBinding(binding)
	-- dummy implementation for documentation purposes only
end

--- FirePreviewEffect: Test-fires a dice lifecycle event on all currently spawned studio preview dice. For pulses, instantiates the bound one-shot prefab. For state effects (RollWaiting, TravelTail), re-spawns the attached instance so the restart is visible.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail, portal.
function DiceStudioLua:FirePreviewEffect(eventName)
	-- dummy implementation for documentation purposes only
end

--- PlayRawEffect: Plays the prefab bound to the named lifecycle event at world origin with no parenting, layer, or transform changes. For debugging the prefab's raw visual appearance.
--- @param eventName string
function DiceStudioLua:PlayRawEffect(eventName)
	-- dummy implementation for documentation purposes only
end

--- GetSoundEventOptions: Gets the sorted list of all registered sound event names, for the Sounds section dropdowns.
--- @return string[]
function DiceStudioLua:GetSoundEventOptions()
	-- dummy implementation for documentation purposes only
end

--- GetEventSound: Gets the sound event name bound to the given dice lifecycle event, or an empty string if nothing is bound.
--- @param eventName string  One of: throwstart, appearance, bouncehit, disappear, teleport, reappear, exit.
--- @return string
function DiceStudioLua:GetEventSound(eventName)
	-- dummy implementation for documentation purposes only
end

--- SetEventSound: Binds (or clears) a sound event to a dice lifecycle event. Pass nil or an empty string to clear.
--- @param eventName string  One of: throwstart, appearance, bouncehit, disappear, teleport, reappear, exit, numberglow.
--- @param soundEventName string|nil
function DiceStudioLua:SetEventSound(eventName, soundEventName)
	-- dummy implementation for documentation purposes only
end

--- GetEventSoundVolume: Gets the volume multiplier (1 = authored volume) for the event's bound sound, or 1 if nothing is bound.
--- @param eventName string
--- @return number
function DiceStudioLua:GetEventSoundVolume(eventName)
	-- dummy implementation for documentation purposes only
end

--- SetEventSoundVolume: Sets the volume multiplier for the event's bound sound. No-op if nothing is bound to the event.
--- @param eventName string
--- @param volume number
function DiceStudioLua:SetEventSoundVolume(eventName, volume)
	-- dummy implementation for documentation purposes only
end

--- FirePreviewSound: Test-plays the sound bound to the given dice lifecycle event (at the bound volume). No-op if nothing is bound.
--- @param eventName string  One of: throwstart, appearance, bouncehit, disappear, teleport, reappear, exit, numberglow.
function DiceStudioLua:FirePreviewSound(eventName)
	-- dummy implementation for documentation purposes only
end

--- GetImpactFamily: Gets the dice impact-sound family id bound to the set, or an empty string for the default (copper) family.
--- @return string
function DiceStudioLua:GetImpactFamily()
	-- dummy implementation for documentation purposes only
end

--- SetImpactFamily: Sets the dice impact-sound family id. Pass an empty string for the default (copper) family. Clears any legacy generic Impact (BounceHit) sound binding, which the family choice supersedes.
--- @param id string
function DiceStudioLua:SetImpactFamily(id)
	-- dummy implementation for documentation purposes only
end

--- GetImpactFamilyVolume: Gets the impact family volume multiplier (1 = the family's authored volume).
--- @return number
function DiceStudioLua:GetImpactFamilyVolume()
	-- dummy implementation for documentation purposes only
end

--- SetImpactFamilyVolume: Sets the impact family volume multiplier (0..2; 1 = the family's authored volume).
--- @param volume number
function DiceStudioLua:SetImpactFamilyVolume(volume)
	-- dummy implementation for documentation purposes only
end

--- FirePreviewImpact: Test-plays the set's chosen impact family at a hard-hit speed (through the Dice.Impact dispatcher).
--- @return nil
function DiceStudioLua:FirePreviewImpact()
	-- dummy implementation for documentation purposes only
end

--- GetMaterialProperties: Gets the material properties for the given category: 'material', 'text', or 'builtin'.
--- @param id string The material category.
--- @return nil|DiceMaterialStudioProperties
function DiceStudioLua:GetMaterialProperties(id)
	-- dummy implementation for documentation purposes only
end

--- AddCurve: Adds a new curve modifier to the dice set and returns it.
--- @return DiceCurveLua
function DiceStudioLua:AddCurve()
	-- dummy implementation for documentation purposes only
end

--- GetMaterial: Gets a dice material wrapper by category: 'material' for surface or 'builtin' for built-in.
--- @param id string The material category.
--- @return DiceMaterialLua
function DiceStudioLua:GetMaterial(id)
	-- dummy implementation for documentation purposes only
end

--- GetMaterialForType: Gets the per-die-type surface material override for the die with the given face count, or nil if that die type has no override (it falls back to the default 'material'). Note that d100 shares the d10 slot.
--- @param numFaces number  The die's face count (e.g. 4, 6, 8, 10, 12, 20).
--- @return nil|DiceMaterialLua
function DiceStudioLua:GetMaterialForType(numFaces)
	-- dummy implementation for documentation purposes only
end

--- SetMaterialForType: Sets the per-die-type surface material override for the die with the given face count. Pass nil to clear the override so that die type falls back to the default 'material'. Note that d100 shares the d10 slot.
--- @param numFaces number  The die's face count (e.g. 4, 6, 8, 10, 12, 20).
--- @param material nil|DiceMaterialLua
function DiceStudioLua:SetMaterialForType(numFaces, value)
	-- dummy implementation for documentation purposes only
end

--- HasMaterialForType: True if the die with the given face count has a per-die-type surface material override (as opposed to falling back to the default 'material').
--- @param numFaces number  The die's face count (e.g. 4, 6, 8, 10, 12, 20).
--- @return boolean
function DiceStudioLua:HasMaterialForType(numFaces)
	-- dummy implementation for documentation purposes only
end

--- GetMaterialPropertiesForType: Gets the tuned surface-material properties for the die with the given face count: the per-type override's properties when that die type has an override, otherwise the default surface material properties.
--- @param numFaces number  The die's face count (e.g. 4, 6, 8, 10, 12, 20).
--- @return DiceMaterialStudioProperties
function DiceStudioLua:GetMaterialPropertiesForType(numFaces)
	-- dummy implementation for documentation purposes only
end

--- SpawnPreview: Spawns a preview die in the dice harness with the specified number of faces.
--- @param nfaces number
--- @return nil
function DiceStudioLua:SpawnPreview(nfaces)
	-- dummy implementation for documentation purposes only
end

--- RecordPreviewVideo: Records a preview video of the current dice set and calls the callback when complete.
--- @param callback function Called when recording is complete.
function DiceStudioLua:RecordPreviewVideo(callback)
	-- dummy implementation for documentation purposes only
end

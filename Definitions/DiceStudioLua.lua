--- @class DiceStudioLua Provides the Lua interface for the Dice Studio, allowing creation and customization of dice sets. Admin-only.
--- @field canSave boolean True if the current dice set has a file and can be saved.
--- @field uploaded boolean True if the current dice set has been uploaded to the cloud.
--- @field dicePanelStyles table Gets or sets the dice panel style table containing bgcolor, trimcolor, and color fields.
--- @field font string Gets or sets the font name used for the dice face numbers.
--- @field fontOptions string[] Gets a list of available font names for dice faces.
--- @field border string Gets or sets the border style name for the dice. Returns 'None' if no border is set.
--- @field borderOptions string[] Gets a list of available border style names, including 'None'.
--- @field customDiceModel string Gets or sets the custom dice 3D model name, or nil if using the default model.
--- @field teleporting boolean Whether dice in this set have the teleporting feature: once a die has almost come to a stop near the end of a roll its momentum freezes, it jumps across the playfield (wrapping around the edges, fading out then back in), and finishes settling at the destination.
--- @field teleportVelocity number For teleporting dice: the linear speed at or below which a die's teleport jump triggers (it is then 'almost at a stop').
--- @field teleportDistance number For teleporting dice: how far the die jumps, as a fraction (0-1) of the playfield width.
--- @field teleportDuration number For teleporting dice: how long the jump slide takes, in seconds (lower = faster).
--- @field customDiceModelOptions table[] Gets a list of available custom dice model options, each as a table with id and text fields.
--- @field particles table<string, boolean> Gets or sets the active particle system names as a table of name-to-true entries.
--- @field particleOptions string[] Gets a list of available particle system names.
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

--- Save: Saves the current dice set to its existing file.
--- @return nil
function DiceStudioLua:Save()
	-- dummy implementation for documentation purposes only
end

--- SaveAs: Saves the current dice set to a new file with the given name.
--- @param name string
--- @return nil
function DiceStudioLua:SaveAs(name)
	-- dummy implementation for documentation purposes only
end

--- Load: Loads a dice set from a local file by name.
--- @param name string
--- @return nil
function DiceStudioLua:Load(name)
	-- dummy implementation for documentation purposes only
end

--- Upload: Uploads the current dice set to the cloud. The set must have been saved first. Throws if the current account is not signed in as an admin.
--- @return nil
function DiceStudioLua:Upload()
	-- dummy implementation for documentation purposes only
end

--- GetLocalFiles: Gets a list of locally saved dice set files, each as a table with id and text fields.
--- @return table
function DiceStudioLua:GetLocalFiles()
	-- dummy implementation for documentation purposes only
end

--- GetEventEffect: Gets the prefab name currently bound to the given dice lifecycle event. Returns an empty string if nothing is bound.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail.
--- @return string
function DiceStudioLua:GetEventEffect(eventName)
	-- dummy implementation for documentation purposes only
end

--- SetEventEffect: Binds (or clears) a prefab to a dice lifecycle event. Pass nil or an empty string to clear.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail.
--- @param effectName string|nil
function DiceStudioLua:SetEventEffect(eventName, effectName)
	-- dummy implementation for documentation purposes only
end

--- GetEventEffectOptions: Gets the list of effect prefab names registered as available for the given dice lifecycle event.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail.
--- @return string[]
function DiceStudioLua:GetEventEffectOptions(eventName)
	-- dummy implementation for documentation purposes only
end

--- FirePreviewEffect: Test-fires a dice lifecycle event on all currently spawned studio preview dice. For pulses, instantiates the bound one-shot prefab. For state effects (RollWaiting, TravelTail), re-spawns the attached instance so the restart is visible.
--- @param eventName string  One of: appearance, bouncehit, disappear, reappear, exit, rollwaiting, traveltail.
function DiceStudioLua:FirePreviewEffect(eventName)
	-- dummy implementation for documentation purposes only
end

--- PlayRawEffect: Plays the prefab bound to the named lifecycle event at world origin with no parenting, layer, or transform changes. For debugging the prefab's raw visual appearance.
--- @param eventName string
function DiceStudioLua:PlayRawEffect(eventName)
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

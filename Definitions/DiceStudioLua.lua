--- @class DiceStudioLua Provides the Lua interface for the Dice Studio, allowing creation and customization of dice sets. Admin-only.
--- @field canSave boolean True if the current dice set has a file and can be saved.
--- @field uploaded boolean True if the current dice set has been uploaded to the cloud.
--- @field dicePanelStyles table Gets or sets the dice panel style table containing bgcolor, trimcolor, and color fields.
--- @field font string Gets or sets the font name used for the dice face numbers.
--- @field fontOptions string[] Gets a list of available font names for dice faces.
--- @field border string Gets or sets the border style name for the dice. Returns 'None' if no border is set.
--- @field borderOptions string[] Gets a list of available border style names, including 'None'.
--- @field customDiceModel string Gets or sets the custom dice 3D model name, or nil if using the default model.
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

--- Upload: Uploads the current dice set to the cloud. The set must have been saved first.
--- @return nil
function DiceStudioLua:Upload()
	-- dummy implementation for documentation purposes only
end

--- GetLocalFiles: Gets a list of locally saved dice set files, each as a table with id and text fields.
--- @return table
function DiceStudioLua:GetLocalFiles()
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

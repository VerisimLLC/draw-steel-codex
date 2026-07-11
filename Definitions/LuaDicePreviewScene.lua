--- @class LuaDicePreviewScene Provides control over the dice preview scene used to render dice in a UI context.
--- @field assetid string Sets the dice set asset identifier to preview. (Write-only)
--- @field selectedIndex number The index of the currently selected die in the preview.
--- @field dragging boolean Sets whether the user is currently dragging a die in the preview. (Write-only)
--- @field fixedTime boolean Sets whether the preview uses a fixed time step (1/60s) instead of real delta time. (Write-only)
--- @field solo boolean Sets whether only the selected die is visible, hiding all others. (Write-only)
--- @field initialRotation number Sets the initial rotation angle in degrees applied to dice when the preview initializes. (Write-only)
--- @field spinAxisAngle number Rotates the idle spin AXIS by this many degrees about the screen-normal (Z) axis, without changing the spin speed. 0 = the default vertical-axis spin; 180 = the spin reversed; 90 = tumbling. (Write-only)
--- @field diceScale number Sets a uniform scale override for all dice in the preview. Set to 0 to use the default calculated scale. (Write-only)
--- @field bgcolor string Sets the preview background to a radial gradient: this color (an HTML color string, e.g. '#ff0000') in the center fading to black at the edges. (Write-only)
--- @field transparent boolean Sets whether the preview renders with a fully transparent background, so the dice composite over whatever is behind the panel. The RT's color is premultiplied and its alpha channel is reconstructed so dice FX (including additive glows) composite correctly -- panels showing the RT should set blend = 'premultiplied'. (Write-only)
--- @field bgtexture string Sets a background texture by image asset identifier. Set to nil or empty string to hide the background texture. (Write-only)
LuaDicePreviewScene = {}

--- PlayExit: Plays the current preview dice's Exit effect and starts their fade-out over fadeOutDuration seconds (pass <= 0 for the die's default vanish time), e.g. to animate the die out as the shop's featured-dice carousel switches sets.
--- @param fadeOutDuration number
--- @return nil
function LuaDicePreviewScene:PlayExit(fadeOutDuration)
	-- dummy implementation for documentation purposes only
end

--- CancelExit: Cancels an in-flight exit fade (see PlayExit): dice that are fading out or have already faded are faded back up to full opacity. No-op when the dice are fully visible, so it is safe to call unconditionally when a view takes over the shared preview scene.
--- @return nil
function LuaDicePreviewScene:CancelExit()
	-- dummy implementation for documentation purposes only
end

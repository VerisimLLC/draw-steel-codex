--- @class audio Provides the Lua interface for the audio system, including sound events, volume control, and music playback.
--- @field events EventSourceLua An event source for subscribing to audio-related events.
--- @field muted boolean Whether all game audio is currently muted.
--- @field masterVolume number The master volume level for all game audio, from 0 to 1.
--- @field currentlyPlaying table A table of currently playing game sound events.
--- @field numPlayingSounds number The number of sound instances currently playing.
--- @field numActiveSoundEvents number The number of active sound events in the current game.
--- @field soundEvents table A table mapping sound event names to their SoundEvent objects.
audio = {}

--- UploadMuted: Uploads the current muted state to the server.
--- @return nil
function audio.UploadMuted()
	-- dummy implementation for documentation purposes only
end

--- UploadMasterVolume: Uploads the current master volume to the server.
--- @return nil
function audio.UploadMasterVolume()
	-- dummy implementation for documentation purposes only
end

--- StopAllSoundEvents: Stops all currently playing sound events.
--- @return nil
function audio.StopAllSoundEvents()
	-- dummy implementation for documentation purposes only
end

--- StopSoundEvent: Stops a specific sound event by its guid.
--- @param guid string
--- @return nil
function audio.StopSoundEvent(guid)
	-- dummy implementation for documentation purposes only
end

--- PreviewSoundEventVolume: Temporarily previews a volume change on a sound event without persisting it to the server.
--- @param guid string The sound event guid.
--- @param volume number The preview volume level.
function audio.PreviewSoundEventVolume(guid, volume)
	-- dummy implementation for documentation purposes only
end

--- SetSoundEventVolume: Sets the volume of a sound event and persists the change to the server.
--- @param guid string The sound event guid.
--- @param volume number The volume level to set.
function audio.SetSoundEventVolume(guid, volume)
	-- dummy implementation for documentation purposes only
end

--- PlaySoundEvent: Starts playing a sound event from the given options table. Returns the guid of the playing sound event.
--- @param options table Options with keys: asset (AudioAssetLua), volume (number).
--- @return nil|string
function audio.PlaySoundEvent(options)
	-- dummy implementation for documentation purposes only
end

--- OpenAudioDevDir: Opens the audio development directory in the system file explorer.
--- @return nil
function audio.OpenAudioDevDir()
	-- dummy implementation for documentation purposes only
end

--- RegisterAudioMod: Registers a code mod as the active audio mod for development purposes.
--- @param codemod CodeModInterface The code mod to register.
function audio.RegisterAudioMod(codemod)
	-- dummy implementation for documentation purposes only
end

--- DevDownloadAudio: Downloads the registered audio mod's assets to the local audio development directory.
--- @return nil
function audio.DevDownloadAudio()
	-- dummy implementation for documentation purposes only
end

--- UploadAudio: Uploads the registered audio mod's assets from the local development directory to the server.
--- @return nil
function audio.UploadAudio()
	-- dummy implementation for documentation purposes only
end

--- MixGroup: Registers a mix group for volume control. The args table must contain name, id, and optionally parent.
--- @param args table The mix group definition with keys: name, id, parent.
function audio.MixGroup(args)
	-- dummy implementation for documentation purposes only
end

--- DispatchSoundEvent: Dispatches a sound event by name to all connected clients and plays it locally.
--- @param name string The sound event name.
--- @param args nil|table Optional arguments passed to the sound event.
function audio.DispatchSoundEvent(name, args)
	-- dummy implementation for documentation purposes only
end

--- FireSoundEvent: Fires a sound event locally by name without dispatching to other clients.
--- @param name string The sound event name.
--- @param args nil|table Optional arguments passed to the sound event.
--- @return nil|table
function audio.FireSoundEvent(name, args)
	-- dummy implementation for documentation purposes only
end

--- SoundEvent: Registers a new sound event from a table definition. The args table must contain name, mixgroup, and sounds.
--- @param args table The sound event definition with keys: name, mixgroup, sounds, volume, delay, pitch, loop, etc.
function audio.SoundEvent(args)
	-- dummy implementation for documentation purposes only
end

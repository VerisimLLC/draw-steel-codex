---@meta

--- Provides the Lua interface for the audio system, including sound events, volume control, and music playback.
--- @class audio
--- @field events EventSourceLua An event source for subscribing to audio-related events.
--- @field muted boolean Whether all game audio is currently muted.
--- @field masterVolume number The master volume level for all game audio, from 0 to 1.
--- @field normalizeLoudness boolean Whether library/anthem track loudness is automatically normalized for this game.
--- @field deviceSelectionSupported boolean True when this platform supports selecting the audio output device (Windows only).
--- @field outputDevice string The output device the app's audio plays to, as a device id from GetOutputDevices; the empty string means the system default. Setting it re-routes the app at the OS level (persisted by Windows across launches) and restarts playback on the new device. Windows only; a no-op elsewhere.
--- @field currentlyPlaying table A table of currently playing game sound events.
--- @field numPlayingSounds number The number of sound instances currently playing.
--- @field numActiveSoundEvents number The number of active sound events in the current game.
--- @field soundEvents table A table mapping sound event names to their SoundEvent objects.
audio = {}

--- Uploads the current muted state to the server.
function audio.UploadMuted() end

--- Uploads the current master volume to the server.
function audio.UploadMasterVolume() end

--- Uploads the current loudness-normalization toggle to the server.
function audio.UploadNormalizeLoudness() end

--- Returns the available audio output devices as a list of {value, text} entries suitable for a dropdown enum, beginning with the system-default entry (value = empty string).
--- @return table
function audio.GetOutputDevices() end

--- Stops all currently playing sound events.
function audio.StopAllSoundEvents() end

--- Stops a specific sound event by its guid.
--- @param guid? string
function audio.StopSoundEvent(guid) end

--- Temporarily previews a volume change on a sound event without persisting it to the server.
--- @param guid string The sound event guid.
--- @param volume number The preview volume level.
function audio.PreviewSoundEventVolume(guid, volume) end

--- Sets the volume of a sound event and persists the change to the server.
--- @param guid string The sound event guid.
--- @param volume number The volume level to set.
function audio.SetSoundEventVolume(guid, volume) end

--- Starts playing a sound event from the given options table. Returns the guid of the playing sound event.
--- @param options table Options with keys: asset (AudioAssetLua), volume (number), pitch (number).
--- @return nil|string
function audio.PlaySoundEvent(options) end

--- Crossfades between two sound events: fades stopAssetId out and startAssetId in over the given duration. Either side may be nil to just fade one in or out.
--- @param stopAssetId nil|string The asset id (guid) of the sound event to fade out, or nil.
--- @param startAssetId nil|string The asset id (guid) of the sound event to fade in, or nil.
--- @param seconds nil|number Crossfade duration in seconds; defaults to 3.0, minimum 0.05.
function audio.CrossfadeSoundEvents(stopAssetId, startAssetId, seconds) end

--- Opens the audio development directory in the system file explorer.
function audio.OpenAudioDevDir() end

--- Registers a code mod as the active audio mod for development purposes.
--- @param codemod CodeModInterface The code mod to register.
function audio.RegisterAudioMod(codemod) end

--- Downloads the registered audio mod's assets to the local audio development directory.
function audio.DevDownloadAudio() end

--- Uploads the registered audio mod's assets from the local development directory to the server.
function audio.UploadAudio() end

--- Registers a mix group for volume control. The args table must contain name, id, and optionally parent.
--- @param args table The mix group definition with keys: name, id, parent.
function audio.MixGroup(args) end

--- Ducks a mix group's volume to a target level. Refcounted: pair each DuckGroup with a ReleaseDuck. fadeDown ramps into the duck; fadeUp (optional, defaults to fadeDown) ramps back out -- pass a slower fadeUp so the bed swells back gently.
--- @param id string The mix group id to duck (e.g. "music").
--- @param level number Target volume multiplier 0..1.
--- @param fadeDown number Fade-in (duck) duration in seconds.
--- @param fadeUp number Optional fade-out (release) duration in seconds; defaults to fadeDown.
function audio.DuckGroup(id, level, fadeDown, fadeUp) end

--- Sets a mix group's shared broadcast level (0..1) -- the DM-controlled layer synced to all clients via the shared audio-mix document. Folds up the parent chain; defaults to 1.0 (transparent) for untouched groups.
--- @param id string The mix group id (e.g. "music", "uisounds").
--- @param value number Broadcast level 0..1.
function audio.SetGroupShared(id, value) end

--- Releases a duck previously applied to a mix group with DuckGroup. Refcounted.
--- @param id string The mix group id to release.
function audio.ReleaseDuck(id) end

--- Clears all mix-group duck and shared-broadcast state. Normally happens automatically on game load/switch; exposed here as a manual escape hatch for recovering from a leaked duck or testing.
function audio.ResetMixState() end

--- Dispatches a sound event by name to all connected clients and plays it locally.
--- @param name string The sound event name.
--- @param args nil|table Optional arguments passed to the sound event.
function audio.DispatchSoundEvent(name, args) end

--- Fires a sound event locally by name without dispatching to other clients.
--- @param name string The sound event name.
--- @param args nil|table Optional arguments passed to the sound event.
--- @return nil|table
function audio.FireSoundEvent(name, args) end

--- Registers a new sound event from a table definition. The args table must contain name, mixgroup, and sounds.
--- @param args table The sound event definition with keys: name, mixgroup, sounds, volume, delay, pitch, loop, etc.
function audio.SoundEvent(args) end

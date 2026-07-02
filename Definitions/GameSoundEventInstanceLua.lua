--- @class GameSoundEventInstanceLua
--- @field isPlaying boolean Whether the underlying sound instance is currently audible (false while paused or finished).
--- @field time number Playback position in seconds. Writable: setting it seeks the sound event for ALL clients (synced through the game document, clamped to the clip length).
--- @field paused boolean Whether the sound event is paused. Writable: setting it pauses/resumes the sound event for ALL clients (synced through the game document; position is held while paused and resumes from the same spot).
GameSoundEventInstanceLua = {}
